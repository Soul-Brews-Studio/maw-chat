import Foundation
import MawCore
import Testing

@testable import MawChatV2

@Test func oracleSessionListIncludesAllSavedSessionsNewestFirstBeforeLimit() async {
  func row(_ id: String, oracle: String = "/neo", date: Double, isOracle: Bool = false)
    -> WorkspaceRow
  {
    WorkspaceRow(
      id: id, title: id == "native:recent" ? "Research database" : id,
      preview: "", oracleID: oracle, oracleName: oracle == "/neo" ? "neo-oracle" : "nexus-oracle",
      tagKey: id, updatedAt: date, isOracle: isOracle, readOnly: false)
  }
  let rows = [
    row("native:old", date: 1), row("chat:other", oracle: "/nexus", date: 500),
    row("oracle:/neo", date: 1000, isOracle: true), row("native:recent", date: 30),
    row("chat:middle", date: 20),
  ]
  let index = WorkspaceIndex()
  let recent = await index.search(
    rows, query: "", favorites: ["/nexus"], tags: [:], limit: 2,
    oracleID: "/neo")
  #expect(recent.map(\.id) == ["native:recent", "chat:middle"])
  let named = await index.search(
    rows, query: "research", favorites: [], tags: [:], limit: 60,
    oracleID: "/neo")
  #expect(named.map(\.id) == ["native:recent"])
  let tagged = await index.search(
    rows, query: "#keep", favorites: [], tags: ["native:old": ["keep"]],
    limit: 60, oracleID: "/neo")
  #expect(tagged.map(\.id) == ["native:old"])
  let all = await index.search(rows, query: "", favorites: [], tags: [:], limit: 60)
  #expect(all.map(\.id) == ["chat:other", "chat:middle"])
}

@Test @MainActor func refreshedInventoryCannotLeaveAnInvisibleOracleFilter() {
  let store = ChatWorkspace()
  store.sidebarOracleID = "/disappeared/project"
  store.browserOracleID = "/disappeared/project"
  store.sidebarGroups = []
  #expect(store.sidebarOracleID == nil)
  #expect(store.browserOracleID == nil)
}

@Test func groupedSidebarNestsSavedSessionsAndKeepsSearchAndFavoritesBounded() async {
  func row(_ id: String, oracle: String, title: String, date: Double, group: Bool = false)
    -> WorkspaceRow
  {
    WorkspaceRow(
      id: id, title: title, preview: "", oracleID: oracle, oracleName: oracle,
      tagKey: id, updatedAt: date, isOracle: group, readOnly: false)
  }
  let rows = [
    row("oracle:neo", oracle: "neo-oracle", title: "neo-oracle", date: 0, group: true),
    row("chat:neo", oracle: "neo-oracle", title: "Earlier", date: 10),
    row("native:neo", oracle: "neo-oracle", title: "Research", date: 20),
    row("oracle:nexus", oracle: "nexus-oracle", title: "nexus-oracle", date: 0, group: true),
    row("chat:nexus", oracle: "nexus-oracle", title: "Latest elsewhere", date: 50),
  ]
  let index = WorkspaceIndex()
  let groups = await index.sections(rows, query: "", favorites: ["neo-oracle"], tags: [:], limit: 1)
  #expect(groups.count == 1)
  #expect(groups[0].oracle.oracleID == "neo-oracle")
  #expect(groups[0].threads.map(\.id) == ["native:neo", "chat:neo"])
  #expect(groups[0].totalSessions == 2)
  let named = await index.sections(rows, query: "research", favorites: [], tags: [:], limit: 20)
  #expect(named.count == 1)
  #expect(named[0].threads.map(\.id) == ["native:neo"])
  #expect(named[0].totalSessions == 2)
  let project = await index.sections(rows, query: "neo-oracle", favorites: [], tags: [:], limit: 20)
  #expect(project.count == 1)
  #expect(project[0].threads.count == 2)
}

@Test func sessionCardsIncludeUnfavoritedSavedSessionsButNeverProjectPlaceholders() async {
  let rows = [
    WorkspaceRow(
      id: "oracle:neo", title: "neo-oracle", preview: "", oracleID: "neo", oracleName: "neo-oracle",
      tagKey: "neo", updatedAt: 40, isOracle: true, readOnly: false),
    WorkspaceRow(
      id: "native:saved", title: "Research", preview: "", oracleID: "neo", oracleName: "neo-oracle",
      tagKey: "saved", updatedAt: 20, isOracle: false, readOnly: false),
    WorkspaceRow(
      id: "chat:other", title: "Other", preview: "", oracleID: "other", oracleName: "project",
      tagKey: "other", updatedAt: 30, isOracle: false, readOnly: false),
  ]
  let index = WorkspaceIndex()
  let all = await index.sessions(
    rows, query: "", favorites: [], tags: [:], limit: 60, scope: .all, oracleID: nil)
  #expect(all.map(\.id) == ["chat:other", "native:saved"])
  let named = await index.sessions(
    rows, query: "research", favorites: [], tags: [:], limit: 1, scope: .oraclesOnly,
    oracleID: "neo")
  #expect(named.map(\.id) == ["native:saved"])
}

@Test @MainActor func browsingAnOracleKeepsTheTreeAndConversationIndependent() {
  let store = ChatWorkspace()
  store.selection = "chat:existing"
  store.draft = "Unsent draft"
  store.browseSessions(in: "neo")
  #expect(store.browserOracleID == "neo")
  #expect(store.sidebarOracleID == nil)
  #expect(store.browsingSessions)
  #expect(store.selection == "chat:existing")
  #expect(store.draft == "Unsent draft")
  store.browseSessions()
  #expect(store.browserOracleID == nil)
}
