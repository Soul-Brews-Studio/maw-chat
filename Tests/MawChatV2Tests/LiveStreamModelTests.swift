import Foundation
import Testing

@testable import MawChatV2

private func pane(_ name: String = "shell", id: String = "oracle:1.0") -> LiveStreamSource {
  LiveStreamSource(target: id, name: name, detail: "/workspace", kind: .tmux)
}

private actor TestLiveProvider: LiveStreamProvider {
  var inventory = [pane()]
  var opened = 0
  var terminated = 0
  var streams: [AsyncThrowingStream<LiveStreamFrame, Error>.Continuation] = []
  func sources() -> [LiveStreamSource] { inventory }
  func setInventory(_ sources: [LiveStreamSource]) { inventory = sources }
  func frames(for source: LiveStreamSource) -> AsyncThrowingStream<LiveStreamFrame, Error> {
    opened += 1
    return AsyncThrowingStream { continuation in
      streams.append(continuation)
      continuation.onTermination = { @Sendable _ in Task { await self.didTerminate() } }
    }
  }
  func didTerminate() { terminated += 1 }
  func emit(_ text: String, at index: Int) {
    streams[index].yield(LiveStreamFrame(payload: .text(text), capturedAt: Date()))
  }
}

@MainActor private func eventually(_ predicate: () async -> Bool) async -> Bool {
  for _ in 0..<100 {
    if await predicate() { return true }
    try? await Task.sleep(for: .milliseconds(5))
  }
  return false
}

@Test @MainActor func liveSourceRefreshKeepsStableIdentityAndCanResume() async {
  let provider = TestLiveProvider()
  let model = LiveStreamModel(makeProvider: { _ in provider })
  await model.refresh(endpoint: "first")
  model.connect(pane())
  #expect(await eventually { await provider.opened == 1 })
  model.pause()
  await provider.setInventory([pane("claude")])
  await model.refresh(endpoint: "first")
  #expect(model.selected?.name == "claude")
  model.resume()
  #expect(await eventually { await provider.opened == 2 })
  model.disconnect()
}

@Test @MainActor func liveStreamDoesNotRetainItsOwner() async {
  let provider = TestLiveProvider()
  var model: LiveStreamModel? = LiveStreamModel(makeProvider: { _ in provider })
  weak let weakModel = model
  await model?.refresh(endpoint: "first")
  model?.connect(pane())
  #expect(await eventually { await provider.opened == 1 })
  model = nil
  #expect(weakModel == nil)
  #expect(await eventually { await provider.terminated == 1 })
  // Also clean up the producer if this regression fails.
  weakModel?.disconnect()
}

@Test @MainActor func liveSelectionPauseAndDisconnectDiscardOldFrames() async {
  let provider = TestLiveProvider()
  await provider.setInventory([pane(), pane("second", id: "oracle:2.0")])
  let model = LiveStreamModel(makeProvider: { _ in provider })
  await model.refresh(endpoint: "first")
  model.connect(pane())
  #expect(await eventually { await provider.opened == 1 })
  await provider.emit("first", at: 0)
  #expect(await eventually { model.payload == .text("first") })
  model.connect(pane("second", id: "oracle:2.0"))
  #expect(model.payload == nil)
  #expect(await eventually { await provider.opened == 2 })
  await provider.emit("second", at: 1)
  await provider.emit("stale", at: 0)
  #expect(await eventually { model.payload == .text("second") })
  model.pause()
  #expect(model.phase == .paused)
  #expect(await eventually { await provider.terminated == 2 })
  await provider.emit("after pause", at: 1)
  #expect(model.payload == .text("second"))
  model.disconnect()
  #expect(model.payload == nil)
  #expect(model.selected == nil)
  #expect(model.phase == .disconnected)
}

@Test @MainActor func liveEndpointChangesAndRemovedPanesDisconnect() async {
  let provider = TestLiveProvider()
  let model = LiveStreamModel(makeProvider: { _ in provider })
  await model.refresh(endpoint: "first")
  model.connect(pane())
  #expect(await eventually { await provider.opened == 1 })
  await model.refresh(endpoint: "second")
  #expect(model.selected == nil)
  #expect(model.phase == .disconnected)
  model.connect(pane())
  #expect(await eventually { await provider.opened == 2 })
  await provider.setInventory([])
  await model.refresh(endpoint: "second")
  #expect(model.selected == nil)
  #expect(model.sources.isEmpty)
  guard case .failed = model.phase else {
    Issue.record("Missing pane must be explicit")
    return
  }
  #expect(await eventually { await provider.terminated == 2 })
}
