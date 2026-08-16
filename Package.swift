// swift-tools-version: 6.2
//
// Bumped from 6.0 solely because `.macOS(.v26)` below is gated on PackageDescription 6.2 — this
// is the manifest API version, unrelated to `.swiftLanguageMode(.v5)` on the targets below, which
// governs how the *sources* compile and is unaffected by this line.
import PackageDescription

let package = Package(
    name: "maillage",
    // v26: the meeting-recording feature needs FoundationModels for the on-device meeting
    // summary, which ships only from macOS 26. See
    // docs/superpowers/specs/2026-08-13-meeting-recording-design.md.
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "maillage", targets: ["Maillage"]),
        .library(name: "MaillageCore", targets: ["MaillageCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
    ],
    targets: [
        .target(
            name: "MaillageCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Maillage",
            dependencies: ["MaillageCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MaillageCoreTests",
            dependencies: ["MaillageCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
