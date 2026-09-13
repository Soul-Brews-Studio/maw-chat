import Foundation
import MawCore
import Testing

@testable import MawChatV2

@Test func liveSourceScopeUsesKnownOracleRootsWithoutHidingOtherPanesPermanently() throws {
  let repos = try JSONDecoder().decode(
    [ChatRepository].self,
    from: Data(
      #"[{"name":"neo-oracle","path":"/repos/neo"},{"name":"other","path":"/repos/neo/vendor/other"}]"#
        .utf8))
  let groups = OracleIndex.groups(state: ChatState(), sessions: [], repositories: repos)
  let paths = [
    "/repos/neo", "/repos/neo/agents/one", "/repos/neo/vendor/other", "/repos/neo-similar",
    "/unknown",
  ]
  let sources = paths.map { LiveStreamSource(target: $0, name: "pane", detail: $0, kind: .tmux) }
  #expect(
    LiveSourceList.filtered(sources, groups: groups, scope: .oraclesOnly, query: "").map(\.target)
      == Array(paths.prefix(2)))
  #expect(
    LiveSourceList.filtered(sources, groups: groups, scope: .all, query: "").count == paths.count)
  #expect(
    LiveSourceList.filtered(sources, groups: groups, scope: .all, query: "neo-oracle").count == 2)
  #expect(LiveSourceList.filtered(sources, groups: [], scope: .all, query: "unknown").count == 1)
  #expect(WorkspaceListScope.all.title == "All projects")
  #expect(WorkspaceListScope.oraclesOnly.title == "Oracles")
}
