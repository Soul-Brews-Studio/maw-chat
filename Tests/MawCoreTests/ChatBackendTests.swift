import Foundation
import Testing

@testable import MawCore

@Test func sseFramesAreSnapshotsNotAppendDeltas() throws {
  var parser = StateEventParser()
  #expect(try parser.consume(": keepalive") == nil)
  #expect(try parser.consume("") == nil)
  #expect(try parser.consume("event: state") == nil)
  #expect(try parser.consume(#"data: {"projects": [],"#) == nil)
  #expect(try parser.consume(#"data: "chats": []}"#) == nil)
  #expect(try parser.consume("")?.chats.isEmpty == true)
  #expect(try parser.consume("event: unknown") == nil)
  #expect(try parser.consume("data: invalid") == nil)
  #expect(try parser.consume("") == nil)
}

@Test func malformedStateIsReported() throws {
  var parser = StateEventParser()
  _ = try parser.consume("event: state")
  _ = try parser.consume("data: broken")
  #expect(throws: (any Error).self) { try parser.consume("") }
  _ = try parser.consume("event: state")
  _ = try parser.consume(#"data: {"projects":[],"chats":[]}"#)
  #expect(try parser.consume("") != nil)
}

@Test func structuredChatDecodesWithoutTerminalData() throws {
  let json =
    #"{"projects":[],"chats":[{"id":"chat-id","title":"Hello","projectId":null,"sessionId":"claude-id","model":"sonnet","permissionMode":"default","status":"running","messages":[{"id":"m1","role":"assistant","content":"Hello","status":"streaming","tools":[{"id":"t1","name":"Read","status":"complete","input":{"file_path":"README.md"}}],"usage":{"inputTokens":2,"outputTokens":3}}]}],"extra":true}"#
  let state = try JSONDecoder().decode(ChatState.self, from: Data(json.utf8))
  #expect(state.chats.first?.sessionId == "claude-id")
  #expect(state.chats.first?.messages.first?.tools?.first?.name == "Read")
  #expect(state.chats.first?.messages.first?.usage?.outputTokens == 3)
}

@Test func savedSessionDoesNotNeedProcessOrTerminal() throws {
  let json =
    #"{"sessionId":"saved-id","name":"Saved chat","cwd":"/tmp","kind":"saved","action":"resume","status":null}"#
  let item = try JSONDecoder().decode(NativeChatSession.self, from: Data(json.utf8))
  #expect(item.id == "saved-id")
  #expect(item.kind == "saved")
}

@Test func sharedBackendReadOnlySmoke() async throws {
  guard ProcessInfo.processInfo.environment["CHAT_LIVE_TEST"] == "1" else { return }
  let backend = ChatBackend()
  #expect(try await backend.health().ok)
  let state = try await backend.state()
  #expect(!state.chats.isEmpty)
  let native = try await backend.nativeSessions()
  #expect(native.contains { $0.kind == "saved" })
}

@Test func liveSSEInitialSnapshot() async throws {
  guard ProcessInfo.processInfo.environment["CHAT_LIVE_TEST"] == "1" else { return }
  try await withThrowingTaskGroup(of: Bool.self) { group in
    group.addTask {
      for try await state in await ChatBackend().events() { return !state.chats.isEmpty }
      return false
    }
    group.addTask {
      try await Task.sleep(for: .seconds(5))
      throw BackendError.message("SSE timeout")
    }
    defer { group.cancelAll() }
    let result = try await group.next()
    #expect(result == true)
  }
}

@Test func searchFindsOracleTitleIDAndTags() {
  #expect(
    ConversationIndex.matches(
      query: "neo #research", title: "Investigate storage", project: "/repos/neo-oracle",
      sessionID: "abc-123", tags: ["research"]))
  #expect(
    ConversationIndex.matches(
      query: "ABC-123", title: "Chat", project: "neo", sessionID: "abc-123", tags: []))
  #expect(
    !ConversationIndex.matches(
      query: "neo billing", title: "Chat", project: "neo-oracle", sessionID: nil, tags: []))
  #expect(
    ConversationIndex.parseTags("Research, #swift, research, , UI") == ["research", "swift", "ui"])
}
