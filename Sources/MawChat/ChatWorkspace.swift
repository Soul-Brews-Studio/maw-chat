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
  var sidebarGroups: [OracleGroup] = []
  private var indexTask: Task<Void, Never>?
  private var indexRevision = 0
  let indexWorker = OracleIndexWorker()
  var selection: String?
  var connected = false
  var health: BackendHealth?
  var error: String?
  var busy = false
  var history: [ChatMessage] = []
  var historyOffset: Int?
  var historyLoading = false
  var draft = ""
  var model = "sonnet"
  var permission = "default"
  var project: String?
  var draftPath: String?
  var draftProjectName: String?
  let backend = ChatBackend()

  var chat: Conversation? { state.chats.first { "chat:" + $0.id == selection } }
  var nativeSession: NativeChatSession? { native.first { "native:" + $0.id == selection } }
  var messages: [ChatMessage] { chat?.messages ?? history }

  func connect() async {
    while !Task.isCancelled {
      do {
        health = try await backend.health()
        for try await snapshot in await backend.events() {
          try Task.checkCancellation()
          state = snapshot
          refreshSidebarIndex()
          connected = true
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
        if sidebarGroups != groups { sidebarGroups = groups }
        indexTask = nil
        return
      }
    }
  }
  func newChat(in oracle: OracleGroup? = nil) {
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
    if selection != nil && !busy { draft = "" }
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
  func send() async {
    guard !busy, connected, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }
    busy = true
    error = nil
    defer { busy = false }
    let text = draft
    let identity = selection
    do {
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
          guard selection == identity else { return }
          project = projectID
        }
        target = try await backend.create(
          title: String(text.prefix(80)), project: projectID, model: model, permission: permission)
        guard selection == identity else { return }
        selection = "chat:" + target.id
      }
      _ = try await backend.send(target.id, text: text)
      if draft == text { draft = "" }
    } catch { self.error = error.localizedDescription }
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
    do {
      let chat = try await backend.importSession(id)
      selection = "chat:" + chat.id
    } catch { self.error = error.localizedDescription }
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
