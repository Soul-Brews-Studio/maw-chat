import AppKit
import MawCore
import SwiftUI

struct ChatWorkspaceView: View {
  @State private var store = ChatWorkspace()
  @State private var follow = true
  @State private var details = false
  private let accent = Color(red: 0.41, green: 0.26, blue: 0.85)
  private let canvas = Color(red: 0.96, green: 0.96, blue: 0.99)
  @FocusState private var composerFocused: Bool
  @AppStorage("MawChat.conversationTags") private var tagJSON = "{}"
  @State private var editing: String?
  @State private var editName = ""
  @State private var originalName = ""
  @State private var editTags = ""
  @State private var renameAllowed = true
  @State private var editError: String?
  @State private var editBusy = false
  var tags: [String: [String]] {
    (try? JSONDecoder().decode([String: [String]].self, from: Data(tagJSON.utf8))) ?? [:]
  }
  func tagKey(chat: Conversation) -> String { chat.sessionId ?? "chat:" + chat.id }
  func startThread(in oracle: OracleGroup? = nil) {
    store.newChat(in: oracle)
    composerFocused = true
  }
  func beginEdit(_ identity: String, name: String, key: String, canRename: Bool) {
    editing = identity
    editName = name
    originalName = name
    editTags = (tags[key] ?? []).joined(separator: ", ")
    renameAllowed = canRename
    editError = nil
  }
  func saveEdits() async {
    guard let identity = editing else { return }
    let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      editError = "Enter a conversation name."
      return
    }
    editBusy = true
    defer { editBusy = false }
    do {
      let key: String
      if identity.hasPrefix("chat:"),
        let chat = store.state.chats.first(where: { "chat:" + $0.id == identity })
      {
        if name != originalName { _ = try await store.backend.rename(chat.id, title: name) }
        key = tagKey(chat: chat)
      } else if identity.hasPrefix("native:"),
        let session = store.native.first(where: { "native:" + $0.id == identity }),
        let id = session.sessionId
      {
        if renameAllowed && name != originalName {
          try await store.backend.renameNative(id, title: name)
        }
        key = id
        await store.refreshNative()
      } else {
        throw BackendError.message("Conversation no longer exists. Refresh and retry.")
      }
      var next = tags
      next[key] = ConversationIndex.parseTags(editTags)
      tagJSON = String(decoding: try JSONEncoder().encode(next), as: UTF8.self)
      editing = nil
    } catch { editError = error.localizedDescription }
  }
  var body: some View {
    NavigationSplitView {
      OracleSidebarView(
        store: store,
        startThread: { startThread(in: $0) },
        beginEdit: { beginEdit($0, name: $1, key: $2, canRename: $3) })
    } detail: {
      VStack(spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 5) {
            Text(
              store.chat?.title ?? store.nativeSession?.name ?? store.draftProjectName.map {
                "New chat in " + $0
              } ?? "New conversation"
            ).font(
              .headline
            ).lineLimit(2)
            if let id = store.chat?.sessionId ?? store.nativeSession?.sessionId {
              Text("Claude session · " + id).font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }
          Spacer()
          if store.chat != nil {
            Button("Sync history", systemImage: "arrow.clockwise") {
              Task { await store.syncHistory() }
            }.handCursor().disabled(store.busy || store.chat?.status == "running")
          }
          if let chat = store.chat {
            Button("Name & tags", systemImage: "tag") {
              beginEdit(
                "chat:" + chat.id, name: chat.title, key: tagKey(chat: chat), canRename: true)
            }.handCursor()
          } else if let session = store.nativeSession {
            Button("Name & tags", systemImage: "tag") {
              beginEdit(
                "native:" + session.id, name: session.name ?? "Untitled conversation",
                key: session.id, canRename: session.action == "resume")
            }.handCursor()
          }
          Toggle("Follow", isOn: $follow).toggleStyle(.button).handCursor()
          Button {
            details.toggle()
          } label: {
            Image(systemName: "info.circle")
          }.handCursor().help("Session details")
        }.padding(20)
        Divider()
        if let error = store.error {
          HStack {
            Text(error).font(.callout).textSelection(.enabled)
            Spacer()
            Button("Dismiss") { store.error = nil }.handCursor()
          }
          .foregroundStyle(.red).padding(12).background(.red.opacity(0.05))
        }
        if details {
          VStack(alignment: .leading, spacing: 5) {
            Text("Backend: http://127.0.0.1:4318")
            Text("Claude: " + (store.health?.claudeVersion ?? "Not available"))
            Text("History comes from the chat server and Claude session files.")
          }.font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
              if store.messages.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                  Text(store.historyLoading ? "Loading your conversation…" : "What’s the move?")
                    .font(.custom("AvenirNext-Bold", size: 42))
                  Text("A wild idea, a tiny fix, or the next big thing.").font(.title3)
                    .foregroundStyle(.secondary)
                }.padding(.vertical, 70)
              }
              ForEach(store.messages) { MessageBubble(message: $0, showSource: details) }
              if store.historyOffset != nil && store.nativeSession != nil {
                Button("Load more history") { Task { await store.readHistory(reset: false) } }
                  .handCursor().disabled(store.historyLoading)
              }
              if store.chat?.historyNextOffset != nil {
                Button("Load remaining history to continue") {
                  Task { await store.loadChatHistory() }
                }.handCursor().disabled(store.busy)
              }
              Color.clear.frame(height: 1).id("bottom")
            }.frame(maxWidth: 780, alignment: .leading).padding(28).frame(maxWidth: .infinity)
          }.onChange(of: store.messages.last?.content) {
            if follow { proxy.scrollTo("bottom", anchor: .bottom) }
          }
          .onChange(of: follow) { if follow { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
        if let session = store.nativeSession {
          VStack(spacing: 10) {
            Text(
              session.action == "resume"
                ? "Saved Claude conversation · ready to continue"
                : "Read-only history · another Claude process may own this conversation"
            )
            .font(.caption).foregroundStyle(.secondary)
            HStack {
              Button("Refresh history") { Task { await store.readHistory(reset: true) } }
                .handCursor().disabled(
                  store.historyLoading)
              Button("Continue this chat") { Task { await store.importSelected() } }
                .buttonStyle(.borderedProminent).handCursor().disabled(
                  session.action != "resume" || store.busy)
            }
          }.padding(20)
        } else {
          ChatComposer(store: store, composerFocused: $composerFocused)
        }
      }.background(canvas)
    }.tint(accent).preferredColorScheme(.light).frame(minWidth: 900, minHeight: 620)
      .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
        VStack(alignment: .leading, spacing: 16) {
          Text("Name and tags").font(.title2.bold())
          TextField("Conversation name", text: $editName).textFieldStyle(.roundedBorder).disabled(
            !renameAllowed)
          if !renameAllowed {
            Text(
              "This Claude session is active. Its name is protected until its owner exits; you can still tag it."
            ).font(.caption).foregroundStyle(.secondary)
          }
          TextField("Tags, separated by commas", text: $editTags).textFieldStyle(.roundedBorder)
          Text("Names are shared with the chat app. Tags are saved on this Mac; search with #tag.")
            .font(.caption).foregroundStyle(.secondary)
          if let editError { Text(editError).foregroundStyle(.red) }
          HStack {
            Button("Cancel") { editing = nil }.handCursor().disabled(editBusy)
            Spacer()
            Button(editBusy ? "Saving…" : "Save") { Task { await saveEdits() } }.buttonStyle(
              .borderedProminent
            ).handCursor().disabled(editBusy)
          }
        }.padding(24).frame(width: 430).interactiveDismissDisabled(editBusy)
      }
      .task { await store.connect() }
      .task { await store.refreshRepositories() }
      .task {
        while !Task.isCancelled {
          await store.refreshNative()
          do { try await Task.sleep(for: .seconds(10)) } catch { break }
        }
      }
      .task(id: store.selection) { await store.selected() }
  }

}

