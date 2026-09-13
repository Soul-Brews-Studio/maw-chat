import Foundation
import MawCore
import Testing

@testable import MawChatV2

private final class SendProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    var data = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 1024)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(contentsOf: buffer.prefix(count))
      }
    }
    let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    #expect(request.httpMethod == "POST")
    switch request.url?.path {
    case "/api/native-sessions/native1/import":
      #expect(body?["permissionMode"] as? String == "default")
    case "/api/chats":
      #expect(body?["projectId"] as? String == "neo")
      #expect(body?["permissionMode"] as? String == "default")
      #expect(body?["model"] as? String == "sonnet")
      #expect(body?["title"] as? String == "follow up")
    case "/api/chats/new-chat/messages":
      let content = body?["content"] as? String
      if content?.hasPrefix("Use @repo:neo-oracle") == true {
        #expect(
          content?.contains("Referenced context (metadata only; not conversation history):") == true
        )
        #expect(content?.contains("repository:/repos/neo") == true)
      } else {
        #expect(content == "Replying to neo-oracle:\n> original\n\nfollow up")
      }
    default: Issue.record("Unexpected test request: \(request.url?.path ?? "nil")")
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(
      self,
      didLoad: Data(
        #"{"id":"new-chat","title":"Test","projectId":"neo","model":"sonnet","permissionMode":"default","status":"idle","messages":[]}"#
          .utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

func isolatedBackend() -> ChatBackend {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [SendProtocol.self]
  return ChatBackend(
    baseURL: URL(string: "http://v2.test")!, session: URLSession(configuration: config))
}

@Test @MainActor func sendUsesSelectedOracleQuotedReplyAndDefaultPermissions() async {
  let store = ChatWorkspace(backend: isolatedBackend())
  store.connected = true
  store.health = try? providerHealth(available: true)
  store.project = "neo"
  store.draft = "follow up"
  store.reply = ReplyContext(sender: "neo-oracle", text: "original")
  await store.send()
  #expect(store.error == nil)
  #expect(store.selection == "chat:new-chat")
  #expect(store.draft.isEmpty)
  #expect(store.reply == nil)
  // REST responses must not overwrite newer authoritative SSE snapshots.
  #expect(store.state.chats.isEmpty)
}

@Test func quotedRepliesRoundTripAndOrdinaryMarkdownIsNotMisclassified() throws {
  let reply = ReplyContext(sender: "neo-oracle", text: "first\n\nsecond")
  let parsed = try #require(QuotedReply.parse(reply.content + "\n\nfollow up"))
  #expect(parsed.sender == "neo-oracle")
  #expect(parsed.quote == "first\n\nsecond")
  #expect(parsed.body == "follow up")
  #expect(QuotedReply.parse("> Ordinary quotation\n\nHello") == nil)
  #expect(QuotedReply.parse("Replying to a:\nnot a quote\n\nbody") == nil)
}

@Test @MainActor func resumeBridgesRESTBeforeSSEAndKeepsExplicitReply() async throws {
  let store = ChatWorkspace(backend: isolatedBackend())
  store.native = try JSONDecoder().decode(
    [NativeChatSession].self,
    from: Data(
      #"""
      [{"sessionId":"native1","name":"Saved","cwd":"/repos/neo","kind":"saved","action":"resume"}]
      """#.utf8))
  store.selection = "native:native1"
  store.reply = ReplyContext(sender: "neo-oracle", text: "original")
  store.model = "haiku"
  await store.importSelected()
  #expect(store.selection == "chat:new-chat")
  await store.selected()
  #expect(store.chat?.id == "new-chat")
  #expect(store.reply?.text == "original")
  #expect(store.model == "sonnet")
  #expect(store.state.chats.isEmpty)
}

func providerHealth(available: Bool) throws -> BackendHealth {
  try JSONDecoder().decode(
    BackendHealth.self,
    from: Data(
      "{\"ok\":true,\"claudeAvailable\":\(available),\"cwd\":\"/repos\"}".utf8))
}

@Test @MainActor func staleSelectionAndUnavailableProviderNeverCreateAChat() async throws {
  let store = ChatWorkspace(backend: isolatedBackend())
  store.connected = true
  store.health = try providerHealth(available: true)
  store.draft = "must not send"
  for identity in ["chat:missing", "native:missing"] {
    store.selection = identity
    #expect(!store.canCompose)
    await store.send()
    #expect(store.error == nil)
    #expect(store.draft == "must not send")
  }
  store.selection = nil
  store.health = try providerHealth(available: false)
  #expect(!store.providerReady)
  await store.send()
  #expect(store.error == nil)
  #expect(store.state.chats.isEmpty)
}

private final class FailedHealthProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
  }
  override func stopLoading() {}
}

@Test @MainActor func failedConnectionCheckClearsStaleProviderHealthAndReportsError() async throws {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [FailedHealthProtocol.self]
  let store = ChatWorkspace(
    backend: ChatBackend(
      baseURL: URL(string: "http://v2.test")!,
      session: URLSession(configuration: config)))
  store.connected = true
  store.health = try providerHealth(available: true)
  await store.checkConnection()
  #expect(store.health == nil)
  #expect(!store.providerReady)
  #expect(store.error?.hasPrefix("Connection check failed:") == true)
}

@Test func repeatedTimestampParsingHasNoPerMessageFormatterAllocation() {
  let clock = ContinuousClock()
  let started = clock.now
  for _ in 0..<1000 {
    #expect(MessageDate.parse("2026-09-13T12:00:00.000Z") != nil)
  }
  #expect(started.duration(to: clock.now) < .seconds(1))
}
