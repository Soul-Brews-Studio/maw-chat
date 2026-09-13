import MawCore
import SwiftUI

struct SidebarSessionCard: View {
  let row: WorkspaceRow
  let query: String
  @Bindable var store: ChatWorkspace
  @Bindable var preferences: WorkspacePreferences
  @Binding var sheet: WorkspaceSheet?
  var body: some View {
    Button {
      select()
    } label: {
      HStack(spacing: 10) {
        OracleAvatar(name: row.oracleName, size: 38)
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(row.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            if preferences.favorites.contains(row.oracleID) {
              Image(systemName: "star.fill").font(.system(size: 9))
                .foregroundStyle(WorkspaceTheme.secondary)
            }
            if row.updatedAt > 0 {
              Text(
                Date(timeIntervalSince1970: row.updatedAt / 1000),
                format: .dateTime.day().month(.abbreviated)
              )
              .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary)
            }
          }
          Text(row.oracleName).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
            .lineLimit(1)
          Text(row.preview).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary)
            .lineLimit(1)
        }
        if row.readOnly { Image(systemName: "lock").font(.system(size: 10)) }
      }.padding(.horizontal, 10).frame(height: 82)
        .background(
          store.selection == row.id ? WorkspaceTheme.selected : .clear,
          in: RoundedRectangle(cornerRadius: 12)
        )
        .contentShape(Rectangle())
    }.buttonStyle(.plain).handCursor().help(row.title)
      .contextMenu {
        Button("Rename session and tags") { if select() { sheet = .edit } }
        Button(
          preferences.favorites.contains(row.oracleID) ? "Unfavorite Oracle" : "Favorite Oracle"
        ) {
          preferences.toggleFavorite(row.oracleID)
        }
      }
  }
  @discardableResult private func select() -> Bool {
    guard store.browsingSessions,
      store.rows.contains(where: {
        $0.id == row.id && $0.oracleID == row.oracleID && $0.tagKey == row.tagKey
      }),
      store.browserOracleID == nil || store.browserOracleID == row.oracleID,
      preferences.listScope.includes(projectName: row.oracleName),
      ConversationIndex.matches(
        query: query, title: row.title,
        project: row.oracleName + " " + row.oracleID, sessionID: row.tagKey,
        tags: preferences.tags[row.tagKey] ?? [])
    else { return false }
    store.selection = row.id
    return true
  }
}
