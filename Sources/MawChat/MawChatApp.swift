import AppKit
import SwiftUI

@main
struct MawChatApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  var body: some Scene {
    WindowGroup("Maw Chat") { ChatWorkspaceView() }
      .defaultSize(width: 1180, height: 820)
  }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    if let url = Bundle.main.url(forResource: "MawChatIcon", withExtension: "icns"),
      let icon = NSImage(contentsOf: url)
    {
      NSApplication.shared.applicationIconImage = icon
    }
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
