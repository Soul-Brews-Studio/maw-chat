import Foundation
import MawCore

enum LiveSourceList {
  static func filtered(
    _ sources: [LiveStreamSource], groups: [OracleGroup], scope: WorkspaceListScope, query: String
  ) -> [LiveStreamSource] {
    // Use real discovery roots, not a substring in a terminal title or an arbitrary parent folder.
    let roots = groups.compactMap { group -> (path: String, name: String)? in
      guard let path = group.path, !path.isEmpty else { return nil }
      return (OracleIndex.normalize(path), group.name)
    }.sorted { $0.path.count > $1.path.count }
    return sources.filter { source in
      let cwd = OracleIndex.normalize(source.detail)
      let project = roots.first { cwd == $0.path || cwd.hasPrefix($0.path + "/") }
      guard scope == .all || project.map({ scope.includes(projectName: $0.name) }) == true else {
        return false
      }
      return query.isEmpty
        || (source.name + " " + source.target + " " + source.detail + " " + (project?.name ?? ""))
          .localizedCaseInsensitiveContains(query)
    }
  }
}
