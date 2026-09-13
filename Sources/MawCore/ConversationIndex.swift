import Foundation

/// Indexes each conversation separately even when many share one Oracle folder.
public enum ConversationIndex {
  public static func matches(
    query: String, title: String, project: String, sessionID: String?, tags: [String]
  ) -> Bool {
    let haystack = ([title, project, sessionID ?? ""] + tags).joined(separator: " ")
    return query.split(whereSeparator: \.isWhitespace).allSatisfy { token in
      let term = token.hasPrefix("#") ? String(token.dropFirst()) : String(token)
      return haystack.localizedCaseInsensitiveContains(term)
    }
  }
  public static func parseTags(_ text: String) -> [String] {
    var result: [String] = []
    for part in text.split(separator: ",") {
      let value = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
      if !value.isEmpty && !result.contains(value) { result.append(value) }
    }
    return Array(result.prefix(20))
  }
}
