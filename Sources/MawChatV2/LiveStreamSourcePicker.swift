import MawCore
import SwiftUI

struct LiveStreamSourcePicker: View {
  @Bindable var stream: LiveStreamModel
  @Binding var endpoint: String
  let groups: [OracleGroup]
  @State private var scope = WorkspaceListScope.oraclesOnly
  @State private var address = ""
  @State private var query = ""
  @Environment(\.dismiss) private var dismiss
  private var eligible: [LiveStreamSource] {
    LiveSourceList.filtered(stream.sources, groups: groups, scope: scope, query: query)
  }
  private var matching: [LiveStreamSource] { Array(eligible.prefix(40)) }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Choose live source").font(.title2.weight(.semibold))
      Text("Tmux · read only. Chat sessions and this live view are independent.")
        .font(.callout).foregroundStyle(WorkspaceTheme.secondary)
      WorkspaceListScopePicker(scope: $scope)
      HStack {
        TextField("Local maw server URL", text: $address).textFieldStyle(.roundedBorder)
        Button("Load panes") {
          if endpoint != address {
            endpoint = address
          } else {
            Task { await stream.refresh(endpoint: endpoint) }
          }
        }.handCursor().disabled(stream.loading)
      }
      if address != endpoint {
        Text("Load panes to apply this server address.").font(.caption).foregroundStyle(.orange)
      }
      TextField("Search tmux panes", text: $query).textFieldStyle(.roundedBorder)
      if stream.loading { ProgressView("Loading real tmux panes…") }
      if let error = stream.inventoryError {
        Text(error).font(.caption).foregroundStyle(.orange).fixedSize(
          horizontal: false, vertical: true)
      }
      ScrollView {
        LazyVStack(spacing: 6) {
          ForEach(matching) { source in
            Button {
              stream.connect(source)
              dismiss()
            } label: {
              HStack(spacing: 10) {
                Image(systemName: "terminal").font(.system(size: 20))
                VStack(alignment: .leading, spacing: 4) {
                  Text(source.name).fontWeight(.medium).lineLimit(1)
                  Text(source.id + " · " + source.detail).font(.caption)
                    .foregroundStyle(WorkspaceTheme.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
              }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(WorkspaceTheme.bubble, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).handCursor().disabled(stream.loading || address != endpoint)
          }
          if !stream.loading && matching.isEmpty {
            Text(
              stream.sources.isEmpty
                ? "No tmux panes available from this server."
                : "No matching panes. Try All projects or another search."
            )
            .foregroundStyle(WorkspaceTheme.secondary).padding(.vertical, 30)
          }
        }
      }.frame(height: 270)
      HStack {
        Text(
          "\(eligible.count) matching · \(matching.count) shown · \(stream.sources.count) total panes"
        )
        .font(.caption).foregroundStyle(WorkspaceTheme.secondary)
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).handCursor()
      }
    }.padding(24).frame(width: 560).background(WorkspaceTheme.sidebar)
      .foregroundStyle(WorkspaceTheme.foreground).preferredColorScheme(.dark)
      .onAppear { address = endpoint }
  }
}
