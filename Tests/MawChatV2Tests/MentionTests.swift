import Foundation
import MawCore
import Testing

@testable import MawChatV2

func mentionFixture() -> MentionCandidate {
  MentionCandidate(
    key: "repository:/repos/neo", kind: "oracle", name: "neo-oracle",
    path: "/repos/neo", sessionId: nil, token: "@repo:neo-oracle", oracleName: "neo-oracle")
}

@Test func mentionTriggerUsesCaretAndIgnoresEmailsAndEscapedAt() throws {
  #expect(MentionText.query("@", caret: 1)?.fragment == "")
  #expect(MentionText.query("hello @neo", caret: 10)?.fragment == "neo")
  #expect(MentionText.query("mail@example.org", caret: 16) == nil)
  #expect(MentionText.query("@@neo", caret: 5) == nil)
  #expect(MentionText.query("hello @neo done", caret: 15) == nil)
  let value = "👋 @ne suffix"
  let query = try #require(MentionText.query(value, caret: 6))
  #expect(query.fragment == "ne")
  let inserted = MentionText.insert(mentionFixture(), into: value, query: query)
  #expect(inserted.text == "👋 @repo:neo-oracle suffix")
  #expect(inserted.caret == "👋 @repo:neo-oracle".utf16.count)
}

@Test func mentionMetadataRequiresAnExplicitCompleteSelectedToken() throws {
  let candidate = mentionFixture()
  #expect(try MentionText.expand("Use @repo:neo-oracle", selected: []) == "Use @repo:neo-oracle")
  #expect(try MentionText.expand("Removed token", selected: [candidate]) == "Removed token")
  for text in ["@repo:neo-oracle-copy", "@@repo:neo-oracle", "name@repo:neo-oracle"] {
    #expect(!MentionText.contains(candidate.token, in: text))
  }
  let text = try MentionText.expand("Use (@repo:neo-oracle).", selected: [candidate, candidate])
  let block = try #require(
    text.components(separatedBy: "```json\n").last?.components(separatedBy: "\n```").first)
  let values = try #require(
    JSONSerialization.jsonObject(with: Data(block.utf8)) as? [[String: String]])
  #expect(values.count == 1)
  #expect(values[0]["key"] == "repository:/repos/neo")
  #expect(values[0]["path"] == "/repos/neo")
  #expect(values[0]["kind"] == "oracle")
  #expect(values[0]["oracleName"] == nil)
  #expect(values[0]["oracleID"] == nil)
  #expect(text.contains("metadata only; not conversation history"))
}

@Test func mentionMetadataEscapesCodeFencesAndCapsReferences() throws {
  let candidates = (0..<40).map { index in
    MentionCandidate(
      key: "repository:\(index)", kind: "repository", name: "unsafe```\(index)",
      path: "/repos/\(index)", sessionId: nil, token: "@repo:r\(index)", oracleName: "repo")
  }
  let text = try MentionText.expand(
    candidates.map(\.token).joined(separator: " "), selected: candidates)
  #expect(text.contains("\\u0060\\u0060\\u0060"))
  #expect(text.components(separatedBy: "```").count == 3)
  let block = text.components(separatedBy: "```json\n")[1].components(separatedBy: "\n```")[0]
  #expect((try JSONSerialization.jsonObject(with: Data(block.utf8)) as? [Any])?.count == 32)
}

@Test func mentionIndexUsesNativeSessionIdentityPathAndCollisionSafeTokens() async throws {
  let state = try JSONDecoder().decode(
    ChatState.self,
    from: Data(
      #"""
      {"projects":[{"id":"neo","name":"neo-oracle","path":"/repos/neo"},
        {"id":"other","name":"neo-oracle","path":"/other/neo"}],"chats":[
        {"id":"chat-id-not-session-id","title":"Actual title","projectId":"neo","sessionId":"12345678-full-session",
         "model":"sonnet","permissionMode":"default","status":"idle","messages":[]}]}
      """#.utf8))
  let native = try JSONDecoder().decode(
    [NativeChatSession].self,
    from: Data(
      #"""
      [{"sessionId":"12345678-full-session","name":"Old title","cwd":"/alias/exact-execution-folder",
        "canonicalPath":"/repos/neo/subfolder","kind":"saved","action":"resume"}]
      """#.utf8))
  let groups = OracleIndex.groups(state: state, sessions: native)
  let index = MentionIndex()
  let candidates = await index.build(groups: groups, state: state, native: native)
  #expect(candidates.count == 3)
  #expect(Set(candidates.map(\.token)).count == 3)
  let session = try #require(candidates.first { $0.kind == "session" })
  #expect(session.sessionId == "12345678-full-session")
  #expect(session.token == "@session:actual-title-12345678")
  #expect(session.path == "/alias/exact-execution-folder")
  #expect(session.key != "chat-id-not-session-id")
  let again = await index.build(groups: groups, state: state, native: native)
  #expect(again == candidates)
  let matches = await index.matches(candidates, query: "actual", scope: .all, favorites: [])
  #expect(matches.map(\.key) == [session.key])
  let favorites = await index.matches(candidates, query: "", scope: .all, favorites: ["/repos/neo"])
  #expect(
    favorites.firstIndex(where: { $0.key == session.key })! < favorites.firstIndex(where: {
      $0.path == "/other/neo"
    })!)
}

@Test @MainActor func sendingMentionUsesSameChatWithFrontendMetadata() async throws {
  let store = ChatWorkspace(backend: isolatedBackend())
  store.state = try JSONDecoder().decode(
    ChatState.self,
    from: Data(
      #"""
      {"projects":[],"chats":[{"id":"new-chat","title":"Existing chat","model":"sonnet",
        "permissionMode":"default","status":"idle","messages":[]}]}
      """#.utf8))
  store.selection = "chat:new-chat"
  store.connected = true
  store.health = try providerHealth(available: true)
  store.draft = "Use @repo:neo-oracle"
  store.selectedMentions = [mentionFixture()]
  await store.send()
  #expect(store.error == nil)
  #expect(store.selection == "chat:new-chat")
  #expect(store.selectedMentions.isEmpty)
  #expect(store.draft.isEmpty)
}

@Test func mentionBindingsStayDistinctWhenInventoryReusesAToken() async throws {
  let index = MentionIndex()
  func candidates(path: String) async throws -> [MentionCandidate] {
    let repositories = try JSONDecoder().decode(
      [ChatRepository].self,
      from: Data(
        "[{\"name\":\"neo-oracle\",\"path\":\"\(path)\",\"modifiedAt\":1}]".utf8))
    return await index.build(
      groups: OracleIndex.groups(state: ChatState(), sessions: [], repositories: repositories),
      state: ChatState(), native: [])
  }
  let old = try #require(await candidates(path: "/old/neo-oracle").first)
  let replacement = try #require(await candidates(path: "/new/neo-oracle").first)
  #expect(old.token == replacement.token)
  let bound = MentionText.binding(replacement, selected: [old])
  #expect(bound.token != old.token)
  #expect(bound.token.count <= 256)
  #expect(MentionText.binding(replacement, selected: [old, bound]) == bound)
  let oldOnly = try MentionText.expand(old.token, selected: [old, bound])
  #expect(oldOnly.contains(old.path))
  #expect(!oldOnly.contains(bound.path))
}
