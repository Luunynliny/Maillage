// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "maillage",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "maillage", targets: ["Maillage"]),
        .library(name: "MaillageCore", targets: ["MaillageCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftgraphs/Grape", from: "1.1.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "MaillageCore",
            dependencies: [
                .product(name: "Grape", package: "Grape"),
                .product(name: "Yams", package: "Yams"),
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
