// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "AIMaster", defaultLocalization: "en", platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AIMaster", path: "Sources/AIMaster", resources: [.process("Resources")]),
        .testTarget(name: "AIMasterTests", dependencies: ["AIMaster"], path: "Tests/AIMasterTests", resources: [.copy("Fixtures")]),
    ]
)
