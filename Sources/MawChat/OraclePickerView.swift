import MawCore
import SwiftUI

struct OraclePickerView: View {
  let groups: [OracleGroup]
  let worker: OracleIndexWorker
  let favorites: Set<String>
  let choose: (OracleGroup) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var results: [OracleGroup] = []
  @FocusState private var searchFocused: Bool
  private struct QueryKey: Equatable {
    let query: String
    let groups: [OracleGroup]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Add Oracle").font(.title2.bold())
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).handCursor()
      }
      Text("Choose an Oracle to keep in Favorites. Start a new thread from its sidebar.")
        .font(.callout).foregroundStyle(.secondary)
      TextField("Type an Oracle name or folder…", text: $query)
        .textFieldStyle(.roundedBorder).focused($searchFocused)
        .accessibilityLabel("Find an Oracle")
        .onSubmit { if let first = results.first { choose(first) } }
      List(results) { oracle in
        Button {
          choose(oracle)
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "folder")
            VStack(alignment: .leading, spacing: 4) {
              Text(oracle.name).font(.headline)
              Text(oracle.path ?? "Local workspace").font(.caption)
                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Image(systemName: favorites.contains(oracle.id) ? "star.fill" : "plus.circle")
              .foregroundStyle(.tint)
          }.padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain).handCursor().accessibilityLabel("Add " + oracle.name)
        .help(oracle.path ?? "Local workspace")
      }
      .listStyle(.plain)
      .overlay {
        if results.isEmpty {
          Text(groups.isEmpty ? "Loading Oracles…" : "No matching Oracle")
            .foregroundStyle(.secondary)
        }
      }
      Text("Favorites stay on this Mac. No chat is created until you send a message.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(24).frame(width: 480, height: 440)
    .task { searchFocused = true }
    .task(id: QueryKey(query: query, groups: groups)) {
      let found = await worker.picker(groups: groups, query: query, favorites: favorites)
      guard !Task.isCancelled else { return }
      results = found
    }
  }
}
