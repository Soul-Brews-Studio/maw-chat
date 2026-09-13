import Foundation
import Testing

@testable import MawChatV2

private final class SnapshotProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    #expect(request.httpMethod == "GET")
    let url = request.url!
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
    var body = Data()
    var headers: [String: String] = [:]
    if url.path == "/api/sessions" {
      #expect(query == [URLQueryItem(name: "local", value: "true")])
      body = Data(
        #"[{"name":"neo","windows":[{"name":"one","panes":[{"target":"neo:one.0","command":"claude","cwd":"/neo"},{"target":"neo:one.0"}]}]}]"#
          .utf8)
    } else if url.path == "/api/capture" {
      let target = query.first(where: { $0.name == "target" })?.value
      switch target {
      case "error": body = Data(#"{"error":"pane disappeared"}"#.utf8)
      case "missing": body = Data(#"{"target":"missing"}"#.utf8)
      case "empty": body = Data(#"{"content":""}"#.utf8)
      case "large-header": headers["Content-Length"] = "2000001"
      case "large-body": body = Data(repeating: 32, count: 2_000_001)
      default:
        #expect(target == "neo:a & b.0")
        body = Data(#"{"content":"\u001b[31mHello\u001b[0m"}"#.utf8)
      }
    } else {
      Issue.record("Unexpected request path")
    }
    let response = HTTPURLResponse(
      url: url, statusCode: url.port == 3462 ? 503 : 200, httpVersion: nil, headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private func snapshotProvider(port: Int = 3461) throws -> TmuxStreamProvider {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [SnapshotProtocol.self]
  return try TmuxStreamProvider(
    endpoint: "http://127.0.0.1:\(port)", session: URLSession(configuration: config))
}

private func source(_ target: String) -> LiveStreamSource {
  LiveStreamSource(target: target, name: "pane", detail: "", kind: .tmux)
}

@Test func liveEndpointOnlyAcceptsLoopbackRoots() throws {
  for valid in ["http://127.0.0.1:3461", "http://localhost:3461/", "https://[::1]:3461"] {
    #expect(throws: Never.self) { try TmuxStreamProvider.localURL(valid) }
  }
  for invalid in [
    "http://example.com", "file:///tmp/tmux", "http://127.0.0.1.evil.test",
    "http://user:secret@localhost", "http://localhost/api", "http://localhost?token=secret",
    "http://localhost/#target", "ws://localhost:3461",
  ] {
    #expect(throws: (any Error).self) { try TmuxStreamProvider.localURL(invalid) }
  }
}

@Test func liveInventoryAndCaptureUseReadOnlyWireContract() async throws {
  let provider = try snapshotProvider()
  let sources = try await provider.sources()
  #expect(sources.count == 1)
  #expect(sources.first?.id == "tmux:neo:one.0")
  #expect(sources.first?.name == "neo / one · claude")
  #expect(sources.first?.detail == "/neo")
  let frame = try await provider.capture(source("neo:a & b.0"))
  #expect(frame.payload == .text("Hello"))
  #expect(try await provider.capture(source("empty")).payload == .text(""))
  let vnc = LiveStreamSource(target: "neo:one.0", name: "screen", detail: "", kind: .vnc)
  #expect(vnc.id != sources.first?.id)
  await #expect(throws: (any Error).self) { try await provider.capture(vnc) }
}

@Test func liveCaptureSurfacesErrorsAndBoundsUnknownLengthBodies() async throws {
  let provider = try snapshotProvider()
  for target in ["error", "missing", "large-header", "large-body"] {
    await #expect(throws: (any Error).self) { try await provider.capture(source(target)) }
  }
  let unavailable = try snapshotProvider(port: 3462)
  await #expect(throws: (any Error).self) { try await unavailable.sources() }
}

@Test func terminalSnapshotsStripControlsAndBoundVisibleWork() {
  let input =
    "\u{1B}[31mred\u{1B}[0m\nไทย\tOK\r\u{07}\u{1B}]52;c;secret\u{07}"
    + "\u{1B}]8;;https://example.com\u{1B}\\link\u{1B}]8;;\u{1B}\\"
  #expect(TerminalSnapshot.plainText(input) == "red\nไทย\tOKlink")
  #expect(TerminalSnapshot.plainText("safe\u{1B}]unterminated") == "safe")
  #expect(TerminalSnapshot.plainText("\u{9B}32mgreen\u{9B}0m") == "green")
  let manyLines = (0..<500).map(String.init).joined(separator: "\n")
  let result = TerminalSnapshot.plainText(manyLines)
  #expect(result.split(separator: "\n").count == 200)
  #expect(result.hasPrefix("300\n"))
  #expect(TerminalSnapshot.plainText(String(repeating: "x", count: 100_000)).count == 65_536)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MAW_LIVE_TEST"] == "1"))
func liveMawServerReturnsRealPaneSnapshot() async throws {
  let provider = try TmuxStreamProvider(endpoint: "http://127.0.0.1:3461")
  let sources = try await provider.sources()
  let first = try #require(sources.first)
  let frame = try await provider.capture(first)
  // Do not log or persist private terminal contents.
  if case .text(let text) = frame.payload {
    #expect(text.count <= 65_536)
    #expect(!text.contains("\u{1B}"))
  } else {
    Issue.record("Expected a text snapshot from tmux")
  }
}
