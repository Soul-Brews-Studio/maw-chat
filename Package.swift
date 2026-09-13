// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MawChat",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "MawChat", targets: ["MawChat"]),
    .executable(name: "MawChatV2", targets: ["MawChatV2"]),
  ],
  targets: [
    .target(name: "MawCore"),
    .executableTarget(name: "MawChat", dependencies: ["MawCore"]),
    .testTarget(name: "MawCoreTests", dependencies: ["MawCore"]),
    .executableTarget(
      name: "MawChatV2", dependencies: ["MawCore"]),
    .testTarget(
      name: "MawChatV2Tests", dependencies: ["MawChatV2", "MawCore"]),
  ]
)
