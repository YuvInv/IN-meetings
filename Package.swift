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
    targets: [
        .target(name: "INMeetingsCore"),
        .testTarget(name: "INMeetingsCoreTests", dependencies: ["INMeetingsCore"]),
    ]
)
