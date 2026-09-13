import AppKit
import SwiftUI

extension View {
  /// Apply inside any `.disabled(...)` modifier so enabled state is inherited.
  func handCursor(enabled: Bool = true) -> some View {
    modifier(HandCursorModifier(active: enabled))
  }
}

private struct HandCursorModifier: ViewModifier {
  @Environment(\.isEnabled) private var isEnabled
  let active: Bool
  func body(content: Content) -> some View {
    content.background {
      CursorRegion(enabled: active && isEnabled)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
  }
}

/// AppKit manages cursor lifetime, including scrolling/removal; no hover state or cursor stack.
private struct CursorRegion: NSViewRepresentable {
  let enabled: Bool
  func makeNSView(context: Context) -> CursorRegionView {
    let view = CursorRegionView()
    view.enabled = enabled
    return view
  }
  func updateNSView(_ view: CursorRegionView, context: Context) {
    guard view.enabled != enabled else { return }
    view.enabled = enabled
    view.window?.invalidateCursorRects(for: view)
  }
}

private final class CursorRegionView: NSView {
  var enabled = true
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.invalidateCursorRects(for: self)
  }
  override func resetCursorRects() {
    super.resetCursorRects()
    let region = bounds.intersection(visibleRect)
    if enabled && !region.isEmpty { addCursorRect(region, cursor: .pointingHand) }
  }
}
