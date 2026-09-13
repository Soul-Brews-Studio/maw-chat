import Foundation
import Testing

@testable import MawCore

/// Isolated HTTP contract proof: never sends a paid turn or changes the real backend.
private final class ProjectProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    var data = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 1024)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(contentsOf: buffer.prefix(count))
      }
    }
    let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
    #expect(request.httpMethod == "POST")
    let json: String
    if request.url?.path == "/api/projects" {
      #expect(body?["name"] == "nexus-oracle")
      #expect(body?["path"] == "/repos/nexus")
      json = #"{"id":"new-project","name":"nexus-oracle","path":"/repos/nexus"}"#
    } else {
      #expect(request.url?.path == "/api/chats")
      #expect(body?["projectId"] == "new-project")
      #expect(body?["permissionMode"] == "default")
      json =
        #"{"id":"new-chat","title":"New Nexus conversation","projectId":"new-project","model":"sonnet","permissionMode":"default","status":"idle","messages":[]}"#
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(json.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@Test func discoveredOracleChatUsesRegisteredProjectAndDefaultPermissions() async throws {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [ProjectProtocol.self]
  let session = URLSession(configuration: config)
  defer { session.invalidateAndCancel() }
  let backend = ChatBackend(baseURL: URL(string: "http://maw-chat.test")!, session: session)
  let project = try await backend.createProject(name: "nexus-oracle", path: "/repos/nexus")
  let chat = try await backend.create(
    title: "New Nexus conversation", project: project.id,
    model: "sonnet", permission: "default")
  #expect(chat.projectId == project.id)
}
