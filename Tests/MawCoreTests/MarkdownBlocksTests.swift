import Testing

@testable import MawCore

@Test func fencedJSONKeepsOriginalLineBreaks() {
  let source = "Referenced context:\n\n```json\n[\n  {\"name\": \"neo\"}\n]\n```\n\nAfter."
  #expect(
    MarkdownBlocks.parse(source) == [
      .paragraph("Referenced context:"),
      .code(language: "json", content: "[\n  {\"name\": \"neo\"}\n]"),
      .paragraph("After."),
    ])
}
@Test func streamingUnclosedFenceIsStillCode() {
  #expect(
    MarkdownBlocks.parse("```swift\nlet answer = 42") == [
      .code(language: "swift", content: "let answer = 42")
    ])
}
@Test func markdownStructureAndUnicodeSurvive() {
  #expect(
    MarkdownBlocks.parse("## หัวข้อ\n\n- One\n- Two\n\n> Quote\n\nA\nparagraph") == [
      .heading(level: 2, text: "หัวข้อ"), .bullet("One"), .bullet("Two"), .quote("Quote"),
      .paragraph("A\nparagraph"),
    ])
}
@Test func longerFenceCanContainTripleBackticks() {
  #expect(
    MarkdownBlocks.parse("````text\n```json\nx\n```\n````") == [
      .code(language: "text", content: "```json\nx\n```")
    ])
}
