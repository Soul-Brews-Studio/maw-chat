import Foundation
import MawCore
import Observation

@MainActor @Observable
final class ChatWorkspace {
  var state = ChatState()
  var native: [NativeChatSession] = []
  var repositories: [ChatRepository] = []
  var inventoryWarning: String?
  var repositoriesLoading = false
  var nativeLoaded = false
  var sidebarGroups: [OracleGroup] = [] {
    didSet {
      if let sidebarOracleID, !sidebarGroups.contains(where: { $0.id == sidebarOracleID }) {
        self.sidebarOracleID = nil
      }
      if let browserOracleID, !sidebarGroups.contains(where: { $0.id == browserOracleID }) {
        self.browserOracleID = nil
      }
    }
  }
  var browsingSessions = false
  var browserOracleID: String?
  var sidebarOracleID: String?
  private var indexTask: Task<Void, Never>?
  private var indexRevision = 0
  let indexWorker = OracleIndexWorker()
  @ObservationIgnored private(set) var navigationRevision = 0
  var selection: String? {
    didSet { if selection != oldValue { navigationRevision &+= 1 } }
  }
  var connected = false
  var health: BackendHealth?
  var error: String?
  var busy = false
  var history: [ChatMessage] = []
  var historyOffset: Int?
  var historyLoading = false
  var draft = ""
  var selectedMentions: [MentionCandidate] = []
  var mentionCandidates: [MentionCandidate] = []
  let mentionIndex = MentionIndex()
  var model = "sonnet"
  var permission = "default"
  var project: String?
  var draftPath: String?
  var draftProjectName: String?
  let backend: ChatBackend
  let rowWorker = WorkspaceIndex()
  var rows: [WorkspaceRow] = []
  var reply: ReplyContext?
  private var didSelectInitial = false
  private var pendingConversation: Conversation?
  private var resumedReply: (identity: String, reply: ReplyContext?)?
  var title: String { chat?.title ?? nativeSession?.name ?? draftProjectName ?? "New conversation" }
  var oracleName: String {
    sidebarGroups.first { group in group.threads.contains { $0.id == selection } }?.name
      ?? draftProjectName ?? "Local workspace"
  }
  init(backend: ChatBackend = ChatBackend()) { self.backend = backend }

  var chat: Conversation? {
    state.chats.first { "chat:" + $0.id == selection }
      ?? (pendingConversation.map { "chat:" + $0.id == selection } == true
        ? pendingConversation : nil)
  }
  var nativeSession: NativeChatSession? { native.first { "native:" + $0.id == selection } }
  var messages: [ChatMessage] { chat?.messages ?? history }
  var providerReady: Bool { connected && health?.claudeAvailable == true }
  var canCompose: Bool { nativeSession == nil && (selection == nil || chat != nil) }

  func checkConnection() async {
    do {
      health = try await backend.health()
      error =
        health?.claudeAvailable == true ? nil : "Claude is unavailable on the local chat server."
    } catch {
      health = nil
      self.error = "Connection check failed: " + error.localizedDescription
    }
  }

