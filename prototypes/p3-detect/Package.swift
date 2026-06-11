// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "p3-detect",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "p3-detect",
            path: "Sources/p3-detect"
        )
    ]
)
