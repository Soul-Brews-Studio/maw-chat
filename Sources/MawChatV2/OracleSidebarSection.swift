import SwiftUI

struct OracleSidebarSection: View {
  let section: WorkspaceSection
  @Bindable var store: ChatWorkspace
  @Bindable var preferences: WorkspacePreferences
  @Binding var sheet: WorkspaceSheet?
  let isExpanded: Bool
  let threadLimit: Int
  let toggle: () -> Void
  let showMore: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        IconButton(
          title: (isExpanded ? "Collapse " : "Expand ") + section.oracle.oracleName,
          icon: isExpanded ? "chevron.down" : "chevron.right", action: toggle)
        Button {
          if !isExpanded { toggle() }
          store.browseSessions(in: section.id)
        } label: {
          HStack(spacing: 9) {
            Image(systemName: "folder").font(.system(size: 17))
            Text(section.oracle.oracleName).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Spacer(minLength: 0)
            Text("\(section.totalSessions)").font(.system(size: 11))
              .foregroundStyle(WorkspaceTheme.secondary)
          }.frame(maxWidth: .infinity, minHeight: 38).contentShape(Rectangle())
        }.buttonStyle(.plain).handCursor()
          .accessibilityLabel("Browse " + section.oracle.oracleName + " sessions")
          .accessibilityValue("\(section.totalSessions) sessions")
        IconButton(
          title: (preferences.favorites.contains(section.id) ? "Unfavorite " : "Favorite ")
            + section.oracle.oracleName,
          icon: preferences.favorites.contains(section.id) ? "star.fill" : "star"
        ) { preferences.toggleFavorite(section.id) }
      }.padding(.horizontal, 5)
        .contextMenu {
          Button("Browse session cards") {
            store.browseSessions(in: section.id)
          }
          Button("Show only " + section.oracle.oracleName) { store.sidebarOracleID = section.id }
          Button("New thread") { newThread() }
        }
      if isExpanded {
        ForEach(section.threads.prefix(threadLimit)) { row in
          Button {
            store.selection = row.id
            store.browsingSessions = false
          } label: {
            HStack(spacing: 9) {
              Image(systemName: "doc.text").font(.system(size: 14))
              VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.system(size: 13)).lineLimit(1)
                if row.updatedAt > 0 {
                  Text(
                    Date(timeIntervalSince1970: row.updatedAt / 1000),
                    format: .dateTime.day().month(.abbreviated)
                  )
                  .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary)
                }
              }
              Spacer(minLength: 0)
              if row.readOnly {
                Image(systemName: "lock").font(.system(size: 10))
                  .foregroundStyle(WorkspaceTheme.secondary)
              }
            }.padding(.leading, 31).padding(.trailing, 9).frame(minHeight: 43)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                store.selection == row.id ? WorkspaceTheme.selected : .clear,
                in: RoundedRectangle(cornerRadius: 8)
              ).contentShape(Rectangle())
          }.buttonStyle(.plain).handCursor().help(row.title)
            .contextMenu {
              Button("Rename session and tags") {
                store.selection = row.id
                store.browsingSessions = false
                sheet = .edit
              }
              Button("New thread in " + section.oracle.oracleName) { newThread() }
            }
        }
        if section.threads.count > threadLimit {
          let more = min(10, section.threads.count - threadLimit)
          Button("Show \(more) more \(more == 1 ? "session" : "sessions")", action: showMore)
            .buttonStyle(.plain).handCursor().font(.system(size: 11))
            .foregroundStyle(WorkspaceTheme.secondary).padding(.leading, 31).padding(.vertical, 7)
        }
        Button(action: newThread) {
          Label("New thread", systemImage: "plus").font(.system(size: 12))
            .foregroundStyle(WorkspaceTheme.secondary).padding(.leading, 31)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).handCursor().disabled(store.busy)
          .accessibilityLabel("New thread in " + section.oracle.oracleName)
      }
    }.padding(.bottom, 8)
  }
  private func newThread() {
    guard let group = store.sidebarGroups.first(where: { $0.id == section.id }) else { return }
    store.newChat(in: group)
  }
}
