import Foundation

enum TerminalSnapshot {
  /// Snapshots are readable text, not a terminal emulator: discard ANSI/control strings.
  static func plainText(_ text: String) -> String {
    enum Mode { case text, escape, csi, controlString, stringEscape }
    var mode = Mode.text
    var output = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
      let value = scalar.value
      switch mode {
      case .text:
        if value == 27 {
          mode = .escape
        } else if value == 0x9B {
          mode = .csi
        } else if value == 0x9D {
          mode = .controlString
        } else if value == 10 || value == 9 || (value >= 32 && !(127...159).contains(value)) {
          output.append(scalar)
        }
      case .escape:
        if value == 91 {
          mode = .csi
        } else if [93, 80, 94, 95].contains(value) {
          mode = .controlString
        } else {
          mode = .text
        }
      case .csi:
        if (0x40...0x7E).contains(value) { mode = .text }
      case .controlString:
        if value == 7 || value == 0x9C { mode = .text } else if value == 27 { mode = .stringEscape }
      case .stringEscape:
        mode = value == 92 ? .text : .controlString
      }
    }
    let tail = String(output).split(separator: "\n", omittingEmptySubsequences: false).suffix(200)
      .joined(separator: "\n")
    return String(tail.suffix(65_536))
  }
}
