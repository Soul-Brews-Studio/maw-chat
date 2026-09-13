import AppKit
import SwiftUI
import Testing

@testable import MawChatV2

@Test @MainActor func codeBlocksWrapToAvailableWidthInsteadOfScrolling() {
  let code = String(repeating: "example-command --option /a/long/path ", count: 12)
  func height(_ width: CGFloat) -> CGFloat {
    NSHostingView(rootView: CodeBlockView(language: "sh", code: code).frame(width: width))
      .fittingSize.height
  }
  #expect(height(260) > height(520))
}

@Test @MainActor func codeBlocksGrowVerticallyWithoutAnInternalScrollCap() {
  let code = (1...50).map { "line \($0)" }.joined(separator: "\n")
  let view = NSHostingView(rootView: CodeBlockView(language: "", code: code).frame(width: 400))
  #expect(view.fittingSize.height > 600)
}
