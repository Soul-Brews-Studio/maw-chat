import AppKit
import SwiftUI
import Testing

@testable import MawChatV2

@Test @MainActor func oracleMenuReservesIdenticalHeightInTreeAndSessionModes() {
  func height(browsing: Bool) -> CGFloat {
    let store = ChatWorkspace()
    store.browsingSessions = browsing
    let view = NSHostingView(
      rootView: OracleSessionScope(store: store, sheet: .constant(nil)).frame(width: 280))
    return view.fittingSize.height
  }
  #expect(height(browsing: false) == height(browsing: true))
}
