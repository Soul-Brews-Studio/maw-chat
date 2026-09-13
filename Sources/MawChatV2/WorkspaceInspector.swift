import SwiftUI

struct WorkspaceInspector: View {
  @Bindable var store: ChatWorkspace
  @Bindable var preferences: WorkspacePreferences
  @Binding var sheet: WorkspaceSheet?
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 13) {
        Spacer()
        IconButton(title: "Workspace settings", icon: "gearshape") { sheet = .settings }
        IconButton(title: "Collapse inspector", icon: "chevron.right.2") {
          preferences.inspector = false
        }
      }.padding(.horizontal, 19).frame(height: 52)
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Button {
            sheet = .members
          } label: {
            Label("Edit Group members", systemImage: "pencil")
              .font(.system(size: 14, weight: .medium)).padding(.horizontal, 14).frame(height: 24)
              .background(WorkspaceTheme.selected, in: RoundedRectangle(cornerRadius: 6))
          }.buttonStyle(.plain).handCursor()
          Text(store.oracleName + ", Claude")
            .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary).lineLimit(2)
          LiveStreamPanel(groups: store.sidebarGroups)
          HStack {
            Text("Routines").font(.system(size: 15)).foregroundStyle(WorkspaceTheme.secondary)
            Spacer()
            IconButton(title: "About routines", icon: "plus") { sheet = .routines }
          }.padding(.top, 10).padding(.bottom, 4)
          Text("No routines yet").font(.system(size: 13))
          Text(
            "No routine service is configured. No runs while the app is closed, the Mac is asleep, or you are logged out."
          )
          .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 20)
        }.padding(.horizontal, 19)
      }
    }
  }
}
