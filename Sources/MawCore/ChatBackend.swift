import Foundation

public struct ChatProject: Codable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let path: String
  public var canonicalPath: String? = nil
}
public struct ChatRepository: Codable, Sendable {
  public let name: String
  public let path: String
  public let modifiedAt: Double?
}
public struct RepositoryInventory: Codable, Sendable {
  public let repositories: [ChatRepository]
  public let warning: String?
}
public struct ChatTool: Codable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let status: String
  public let input: JSONValue?
}
public indirect enum JSONValue: Codable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null
  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let v = try? c.decode(String.self) {
      self = .string(v)
    } else if let v = try? c.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? c.decode(Double.self) {
      self = .number(v)
    } else if let v = try? c.decode([String: JSONValue].self) {
      self = .object(v)
    } else {
      self = .array(try c.decode([JSONValue].self))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .null: try c.encodeNil()
    }
  }
  public var pretty: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
  }
}
public struct ChatUsage: Codable, Sendable {
  public let inputTokens: Int
  public let outputTokens: Int
  public let costUsd: Double?
}
public struct ChatMessage: Codable, Identifiable, Sendable {
  public var createdAt: String? = nil
  public let id: String
  public let role: String
  public let content: String
  public let status: String?
  public let tools: [ChatTool]?
  public let error: String?
  public let usage: ChatUsage?
  public let history: JSONValue?
}
public struct ChatSync: Codable, Sendable {
  public let status: String
  public let error: String?
}
public struct Conversation: Codable, Identifiable, Sendable {
  public let id: String
  public var title: String
  public let projectId: String?
  public let sessionId: String?
  public let model: String
  public let permissionMode: String
  public let messages: [ChatMessage]
  public let status: String
  public let sync: ChatSync?
  public let historyNextOffset: Int?
  public let historyUnavailable: Bool?
  public var createdAt: String? = nil
  public var updatedAt: String? = nil
}
public struct ChatState: Codable, Sendable {
  public var projects: [ChatProject]
  public var chats: [Conversation]
  public init(projects: [ChatProject] = [], chats: [Conversation] = []) {
    self.projects = projects
    self.chats = chats
  }
}
public struct NativeChatSession: Codable, Identifiable, Sendable {
  public var id: String { sessionId ?? "\(kind)-\(name ?? cwd)" }
  public let sessionId: String?
  public let name: String?
  public let cwd: String
  public let kind: String
  public let action: String
  public let status: String?
  public var canonicalPath: String? = nil
  public var startedAt: Double? = nil
  public var updatedAt: Double? = nil
}
public struct ChatHistory: Codable, Sendable {
  public let messages: [ChatMessage]
  public let nextOffset: Int?
}
public struct BackendHealth: Codable, Sendable {
  public let ok: Bool
  public let claudeAvailable: Bool
  public let claudeVersion: String?
  public let cwd: String
}

/// SSE framing, separate from server-side Claude JSONL parsing.
public struct StateEventParser: Sendable {
  private var event = ""
  private var data: [String] = []
  public init() {}
  public mutating func consume(_ line: String) throws -> ChatState? {
    if line.isEmpty {
      defer {
        event = ""
        data = []
      }
      guard event == "state", !data.isEmpty else { return nil }
      return try JSONDecoder().decode(ChatState.self, from: Data(data.joined(separator: "\n").utf8))
    }
    if line.hasPrefix("event:") {
      event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
    }
    if line.hasPrefix("data:") {
      let value = line.dropFirst(5)
      data.append(String(value.first == " " ? value.dropFirst() : value))
    }
    return nil
  }
}

