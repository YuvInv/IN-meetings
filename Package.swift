// swift-tools-version: 5.9
import PackageDescription

// Root SwiftPM package: the shared, testable core for the IN-meetings app.
// App targets live under `Apps/` (XcodeGen) and link this library — see IMPLEMENTATION_PLAN.md §1.
// Minimum is macOS 14 (where the Core Audio process-tap SPI exists); the app deploys to macOS 26.
let package = Package(
    name: "INMeetingsCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "INMeetingsCore", targets: ["INMeetingsCore"]),
    ],
    dependencies: [
        // Local SQLite index + dashboard store (ADR-006). Pinned to the 6.x line (Swift 5.9 toolchain).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .target(name: "INMeetingsCore", dependencies: [
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .testTarget(name: "INMeetingsCoreTests", dependencies: ["INMeetingsCore"]),
    ]
)
