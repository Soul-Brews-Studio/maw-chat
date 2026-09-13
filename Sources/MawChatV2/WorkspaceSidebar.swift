import MawCore
import SwiftUI

struct WorkspaceSidebar: View {
  @Bindable var store: ChatWorkspace
  @Bindable var preferences: WorkspacePreferences
  @Binding var sheet: WorkspaceSheet?
  @State private var query = ""
  @State private var results: [WorkspaceSection] = []
  @State private var sessionResults: [WorkspaceRow] = []
  @State private var collapsed: Set<String> = []
  @State private var expanded: Set<String> = []
  @State private var threadLimits: [String: Int] = [:]
  @State private var limit = 20
  @FocusState private var searchFocused: Bool
  private struct SearchKey: Equatable {
    let rows: [WorkspaceRow]
    let query: String
    let favorites: Set<String>
    let tags: [String: [String]]
    let limit: Int
    let scope: WorkspaceListScope
    let oracleID: String?
    let browsing: Bool
    let browserOracleID: String?
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()
        IconButton(title: "New conversation · Choose Oracle", icon: "plus") { sheet = .oracle }
          .keyboardShortcut("n", modifiers: .command)
      }.padding(.trailing, 18).frame(height: 52)
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").foregroundStyle(WorkspaceTheme.secondary)
        TextField(
          store.browsingSessions ? "Search sessions" : "Search Oracles or sessions", text: $query
        ).textFieldStyle(.plain)
          .font(.system(size: 16)).focused($searchFocused).accessibilityLabel(
            "Search conversations")
        if !query.isEmpty {
          IconButton(title: "Clear search", icon: "xmark.circle.fill") { query = "" }
        }
      }.padding(.horizontal, 12).frame(height: 38)
        .background(WorkspaceTheme.bubble, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(WorkspaceTheme.separator))
        .padding(.horizontal, 13).padding(.bottom, 9)
      OracleSessionScope(store: store, sheet: $sheet)
      ScrollView {
        LazyVStack(spacing: 5) {
          if store.browsingSessions {
            ForEach(sessionResults) { row in
              SidebarSessionCard(
                row: row, query: query, store: store, preferences: preferences, sheet: $sheet)
            }
            if sessionResults.count == limit {
              Button("Show more sessions") { limit += 60 }.buttonStyle(.plain).handCursor().padding(
                12)
            }
          } else {
            ForEach(results) { section in
              OracleSidebarSection(
                section: section, store: store, preferences: preferences, sheet: $sheet,
                isExpanded: !collapsed.contains(section.id)
                  && (expanded.contains(section.id) || preferences.favorites.contains(section.id)
                    || store.sidebarOracleID == section.id || !query.isEmpty),
                threadLimit: threadLimits[section.id, default: 5],
                toggle: { toggle(section.id) },
                showMore: { threadLimits[section.id, default: 5] += 10 })
            }
            if results.count == limit {
              Button("Show more Oracles") { limit += 20 }
                .buttonStyle(.plain).padding(12).handCursor()
            }
          }
          if store.browsingSessions ? sessionResults.isEmpty : results.isEmpty {
            VStack(spacing: 10) {
              Text(query.isEmpty ? "No sessions in this view" : "No matching sessions")
              Button("Choose Oracle") { sheet = store.browsingSessions ? .sessions : .oracle }
                .handCursor()
            }.foregroundStyle(WorkspaceTheme.secondary).padding(.top, 24)
          }
        }.padding(.horizontal, 13)
      }
      VStack(alignment: .leading, spacing: 15) {
        Button {
          sheet = .marketplace
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2").font(.system(size: 19))
              .frame(width: 34, height: 34).background(WorkspaceTheme.bubble, in: Circle())
            Text("Marketplace").font(.system(size: 16, weight: .medium))
          }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).handCursor()
        Button {
          sheet = .sessions
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 34))
              .foregroundStyle(Color(red: 0.46, green: 0.64, blue: 0.92))
            Text("Your workspace").font(.system(size: 16, weight: .medium))
          }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).handCursor().keyboardShortcut("o", modifiers: .command)
        HStack(spacing: 5) {
          Circle().fill(store.connected ? .orange : .red).frame(width: 5, height: 5)
          Text(
            store.providerReady
              ? "Shared local server · Claude ready"
              : store.connected
                ? "Server connected · Claude unavailable" : "Server offline · reconnecting…"
          )
          .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary)
        }
      }.padding(.horizontal, 21).padding(.vertical, 15)
    }.background(WorkspaceTheme.sidebar)
      .background {
        Button("Focus search") { searchFocused = true }.keyboardShortcut("k", modifiers: .command)
          .hidden().accessibilityHidden(true)
      }
      .onChange(of: query) {
        limit = store.browsingSessions ? 60 : 20
        sessionResults = []
        results = []
        collapsed = []
        threadLimits = [:]
      }
      .onChange(of: store.selection) {
        if let row = store.rows.first(where: { $0.id == store.selection }) {
          expanded.insert(row.oracleID)
          collapsed.remove(row.oracleID)
        }
      }
      .onChange(of: preferences.listScope) {
        sessionResults = []
        results = []
        limit = store.browsingSessions ? 60 : 20
        if let group = store.sidebarGroups.first(where: { $0.id == store.browserOracleID }),
          !preferences.listScope.includes(projectName: group.name)
        {
          store.browserOracleID = nil
        }
        if let group = store.sidebarGroups.first(where: { $0.id == store.sidebarOracleID }),
          !preferences.listScope.includes(projectName: group.name)
        {
          store.sidebarOracleID = nil
        }
      }
      .onChange(of: store.browserOracleID) {
        sessionResults = []
        query = ""
        limit = 60
      }
      .onChange(of: store.browsingSessions) {
        sessionResults = []
        query = ""
        limit = store.browsingSessions ? 60 : 20
      }
      .onChange(of: store.sidebarOracleID) {
        query = ""
        limit = 20
      }
      .task(
        id: SearchKey(
          rows: store.rows, query: query, favorites: preferences.favorites,
          tags: preferences.tags, limit: limit, scope: preferences.listScope,
          oracleID: store.sidebarOracleID, browsing: store.browsingSessions,
          browserOracleID: store.browserOracleID)
      ) {
        if store.browsingSessions {
          let found = await store.rowWorker.sessions(
            store.rows, query: query,
            favorites: preferences.favorites, tags: preferences.tags, limit: limit,
            scope: preferences.listScope, oracleID: store.browserOracleID)
          guard !Task.isCancelled else { return }
          sessionResults = found
        } else {
          let found = await store.rowWorker.sections(
            store.rows, query: query, favorites: preferences.favorites, tags: preferences.tags,
            limit: limit, scope: preferences.listScope, oracleID: store.sidebarOracleID)
          guard !Task.isCancelled else { return }
          results = found
        }
      }
  }
  private func toggle(_ id: String) {
    if collapsed.remove(id) != nil {
      expanded.insert(id)
      return
    }
    let currentlyExpanded =
      expanded.contains(id) || preferences.favorites.contains(id)
      || store.sidebarOracleID == id || !query.isEmpty
    if currentlyExpanded {
      collapsed.insert(id)
      expanded.remove(id)
    } else {
      expanded.insert(id)
    }
  }
}
