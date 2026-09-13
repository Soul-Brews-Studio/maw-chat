import AppKit
import MawCore
import SwiftUI

struct MarkdownContent: View, Equatable {
  let text: String
  private func inline(_ value: String) -> AttributedString {
    (try? AttributedString(
      markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(value)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
        switch block {
        case .paragraph(let value): Text(inline(value)).textSelection(.enabled)
        case .heading(let level, let value):
          Text(inline(value)).font(
            .system(size: level == 1 ? 24 : level == 2 ? 20 : 16, weight: .semibold)
          ).padding(.top, 4).textSelection(.enabled)
        case .code(let language, let content): CodeBlockView(language: language, code: content)
        case .quote(let value):
          Text(inline(value)).foregroundStyle(.secondary).padding(.leading, 12).textSelection(
            .enabled)
        case .bullet(let value):
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 4)).padding(.top, 6)
            Text(inline(value)).textSelection(.enabled)
          }
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct CodeBlockView: View {
  let language: String
  let code: String
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(language.isEmpty ? "Code" : language).font(.caption.weight(.medium))
        Spacer()
        Button("Copy code", systemImage: "doc.on.doc") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(code, forType: .string)
        }.buttonStyle(.plain).font(.caption).handCursor()
      }.foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 8)
      Divider()
      Text(verbatim: code).font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
    }.background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.08), lineWidth: 1))
  }
}
