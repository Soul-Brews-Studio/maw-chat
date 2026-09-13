import MawCore
import SwiftUI

struct LiveStreamPanel: View {
  let groups: [OracleGroup]
  @State private var stream = LiveStreamModel()
  @AppStorage("v2.streamEndpoint") private var endpoint = "http://127.0.0.1:3461"
  @State private var choosing = false
  @State private var expanded = false
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("Live view", systemImage: "rectangle.on.rectangle").font(
          .system(size: 14, weight: .semibold))
        Spacer()
        if stream.selected != nil {
          IconButton(title: "Expand live view", icon: "arrow.up.left.and.arrow.down.right") {
            expanded = true
          }
        }
      }
      if let source = stream.selected {
        Text(source.name).font(.system(size: 11)).lineLimit(2).help(
          source.id + " · " + source.detail)
      }
      LiveStreamContent(stream: stream, scale: .fit).frame(height: 210)
        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 9))
      HStack(spacing: 12) {
        Button("Choose source") { choosing = true }.buttonStyle(.plain).handCursor()
        Spacer(minLength: 0)
        if stream.selected != nil {
          Button(stream.phase == .live || stream.phase == .connecting ? "Pause" : "Reconnect") {
            if stream.phase == .live || stream.phase == .connecting {
              stream.pause()
            } else {
              stream.resume()
            }
          }.buttonStyle(.plain).handCursor()
          IconButton(title: "Disconnect live source", icon: "xmark.circle") { stream.disconnect() }
        }
      }.font(.system(size: 12))
      LiveStreamStatus(stream: stream)
      Text("Read-only tmux snapshots · 1 second refresh. VNC source planned.")
        .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary)
      if let error = stream.inventoryError {
        Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3).help(error)
      }
    }
    .task(id: endpoint) { await stream.refresh(endpoint: endpoint) }
    .onDisappear { stream.disconnect() }
    .sheet(isPresented: $choosing) {
      LiveStreamSourcePicker(stream: stream, endpoint: $endpoint, groups: groups)
    }
    .sheet(isPresented: $expanded) {
      VStack(spacing: 14) {
        HStack {
          Text(stream.selected?.name ?? "Live view").font(.headline).lineLimit(1)
          Spacer()
          Button("Done") { expanded = false }.keyboardShortcut(.cancelAction).handCursor()
        }
        LiveStreamContent(stream: stream, scale: .actual)
        LiveStreamStatus(stream: stream)
      }.padding(24).frame(minWidth: 640, idealWidth: 820, minHeight: 440, idealHeight: 560)
        .background(WorkspaceTheme.sidebar).preferredColorScheme(.dark)
    }
  }

}

private struct LiveStreamContent: View {
  @Bindable var stream: LiveStreamModel
  let scale: LiveViewScale
  var body: some View {
    if let payload = stream.payload {
      LiveStreamPayloadView(payload: payload, scale: scale).equatable()
    } else {
      VStack(spacing: 12) {
        if stream.phase == .connecting {
          ProgressView()
        } else {
          Image(systemName: "desktopcomputer").font(.system(size: 30, weight: .light))
        }
        Text(stream.phase == .connecting ? "Connecting…" : "No live source selected")
          .font(.system(size: 13, weight: .semibold))
        Text("Choose a tmux pane to view its output. This panel cannot type or send commands.")
          .font(.system(size: 11)).multilineTextAlignment(.center)
      }.foregroundStyle(WorkspaceTheme.secondary).padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

private struct LiveStreamStatus: View {
  @Bindable var stream: LiveStreamModel
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      switch stream.phase {
      case .disconnected: Text("Disconnected")
      case .connecting: Text("Connecting · previous snapshot may be shown")
      case .live:
        Text("Live · \(stream.selected?.kind.rawValue ?? "source") · read only").foregroundStyle(
          .green)
      case .paused: Text("Paused · last snapshot")
      case .failed(let error):
        Text("Disconnected · " + error).foregroundStyle(.orange).lineLimit(3).help(error)
      }
      if let date = stream.updatedAt {
        Text("Last snapshot: " + date.formatted(date: .omitted, time: .standard))
      }
    }.font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary)
  }
}
