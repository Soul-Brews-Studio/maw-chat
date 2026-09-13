import Foundation
import MawCore

struct WorkspaceRow: Identifiable, Sendable, Equatable {
  let id: String
  let title: String
  let preview: String
  let oracleID: String
  let oracleName: String
  let tagKey: String
  let updatedAt: Double
  let isOracle: Bool
  let readOnly: Bool
}

/// Small metadata projections only; never scans full transcripts on keystrokes.
actor WorkspaceIndex {
  func rows(groups: [OracleGroup], state: ChatState) -> [WorkspaceRow] {
    let chats = Dictionary(uniqueKeysWithValues: state.chats.map { ("chat:" + $0.id, $0) })
    return groups.flatMap { group in
      let oracle = WorkspaceRow(
        id: "oracle:" + group.id, title: group.name,
        preview: "Start a conversation", oracleID: group.id, oracleName: group.name,
        tagKey: group.id, updatedAt: group.modifiedAt, isOracle: true, readOnly: false)
      return [oracle]
        + group.threads.map { thread in
          let preview = chats[thread.id]?.messages.last(where: { !$0.content.isEmpty })?.content
          return WorkspaceRow(
            id: thread.id, title: thread.title,
            preview: preview.map {
              String($0.prefix(140)).replacingOccurrences(of: "\n", with: " ")
            }
              ?? group.name + (thread.isReadOnly ? " · Active session" : " · Claude session"),
            oracleID: group.id, oracleName: group.name, tagKey: thread.tagKey,
            updatedAt: thread.updatedAt, isOracle: false, readOnly: thread.isReadOnly)
        }
    }
  }
  func search(
    _ rows: [WorkspaceRow], query: String, favorites: Set<String>,
    tags: [String: [String]], limit: Int, scope: WorkspaceListScope = .all, oracleID: String? = nil
  ) -> [WorkspaceRow] {
    let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return Array(
      rows.filter { row in
        let visible =
          oracleID != nil || searching || favorites.contains(row.oracleID)
          || row.id.hasPrefix("chat:")
        let inOracle = oracleID == nil || (row.oracleID == oracleID && !row.isOracle)
        return visible && inOracle && scope.includes(projectName: row.oracleName)
          && ConversationIndex.matches(
            query: query, title: row.title,
            project: row.oracleName + " " + row.oracleID, sessionID: row.tagKey,
            tags: tags[row.tagKey] ?? [])
      }.sorted { a, b in
        let af = favorites.contains(a.oracleID)
        let bf = favorites.contains(b.oracleID)
        if af != bf { return af }
        if a.isOracle != b.isOracle { return !a.isOracle }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        return a.id < b.id
      }.prefix(limit))
  }
  func picker(
    groups: [OracleGroup], query: String, favorites: Set<String>,
    scope: WorkspaceListScope
  ) -> (groups: [OracleGroup], total: Int) {
    let eligible = groups.filter { scope.includes(projectName: $0.name) }
    return (OracleIndex.picker(eligible, query: query, favorites: favorites), eligible.count)
  }

}

enum MessageDate {
  private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let whole = Date.ISO8601FormatStyle()
  static func parse(_ value: String?) -> Date? {
    guard let value else { return nil }
    return (try? fractional.parse(value)) ?? (try? whole.parse(value))
  }
}

struct ReplyContext: Equatable {
  let sender: String
  let text: String
  var content: String {
    "Replying to \(sender):\n"
      + text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { "> " + $0 }.joined(separator: "\n")
  }
}
