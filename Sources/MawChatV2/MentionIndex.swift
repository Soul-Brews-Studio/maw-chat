import Foundation
import MawCore

struct MentionCandidate: Identifiable, Encodable, Equatable, Sendable {
  var id: String { key }
  let key: String
  let kind: String
  let name: String
  let path: String
  let sessionId: String?
  var token: String
  let oracleName: String
  var oracleID: String? = nil
  enum CodingKeys: String, CodingKey { case key, kind, name, path, sessionId, token }
}

actor MentionIndex {
  private var previous: [MentionCandidate] = []
  private var cached: [MentionCandidate] = []

  func build(groups: [OracleGroup], state: ChatState, native: [NativeChatSession])
    -> [MentionCandidate]
  {
    let sessions = Dictionary(
      native.compactMap { item in item.sessionId.map { ($0, item) } },
      uniquingKeysWith: { first, _ in first })
    let chats = Dictionary(
      state.chats.compactMap { item in item.sessionId.map { ($0, item) } },
      uniquingKeysWith: { first, _ in first })
    let projects = Dictionary(uniqueKeysWithValues: state.projects.map { ($0.id, $0.path) })
    var descriptors: [MentionCandidate] = []
    for group in groups {
      if let path = group.path {
        descriptors.append(
          MentionCandidate(
            key: "repository:" + group.id,
            kind: URL(fileURLWithPath: path).lastPathComponent.lowercased().hasSuffix("-oracle")
              ? "oracle" : "repository",
            name: group.name, path: path, sessionId: nil, token: "", oracleName: group.name,
            oracleID: group.id))
      }
      for thread in group.threads {
        guard let id = thread.sessionID,
          let path = sessions[id]?.cwd ?? chats[id]?.projectId.flatMap({ projects[$0] }),
          !path.isEmpty
        else { continue }
        descriptors.append(
          MentionCandidate(
            key: "session:" + id, kind: "session",
            name: thread.title, path: path, sessionId: id, token: "", oracleName: group.name,
            oracleID: group.id))
      }
    }
    var seen: Set<String> = []
    descriptors = descriptors.filter { seen.insert($0.key).inserted }
    descriptors.sort { $0.key < $1.key }
    guard descriptors != previous else { return cached }
    previous = descriptors
    var candidates = descriptors.map { candidate in
      var result = candidate
      if let session = candidate.sessionId {
        result.token =
          "@session:" + Self.slug(candidate.name, fallback: "session", limit: 231)
          + "-" + Self.slug(String(session.prefix(8)), fallback: Self.hash(session), limit: 8)
      } else {
        result.token = "@repo:" + Self.slug(candidate.name, fallback: "repository", limit: 243)
      }
      return result
    }
    let counts = Dictionary(grouping: candidates, by: \.token).mapValues(\.count)
    for index in candidates.indices where counts[candidates[index].token, default: 0] > 1 {
      let identity = candidates[index].sessionId ?? String(candidates[index].key.dropFirst(11))
      candidates[index].token += "-" + Self.hash(identity)
    }
    cached = candidates.sorted {
      $0.name == $1.name
        ? $0.key < $1.key : $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    return cached
  }

  func matches(
    _ candidates: [MentionCandidate], query: String, scope: WorkspaceListScope,
    favorites: Set<String>
  ) -> [MentionCandidate] {
    let term = query.lowercased()
    return Array(
      candidates.filter {
        scope.includes(projectName: $0.oracleName)
          && [$0.name, $0.path, $0.token, $0.sessionId ?? ""].contains {
            $0.localizedCaseInsensitiveContains(term) || term.isEmpty
          }
      }.sorted {
        let a = favorites.contains($0.oracleID ?? $0.path)
        let b = favorites.contains($1.oracleID ?? $1.path)
        if a != b { return a }
        let startsA = $0.name.lowercased().hasPrefix(term)
        let startsB = $1.name.lowercased().hasPrefix(term)
        if startsA != startsB { return startsA }
        if $0.kind != $1.kind { return $0.kind < $1.kind }
        return $0.name == $1.name
          ? $0.key < $1.key : $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }.prefix(8))
  }

  private static func slug(_ name: String, fallback: String, limit: Int) -> String {
    let normalized = String(
      String.UnicodeScalarView(
        name.decomposedStringWithCompatibilityMapping.unicodeScalars.filter {
          !(0x300...0x36F).contains($0.value)
        })
    ).lowercased()
    let slug = normalized.replacingOccurrences(
      of: "[^a-z0-9]+", with: "-", options: .regularExpression
    )
    .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let bounded = String(slug.prefix(limit)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return bounded.isEmpty ? fallback : bounded
  }
  static func hash(_ value: String) -> String {
    var hash: UInt32 = 0x811C_9DC5
    for scalar in value.unicodeScalars { hash = (hash ^ scalar.value) &* 0x0100_0193 }
    let text = String(hash, radix: 36)
    return String((String(repeating: "0", count: max(0, 6 - text.count)) + text).suffix(6))
  }
}
