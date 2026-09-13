import MawCore
import SwiftUI

/// Sidebar hierarchy and colorful session drill-down share data, not presentation state.
struct OracleSessionScope: View {
  @Bindable var store: ChatWorkspace
  @Binding var sheet: WorkspaceSheet?
  private var group: OracleGroup? {
    let id = store.browsingSessions ? store.browserOracleID : store.sidebarOracleID
    return store.sidebarGroups.first { $0.id == id }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Button {
          sheet = .sessions
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "folder")
            Text(group?.name ?? (store.browsingSessions ? "All sessions" : "All Oracles"))
              .lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9))
          }.font(.system(size: 13, weight: .medium)).contentShape(Rectangle())
        }.buttonStyle(.plain).handCursor().help("Choose an Oracle to browse its sessions")
        Spacer(minLength: 0)
        if let group {
          IconButton(title: "New conversation in " + group.name, icon: "plus") {
            store.newChat(in: group)
          }.disabled(store.busy)
          if !store.browsingSessions {
            IconButton(title: "Show all Oracles", icon: "xmark.circle") {
              store.sidebarOracleID = nil
            }
          }
        } else {
          IconButton(title: "Refresh sessions", icon: "arrow.clockwise") {
            Task { await store.refreshNative() }
          }
        }
      }.frame(height: 30)
      Button {
        if store.browsingSessions {
          store.browsingSessions = false
        } else {
          store.browseSessions(in: store.sidebarOracleID)
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: store.browsingSessions ? "chevron.left" : "rectangle.grid.1x2")
            .frame(width: 14)
          Text(store.browsingSessions ? "Back to Oracles" : "Browse sessions")
        }.font(.system(size: 12, weight: .medium))
          .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
          .contentShape(Rectangle())
      }.buttonStyle(.plain).handCursor()
      Text(
        group.map { "Recent · \($0.threads.count) sessions · search by name or tag" }
          ?? "Recent chats · favorites first"
      )
      .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary).lineLimit(1).frame(
        height: 14)
    }.padding(.horizontal, 20).padding(.bottom, 10)
  }
}
