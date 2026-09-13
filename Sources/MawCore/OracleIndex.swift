import Foundation

public struct OracleThread: Identifiable, Sendable, Equatable {
  public let id: String
  public let title: String
  public let sessionID: String?
  public let tagKey: String
  public let updatedAt: Double
  public let isReadOnly: Bool
  public let isRunning: Bool
}

public struct OracleGroup: Identifiable, Sendable, Equatable {
  public var id: String { path ?? "local-workspace" }
  public let name: String
  public let path: String?
  public var projectID: String?
  public var threads: [OracleThread]
  public var modifiedAt: Double
}

/// One sidebar projection for imported chats and SDK-discovered Claude sessions.
public enum OracleIndex {
  public static func groups(
    state: ChatState, sessions: [NativeChatSession], repositories: [ChatRepository] = [],
    query: String = "", tags: [String: [String]] = [:], favorites: Set<String> = []
  ) -> [OracleGroup] {
    var byPath: [String: OracleGroup] = [:]
    var projectPaths: [String: String] = [:]
    for repo in repositories {
      let path = normalize(repo.path)
      byPath[path] = OracleGroup(
        name: repo.name, path: path, projectID: nil,
        threads: [], modifiedAt: repo.modifiedAt ?? 0)
    }
    for project in state.projects {
      let path = normalize(project.canonicalPath ?? project.path)
      projectPaths[project.id] = path
      if byPath[path]?.projectID == nil {
        byPath[path] = OracleGroup(
          name: project.name, path: path, projectID: project.id,
          threads: [], modifiedAt: byPath[path]?.modifiedAt ?? 0)
      }
    }
    // Prefer a saved project/repository parent over inventing a group for a subdirectory.
    let roots = Set(byPath.keys)
    let imported = Set(state.chats.compactMap(\.sessionId))
    var seen: Set<String> = []
    for session in sessions.sorted(by: { timestamp($0) > timestamp($1) }) {
      guard let id = session.sessionId, !id.isEmpty, !imported.contains(id),
        seen.insert(id).inserted
      else { continue }
      let cwd = normalize(session.canonicalPath ?? session.cwd)
      let path = enclosingRoot(cwd, roots: roots) ?? cwd
      if byPath[path] == nil {
        // Discovery is bounded server-side; don't lose history outside its inventory.
        byPath[path] = OracleGroup(
          name: URL(fileURLWithPath: path).lastPathComponent,
          path: path, projectID: nil, threads: [], modifiedAt: 0)
      }
      byPath[path]?.threads.append(
        OracleThread(
          id: "native:" + id,
          title: session.name ?? "Untitled conversation", sessionID: id, tagKey: id,
          updatedAt: timestamp(session), isReadOnly: session.action != "resume",
          isRunning: session.status == "running"))
    }
    for chat in state.chats {
      let path = chat.projectId.flatMap { projectPaths[$0] } ?? ""
      if byPath[path] == nil {
        byPath[path] = OracleGroup(
          name: "Local workspace", path: nil, projectID: nil,
          threads: [], modifiedAt: 0)
      }
      byPath[path]?.threads.append(
        OracleThread(
          id: "chat:" + chat.id, title: chat.title,
          sessionID: chat.sessionId, tagKey: chat.sessionId ?? "chat:" + chat.id,
          updatedAt: timestamp(chat.updatedAt ?? chat.createdAt), isReadOnly: false,
          isRunning: chat.status == "running"))
    }
    return filtered(Array(byPath.values), query: query, tags: tags, favorites: favorites)
  }

  /// Search the cached metadata, not messages or the repository inventory again.
  public static func filtered(
    _ groups: [OracleGroup], query: String = "", tags: [String: [String]] = [:],
    favorites: Set<String> = []
  ) -> [OracleGroup] {
    return groups.compactMap { group -> OracleGroup? in
      var group = group
      group.threads.sort {
        $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id
      }
      group.threads = group.threads.filter {
        ConversationIndex.matches(
          query: query, title: $0.title,
          project: group.name + " " + (group.path ?? ""), sessionID: $0.sessionID,
          tags: tags[$0.tagKey] ?? [])
      }
      let matchesProject = ConversationIndex.matches(
        query: query, title: group.name,
        project: group.path ?? "", sessionID: nil, tags: [])
      return matchesProject || !group.threads.isEmpty ? group : nil
    }.sorted {
      let a = favorites.contains($0.id)
      let b = favorites.contains($1.id)
      if a != b { return a }
      if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
      return $0.id.localizedStandardCompare($1.id) == .orderedAscending
    }
  }

  public static func sidebar(
    _ groups: [OracleGroup], query: String = "", tags: [String: [String]] = [:],
    favorites: Set<String> = []
  ) -> [OracleGroup] {
    let input =
      query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? groups.filter { favorites.contains($0.id) } : groups
    return filtered(input, query: query, tags: tags, favorites: favorites)
  }

  /// Oracle chooser searches names/paths before limiting the displayed results.
  public static func picker(
    _ groups: [OracleGroup], query: String = "", favorites: Set<String> = []
  ) -> [OracleGroup] {
    let matching = groups.filter {
      ConversationIndex.matches(
        query: query, title: $0.name,
        project: $0.path ?? "", sessionID: nil, tags: [])
    }
    return Array(
      matching.sorted {
        let a = favorites.contains($0.id)
        let b = favorites.contains($1.id)
        if a != b { return a }
        if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
        return $0.id < $1.id
      }.prefix(30))
  }

  private static func enclosingRoot(_ cwd: String, roots: Set<String>) -> String? {
    var candidate = cwd
    while !candidate.isEmpty {
      if roots.contains(candidate) { return candidate }
      if candidate == "/" { return nil }
      guard let slash = candidate.lastIndex(of: "/") else { return nil }
      candidate = slash == candidate.startIndex ? "/" : String(candidate[..<slash])
    }
    return nil
  }

  public static func normalize(_ path: String) -> String {
    var path = path
    while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
    return path
  }
  private static func timestamp(_ session: NativeChatSession) -> Double {
    session.updatedAt ?? session.startedAt ?? 0
  }
  private static func timestamp(_ text: String?) -> Double {
    guard let text else { return 0 }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date.timeIntervalSince1970 * 1000 }
    formatter.formatOptions = [.withInternetDateTime]
    return (formatter.date(from: text)?.timeIntervalSince1970 ?? 0) * 1000
  }
}

/// A serial non-main executor for CPU work; callers coalesce updates and reject stale results.
public actor OracleIndexWorker {
  public init() {}
  public func build(state: ChatState, sessions: [NativeChatSession], repositories: [ChatRepository])
    -> [OracleGroup]
  {
    OracleIndex.groups(state: state, sessions: sessions, repositories: repositories)
  }
  public func search(
    groups: [OracleGroup], query: String, tags: [String: [String]], favorites: Set<String>
  ) -> [OracleGroup] {
    guard !Task.isCancelled else { return [] }
    return OracleIndex.sidebar(groups, query: query, tags: tags, favorites: favorites)
  }
  public func picker(groups: [OracleGroup], query: String, favorites: Set<String>) -> [OracleGroup]
  {
    guard !Task.isCancelled else { return [] }
    return OracleIndex.picker(groups, query: query, favorites: favorites)
  }

}
