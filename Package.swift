// swift-tools-version: 6.0
import PackageDescription

let swift5 = [SwiftSetting.swiftLanguageMode(.v5)]

let package = Package(
    name: "Tactile",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Tactile", targets: ["Tactile"]),
    ],
    targets: [
        // Everything that isn't UI: pairing, TLS, Tailscale, the servers,
        // input injection and the service that ties them together.
        .target(
            name: "TactileCore",
            swiftSettings: swift5
        ),
        // The menu bar app, plus the iPad web app it serves.
        .executableTarget(
            name: "Tactile",
            dependencies: ["TactileCore"],
            resources: [.copy("Web")],
            swiftSettings: swift5
        ),
        // `swift run tactile-checks`: the test suite. It's a plain executable
        // so it runs with only the Command Line Tools (XCTest and Swift
        // Testing ship with Xcode). It also runs the web tests in WebKit.
        .executableTarget(
            name: "tactile-checks",
            dependencies: ["TactileCore"],
            path: "Tests/TactileChecks",
            swiftSettings: swift5
        ),
    ]
)
