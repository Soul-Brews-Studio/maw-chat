import Foundation
import Testing

@testable import MawCore

private func chatState() throws -> ChatState {
  try JSONDecoder().decode(
    ChatState.self,
    from: Data(
      #"""
      {"projects":[{"id":"nexus","name":"nexus-oracle","path":"/alias/nexus","canonicalPath":"/repos/nexus"}],
       "chats":[{"id":"imported","title":"Imported conversation","projectId":"nexus","sessionId":"shared","model":"sonnet","permissionMode":"default","status":"idle","messages":[],"updatedAt":"2026-09-12T10:00:00.000Z"}]}
      """#.utf8))
}
private func savedSessions() throws -> [NativeChatSession] {
  try JSONDecoder().decode(
    [NativeChatSession].self,
    from: Data(
      #"""
      [{"sessionId":"shared","name":"Imported native copy","cwd":"/repos/nexus","kind":"saved","action":"resume","updatedAt":1789207200000},
       {"sessionId":"recent","name":"Newest chat","cwd":"/repos/nexus/subfolder","kind":"saved","action":"resume","updatedAt":1789210800000},
       {"sessionId":"active","name":"Active chat","cwd":"/alias/nexus","canonicalPath":"/repos/nexus","kind":"interactive","action":"resumeAfterExit","updatedAt":1789190000000},
       {"sessionId":"older","name":"Older chat","cwd":"/repos/nexus","kind":"saved","action":"resume","startedAt":1789100000000}]
      """#.utf8))
}

@Test func unifiedOracleShowsEveryConversationOnceNewestFirst() throws {
  let group = try #require(OracleIndex.groups(state: chatState(), sessions: savedSessions()).first)
  #expect(group.path == "/repos/nexus")
  #expect(group.projectID == "nexus")
  #expect(
    group.threads.map(\.id) == ["native:recent", "chat:imported", "native:active", "native:older"])
  #expect(group.threads.first(where: { $0.id == "native:active" })?.isReadOnly == true)
}

@Test func oracleSearchIncludesSavedHistoryAndExcludesEmptyUnrelatedGroups() throws {
  let state = try chatState()
  let sessions = try savedSessions()
  let group = try #require(
    OracleIndex.groups(state: state, sessions: sessions, query: "nexus").first)
  #expect(group.threads.count == 4)
  #expect(OracleIndex.groups(state: state, sessions: sessions, query: "missing").isEmpty)
  let tagged = OracleIndex.groups(
    state: state, sessions: sessions, query: "#research", tags: ["older": ["research"]])
  #expect(tagged.first?.threads.map(\.id) == ["native:older"])
}

@Test func favoritesPinDiscoveredOraclesAndKeepNewThreadTarget() {
  let repos = [
    ChatRepository(name: "neo-oracle", path: "/repos/neo/", modifiedAt: 1),
    ChatRepository(name: "nexus-oracle", path: "/repos/nexus", modifiedAt: 2),
  ]
  let groups = OracleIndex.groups(
    state: ChatState(), sessions: [], repositories: repos, favorites: ["/repos/neo"])
  #expect(groups.map(\.path) == ["/repos/neo", "/repos/nexus"])
  #expect(groups.first?.projectID == nil)
  #expect(groups.first?.name == "neo-oracle")
}

@Test func nativeDuplicatesDoNotCollapseDifferentSessionIDs() throws {
  let sessions = try savedSessions()
  let groups = OracleIndex.groups(
    state: ChatState(), sessions: sessions + sessions,
    repositories: [ChatRepository(name: "nexus-oracle", path: "/repos/nexus", modifiedAt: 0)])
  #expect(groups.count == 1)
  #expect(groups.first?.threads.count == 4)
}

@Test func benchmarkThousandRepositoryProjection() {
  let repositories = (0..<1000).map {
    ChatRepository(name: "oracle-\($0)", path: "/repos/oracle-\($0)", modifiedAt: Double($0))
  }
  let sessions = (0..<225).map {
    NativeChatSession(
      sessionId: "session-\($0)", name: "Saved conversation \($0)",
      cwd: "/repos/oracle-\($0)/src", kind: "saved", action: "resume", status: nil,
      updatedAt: Double($0))
  }
  let elapsed = ContinuousClock().measure {
    for _ in 0..<10 {
      #expect(
        OracleIndex.groups(
          state: ChatState(), sessions: sessions,
          repositories: repositories
        ).count == 1000)
    }
  }
  print("SIDEBAR_BENCH 10 x 1000 repositories + 225 sessions: \(elapsed)")
  #expect(elapsed < .seconds(1))
}

@Test func nestedRepositoriesUseDeepestParentNotAnArbitraryAncestor() throws {
  let sessions = try JSONDecoder().decode(
    [NativeChatSession].self,
    from: Data(
      #"""
      [{"sessionId":"nested","cwd":"/repos/oracle/agents/child/src","kind":"saved","action":"resume"}]
      """#.utf8))
  let repos = [
    ChatRepository(name: "parent", path: "/repos/oracle", modifiedAt: 0),
    ChatRepository(name: "child", path: "/repos/oracle/agents/child", modifiedAt: 0),
  ]
  for _ in 0..<20 {
    let groups = OracleIndex.groups(state: ChatState(), sessions: sessions, repositories: repos)
    #expect(groups.first { $0.name == "child" }?.threads.count == 1)
    #expect(groups.first { $0.name == "parent" }?.threads.isEmpty == true)
  }
}

@Test func emptySearchShowsOnlyFavoritesButSearchFindsAnyOracle() {
  let repos = (0..<1000).map {
    ChatRepository(name: "oracle-\($0)", path: "/repos/oracle-\($0)", modifiedAt: Double($0))
  }
  let groups = OracleIndex.groups(state: ChatState(), sessions: [], repositories: repos)
  let favorites: Set<String> = ["/repos/oracle-42", "/repos/oracle-99"]
  #expect(OracleIndex.sidebar(groups, favorites: favorites).count == 2)
  #expect(OracleIndex.sidebar(groups).isEmpty)
  #expect(
    OracleIndex.sidebar(groups, query: "oracle-500", favorites: favorites).map(\.path) == [
      "/repos/oracle-500"
    ])
  #expect(OracleIndex.sidebar(groups, query: "   ", favorites: favorites).count == 2)
}

@Test func oraclePickerSearchesBeforeLimitingAndPinsExistingFavoritesFirst() {
  let repos = (0..<1000).map {
    ChatRepository(name: "oracle-\($0)", path: "/repos/oracle-\($0)", modifiedAt: Double($0))
  }
  let groups = OracleIndex.groups(state: ChatState(), sessions: [], repositories: repos)
  #expect(OracleIndex.picker(groups).count == 30)
  #expect(OracleIndex.picker(groups, query: "oracle-42").contains { $0.path == "/repos/oracle-42" })
  #expect(
    OracleIndex.picker(groups, favorites: ["/repos/oracle-42"]).first?.path == "/repos/oracle-42")
  #expect(OracleIndex.picker(groups, query: "does-not-exist").isEmpty)
}
