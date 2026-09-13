import Foundation
import Observation

@MainActor @Observable
final class WorkspacePreferences {
  private let defaults: UserDefaults
  var favorites: Set<String> { didSet { defaults.set(Array(favorites), forKey: "v2.favorites") } }
  var tags: [String: [String]] {
    didSet { defaults.set(try? JSONEncoder().encode(tags), forKey: "v2.tags") }
  }
  var listScope: WorkspaceListScope {
    didSet { defaults.set(listScope.rawValue, forKey: "v2.listScope") }
  }
  var inspector = true
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    listScope =
      defaults.string(forKey: "v2.listScope").flatMap(WorkspaceListScope.init(rawValue:)) ?? .all
    favorites = Set(defaults.stringArray(forKey: "v2.favorites") ?? [])
    tags =
      defaults.data(forKey: "v2.tags")
      .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
  }
  func toggleFavorite(_ id: String) {
    if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
  }
}
