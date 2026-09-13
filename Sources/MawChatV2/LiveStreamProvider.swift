import Foundation

struct LiveStreamSource: Identifiable, Equatable, Sendable {
  enum Kind: String, Sendable { case tmux, vnc }
  var id: String { kind.rawValue + ":" + target }
  let target: String
  let name: String
  let detail: String
  let kind: Kind
}

struct LiveStreamFrame: Equatable, Sendable {
  enum Payload: Equatable, Sendable {
    case text(String)
    case image(Data)
  }
  let payload: Payload
  let capturedAt: Date
}

protocol LiveStreamProvider: Sendable {
  func sources() async throws -> [LiveStreamSource]
  func frames(for source: LiveStreamSource) async -> AsyncThrowingStream<LiveStreamFrame, Error>
}

enum LiveStreamError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self {
    case .message(let message): message
    }
  }
}

/// Only GET inventory/capture. Never connect to maw's interactive PTY/control WebSockets.
actor TmuxStreamProvider: LiveStreamProvider {
  private let baseURL: URL
  private let session: URLSession
  init(endpoint: String, session: URLSession? = nil) throws {
    baseURL = try Self.localURL(endpoint)
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 4
      configuration.timeoutIntervalForResource = 6
      configuration.httpShouldSetCookies = false
      configuration.urlCredentialStorage = nil
      configuration.urlCache = nil
      self.session = URLSession(
        configuration: configuration, delegate: NoStreamRedirects(), delegateQueue: nil)
    }
  }
  deinit { session.invalidateAndCancel() }

  static func localURL(_ text: String) throws -> URL {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
      ["localhost", "127.0.0.1", "[::1]", "::1"].contains(url.host?.lowercased() ?? ""),
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      url.path.isEmpty || url.path == "/"
    else {
      throw LiveStreamError.message(
        "Use a local maw server URL, for example http://127.0.0.1:3461.")
    }
    return url
  }
  func sources() async throws -> [LiveStreamSource] {
    struct Session: Decodable {
      struct Window: Decodable {
        struct Pane: Decodable {
          let target: String
          let command: String?
          let cwd: String?
        }
        let name: String
        let panes: [Pane]
      }
      let name: String
      let windows: [Window]
    }
    let sessions = try JSONDecoder().decode(
      [Session].self,
      from: await get("/api/sessions", query: [URLQueryItem(name: "local", value: "true")]))
    var seen: Set<String> = []
    return sessions.flatMap { session in
      session.windows.flatMap { window in
        window.panes.compactMap { pane in
          guard !pane.target.isEmpty, seen.insert(pane.target).inserted else { return nil }
          return LiveStreamSource(
            target: pane.target,
            name: session.name + " / " + window.name + " · " + (pane.command ?? "tmux"),
            detail: pane.cwd ?? "", kind: .tmux)
        }
      }
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
  func capture(_ source: LiveStreamSource) async throws -> LiveStreamFrame {
    struct Capture: Decodable {
      let content: String?
      let error: String?
    }
    guard source.kind == .tmux, !source.target.isEmpty else {
      throw LiveStreamError.message("Choose a tmux pane first.")
    }
    let result = try JSONDecoder().decode(
      Capture.self,
      from: await get("/api/capture", query: [URLQueryItem(name: "target", value: source.target)]))
    if let error = result.error { throw LiveStreamError.message("Capture failed: " + error) }
    guard let content = result.content else {
      throw LiveStreamError.message("The server returned no capture content.")
    }
    return LiveStreamFrame(payload: .text(TerminalSnapshot.plainText(content)), capturedAt: Date())
  }
  func frames(for source: LiveStreamSource) -> AsyncThrowingStream<LiveStreamFrame, Error> {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task {
        do {
          while !Task.isCancelled {
            let frame = try await capture(source)
            try Task.checkCancellation()
            continuation.yield(frame)
            try await Task.sleep(for: .seconds(1))
          }
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }
  private func get(_ path: String, query: [URLQueryItem]) async throws -> Data {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    components.path = path
    components.queryItems = query
    var request = URLRequest(url: components.url!)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let (bytes, response) = try await session.bytes(for: request)
    defer { bytes.task.cancel() }
    try Task.checkCancellation()
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
      throw LiveStreamError.message(
        "Cannot read maw server (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
    }
    let maximum = 2_000_000
    guard response.expectedContentLength <= maximum else {
      throw LiveStreamError.message("The maw response is too large.")
    }
    return try await withTaskCancellationHandler {
      var data = Data()
      for try await byte in bytes {
        try Task.checkCancellation()
        guard data.count < maximum else {
          throw LiveStreamError.message("The maw response is too large.")
        }
        data.append(byte)
      }
      return data
    } onCancel: {
      bytes.task.cancel()
    }
  }
}

private final class NoStreamRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
