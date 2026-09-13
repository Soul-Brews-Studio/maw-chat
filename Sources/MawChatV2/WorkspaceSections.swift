import Foundation
import MawCore

struct WorkspaceSection: Identifiable, Equatable, Sendable {
  var id: String { oracle.oracleID }
  let oracle: WorkspaceRow
  let threads: [WorkspaceRow]
  let totalSessions: Int
}

extension WorkspaceIndex {
  /// Project only metadata on the actor; bound groups here and visible children in the lazy view.
  func sections(
    _ rows: [WorkspaceRow], query: String, favorites: Set<String>,
    tags: [String: [String]], limit: Int, scope: WorkspaceListScope = .all, oracleID: String? = nil
  ) -> [WorkspaceSection] {
    let matches = search(
      rows, query: query, favorites: favorites, tags: tags,
      limit: rows.count, scope: scope, oracleID: oracleID)
    let eligible = Set(matches.map(\.oracleID))
    let headers = rows.filter {
      $0.isOracle
        && (eligible.contains($0.oracleID)
          || ($0.oracleID == oracleID && scope.includes(projectName: $0.oracleName)))
    }
    let allThreads = Dictionary(grouping: rows.filter { !$0.isOracle }, by: \.oracleID)
    let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let matchedThreads = Dictionary(grouping: matches.filter { !$0.isOracle }, by: \.oracleID)
    return Array(
      headers.map { header in
        let all = allThreads[header.oracleID] ?? []
        let threads = searching ? matchedThreads[header.oracleID] ?? [] : all
        return WorkspaceSection(
          oracle: header,
          threads: threads.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
          }, totalSessions: all.count)
      }.sorted { a, b in
        let af = favorites.contains(a.id)
        let bf = favorites.contains(b.id)
        if af != bf { return af }
        let ad = a.threads.first?.updatedAt ?? a.oracle.updatedAt
        let bd = b.threads.first?.updatedAt ?? b.oracle.updatedAt
        return ad == bd ? a.id < b.id : ad > bd
      }.prefix(limit))
  }
}

extension WorkspaceIndex {
  func sessions(
    _ rows: [WorkspaceRow], query: String, favorites: Set<String>, tags: [String: [String]],
    limit: Int, scope: WorkspaceListScope, oracleID: String?
  ) -> [WorkspaceRow] {
    // Colorful session browsing includes saved-only sessions, even without an imported chat or favorite.
    Array(
      rows.filter { row in
        !row.isOracle && (oracleID == nil || row.oracleID == oracleID)
          && scope.includes(projectName: row.oracleName)
          && ConversationIndex.matches(
            query: query, title: row.title,
            project: row.oracleName + " " + row.oracleID, sessionID: row.tagKey,
            tags: tags[row.tagKey] ?? [])
      }.sorted { a, b in
        let af = favorites.contains(a.oracleID)
        let bf = favorites.contains(b.oracleID)
        if af != bf { return af }
        return a.updatedAt == b.updatedAt ? a.id < b.id : a.updatedAt > b.updatedAt
      }.prefix(limit))
  }
}
