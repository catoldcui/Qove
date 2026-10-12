// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Qove",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Qove", path: "Sources/Qove")
    ]
)
