import Foundation
import MawCore
import Testing

@testable import MawChatV2

private actor CreationGate {
  private var started = false
  private var startWaiter: CheckedContinuation<Void, Never>?
  private var releaseWaiter: CheckedContinuation<Void, Never>?
  func holdResponse() async {
    started = true
    startWaiter?.resume()
    startWaiter = nil
    await withCheckedContinuation { releaseWaiter = $0 }
  }
  func waitForRequest() async {
    if !started { await withCheckedContinuation { startWaiter = $0 } }
  }
  func release() {
    releaseWaiter?.resume()
    releaseWaiter = nil
  }
}

private final class DelayedCreationProtocol: URLProtocol, @unchecked Sendable {
  static let gate = CreationGate()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    #expect(request.url?.path == "/api/chats", "Navigation change must prevent a message POST")
    Task {
      await Self.gate.holdResponse()
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(
        self,
        didLoad: Data(
          #"{"id":"old-chat","title":"Old","projectId":"neo","model":"sonnet","permissionMode":"default","status":"idle","messages":[]}"#
            .utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() {}
}

@Test @MainActor func switchingOracleWhileCreateAwaitsCannotSendOrHijackNewDraft() async throws {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [DelayedCreationProtocol.self]
  let store = ChatWorkspace(
    backend: ChatBackend(
      baseURL: URL(string: "http://v2.test")!,
      session: URLSession(configuration: config)))
  store.connected = true
  store.health = try providerHealth(available: true)
  store.project = "neo"
  store.draft = "old draft"
  let sending = Task { await store.send() }
  await DelayedCreationProtocol.gate.waitForRequest()
  store.newChat()
  store.project = "nexus"
  store.draft = "new draft"
  await DelayedCreationProtocol.gate.release()
  await sending.value
  #expect(store.selection == nil)
  #expect(store.project == "nexus")
  #expect(store.draft == "new draft")
  #expect(store.error == nil)
  #expect(!store.busy)
}
