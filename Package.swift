// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TangoDisplay",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0")
    ],
    targets: [
        // Pure-logic library — no AppKit/SwiftUI — importable by both the app and the test runner
        .target(
            name: "TangoDisplayCore",
            path: "Sources/TangoDisplayCore"
        ),
        // ObjC/ObjC++ helpers — @try/@catch wrappers Swift cannot express, plus the
        // ShellacFilters declick/dehum DSP cores wrapped as in-process Audio Units
        .target(
            name: "TangoDisplayObjC",
            path: "Sources/TangoDisplayObjC",
            exclude: ["shellac/README.md", "shellac/LICENSE.txt"],
            publicHeadersPath: "include"
        ),
        // Main app executable
        .executableTarget(
            name: "TangoDisplay",
            dependencies: [
                "TangoDisplayCore",
                "TangoDisplayObjC",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/TangoDisplay",
            resources: [
                .copy("Resources/SetlistLogo.png"),
                .copy("Resources/RemoteUI")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        // Lightweight test runner executable — no XCTest needed (CLI tools only, no Xcode.app)
        // Usage: swift run TangoDisplayTests
        .executableTarget(
            name: "TangoDisplayTests",
            dependencies: ["TangoDisplayCore", "TangoDisplayObjC"],
            path: "Tests/TangoDisplayTests"
        )
    ]
)
