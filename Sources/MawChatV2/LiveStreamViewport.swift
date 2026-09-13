import AppKit
import SwiftUI

enum LiveViewScale: Equatable {
  case fit, actual
}

enum SnapshotFit {
  static func scale(content: CGSize, viewport: CGSize, inset: CGFloat = 10) -> CGFloat {
    guard content.width > 0, content.height > 0 else { return 1 }
    let width = max(0, viewport.width - inset * 2)
    let height = max(0, viewport.height - inset * 2)
    return min(1, width / content.width, height / content.height)
  }
}

/// Native, bounded drawing: fitting never wraps, scrolls, or resizes the real terminal.
struct FittedTerminalSnapshot: NSViewRepresentable {
  let text: String
  func makeNSView(context: Context) -> TerminalSnapshotView { TerminalSnapshotView() }
  func updateNSView(_ view: TerminalSnapshotView, context: Context) { view.setText(text) }
}

final class TerminalSnapshotView: NSView {
  private var text: String?
  private var styled = NSAttributedString(string: "")
  private var measured = CGSize.zero
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityLabel("Fitted read-only tmux output")
  }
  required init?(coder: NSCoder) { nil }
  func setText(_ value: String) {
    guard value != text else { return }
    text = value
    styled = NSAttributedString(
      string: value.isEmpty ? "Pane is empty" : value,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor(white: 0.9, alpha: 1),
      ])
    let natural = styled.size()
    measured = CGSize(width: ceil(natural.width), height: ceil(natural.height))
    setAccessibilityValue(value)
    needsDisplay = true
  }
  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    let scale = SnapshotFit.scale(content: measured, viewport: bounds.size)
    guard scale > 0 else { return }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSBezierPath(rect: bounds).addClip()
    let transform = NSAffineTransform()
    transform.translateX(by: 10, yBy: 10)
    transform.scale(by: scale)
    transform.concat()
    styled.draw(at: .zero)
  }
}

/// Renderer boundary for future image-frame providers; no VNC transport is enabled yet.
struct LiveStreamPayloadView: View, Equatable {
  let payload: LiveStreamFrame.Payload
  let scale: LiveViewScale
  var body: some View {
    switch payload {
    case .text(let text):
      Group {
        if scale == .fit {
          FittedTerminalSnapshot(text: text)
        } else {
          ScrollView([.vertical, .horizontal]) {
            Text(verbatim: text.isEmpty ? "Pane is empty" : text)
              .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
              .foregroundStyle(WorkspaceTheme.foreground)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
          }.accessibilityLabel("Read-only tmux output")
        }
      }.contextMenu {
        Button("Copy snapshot") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        }
      }
    case .image(let data):
      if let image = NSImage(data: data) {
        Image(nsImage: image).resizable().scaledToFit().accessibilityLabel("Live screen snapshot")
      } else {
        Text("Unable to display this screen snapshot.")
      }
    }
  }
}
