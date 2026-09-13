import MawCore
import SwiftUI

struct OracleChooser: View {
  @Bindable var store: ChatWorkspace
  @Bindable var preferences: WorkspacePreferences
  let browsing: Bool
  @State private var query = ""
  @State private var results: [OracleGroup] = []
  @State private var eligibleCount = 0
  @Environment(\.dismiss) private var dismiss
  @FocusState private var focused: Bool
  private struct Query: Equatable {
    let text: String
    let groups: [OracleGroup]
    let favorites: Set<String>
    let scope: WorkspaceListScope
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(browsing ? "Browse Oracle sessions" : "New conversation").font(
          .title2.weight(.semibold))
        Spacer()
        IconButton(title: "Refresh Oracles", icon: "arrow.clockwise") {
          Task {
            await store.refreshRepositories()
            await store.refreshNative()
          }
        }.disabled(store.repositoriesLoading)
      }
      Text(
        browsing
          ? "Choose an Oracle to see all its recent sessions. Star to keep it on top."
          : "Choose an Oracle to start a chat, or browse its saved sessions."
      )
      .font(.callout).foregroundStyle(WorkspaceTheme.secondary)
      WorkspaceListScopePicker(scope: $preferences.listScope)
      TextField("Search Oracles", text: $query).textFieldStyle(.roundedBorder).focused($focused)
      ScrollView {
        LazyVStack(spacing: 4) {
          ForEach(results) { group in
            HStack(spacing: 12) {
              Button {
                if browsing {
                  store.browseSessions(in: group.id)
                } else {
                  preferences.favorites.insert(group.id)
                  store.newChat(in: group)
                }
                dismiss()
              } label: {
                HStack(spacing: 12) {
                  OracleAvatar(name: group.name, size: 34)
                  VStack(alignment: .leading, spacing: 3) {
                    HStack {
                      Text(group.name).fontWeight(.medium).lineLimit(1)
                      Text("\(group.threads.count)").font(.caption)
                        .foregroundStyle(WorkspaceTheme.secondary)
                    }
                    Text(group.path ?? "Local workspace").font(.caption)
                      .foregroundStyle(WorkspaceTheme.secondary).lineLimit(1)
                  }
                  Spacer()
                }.padding(8).contentShape(Rectangle())
              }.buttonStyle(.plain).handCursor().disabled(store.busy)
              IconButton(
                title: browsing
                  ? "New conversation in " + group.name : "View sessions in " + group.name,
                icon: browsing ? "plus" : "list.bullet"
              ) {
                if browsing {
                  store.newChat(in: group)
                } else {
                  store.browseSessions(in: group.id)
                }
                dismiss()
              }.disabled(store.busy)
              IconButton(
                title: preferences.favorites.contains(group.id)
                  ? "Unfavorite " + group.name : "Favorite " + group.name,
                icon: preferences.favorites.contains(group.id) ? "star.fill" : "star"
              ) {
                preferences.toggleFavorite(group.id)
              }
            }
          }
        }
        if results.isEmpty {
          Text(query.isEmpty ? "No projects in this list" : "No matching projects")
            .font(.callout).foregroundStyle(WorkspaceTheme.secondary).padding(.vertical, 24)
        }
      }.frame(height: 260)
      if let warning = store.inventoryWarning {
        DisclosureGroup {
          Text(warning).font(.caption).foregroundStyle(WorkspaceTheme.secondary)
            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        } label: {
          Label("Repository discovery is limited", systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(WorkspaceTheme.secondary).handCursor()
        }
      }
      HStack {
        Text("\(eligibleCount) projects · \(results.count) shown")
          .font(.caption).foregroundStyle(WorkspaceTheme.secondary)
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).handCursor()
      }
    }.frame(width: 470).task { focused = true }
      .task(
        id: Query(
          text: query, groups: store.sidebarGroups, favorites: preferences.favorites,
          scope: preferences.listScope)
      ) {
        let found = await store.rowWorker.picker(
          groups: store.sidebarGroups, query: query,
          favorites: preferences.favorites, scope: preferences.listScope)
        if !Task.isCancelled {
          results = found.groups
          eligibleCount = found.total
        }
      }
  }
}
