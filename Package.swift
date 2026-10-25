// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tactile",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Tactile",
            resources: [.copy("Web")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
