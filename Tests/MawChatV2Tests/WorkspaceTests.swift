import Foundation
import MawCore
import Testing

@testable import MawChatV2

private func stateFixture() throws -> ChatState {
  try JSONDecoder().decode(
    ChatState.self,
    from: Data(
      #"""
      {"projects":[{"id":"neo","name":"neo-oracle","path":"/repos/neo"},
        {"id":"nexus","name":"nexus-oracle","path":"/repos/nexus"}],"chats":[
        {"id":"n1","title":"Neo research","projectId":"neo","sessionId":"session1",
          "model":"sonnet","permissionMode":"default","status":"idle",
          "updatedAt":"2026-09-13T12:00:00.000Z","messages":[
            {"id":"m1","role":"assistant","content":"Actual server content",
             "createdAt":"2026-09-13T12:00:00.000Z"}]},
        {"id":"x1","title":"Nexus notes","projectId":"nexus","model":"sonnet",
          "permissionMode":"default","status":"running","messages":[]}]}
      """#.utf8))
}

@Test func v2ProjectsRealConversationsAndPreviewsWithoutInventingData() async throws {
  let state = try stateFixture()
  let groups = OracleIndex.groups(state: state, sessions: [])
  let index = WorkspaceIndex()
  let rows = await index.rows(groups: groups, state: state)
  #expect(rows.filter { !$0.isOracle }.count == 2)
  #expect(rows.first { $0.id == "chat:n1" }?.preview == "Actual server content")
  #expect(rows.first { $0.id == "chat:n1" }?.oracleID == "/repos/neo")
  #expect(rows.first { $0.id == "chat:n1" }?.tagKey == "session1")
  let result = await index.search(rows, query: "nexus", favorites: [], tags: [:], limit: 60)
  #expect(Set(result.map(\.id)) == ["chat:x1", "oracle:/repos/nexus"])
}

@Test func v2FavoritesLeadAndSearchIncludesUnpinnedSessionsAndTags() async throws {
  let state = try stateFixture()
  let native = try JSONDecoder().decode(
    [NativeChatSession].self,
    from: Data(
      #"""
      [{"sessionId":"native1","name":"Hidden saved discussion","cwd":"/repos/neo",
      "kind":"saved","action":"resume"}]
      """#.utf8))
  let index = WorkspaceIndex()
  let rows = await index.rows(
    groups: OracleIndex.groups(state: state, sessions: native), state: state)
  let normal = await index.search(rows, query: "", favorites: [], tags: [:], limit: 60)
  #expect(normal.count == 2)
  let favorites = await index.search(
    rows, query: "", favorites: ["/repos/nexus"], tags: [:], limit: 60)
  #expect(favorites.first?.oracleID == "/repos/nexus")
  let tagged = await index.search(
    rows, query: "#important", favorites: [],
    tags: ["native1": ["important"]], limit: 60)
  #expect(tagged.map(\.id) == ["native:native1"])
  let bounded = await index.search(rows, query: "neo", favorites: [], tags: [:], limit: 1)
  #expect(bounded.count == 1)
}

@Test func messageDatesPreserveActualBackendTimestamp() throws {
  let message = try stateFixture().chats[0].messages[0]
  #expect(MessageDate.parse(message.createdAt)?.timeIntervalSince1970 == 1_789_300_800)
  #expect(MessageDate.parse("2026-09-13T12:00:00Z") != nil)
  #expect(MessageDate.parse(nil) == nil)
  #expect(MessageDate.parse("invalid") == nil)
}

@Test func v2LayoutMatchesReferenceAndProtectsNarrowConversation() {
  let wide = WorkspaceLayout(width: 1280, inspectorPreferred: true)
  #expect(wide.sidebar == 280)
  #expect(wide.inspector == 320)
  #expect(wide.showsInspector)
  #expect(!WorkspaceLayout(width: 800, inspectorPreferred: true).showsInspector)
  #expect(!WorkspaceLayout(width: 1280, inspectorPreferred: false).showsInspector)
}

@Test @MainActor func newConversationSelectsOracleWithoutServerWrites() throws {
  let store = ChatWorkspace(backend: isolatedBackend())
  store.state = try stateFixture()
  store.selection = "chat:n1"
  store.permission = "acceptEdits"
  store.reply = ReplyContext(sender: "Claude", text: "previous")
  let oracle = try #require(
    OracleIndex.groups(state: store.state, sessions: []).first { $0.name == "nexus-oracle" })
  store.newChat(in: oracle)
  #expect(store.selection == nil)
  #expect(store.project == "nexus")
  #expect(store.draftPath == "/repos/nexus")
  #expect(store.permission == "default")
  #expect(store.reply == nil)
  #expect(store.state.chats.count == 2)
}

@Test @MainActor func activeAndSavedNativeSessionsCannotSendWithoutImport() async throws {
  let store = ChatWorkspace(backend: isolatedBackend())
  store.native = try JSONDecoder().decode(
    [NativeChatSession].self,
    from: Data(
      #"""
      [{"sessionId":"native1","name":"Saved","cwd":"/repos/neo","kind":"saved","action":"resume"}]
      """#.utf8))
  store.selection = "native:native1"
  store.connected = true
  store.health = try providerHealth(available: true)
  store.draft = "must never send"
  await store.send()
  #expect(!store.busy)
  #expect(store.error == nil)
  #expect(store.draft == "must never send")
  store.state = try stateFixture()
  store.selection = "chat:x1"
  await store.send()
  #expect(store.draft == "must never send")
  #expect(store.error == nil)
}

@Test @MainActor func favoritesAndTagsPersistInV2Namespace() throws {
  let suite = "MawChatV2Tests-" + UUID().uuidString
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let prefs = WorkspacePreferences(defaults: defaults)
  prefs.toggleFavorite("/repos/neo")
  prefs.tags["session1"] = ["research"]
  let restored = WorkspacePreferences(defaults: defaults)
  #expect(restored.favorites == ["/repos/neo"])
  #expect(restored.tags["session1"] == ["research"])
  #expect(defaults.object(forKey: "MawChat.favoriteOracles") == nil)
}

@Test func repliesIncludeQuotedContextOnlyWhenExplicitlySelected() {
  let reply = ReplyContext(sender: "neo-oracle", text: "first\nsecond")
  #expect(reply.content == "Replying to neo-oracle:\n> first\n> second")
}
