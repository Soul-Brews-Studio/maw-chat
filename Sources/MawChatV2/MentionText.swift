import Foundation

struct MentionQuery: Equatable {
  let range: NSRange
  let fragment: String
}

enum MentionText {
  private static let trigger = try! NSRegularExpression(pattern: "(?:^|\\s)@([^\\s@]*)$")
  static func query(_ text: String, caret: Int) -> MentionQuery? {
    let source = text as NSString
    let end = min(max(0, caret), source.length)
    let prefix = source.substring(to: end)
    guard let match = trigger.firstMatch(in: prefix, range: NSRange(location: 0, length: end))
    else { return nil }
    let fragment = match.range(at: 1)
    return MentionQuery(
      range: NSRange(location: fragment.location - 1, length: fragment.length + 1),
      fragment: (prefix as NSString).substring(with: fragment))
  }
  // Preserve bindings across inventory refreshes, even if a different project reuses a name.
  static func binding(_ candidate: MentionCandidate, selected: [MentionCandidate])
    -> MentionCandidate
  {
    if let existing = selected.first(where: { $0.key == candidate.key }) { return existing }
    let tokens = Set(selected.map(\.token))
    var bound = candidate
    var attempt = 0
    while tokens.contains(bound.token) {
      let suffix = "-" + MentionIndex.hash(candidate.key) + (attempt == 0 ? "" : "-\(attempt)")
      bound.token = String(candidate.token.prefix(256 - suffix.count)) + suffix
      attempt += 1
    }
    return bound
  }
  static func insert(_ candidate: MentionCandidate, into text: String, query: MentionQuery) -> (
    text: String, caret: Int
  ) {
    let source = text as NSString
    let suffix = source.substring(from: NSMaxRange(query.range))
    let inserted = candidate.token + (suffix.hasPrefix(" ") ? "" : " ")
    return (
      source.replacingCharacters(in: query.range, with: inserted),
      query.range.location + inserted.utf16.count
    )
  }
  static func contains(_ token: String, in text: String) -> Bool {
    var start = text.startIndex
    func tokenCharacter(_ value: Character) -> Bool {
      value.isLetter || value.isNumber || "_:@-".contains(value)
    }
    while start < text.endIndex, let range = text.range(of: token, range: start..<text.endIndex) {
      let before =
        range.lowerBound == text.startIndex
        || !tokenCharacter(text[text.index(before: range.lowerBound)])
      let after = range.upperBound == text.endIndex || !tokenCharacter(text[range.upperBound])
      if before && after { return true }
      start = range.upperBound
    }
    return false
  }
  static func expand(_ text: String, selected: [MentionCandidate]) throws -> String {
    var keys: Set<String> = []
    let references = Array(
      selected.filter { contains($0.token, in: text) && keys.insert($0.key).inserted }.prefix(32))
    guard !references.isEmpty else { return text }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let metadata = String(decoding: try encoder.encode(references), as: UTF8.self)
      .replacingOccurrences(of: "`", with: "\\u0060")
    return text + "\n\nReferenced context (metadata only; not conversation history):\n```json\n"
      + metadata + "\n```"
  }
}
