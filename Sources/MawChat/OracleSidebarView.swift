import AppKit
import MawCore
import SwiftUI

/// Independent Observation scope: this view never reads the composer draft or messages.
struct OracleSidebarView: View {
  @Bindable var store: ChatWorkspace
  let startThread: (OracleGroup?) -> Void
  let beginEdit: (String, String, String, Bool) -> Void
  @State private var query = ""
  @State private var choosingOracle = false
  @State private var matches: [OracleGroup] = []
  @State private var collapsed: Set<String> = []
  @State private var expanded: Set<String> = []
  @State private var projectLimit = 30
  @AppStorage("MawChat.favoriteOracles") private var favoriteJSON = "[]"
  @AppStorage("MawChat.conversationTags") private var tagJSON = "{}"
  @FocusState private var searchFocused: Bool
  private let accent = Color(red: 0.41, green: 0.26, blue: 0.85)
  private var favorites: Set<String> {
    Set((try? JSONDecoder().decode([String].self, from: Data(favoriteJSON.utf8))) ?? [])
  }
  private var tags: [String: [String]] {
    (try? JSONDecoder().decode([String: [String]].self, from: Data(tagJSON.utf8))) ?? [:]
  }
  private var idle: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  private struct SearchKey: Equatable {
    let groups: [OracleGroup]
    let query: String
    let favorites: String
    let tags: String
  }
  private var searchKey: SearchKey {
    SearchKey(groups: store.sidebarGroups, query: query, favorites: favoriteJSON, tags: tagJSON)
  }
  private enum Row: Identifiable {
    case oracle(OracleGroup)
    case thread(OracleThread)
    case newThread(OracleGroup)
    case moreThreads(OracleGroup, Int)
    case moreProjects(Int)
    var id: String {
      switch self {
      case .oracle(let group): "oracle:" + group.id
      case .thread(let thread): thread.id
      case .newThread(let group): "new:" + group.id
      case .moreThreads(let group, _): "more:" + group.id
      case .moreProjects: "more-projects"
      }
    }
    var selectable: Bool {
      if case .thread = self { return true }
      return false
    }
  }
  /// Flat stable identities: every ForEach item produces exactly one List row.
  private var rows: [Row] {
    var result: [Row] = []
    for oracle in matches.prefix(projectLimit) {
      result.append(.oracle(oracle))
      if collapsed.contains(oracle.id) && idle { continue }
      let threads =
        expanded.contains(oracle.id) || !idle
        ? oracle.threads : Array(oracle.threads.prefix(5))
      result += threads.map(Row.thread)
      if threads.count < oracle.threads.count {
        result.append(.moreThreads(oracle, oracle.threads.count - threads.count))
      }
      result.append(.newThread(oracle))
    }
    if matches.count > projectLimit { result.append(.moreProjects(matches.count - projectLimit)) }
    return result
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack(spacing: 8) {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable().scaledToFit().frame(width: 28, height: 28)
          .accessibilityHidden(true)
        Text("Maw Chat").font(.title2.bold())
      }.padding(.top, 12)
      Button("Add Oracle", systemImage: "folder.badge.plus") { choosingOracle = true }
        .buttonStyle(.borderedProminent).keyboardShortcut("o", modifiers: .command).handCursor()
        .disabled(store.busy)
      HStack {
        TextField("Search Oracles, chats, #tags…", text: $query)
          .textFieldStyle(.roundedBorder).accessibilityLabel("Search conversations")
          .focused($searchFocused)
        Button {
          searchFocused = true
        } label: {
          Image(systemName: "magnifyingglass")
        }
        .buttonStyle(.plain).keyboardShortcut("k", modifiers: .command).handCursor()
        .help("Search conversations (⌘K)")
      }
      HStack {
        Text(idle ? "Favorites" : "Search results").font(.headline)
        Spacer()
        Text("Recent first").font(.caption).foregroundStyle(.secondary)
      }
      List(selection: $store.selection) {
        ForEach(rows) { row in
          HStack(spacing: 0) { rowContent(row) }
            .tag(row.id).selectionDisabled(!row.selectable)
            .listRowInsets(EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 4))
        }
      }
      .listStyle(.sidebar).scrollContentBackground(.hidden)
      .overlay {
        if matches.isEmpty {
          Text(
            !store.nativeLoaded
              ? "Loading conversations…"
              : idle
                ? "Search for an Oracle, then star it to keep it here."
                : "No matching Oracles or conversations"
          )
          .font(.callout).foregroundStyle(.secondary).padding()
        }
      }
      if let warning = store.inventoryWarning {
        Label("Repository discovery is limited", systemImage: "exclamationmark.triangle")
          .font(.caption2).foregroundStyle(.secondary).help(warning)
      }
      HStack {
        Label(
          store.connected ? "Connected" : "Reconnecting…",
          systemImage: store.connected ? "checkmark.circle" : "arrow.triangle.2.circlepath"
        )
        .font(.caption).foregroundStyle(store.connected ? .green : .secondary)
        Spacer()
        Button {
          Task {
            await store.refreshNative()
            await store.refreshRepositories()
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain).handCursor().help("Refresh Oracles and conversations")
      }
      Text("Shared chat server · localhost:4318").font(.caption2).foregroundStyle(.secondary)
    }
    .padding(16).background(Color(red: 0.93, green: 0.92, blue: 0.98))
    .navigationSplitViewColumnWidth(min: 250, ideal: 310, max: 400)
    .sheet(isPresented: $choosingOracle) {
      OraclePickerView(groups: store.sidebarGroups, worker: store.indexWorker, favorites: favorites)
      { oracle in
        var next = favorites
        next.insert(oracle.id)
        favoriteJSON = String(
          decoding: (try? JSONEncoder().encode(next.sorted())) ?? Data("[]".utf8), as: UTF8.self)
        collapsed.remove(oracle.id)
        query = ""
        choosingOracle = false
      }
    }
    .task(id: searchKey) {
      let result = await store.indexWorker.search(
        groups: store.sidebarGroups,
        query: query, tags: tags, favorites: favorites)
      guard !Task.isCancelled else { return }
      matches = result
    }
    .onChange(of: query) {
      projectLimit = 30
      // Clear immediately to the tiny favorites projection, never the full inventory.
      if idle {
        matches = OracleIndex.sidebar(store.sidebarGroups, tags: tags, favorites: favorites)
      }
    }
  }

  @ViewBuilder private func rowContent(_ row: Row) -> some View {
    switch row {
    case .oracle(let oracle): oracleHeader(oracle)
    case .thread(let thread): threadRow(thread)
    case .newThread(let oracle):
      Button {
        startThread(oracle)
      } label: {
        Label("New thread", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain).font(.system(size: 13, weight: .medium))
      .foregroundStyle(accent).padding(.leading, 18).padding(.vertical, 8)
      .accessibilityLabel("New thread in " + oracle.name).handCursor().disabled(store.busy)
      .help("Start a new conversation in " + (oracle.path ?? "Local workspace"))
    case .moreThreads(let oracle, let count):
      Button("Show \(count) more threads") { _ = expanded.insert(oracle.id) }
        .buttonStyle(.plain).font(.caption).foregroundStyle(accent).handCursor().padding(
          .leading, 18)
    case .moreProjects(let count):
      Button("Show more results (\(count) remaining)") { projectLimit += 30 }
        .buttonStyle(.plain).font(.caption).foregroundStyle(accent).handCursor()
    }
  }
  private func oracleHeader(_ oracle: OracleGroup) -> some View {
    HStack(spacing: 8) {
      Button {
        if !collapsed.insert(oracle.id).inserted { collapsed.remove(oracle.id) }
      } label: {
        HStack(spacing: 8) {
          Image(
            systemName: collapsed.contains(oracle.id) && idle ? "chevron.right" : "chevron.down"
          )
          .font(.system(size: 10, weight: .semibold)).frame(width: 10)
          Image(systemName: "folder")
          Text(oracle.name).lineLimit(1)
          Spacer(minLength: 0)
          Text(oracle.threads.count.formatted()).font(.caption).monospacedDigit()
        }
      }
      .buttonStyle(.plain).help(oracle.path ?? "Local workspace")
      .accessibilityLabel("\(oracle.name), \(oracle.threads.count) conversations")
      Button {
        var next = favorites
        if !next.insert(oracle.id).inserted { next.remove(oracle.id) }
        favoriteJSON = String(
          decoding: (try? JSONEncoder().encode(next.sorted())) ?? Data("[]".utf8), as: UTF8.self)
      } label: {
        Image(systemName: favorites.contains(oracle.id) ? "star.fill" : "star")
          .foregroundStyle(accent)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        (favorites.contains(oracle.id) ? "Unfavorite " : "Favorite ") + oracle.name
      )
      .help("Favorites stay at the top. Saved on this Mac.")
    }
    .font(.system(size: 14, weight: .semibold))
    .foregroundStyle(Color(red: 0.15, green: 0.14, blue: 0.23)).padding(.top, 8).handCursor()
  }
  private func threadRow(_ thread: OracleThread) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: thread.isRunning ? "ellipsis.bubble" : "doc.text").padding(.top, 2)
      VStack(alignment: .leading, spacing: 4) {
        Text(thread.title).lineLimit(2)
        if let labels = tags[thread.tagKey], !labels.isEmpty {
          Text(labels.map { "#" + $0 }.joined(separator: " ")).font(.caption).foregroundStyle(
            accent)
        }
      }
      Spacer(minLength: 0)
      if thread.isReadOnly { Image(systemName: "lock").font(.caption).foregroundStyle(.secondary) }
    }
    .font(.system(size: 13, weight: .medium)).padding(.vertical, 6).padding(.leading, 18)
    .handCursor()
    .help(thread.title + (thread.sessionID.map { "\n" + $0 } ?? ""))
    .contextMenu {
      Button("Name and tags…") {
        beginEdit(thread.id, thread.title, thread.tagKey, !thread.isReadOnly)
      }
    }
  }
}
