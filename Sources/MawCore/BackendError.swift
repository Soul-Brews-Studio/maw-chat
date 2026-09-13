import Foundation

public enum BackendError: Error, LocalizedError, Sendable {
  case message(String)
  public var errorDescription: String? {
    switch self {
    case .message(let text): return text
    }
  }
}
