import AppKit
import SwiftUI

enum WorkspaceTheme {
  static let background = Color(hex: 0x070707)
  static let sidebar = Color(hex: 0x111111)
  static let bubble = Color(hex: 0x262626)
  static let selected = Color(hex: 0x353535)
  static let composer = Color(hex: 0x2D2D2D)
  static let foreground = Color(hex: 0xF3F3F3)
  static let secondary = Color(hex: 0xABABAB)
  static let separator = Color(hex: 0x292929)
  static let userBubble = Color(hex: 0x5A5A5A)
  static let green = Color(hex: 0x33B98D)
}

extension Color {
  fileprivate init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 255) / 255,
      green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
  }
}

struct WorkspaceLayout {
  let sidebar: CGFloat = 280
  let inspector: CGFloat = 320
  let showsInspector: Bool
  init(width: CGFloat, inspectorPreferred: Bool) {
    showsInspector = inspectorPreferred && width >= 1026
  }
}

struct IconButton: View {
  let title: String
  let icon: String
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 17))
        .frame(width: 26, height: 30).contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(WorkspaceTheme.secondary)
      .help(title).accessibilityLabel(title).handCursor()
  }
}

struct OracleAvatar: View {
  let name: String
  var conversation = false
  var size: CGFloat = 40
  private var tint: Color {
    let colors: [Color] = [.purple, .blue, .pink, .teal, .orange]
    return colors[name.utf8.reduce(0) { ($0 + Int($1)) % colors.count }]
  }
  var body: some View {
    ZStack {
      Circle().fill(conversation ? WorkspaceTheme.bubble : tint)
      if conversation {
        Image(systemName: "person.2.fill").font(.system(size: size * 0.42))
      } else {
        HStack(spacing: size * 0.14) {
          Capsule().frame(width: size * 0.08, height: size * 0.19)
          Capsule().frame(width: size * 0.08, height: size * 0.19)
        }.rotationEffect(.degrees(-18)).foregroundStyle(Color.black.opacity(0.8))
      }
    }.frame(width: size, height: size).accessibilityHidden(true)
  }
}
