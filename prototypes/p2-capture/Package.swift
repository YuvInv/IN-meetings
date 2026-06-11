// swift-tools-version: 5.9
import PackageDescription

// Embeds Info.plist (NSAudioCaptureUsageDescription / NSMicrophoneUsageDescription) into the binary
// via -sectcreate so TCC shows the permission prompts for this CLI tool.
let package = Package(
    name: "p2-capture",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "p2-capture",
            path: "Sources/p2-capture",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ])
            ]
        )
    ]
)
