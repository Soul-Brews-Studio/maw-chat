import Foundation

public enum MarkdownBlock: Equatable, Sendable {
  case paragraph(String)
  case code(language: String, content: String)
  case heading(level: Int, text: String)
  case quote(String)
  case bullet(String)
}

public enum MarkdownBlocks {
  public static func parse(_ text: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var code: [String] = []
    var fence: Character?
    var fenceCount = 0
    var language = ""
    func flushParagraph() {
      if !paragraph.isEmpty {
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph = []
      }
    }
    for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if let active = fence {
        let count = trimmed.prefix(while: { $0 == active }).count
        if count >= fenceCount
          && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty
        {
          blocks.append(.code(language: language, content: code.joined(separator: "\n")))
          fence = nil
          code = []
        } else {
          code.append(line)
        }
        continue
      }
      if let first = trimmed.first, first == "`" || first == "~" {
        let count = trimmed.prefix(while: { $0 == first }).count
        if count >= 3 {
          flushParagraph()
          fence = first
          fenceCount = count
          language = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
          continue
        }
      }
      if trimmed.isEmpty {
        flushParagraph()
        continue
      }
      let hashes = trimmed.prefix(while: { $0 == "#" }).count
      if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
        flushParagraph()
        blocks.append(.heading(level: hashes, text: String(trimmed.dropFirst(hashes + 1))))
        continue
      }
      if trimmed.hasPrefix("> ") {
        flushParagraph()
        blocks.append(.quote(String(trimmed.dropFirst(2))))
        continue
      }
      if ["- ", "* ", "+ "].contains(where: { trimmed.hasPrefix($0) }) {
        flushParagraph()
        blocks.append(.bullet(String(trimmed.dropFirst(2))))
        continue
      }
      paragraph.append(line)
    }
    if fence != nil {
      blocks.append(.code(language: language, content: code.joined(separator: "\n")))
    }
    flushParagraph()
    return blocks
  }
}
