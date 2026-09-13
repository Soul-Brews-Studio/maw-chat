import SwiftUI

struct WorkspaceComposer: View {
  @Bindable var store: ChatWorkspace
  @Bindable var preferences: WorkspacePreferences
  @Binding var sheet: WorkspaceSheet?
  @State private var focusRequest = 0
  @State private var mentionRequest = 0
  private var running: Bool { store.chat?.status == "running" }
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      if let error = store.error {
        HStack {
          Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
          Spacer()
          IconButton(title: "Dismiss error", icon: "xmark") { store.error = nil }
        }
      }
      if store.selection != nil && store.chat == nil && store.nativeSession == nil {
        Text("Conversation unavailable. Refresh sessions or choose a new Oracle.")
          .font(.caption).foregroundStyle(WorkspaceTheme.secondary)
      }
      if let native = store.nativeSession {
        HStack {
          Text(
            native.action == "resume"
              ? "Saved Claude session · resume to reply" : "Active elsewhere · read only"
          )
          .font(.caption).foregroundStyle(WorkspaceTheme.secondary)
          Spacer()
          if native.action == "resume" {
            Button("Resume") { Task { await store.importSelected() } }.handCursor().disabled(
              store.busy)
          }
        }
      }
      HStack(spacing: 9) {
        Text("Provider").font(.system(size: 15)).foregroundStyle(WorkspaceTheme.secondary)
        Menu {
          Text("Claude Code · shared local server")
          Divider()
          Picker("Model", selection: $store.model) {
            Text("Sonnet").tag("sonnet")
            Text("Opus").tag("opus")
            Text("Haiku").tag("haiku")
          }
        } label: {
          Text("claude")
        }
        .menuStyle(.borderlessButton).padding(.horizontal, 12).frame(width: 147, height: 24)
        .background(WorkspaceTheme.bubble, in: RoundedRectangle(cornerRadius: 6))
        .handCursor().disabled(running || store.nativeSession != nil)
        IconButton(title: "Provider settings", icon: "gearshape") { sheet = .settings }
        Spacer()
      }
      HStack {
        Text("Reply as").font(.system(size: 15)).foregroundStyle(WorkspaceTheme.secondary)
        Spacer()
        Button {
          mentionRequest &+= 1
        } label: {
          HStack {
            Text("Mention")
            Image(systemName: "chevron.down").font(.caption)
          }
          .padding(.horizontal, 12).frame(height: 25)
          .background(WorkspaceTheme.bubble, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).handCursor().disabled(!store.canCompose)
        Button {
          sheet = .oracle
        } label: {
          HStack {
            Text("Choose Oracle")
            Image(systemName: "chevron.down").font(.caption)
          }
          .padding(.horizontal, 12).frame(height: 25)
          .background(WorkspaceTheme.bubble, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).handCursor().disabled(store.busy || running)
      }
      Text(
        "Type @ to reference an Oracle or session. Context is metadata, not conversation history."
      )
      .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary)
      Text("To: http://127.0.0.1:4318 · \(store.model) · \(store.oracleName)")
        .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary).lineLimit(1).help(
          store.oracleName)
      Text(
        "Sends your draft and quoted reply through the shared chat server. Permissions: \(store.permission). Saved sessions remain on this Mac."
      )
      .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary).fixedSize(
        horizontal: false, vertical: true)
      if let reply = store.reply {
        HStack(alignment: .top) {
          RoundedRectangle(cornerRadius: 2).fill(WorkspaceTheme.green).frame(width: 3)
          VStack(alignment: .leading, spacing: 3) {
            Text(reply.sender).font(.caption.weight(.semibold))
            Text(reply.text).lineLimit(2).font(.caption).foregroundStyle(WorkspaceTheme.secondary)
          }
          Spacer()
          IconButton(title: "Cancel reply", icon: "xmark") { store.reply = nil }
        }.padding(10).frame(maxHeight: 70)
          .background(WorkspaceTheme.sidebar, in: RoundedRectangle(cornerRadius: 9))
      }
      HStack(alignment: .bottom, spacing: 10) {
        Button {
          sheet = .oracle
        } label: {
          Image(systemName: "plus").font(.system(size: 23, weight: .light))
            .frame(width: 33, height: 33).background(WorkspaceTheme.selected, in: Circle())
        }.buttonStyle(.plain).handCursor().help("Choose Oracle for a new conversation")
          .disabled(store.busy || running)
        MentionComposerField(
          store: store, preferences: preferences,
          mentionRequest: mentionRequest, focusRequest: focusRequest
        ).zIndex(1)
        Button {
          Task { if running { await store.stop() } else { await store.send() } }
        } label: {
          Image(systemName: running ? "stop.fill" : "arrow.up")
            .font(.system(size: 21, weight: .medium)).foregroundStyle(WorkspaceTheme.background)
            .frame(width: 33, height: 33).background(WorkspaceTheme.secondary, in: Circle())
        }.buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command)
          .handCursor().disabled(
            (!running && !store.providerReady) || store.busy || !store.canCompose
              || (!running && store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          )
          .accessibilityLabel(running ? "Stop generation" : "Send message").help("⌘Return to send")
      }.padding(.horizontal, 9).padding(.vertical, 7)
        .background(WorkspaceTheme.composer, in: RoundedRectangle(cornerRadius: 27))
        .overlay(RoundedRectangle(cornerRadius: 27).stroke(WorkspaceTheme.selected))
    }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 20)
      .onChange(of: store.model) {
        if let chat = store.chat, chat.model != store.model { Task { await store.updateOptions() } }
      }
      .onChange(of: store.reply) { if store.reply != nil { focusRequest &+= 1 } }
  }
}
