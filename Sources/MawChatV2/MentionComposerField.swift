import AppKit
import SwiftUI

struct MentionComposerField: View {
  @Bindable var store: ChatWorkspace
  @Bindable var preferences: WorkspacePreferences
  let mentionRequest: Int
  let focusRequest: Int
  @State private var caret = 0
  @State private var query: MentionQuery?
  @State private var matches: [MentionCandidate] = []
  @State private var active = 0
  @FocusState private var focused: Bool
  private struct Search: Equatable {
    let query: MentionQuery?
    let candidates: [MentionCandidate]
    let scope: WorkspaceListScope
    let favorites: Set<String>
  }
  var body: some View {
    TextField("Message…", text: $store.draft, axis: .vertical)
      .textFieldStyle(.plain).font(.system(size: 16)).lineLimit(1...5).focused($focused)
      .padding(.vertical, 6).accessibilityLabel("Message").disabled(!store.canCompose)
      .overlay(alignment: .bottomLeading) {
        if query != nil && focused {
          suggestions.padding(.bottom, 42)
        }
      }
      .onChange(of: store.draft) {
        let editor = NSApp.keyWindow?.firstResponder as? NSTextView
        if let editor, editor.string == store.draft {
          caret = editor.selectedRange().location
        } else {
          caret = store.draft.utf16.count
        }
        updateQuery()
        store.selectedMentions.removeAll { !MentionText.contains($0.token, in: store.draft) }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)
      ) { note in
        guard focused, let editor = note.object as? NSTextView,
          editor === NSApp.keyWindow?.firstResponder, !editor.hasMarkedText(),
          editor.string == store.draft
        else { return }
        caret = editor.selectedRange().location
        updateQuery()
      }
      .onChange(of: mentionRequest) {
        let position = min(caret, store.draft.utf16.count)
        let text = store.draft as NSString
        let prefix = text.substring(to: position)
        let marker = prefix.isEmpty || prefix.last?.isWhitespace == true ? "@" : " @"
        store.draft = text.replacingCharacters(
          in: NSRange(location: position, length: 0), with: marker)
        restoreCaret(position + marker.utf16.count)
      }
      .onChange(of: focusRequest) { focused = true }
      .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape]) { press in
        guard query != nil else { return .ignored }
        if press.key == .escape {
          query = nil
          return .handled
        }
        guard !matches.isEmpty else { return .ignored }
        if press.key == .return {
          guard !press.modifiers.contains(.command), !press.modifiers.contains(.shift) else {
            return .ignored
          }
          choose(matches[min(active, matches.count - 1)])
        } else {
          active = (active + (press.key == .downArrow ? 1 : matches.count - 1)) % matches.count
        }
        return .handled
      }
      .task(
        id: Search(
          query: query, candidates: store.mentionCandidates,
          scope: preferences.listScope, favorites: preferences.favorites)
      ) {
        guard let query else {
          matches = []
          return
        }
        let found = await store.mentionIndex.matches(
          store.mentionCandidates, query: query.fragment,
          scope: preferences.listScope, favorites: preferences.favorites)
        guard !Task.isCancelled else { return }
        matches = found
        active = 0
      }
  }
  private var suggestions: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Mention an Oracle, repository or session").font(.caption.weight(.semibold))
        .foregroundStyle(WorkspaceTheme.secondary).padding(.horizontal, 10).padding(.top, 10)
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, candidate in
              Button {
                choose(candidate)
              } label: {
                HStack(spacing: 9) {
                  Image(systemName: candidate.kind == "session" ? "text.bubble" : "folder")
                  VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(candidate.kind.capitalized + " · " + candidate.path).font(.caption)
                      .foregroundStyle(WorkspaceTheme.secondary).lineLimit(1)
                  }
                  Spacer(minLength: 0)
                }.padding(.horizontal, 10).padding(.vertical, 7).frame(
                  maxWidth: .infinity, alignment: .leading
                )
                .background(
                  index == active ? WorkspaceTheme.selected : .clear,
                  in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
              }.buttonStyle(.plain).handCursor().id(candidate.id)
            }
            if matches.isEmpty { Text("No matches in this list").font(.caption).padding(12) }
          }.padding(.horizontal, 4)
        }.frame(height: min(224, CGFloat(max(matches.count, 1)) * 48))
          .onChange(of: active) {
            if matches.indices.contains(active) { proxy.scrollTo(matches[active].id) }
          }
      }
      Text("↑ ↓ to choose · Return to insert · Esc to close · metadata only")
        .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary).padding(.horizontal, 10)
        .padding(.bottom, 8)
    }.background(WorkspaceTheme.sidebar, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(WorkspaceTheme.selected))
      .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
  }
  private func updateQuery() {
    let next = MentionText.query(store.draft, caret: caret)
    if next != query {
      query = next
      matches = []
      active = 0
    }
  }
  private func choose(_ candidate: MentionCandidate) {
    guard let query, store.canCompose, matches.contains(candidate),
      MentionText.query(store.draft, caret: caret) == query
    else { return }
    let bound = MentionText.binding(candidate, selected: store.selectedMentions)
    guard
      store.selectedMentions.count < 32
        || store.selectedMentions.contains(where: { $0.key == bound.key })
    else {
      store.error = "A message can reference up to 32 items."
      return
    }
    let inserted = MentionText.insert(bound, into: store.draft, query: query)
    if !store.selectedMentions.contains(where: { $0.key == bound.key }) {
      store.selectedMentions.append(bound)
    }
    store.draft = inserted.text
    self.query = nil
    let suffix = (inserted.text as NSString).substring(from: inserted.caret)
    restoreCaret(inserted.caret + (suffix.hasPrefix(" ") ? 1 : 0))
  }
  private func restoreCaret(_ position: Int) {
    caret = position
    focused = true
    let draft = store.draft
    let revision = store.navigationRevision
    Task { @MainActor in
      await Task.yield()
      guard focused, draft == store.draft, revision == store.navigationRevision,
        let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.string == draft
      else { return }
      editor.setSelectedRange(
        NSRange(location: min(position, editor.string.utf16.count), length: 0))
      updateQuery()
    }
  }
}
