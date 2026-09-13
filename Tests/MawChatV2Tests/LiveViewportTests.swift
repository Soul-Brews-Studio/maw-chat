import AppKit
import Testing

@testable import MawChatV2

@Test func fittedSnapshotStaysInsideBothAxesAndNeverUpscales() {
  #expect(
    SnapshotFit.scale(
      content: CGSize(width: 100, height: 100), viewport: CGSize(width: 220, height: 220)) == 1)
  #expect(
    SnapshotFit.scale(
      content: CGSize(width: 1000, height: 100), viewport: CGSize(width: 220, height: 220)) == 0.2)
  #expect(
    SnapshotFit.scale(
      content: CGSize(width: 100, height: 1000), viewport: CGSize(width: 220, height: 220)) == 0.2)
  #expect(
    SnapshotFit.scale(
      content: CGSize(width: 100, height: 100), viewport: CGSize(width: 5, height: 5)) == 0)
  #expect(SnapshotFit.scale(content: .zero, viewport: .zero) == 1)
}

@Test @MainActor func fittedSnapshotIsReadOnlyAccessibleAndHasNoScrollView() {
  let view = TerminalSnapshotView(frame: NSRect(x: 0, y: 0, width: 280, height: 210))
  view.setText("hello\nworld")
  #expect(view.accessibilityRole() == .staticText)
  #expect(view.accessibilityValue() as? String == "hello\nworld")
  #expect(view.subviews.isEmpty)
  view.setFrameSize(NSSize(width: 200, height: 100))
  #expect(view.bounds.size == NSSize(width: 200, height: 100))
  view.setText("")
  #expect(view.accessibilityValue() as? String == "")
}