  func connect() async {
    while !Task.isCancelled {
      do {
        health = try await backend.health()
        for try await snapshot in await backend.events() {
          try Task.checkCancellation()
          state = snapshot
          if let pendingConversation,
            snapshot.chats.contains(where: { $0.id == pendingConversation.id })
          {
            self.pendingConversation = nil
          }
          refreshSidebarIndex()
          connected = true
          if !didSelectInitial {
            didSelectInitial = true
            if selection == nil { selection = snapshot.chats.first.map { "chat:" + $0.id } }
          }
        }
        connected = false
      } catch is CancellationError { return } catch {
        connected = false
        self.error = error.localizedDescription
      }
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
    }
  }
  func refreshNative() async {
    do {
      native = try await backend.nativeSessions()
      nativeLoaded = true
      refreshSidebarIndex()
    } catch is CancellationError {} catch {
      self.error = error.localizedDescription
    }
  }
  func refreshRepositories() async {
    guard !repositoriesLoading else { return }
    repositoriesLoading = true
    defer { repositoriesLoading = false }
    do {
      let inventory = try await backend.repositories()
      repositories = inventory.repositories
      inventoryWarning = inventory.warning
      refreshSidebarIndex()
    } catch is CancellationError {} catch {
      inventoryWarning = error.localizedDescription
    }
  }
  private func refreshSidebarIndex() {
    indexRevision &+= 1
    guard indexTask == nil else { return }
    indexTask = Task { [weak self] in
      while let self, !Task.isCancelled {
        let revision = indexRevision
        let groups = await indexWorker.build(
          state: state, sessions: native, repositories: repositories)
        // One build at a time. Intermediate snapshots are coalesced, never published late.
        if revision != indexRevision { continue }
        let projected = await rowWorker.rows(groups: groups, state: state)
        if revision != indexRevision { continue }
        let mentions = await mentionIndex.build(groups: groups, state: state, native: native)
        if revision != indexRevision { continue }
        if mentionCandidates != mentions { mentionCandidates = mentions }
        if sidebarGroups != groups { sidebarGroups = groups }
        if rows != projected { rows = projected }
        indexTask = nil
        return
      }
    }
  }
  func browseSessions(in oracleID: String? = nil) {
    browserOracleID = oracleID
    browsingSessions = true
  }
  func newChat(in oracle: OracleGroup? = nil) {
    if browsingSessions { browserOracleID = oracle?.id }
    if sidebarOracleID != oracle?.id { sidebarOracleID = nil }
    navigationRevision &+= 1
    selectedMentions = []
    didSelectInitial = true
    reply = nil
    selection = nil
    project = oracle?.projectID
    draftPath = oracle?.path
    draftProjectName = oracle?.name
    permission = "default"
    draft = ""
    history = []
    error = nil
  }
  func selected() async {
    reply = resumedReply?.identity == selection ? resumedReply?.reply : nil
    resumedReply = nil
    if selection != nil && !busy {
      draft = ""
      selectedMentions = []
    }
    historyLoading = false
    history = []
    historyOffset = nil
    error = nil
    if let chat {
      model = chat.model
      permission = chat.permissionMode
      project = chat.projectId
    } else if nativeSession != nil {
      await readHistory(reset: true)
    }
  }
  func readHistory(reset: Bool) async {
    guard let id = nativeSession?.sessionId else { return }
    let identity = selection
    historyLoading = true
    defer { if selection == identity { historyLoading = false } }
    do {
      let page = try await backend.history(id, offset: reset ? 0 : (historyOffset ?? 0))
      try Task.checkCancellation()
      guard selection == identity else { return }
      if reset {
        history = page.messages
      } else {
        let known = Set(history.map(\.id))
        history += page.messages.filter { !known.contains($0.id) }
      }
      historyOffset = page.nextOffset
    } catch is CancellationError {} catch {
      if selection == identity { self.error = error.localizedDescription }
    }
  }
  // REST responses are not merged over SSE snapshots: they may be older. Selection
  // can be updated immediately; the server's state event is the data authority.
  // A pending new/imported chat bridges REST-before-SSE without duplicating creation.
  func send() async {
    guard canCompose, chat?.status != "running", !busy, providerReady,
      !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return
    }
    busy = true
    error = nil
    defer { busy = false }
    var revision = navigationRevision
    let originalDraft = draft
    let content = reply.map { $0.content + "\n\n" + draft } ?? draft
    do {
      let text = try MentionText.expand(content, selected: selectedMentions)
      let target: Conversation
      if let chat {
        target = chat
      } else {
        var projectID = project
        if projectID == nil, let path = draftPath {
          if let existing = state.projects.first(where: {
            OracleIndex.normalize($0.canonicalPath ?? $0.path) == path
          }) {
            projectID = existing.id
          } else {
            let created = try await backend.createProject(
              name: draftProjectName ?? URL(fileURLWithPath: path).lastPathComponent, path: path)
            projectID = created.id
          }
          guard navigationRevision == revision else { return }
          project = projectID
        }
        target = try await backend.create(
          title: String(originalDraft.prefix(80)), project: projectID, model: model,
          permission: permission)
        guard navigationRevision == revision else { return }
        pendingConversation = target
        selection = "chat:" + target.id
        revision = navigationRevision
      }
      _ = try await backend.send(target.id, text: text)
      if navigationRevision == revision && draft == originalDraft {
        draft = ""
        selectedMentions = []
        reply = nil
      }
    } catch { if navigationRevision == revision { self.error = error.localizedDescription } }
  }
  func stop() async {
    guard let id = chat?.id else { return }
    do { _ = try await backend.stop(id) } catch { self.error = error.localizedDescription }
  }
  func importSelected() async {
    guard let session = nativeSession, let id = session.sessionId, session.action == "resume", !busy
    else { return }
    busy = true
    defer { busy = false }
    let identity = selection
    let quoted = reply
    do {
      let chat = try await backend.importSession(id)
      guard selection == identity else { return }
      pendingConversation = chat
      resumedReply = ("chat:" + chat.id, quoted)
      selection = "chat:" + chat.id
    } catch { if selection == identity { self.error = error.localizedDescription } }
  }
  func syncHistory() async {
    guard let id = chat?.id, !busy else { return }
    busy = true
    defer { busy = false }
    do { _ = try await backend.sync(id) } catch { self.error = error.localizedDescription }
  }
  func loadChatHistory() async {
    guard let id = chat?.id, !busy else { return }
    busy = true
    defer { busy = false }
    do { _ = try await backend.loadHistory(id) } catch { self.error = error.localizedDescription }
  }
  func updateOptions() async {
    guard let id = chat?.id else { return }
    do { _ = try await backend.update(id, model: model, permission: permission) } catch {
      self.error = error.localizedDescription
      if let chat {
        model = chat.model
        permission = chat.permissionMode
      }
    }
  }
}
