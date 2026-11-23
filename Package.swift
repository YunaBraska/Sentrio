// swift-tools-version: 5.9
import Foundation
import PackageDescription

let isAppStoreBuild = ProcessInfo.processInfo.environment["SENTRIO_APP_STORE"] == "1"
let packageDependencies: [Package.Dependency] = isAppStoreBuild
    ? []
    : [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")]
let coreDependencies: [Target.Dependency] = isAppStoreBuild
    ? []
    : [.product(name: "Sparkle", package: "Sparkle")]
let appStoreSettings: [SwiftSetting] = isAppStoreBuild
    ? [.define("SENTRIO_APP_STORE")]
    : []

let package = Package(
    name: "Sentrio",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    dependencies: packageDependencies,
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
            dependencies: coreDependencies,
            path: "Sources/SentrioCore",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: appStoreSettings
        ),
        .testTarget(
            name: "SentrioTests",
            dependencies: ["SentrioCore"],
            path: "Tests/SentrioTests"
        ),
    ]
)
