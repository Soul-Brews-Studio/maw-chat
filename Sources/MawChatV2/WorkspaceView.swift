import MawCore
import SwiftUI

struct WorkspaceView: View {
  @State private var store = ChatWorkspace()
  @State private var preferences = WorkspacePreferences()
  @State private var sheet: WorkspaceSheet?
  var body: some View {
    GeometryReader { geometry in
      let layout = WorkspaceLayout(
        width: geometry.size.width, inspectorPreferred: preferences.inspector)
      HStack(spacing: 0) {
        WorkspaceSidebar(store: store, preferences: preferences, sheet: $sheet)
          .frame(width: layout.sidebar)
        Rectangle().fill(WorkspaceTheme.separator).frame(width: 1)
        VStack(spacing: 0) {
          WorkspaceHeader(store: store, preferences: preferences, sheet: $sheet)
          Rectangle().fill(WorkspaceTheme.separator).frame(height: 1)
          WorkspaceTranscript(store: store)
          WorkspaceComposer(store: store, preferences: preferences, sheet: $sheet)
        }.frame(maxWidth: .infinity)
        if layout.showsInspector {
          Rectangle().fill(WorkspaceTheme.separator).frame(width: 1)
          WorkspaceInspector(store: store, preferences: preferences, sheet: $sheet)
            .frame(width: layout.inspector)
        }
      }
    }.background(WorkspaceTheme.background).foregroundStyle(WorkspaceTheme.foreground)
      .font(.system(size: 14)).preferredColorScheme(.dark).tint(.white)
      .ignoresSafeArea()
      .sheet(item: $sheet) { selected in
        WorkspaceSheetView(kind: selected, store: store, preferences: preferences)
          .preferredColorScheme(.dark)
      }
      .task { await store.connect() }
      .task { await store.refreshRepositories() }
      .task {
        while !Task.isCancelled {
          await store.refreshNative()
          do { try await Task.sleep(for: .seconds(15)) } catch { return }
        }
      }
      .task(id: store.selection) { await store.selected() }
  }
}

struct WorkspaceHeader: View {
  @Bindable var store: ChatWorkspace
  @Bindable var preferences: WorkspacePreferences
  @Binding var sheet: WorkspaceSheet?
  var body: some View {
    HStack(spacing: 11) {
      OracleAvatar(name: store.oracleName, size: 24)
      Text(store.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
      Spacer(minLength: 8)
      IconButton(title: "View sessions in " + store.oracleName, icon: "list.bullet") {
        if let group = store.sidebarGroups.first(where: { group in
          group.threads.contains(where: { $0.id == store.selection })
        }), preferences.listScope.includes(projectName: group.name) {
          store.browseSessions(in: group.id)
        } else {
          sheet = .sessions
        }
      }
      Button {
        sheet = .edit
      } label: {
        Label("Rename", systemImage: "pencil").font(.system(size: 12))
      }.buttonStyle(.plain).handCursor().help("Rename this session and edit tags")
        .accessibilityLabel("Rename session and tags")
        .disabled(store.selection == nil)
      Menu {
        Button("Sync saved history") { Task { await store.syncHistory() } }
          .disabled(store.chat == nil || store.busy || store.chat?.status == "running")
        Button("Load more server history") { Task { await store.loadChatHistory() } }
          .disabled(store.chat?.historyNextOffset == nil || store.busy)
        Button("Refresh sessions") { Task { await store.refreshNative() } }
      } label: {
        HStack(spacing: 2) {
          Image(systemName: "clock.arrow.circlepath")
          Image(systemName: "chevron.down").font(.system(size: 8))
        }.frame(height: 30)
      }.menuStyle(.borderlessButton).fixedSize().handCursor()
        .foregroundStyle(WorkspaceTheme.secondary).help("History")
      IconButton(title: "Toggle inspector", icon: "sidebar.right") {
        preferences.inspector.toggle()
      }
    }.padding(.horizontal, 18).frame(height: 52)
  }
}
