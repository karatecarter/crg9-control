// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CRG9Control", platforms: [.macOS(.v13)],
    products: [.executable(name: "CRG9Control", targets: ["CRG9App"]),
               .executable(name: "crg9-control", targets: ["CRG9CLI"])],
    targets: [.target(name: "CRG9Core"),
              .executableTarget(name: "CRG9App", dependencies: ["CRG9Core"]),
              .executableTarget(name: "CRG9CLI", dependencies: ["CRG9Core"]),
              .testTarget(name: "CRG9CoreTests", dependencies: ["CRG9Core"])])
