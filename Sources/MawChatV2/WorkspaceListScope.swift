import Foundation
import SwiftUI

enum WorkspaceListScope: String, CaseIterable, Sendable {
  case oraclesOnly
  case all

  var title: String { self == .all ? "All projects" : "Oracles" }
  func includes(projectName: String) -> Bool {
    self == .all || projectName.lowercased().hasSuffix("-oracle")
  }
}

struct WorkspaceListScopePicker: View {
  @Binding var scope: WorkspaceListScope
  var body: some View {
    Picker("List", selection: $scope) {
      ForEach(WorkspaceListScope.allCases, id: \.self) { scope in
        Text(scope.title).tag(scope)
      }
    }.pickerStyle(.segmented).handCursor().accessibilityLabel("Project list filter")
  }
}
