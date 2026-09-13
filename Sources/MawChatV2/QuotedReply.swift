import Foundation
import SwiftUI

struct QuotedReply: Equatable {
  let sender: String
  let quote: String
  let body: String

  /// Only the explicit wire format authored by this client becomes a reply card.
  static func parse(_ content: String) -> QuotedReply? {
    let lines = content.components(separatedBy: "\n")
    guard let first = lines.first, first.hasPrefix("Replying to "), first.hasSuffix(":"),
      lines.count > 3
    else { return nil }
    var index = 1
    var quoted: [String] = []
    while index < lines.count && lines[index].hasPrefix("> ") {
      quoted.append(String(lines[index].dropFirst(2)))
      index += 1
    }
    guard !quoted.isEmpty, index < lines.count, lines[index].isEmpty else { return nil }
    return QuotedReply(
      sender: String(first.dropFirst(12).dropLast()),
      quote: quoted.joined(separator: "\n"),
      body: lines.dropFirst(index + 1).joined(separator: "\n"))
  }
}

struct QuotedReplyCard: View {
  let reply: QuotedReply
  var body: some View {
    HStack(alignment: .top, spacing: 7) {
      RoundedRectangle(cornerRadius: 2).fill(WorkspaceTheme.green).frame(width: 3)
      VStack(alignment: .leading, spacing: 3) {
        Text(reply.sender).font(.system(size: 11, weight: .semibold))
        Text(reply.quote).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary)
          .lineLimit(3).textSelection(.enabled)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.padding(10).fixedSize(horizontal: false, vertical: true)
      .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 9))
      .overlay(RoundedRectangle(cornerRadius: 9).stroke(WorkspaceTheme.separator))
  }
}
