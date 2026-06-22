// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Profiles",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ProfilesCore"),
        .target(name: "ProfilesUI", dependencies: ["ProfilesCore"]),
        .target(name: "XCTest"),
        .executableTarget(name: "Profiles", dependencies: ["ProfilesCore", "ProfilesUI"]),
        .executableTarget(name: "ProfilesCoreTests", dependencies: ["ProfilesCore", "XCTest"]),
        .executableTarget(name: "ProfilesSnapshotTests", dependencies: ["ProfilesCore", "ProfilesUI", "XCTest"]),
    ]
)
