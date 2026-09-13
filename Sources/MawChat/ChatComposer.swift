import MawCore
import SwiftUI

/// Reads draft state here, not in the parent workspace/outline body.
struct ChatComposer: View {
  @Bindable var store: ChatWorkspace
  @FocusState.Binding var composerFocused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      TextField("Message Claude…", text: $store.draft, axis: .vertical).lineLimit(3...7)
        .focused($composerFocused)
        .textFieldStyle(.plain).padding(16).background(
          .white, in: RoundedRectangle(cornerRadius: 14))
      HStack {
        if store.project == nil, let path = store.draftPath {
          Label(store.draftProjectName ?? path, systemImage: "folder")
            .lineLimit(1).help(path)
        } else {
          Picker(
            "Project",
            selection: Binding(
              get: { store.project },
              set: { id in
                store.project = id
                let project = store.state.projects.first { $0.id == id }
                store.draftPath = project.map { OracleIndex.normalize($0.canonicalPath ?? $0.path) }
                store.draftProjectName = project?.name
              }
            )
          ) {
            Text("Local workspace").tag(Optional<String>.none)
            ForEach(store.state.projects) { Text($0.name).tag(Optional($0.id)) }
          }.frame(maxWidth: 210).handCursor().disabled(store.chat != nil || store.busy)

        }
        Picker("Model", selection: $store.model) {
          Text("Sonnet").tag("sonnet")
          Text("Opus").tag("opus")
          Text("Haiku").tag("haiku")
        }.frame(maxWidth: 145).handCursor().disabled(store.busy || store.chat?.status == "running")
          .onChange(of: store.model) {
            if store.chat?.model != store.model { Task { await store.updateOptions() } }
          }
        Picker("Permissions", selection: $store.permission) {
          Text("Default").tag("default")
          Text("Full access").tag("bypassPermissions")
        }.frame(maxWidth: 190).handCursor().disabled(store.busy || store.chat?.status == "running")
          .onChange(of: store.permission) {
            if store.chat?.permissionMode != store.permission {
              Task { await store.updateOptions() }
            }
          }
        Spacer()
        if store.chat?.status == "running" {
          Button("Stop", systemImage: "stop.fill") { Task { await store.stop() } }.tint(.red)
            .handCursor()
        } else {
          Button("Send", systemImage: "arrow.up") { Task { await store.send() } }
            .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
            .handCursor()
            .disabled(
              store.busy || !store.connected
                || store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || store.chat?.historyNextOffset != nil)
        }
      }
      Text(
        store.permission == "bypassPermissions"
          ? "Full access lets Claude run commands and modify files without approval."
          : "Claude Code · shared chat backend · ⌘ Return to send"
      )
      .font(.caption).foregroundStyle(
        store.permission == "bypassPermissions" ? .orange : .secondary)
      if let sync = store.chat?.sync {
        Text(sync.status == "synced" ? "Synced with Claude" : (sync.error ?? "History sync failed"))
          .font(.caption).foregroundStyle(.secondary)
      }
    }.padding(20)
  }
}
