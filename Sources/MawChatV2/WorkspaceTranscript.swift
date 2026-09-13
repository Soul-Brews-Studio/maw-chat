import AppKit
import MawCore
import SwiftUI

struct WorkspaceTranscript: View {
  @Bindable var store: ChatWorkspace
  @State private var limit = 60
  @State private var following = true
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 22) {
          if store.messages.count > limit {
            Button("Show earlier messages (\(store.messages.count - limit))") { limit += 60 }
              .buttonStyle(.plain).handCursor().frame(maxWidth: .infinity)
          }
          if store.historyOffset != nil {
            Button("Load more saved history") { Task { await store.readHistory(reset: false) } }
              .handCursor().disabled(store.historyLoading)
          }
          if store.historyLoading { ProgressView().frame(maxWidth: .infinity) }
          if store.messages.isEmpty && !store.historyLoading {
            VStack(spacing: 12) {
              OracleAvatar(name: store.oracleName, size: 48)
              Text(store.selection == nil ? "Start a conversation" : "No messages yet")
                .font(.title3.weight(.semibold))
              Text(store.oracleName).foregroundStyle(WorkspaceTheme.secondary)
            }.frame(maxWidth: .infinity).padding(.top, 100)
          }
          ForEach(store.messages.suffix(limit)) { message in
            WorkspaceMessage(message: message, sender: store.oracleName) {
              store.reply = ReplyContext(
                sender: message.role == "user" ? "You" : store.oracleName,
                text: message.content)
            }
          }
          Color.clear.frame(height: 1).id("bottom")
        }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)
      }.defaultScrollAnchor(.bottom)
        .overlay(alignment: .bottomTrailing) {
          Button {
            following.toggle()
            if following { proxy.scrollTo("bottom", anchor: .bottom) }
          } label: {
            Image(systemName: following ? "pause.circle" : "arrow.down.circle.fill")
          }.buttonStyle(.plain).handCursor().foregroundStyle(WorkspaceTheme.secondary)
            .help(following ? "Pause auto-scroll" : "Follow latest messages").padding(8)
        }
        .onChange(of: store.selection) {
          limit = 60
          following = true
        }
        .onChange(of: store.messages.last?.content) {
          if following { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
  }
}

struct WorkspaceMessage: View {
  let message: ChatMessage
  let sender: String
  let reply: () -> Void
  private var isUser: Bool { message.role == "user" }
  var body: some View {
    let quoted = QuotedReply.parse(message.content)
    let content = quoted?.body ?? message.content
    VStack(alignment: .leading, spacing: 7) {
      if let date = MessageDate.parse(message.createdAt) {
        Text(date.formatted(date: .abbreviated, time: .shortened))
          .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary)
          .frame(maxWidth: .infinity).padding(.vertical, 18)
      }
      if !isUser {
        Text(sender).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
      }
      HStack {
        if isUser { Spacer(minLength: 65) }
        VStack(alignment: .leading, spacing: 8) {
          if let quoted { QuotedReplyCard(reply: quoted) }
          if !content.isEmpty {
            if content.count < 100 && !content.contains("\n") {
              Text(content).font(.system(size: 16)).textSelection(.enabled)
                .padding(.horizontal, 15).padding(.vertical, 11)
                .background(
                  isUser ? WorkspaceTheme.userBubble : WorkspaceTheme.bubble, in: Capsule())
            } else {
              MarkdownContent(text: content).equatable().font(.system(size: 14))
                .padding(14).background(
                  isUser ? WorkspaceTheme.userBubble : WorkspaceTheme.bubble,
                  in: RoundedRectangle(cornerRadius: 18))
            }
          }
          if let tools = message.tools, !tools.isEmpty {
            DisclosureGroup("\(tools.count) tool \(tools.count == 1 ? "activity" : "activities")") {
              ForEach(tools) { tool in
                DisclosureGroup(tool.name + " · " + tool.status) {
                  Text(tool.input?.pretty ?? "No input details")
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }.padding(6)
              }
            }.font(.caption).foregroundStyle(WorkspaceTheme.secondary)
          }
          if message.status == "streaming" { ProgressView().controlSize(.small) }
          if let error = message.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
          HStack(spacing: 14) {
            Button("Reply", action: reply).handCursor().disabled(message.content.isEmpty)
            Button("Copy") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(message.content, forType: .string)
            }.handCursor()
          }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
        }.frame(maxWidth: isUser ? 550 : 520, alignment: isUser ? .trailing : .leading)
        if !isUser { Spacer(minLength: 65) }
      }
    }
  }
}