public actor ChatBackend {
  public let baseURL: URL
  private let session: URLSession
  public init(baseURL: URL = URL(string: "http://127.0.0.1:4318")!, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.session = session
  }
  public func state() async throws -> ChatState { try await request("state") }
  public func health() async throws -> BackendHealth { try await request("health") }
  public func repositories() async throws -> RepositoryInventory {
    try await request("repositories")
  }
  public func createProject(name: String, path: String) async throws -> ChatProject {
    try await request(
      "projects", method: "POST", body: ["name": .string(name), "path": .string(path)])
  }
  public func nativeSessions() async throws -> [NativeChatSession] {
    struct Envelope: Decodable { let sessions: [NativeChatSession] }
    let response: Envelope = try await request("native-sessions")
    return response.sessions
  }
  public func history(_ id: String, offset: Int = 0) async throws -> ChatHistory {
    try await request("native-sessions/\(encoded(id))/messages?offset=\(offset)&limit=100")
  }
  public func create(title: String, project: String?, model: String, permission: String)
    async throws -> Conversation
  {
    var body: [String: JSONValue] = [
      "title": .string(title), "model": .string(model), "permissionMode": .string(permission),
    ]
    body["projectId"] = project.map(JSONValue.string) ?? .null
    return try await request("chats", method: "POST", body: body)
  }
  public func send(_ id: String, text: String) async throws -> Conversation {
    try await request(
      "chats/\(encoded(id))/messages", method: "POST", body: ["content": .string(text)])
  }
  public func stop(_ id: String) async throws -> Conversation {
    try await request("chats/\(encoded(id))/stop", method: "POST", body: [:])
  }
  public func sync(_ id: String) async throws -> Conversation {
    try await request("chats/\(encoded(id))/sync", method: "POST", body: [:])
  }
  public func loadHistory(_ id: String) async throws -> Conversation {
    try await request("chats/\(encoded(id))/history", method: "POST", body: [:])
  }
  public func importSession(_ id: String) async throws -> Conversation {
    try await request(
      "native-sessions/\(encoded(id))/import", method: "POST",
      body: ["permissionMode": .string("default")])
  }
  public func renameNative(_ id: String, title: String) async throws {
    struct Response: Decodable, Sendable { let session: NativeChatSession }
    let _: Response = try await request(
      "native-sessions/\(encoded(id))", method: "PATCH", body: ["title": .string(title)])
  }
  public func update(_ id: String, model: String, permission: String) async throws -> Conversation {
    try await request(
      "chats/\(encoded(id))", method: "PATCH",
      body: ["model": .string(model), "permissionMode": .string(permission)])
  }
  public func rename(_ id: String, title: String) async throws -> Conversation {
    try await request("chats/\(encoded(id))", method: "PATCH", body: ["title": .string(title)])
  }
  public func events() -> AsyncThrowingStream<ChatState, Error> {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task {
        do {
          var req = URLRequest(url: baseURL.appendingPathComponent("api/events"))
          req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
          req.timeoutInterval = 60 * 60
          let (bytes, response) = try await session.bytes(for: req)
          try validate(response)
          var parser = StateEventParser()
          // AsyncBytes.lines omits empty lines on this platform. SSE requires
          // those frame boundaries, so preserve them while decoding UTF-8 lines.
          var line = Data()
          for try await byte in bytes {
            try Task.checkCancellation()
            if byte == 10 {
              if line.last == 13 { line.removeLast() }
              if let state = try parser.consume(String(decoding: line, as: UTF8.self)) {
                continuation.yield(state)
              }
              line.removeAll(keepingCapacity: true)
            } else {
              guard line.count < 16 * 1024 * 1024 else {
                throw BackendError.message("Server event exceeded 16 MiB.")
              }
              line.append(byte)
            }
          }
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
  private func encoded(_ id: String) -> String {
    id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
  }
  private func request<T: Decodable & Sendable>(
    _ path: String, method: String = "GET", body: [String: JSONValue]? = nil
  ) async throws -> T {
    let url = URL(string: "api/" + path, relativeTo: baseURL.appendingPathComponent("/"))!
      .absoluteURL
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.timeoutInterval = 30
    if let body {
      req.httpBody = try JSONEncoder().encode(body)
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await session.data(for: req)
    try validate(response, data: data)
    return try JSONDecoder().decode(T.self, from: data)
  }
  private func validate(_ response: URLResponse, data: Data = Data()) throws {
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      let error = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
      throw BackendError.message(
        error ?? "Chat server unavailable. Check that http://127.0.0.1:4318 is running.")
    }
  }
}
