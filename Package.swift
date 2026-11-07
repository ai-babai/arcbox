// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Arcbox",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ArcboxDesktop", targets: ["ArcboxApp"]),
        .executable(name: "arcbox", targets: ["ArcboxCLI"])
    ],
    targets: [
        .target(name: "ArcboxCore", resources: [.process("Resources")]),
        .executableTarget(name: "ArcboxApp", dependencies: ["ArcboxCore"]),
        .executableTarget(name: "ArcboxCLI", dependencies: ["ArcboxCore"])
    ]
)
