import Foundation
import MawCore
import Testing

@testable import MawChatV2

@Test func oracleOnlyMatchesProjectNameSuffixNotTitlesOrParentPaths() {
  #expect(WorkspaceListScope.oraclesOnly.includes(projectName: "neo-oracle"))
  #expect(WorkspaceListScope.oraclesOnly.includes(projectName: "NEXUS-ORACLE"))
  for name in [
    "oracle", "omx-grokbot", "neo-oracle-vault", "neo-oracle-worktree", "Local workspace",
  ] {
    #expect(!WorkspaceListScope.oraclesOnly.includes(projectName: name))
    #expect(WorkspaceListScope.all.includes(projectName: name))
  }
}

@Test @MainActor func listScopePersistsAndDoesNotRemoveFavoritesOrTags() throws {
  let suite = "V2ListScope-" + UUID().uuidString
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let prefs = WorkspacePreferences(defaults: defaults)
  #expect(prefs.listScope == .all)
  prefs.favorites = ["/repos/omx-grokbot"]
  prefs.tags = ["session1": ["important"]]
  prefs.listScope = .oraclesOnly
  let restored = WorkspacePreferences(defaults: defaults)
  #expect(restored.listScope == .oraclesOnly)
  #expect(restored.favorites == prefs.favorites)
  #expect(restored.tags == prefs.tags)
  defaults.set("unknown-future-value", forKey: "v2.listScope")
  #expect(WorkspacePreferences(defaults: defaults).listScope == .all)
}

@Test func sidebarScopeCannotBeBypassedByFavoriteSearchOrChatTitle() async {
  let rows = [
    WorkspaceRow(
      id: "chat:neo", title: "Research", preview: "", oracleID: "/neo",
      oracleName: "neo-oracle", tagKey: "neo", updatedAt: 1, isOracle: false, readOnly: false),
    WorkspaceRow(
      id: "chat:other", title: "nexus-oracle", preview: "", oracleID: "/neo-oracle/child",
      oracleName: "worktree", tagKey: "other", updatedAt: 2, isOracle: false, readOnly: false),
  ]
  let index = WorkspaceIndex()
  let filtered = await index.search(
    rows, query: "", favorites: ["/neo-oracle/child"],
    tags: [:], limit: 60, scope: .oraclesOnly)
  #expect(filtered.map(\.id) == ["chat:neo"])
  let searched = await index.search(
    rows, query: "nexus", favorites: [],
    tags: [:], limit: 60, scope: .oraclesOnly)
  #expect(searched.isEmpty)
  let all = await index.search(rows, query: "", favorites: [], tags: [:], limit: 60, scope: .all)
  #expect(all.count == 2)
}

@Test func chooserFiltersBeforeThirtyResultLimitAndRestoresAll() async throws {
  let repositoryJSON =
    (0..<40).map {
      #"{"name":"project-\#($0)","path":"/repos/\#($0)","modifiedAt":100}"#
    } + [#"{"name":"neo-oracle","path":"/repos/neo","modifiedAt":1}"#]
  let repositories = try JSONDecoder().decode(
    [ChatRepository].self,
    from: Data(("[" + repositoryJSON.joined(separator: ",") + "]").utf8))
  let groups = OracleIndex.groups(state: ChatState(), sessions: [], repositories: repositories)
  let index = WorkspaceIndex()
  let filtered = await index.picker(groups: groups, query: "", favorites: [], scope: .oraclesOnly)
  #expect(filtered.groups.map(\.name) == ["neo-oracle"])
  #expect(filtered.total == 1)
  let all = await index.picker(groups: groups, query: "", favorites: [], scope: .all)
  #expect(all.groups.count == 30)
  #expect(all.total == 41)
  let match = await index.picker(groups: groups, query: "neo", favorites: [], scope: .oraclesOnly)
  #expect(match.groups.count == 1)
}