private struct MessageBubble: View {
  let message: ChatMessage
  let showSource: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(message.role == "user" ? "You" : "Claude").font(.headline)
        if message.status == "streaming" { ProgressView().controlSize(.small) }
        Spacer()
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(message.content, forType: .string)
        } label: {
          Image(systemName: "doc.on.doc")
        }.buttonStyle(.plain).handCursor().help("Copy message")
      }
      if !message.content.isEmpty { MarkdownContent(text: message.content).equatable() }
      if let tools = message.tools {
        ForEach(tools) { tool in
          DisclosureGroup {
            Text(tool.input?.pretty ?? "No input").font(.system(.caption, design: .monospaced))
              .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
          } label: {
            Text("\(tool.name) · \(tool.status)").handCursor()
          }.font(.callout)
        }
      }
      if let error = message.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
      if let usage = message.usage {
        Text("\(usage.inputTokens.formatted()) tokens in · \(usage.outputTokens.formatted()) out")
          .font(.caption).foregroundStyle(.secondary)
      }
      if showSource, let history = message.history {
        DisclosureGroup {
          CodeBlockView(language: "json", code: history.pretty)
        } label: {
          Text("Source details").handCursor()
        }.font(.caption)
      }
    }.padding(18).background(
      message.role == "user" ? Color.purple.opacity(0.07) : Color.white,
      in: RoundedRectangle(cornerRadius: 14))
  }
}
