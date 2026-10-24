// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sentrio",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Thin executable — only contains main.swift
        .executableTarget(
            name: "Sentrio",
            dependencies: ["SentrioCore"],
            path: "Sources/Sentrio"
        ),
        // Library with all app logic — importable by tests
        .target(
            name: "SentrioCore",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/SentrioCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "SentrioTests",
            dependencies: ["SentrioCore"],
            path: "Tests/SentrioTests"
        ),
    ]
)
