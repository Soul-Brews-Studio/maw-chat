import AppKit
import SwiftUI

@main struct MawChatV2App {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = WorkspaceAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
  }
}

@MainActor final class WorkspaceAppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?
  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 880),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.title = "Maw Chat V2"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    window.backgroundColor = NSColor(white: 7 / 255, alpha: 1)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentMinSize = NSSize(width: 760, height: 600)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: WorkspaceView())
    self.window = window
    installMenus()
    if let url = Bundle.main.url(forResource: "MawChatIcon", withExtension: "icns") {
      NSApp.applicationIconImage = NSImage(contentsOf: url)
    }
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  private func installMenus() {
    let menu = NSMenu()
    let app = NSMenuItem()
    app.submenu = NSMenu()
    app.submenu?.addItem(
      withTitle: "Quit Maw Chat V2", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    menu.addItem(app)
    let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    edit.submenu = NSMenu(title: "Edit")
    for (title, action, key) in [
      ("Undo", Selector(("undo:")), "z"),
      ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
      ("Paste", #selector(NSText.paste(_:)), "v"),
      ("Select All", #selector(NSText.selectAll(_:)), "a"),
    ] {
      edit.submenu?.addItem(withTitle: title, action: action, keyEquivalent: key)
    }
    menu.addItem(edit)
    NSApp.mainMenu = menu
  }
}
