import MawCore
import SwiftUI

enum WorkspaceSheet: String, Identifiable {
  case oracle, sessions, settings, edit, marketplace, members, routines
  var id: String { rawValue }
}

struct WorkspaceSheetView: View {
  let kind: WorkspaceSheet
  @Bindable var store: ChatWorkspace
  @Bindable var preferences: WorkspacePreferences
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(spacing: 0) {
      switch kind {
      case .oracle: OracleChooser(store: store, preferences: preferences, browsing: false)
      case .sessions: OracleChooser(store: store, preferences: preferences, browsing: true)
      case .edit: ConversationEditor(store: store, preferences: preferences)
      case .settings: ProviderSettings(store: store, preferences: preferences)
      case .marketplace:
        explanation(
          "Marketplace", icon: "square.grid.2x2",
          detail:
            "This server provides your Oracle repositories, not a bot marketplace. Choose an Oracle from Your workspace to start a conversation."
        )
      case .members:
        explanation(
          "Group members", icon: "person.2",
          detail:
            "This conversation belongs to \(store.oracleName) and uses Claude Code. The shared server does not expose multi-bot group routing. Choose Oracle starts a separate conversation; it does not add a group member."
        )
      case .routines:
        explanation(
          "Routines", icon: "clock",
          detail:
            "No routine service is configured on the shared chat server. This lab does not schedule or run background prompts."
        )
      }
    }.padding(24).frame(width: kind == .oracle || kind == .sessions ? 518 : 468)
      .fixedSize(horizontal: true, vertical: true)
      .background(WorkspaceTheme.sidebar).foregroundStyle(WorkspaceTheme.foreground)
  }
  private func explanation(_ title: String, icon: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Label(title, systemImage: icon).font(.title2.weight(.semibold))
      Text(detail).foregroundStyle(WorkspaceTheme.secondary).fixedSize(
        horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).handCursor()
      }
    }.frame(width: 420)
  }
}

struct ProviderSettings: View {
  @Bindable var store: ChatWorkspace
  @Bindable var preferences: WorkspacePreferences
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Workspace settings").font(.title2.weight(.semibold))
      WorkspaceListScopePicker(scope: $preferences.listScope)
      Text("Applies to the sidebar and Oracle chooser. Favorites and chats are kept when hidden.")
        .font(.caption).foregroundStyle(WorkspaceTheme.secondary)
      Divider()
      LabeledContent("Server", value: "http://127.0.0.1:4318")
      LabeledContent("Provider", value: "Claude Code")
      LabeledContent("Connection", value: store.connected ? "Live SSE connected" : "Reconnecting")
      LabeledContent("Version", value: store.health?.claudeVersion ?? "Unavailable")
      LabeledContent(
        "Claude available", value: store.health?.claudeAvailable == true ? "Yes" : "No")
      if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
      Picker("Model", selection: $store.model) {
        Text("Sonnet").tag("sonnet")
        Text("Opus").tag("opus")
        Text("Haiku").tag("haiku")
      }.handCursor().disabled(store.nativeSession != nil || store.chat?.status == "running")
      Picker("Permissions", selection: $store.permission) {
        Text("Default").tag("default")
        Text("Accept edits").tag("acceptEdits")
        Text("Plan only").tag("plan")
      }.handCursor().disabled(store.nativeSession != nil || store.chat?.status == "running")
      Text(
        "New conversations always start with Default permissions. The server controls execution and saved history."
      )
      .font(.caption).foregroundStyle(WorkspaceTheme.secondary)
      HStack {
        Button("Check connection") { Task { await store.checkConnection() } }
          .handCursor()
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).handCursor()
      }
    }.frame(width: 420)
      .onChange(of: store.permission) {
        if let chat = store.chat, chat.permissionMode != store.permission {
          Task { await store.updateOptions() }
        }
      }
  }
}

struct ConversationEditor: View {
  @Bindable var store: ChatWorkspace
  @Bindable var preferences: WorkspacePreferences
  @State private var name = ""
  @State private var tags = ""
  @State private var error: String?
  @State private var saving = false
  @Environment(\.dismiss) private var dismiss
  private var tagKey: String {
    store.chat?.sessionId ?? store.nativeSession?.sessionId ?? store.selection ?? ""
  }
  private var canRename: Bool {
    store.nativeSession == nil || store.nativeSession?.action == "resume"
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Name and tags").font(.title2.weight(.semibold))
      TextField("Conversation name", text: $name).textFieldStyle(.roundedBorder).disabled(
        !canRename)
      TextField("Tags, comma separated", text: $tags).textFieldStyle(.roundedBorder)
      Text("Tags are saved locally in v2. Names are shared with the web frontend.")
        .font(.caption).foregroundStyle(WorkspaceTheme.secondary)
      if let error { Text(error).foregroundStyle(.red) }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).handCursor()
        Spacer()
        Button("Save") { Task { await save() } }.keyboardShortcut(.defaultAction)
          .handCursor().disabled(
            saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.frame(width: 420)
      .onAppear {
        name = store.title
        tags = (preferences.tags[tagKey] ?? []).joined(separator: ", ")
      }
  }
  private func save() async {
    saving = true
    defer { saving = false }
    do {
      let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
      if canRename && title != store.title {
        if let id = store.chat?.id {
          _ = try await store.backend.rename(id, title: title)
        } else if let id = store.nativeSession?.sessionId {
          try await store.backend.renameNative(id, title: title)
          await store.refreshNative()
        }
      }
      preferences.tags[tagKey] = ConversationIndex.parseTags(tags)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
