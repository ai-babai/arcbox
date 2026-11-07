// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Arcbox",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ArcboxDesktop", targets: ["ArcboxApp"]),
        .executable(name: "arcbox", targets: ["ArcboxCLI"]),
    ],
    dependencies: [.package(url: "https://github.com/typelift/SwiftCheck.git", exact: "0.12.0")],
    targets: [
        .target(name: "ArcboxCore", resources: [.process("Resources")]),
        .executableTarget(name: "ArcboxApp", dependencies: ["ArcboxCore"]),
        .executableTarget(name: "ArcboxCLI", dependencies: ["ArcboxCore"]),
        .testTarget(name: "ArcboxCoreTests", dependencies: ["ArcboxCore", "SwiftCheck"]),
    ]
)
