// swift-tools-version: 6.2
//
// Bumped from 6.0 solely because `.macOS(.v26)` below is gated on PackageDescription 6.2 — this
// is the manifest API version, unrelated to `.swiftLanguageMode(.v5)` on the targets below, which
// governs how the *sources* compile and is unaffected by this line.
import PackageDescription

let package = Package(
    name: "maillage",
    // v26: originally required by FoundationModels, which the meeting-recording feature used for
    // an on-device summary — see docs/superpowers/specs/2026-08-13-meeting-recording-design.md.
    // FoundationModels is gone now, replaced by the bundled mlx-swift-lm model below, which has no
    // comparable OS-version floor. Open question, not yet investigated: does anything else in the
    // app still need macOS 26? See CLAUDE.md's Stack section.
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "maillage", targets: ["Maillage"]),
        .library(name: "MaillageCore", targets: ["MaillageCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.1.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.3"),
    ],
    targets: [
        .target(
            name: "MaillageCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
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
