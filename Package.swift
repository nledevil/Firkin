// swift-tools-version: 6.0
import PackageDescription

// Firkin builds without an Xcode project: Command Line Tools are enough.
// Scripts/package_app.sh wraps the built executable into Firkin.app.
let package = Package(
    name: "Firkin",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        // Auto-updates. Sparkle also provides the sign_update/generate_appcast
        // tools under .build/artifacts, used by the release workflow.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
    ],
    targets: [
        // Homebrew data layer: models, JSON decoding, process execution.
        // Kept free of SwiftUI so it stays unit-testable.
        .target(
            name: "FirkinKit",
            path: "Sources/FirkinKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The SwiftUI app.
        .executableTarget(
            name: "Firkin",
            dependencies: [
                "FirkinKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Firkin",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FirkinKitTests",
            dependencies: ["FirkinKit"],
            path: "Tests/FirkinKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
