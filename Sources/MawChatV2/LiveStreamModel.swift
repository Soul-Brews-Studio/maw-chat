import Foundation
import Observation

@MainActor @Observable
final class LiveStreamModel {
  enum Phase: Equatable {
    case disconnected, connecting, live, paused
    case failed(String)
  }
  private(set) var sources: [LiveStreamSource] = []
  private(set) var selected: LiveStreamSource?
  private(set) var payload: LiveStreamFrame.Payload?
  private(set) var updatedAt: Date?
  private(set) var phase = Phase.disconnected
  private(set) var loading = false
  private(set) var inventoryError: String?
  private var endpoint = ""
  @ObservationIgnored private var provider: (any LiveStreamProvider)?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var revision = 0
  @ObservationIgnored private var inventoryRevision = 0
  private let makeProvider: @Sendable (String) throws -> any LiveStreamProvider
  init(
    makeProvider: @escaping @Sendable (String) throws -> any LiveStreamProvider = {
      try TmuxStreamProvider(endpoint: $0)
    }
  ) {
    self.makeProvider = makeProvider
  }
  deinit { task?.cancel() }

  func refresh(endpoint: String) async {
    inventoryRevision &+= 1
    let version = inventoryRevision
    loading = true
    inventoryError = nil
    defer { if inventoryRevision == version { loading = false } }
    do {
      if self.endpoint != endpoint || provider == nil {
        disconnect()
        self.endpoint = endpoint
        sources = []
        provider = nil
        provider = try makeProvider(endpoint)
      }
      guard let provider else { return }
      let found = try await provider.sources()
      try Task.checkCancellation()
      guard inventoryRevision == version else { return }
      sources = found
      if let selected {
        if let current = found.first(where: { $0.id == selected.id }) {
          self.selected = current
        } else {
          disconnect()
          phase = .failed("The selected pane no longer exists. Choose another source.")
        }
      }
    } catch is CancellationError {} catch {
      if inventoryRevision == version { inventoryError = error.localizedDescription }
    }
  }
  func connect(_ source: LiveStreamSource) {
    guard let provider, let source = sources.first(where: { $0.id == source.id }) else {
      inventoryError = "That source is no longer available. Refresh the pane list."
      return
    }
    revision &+= 1
    let version = revision
    task?.cancel()
    if selected?.id != source.id {
      payload = nil
      updatedAt = nil
    }
    selected = source
    phase = .connecting
    task = Task { [weak self] in
      do {
        for try await frame in await provider.frames(for: source) {
          try Task.checkCancellation()
          // Do not hold the model across the next suspension point.
          self?.receive(frame, version: version)
        }
        if !Task.isCancelled {
          self?.fail("The stream ended. Reconnect to resume.", version: version)
        }
      } catch is CancellationError {} catch {
        if !Task.isCancelled { self?.fail(error.localizedDescription, version: version) }
      }
    }
  }
  private func receive(_ frame: LiveStreamFrame, version: Int) {
    guard revision == version else { return }
    // Timestamp changes do not invalidate the much larger snapshot view.
    if payload != frame.payload { payload = frame.payload }
    updatedAt = frame.capturedAt
    if phase != .live { phase = .live }
  }
  private func fail(_ message: String, version: Int) {
    guard revision == version else { return }
    phase = .failed(message)
  }

  func pause() {
    revision &+= 1
    task?.cancel()
    task = nil
    if selected != nil { phase = .paused }
  }
  func resume() { if let selected { connect(selected) } }
  func disconnect() {
    revision &+= 1
    task?.cancel()
    task = nil
    selected = nil
    payload = nil
    updatedAt = nil
    phase = .disconnected
  }
}
