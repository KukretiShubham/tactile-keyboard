import Foundation
import Security
import TactileCore

/// The updater, against releases made here: a small signed stand-in app,
/// zipped, with its checksum and a GitHub-style description.
enum UpdateChecks {
    static func run(_ checks: Checks) {
        checks.run("updates: version numbers compare as numbers") {
            try expect(Updater.isNewer("1.10.0", than: "1.9.2"), "1.10.0 > 1.9.2")
            try expect(Updater.isNewer("1.4.0", than: "1.3"), "1.4.0 > 1.3")
            try expect(!Updater.isNewer("1.3.0", than: "1.3"), "1.3.0 = 1.3")
            try expect(!Updater.isNewer("1.2.9", than: "1.3.0"), "1.2.9 < 1.3.0")
        }

        checks.run("updates: a newer release installs in place, leaving nothing behind") {
            try withTemporaryDirectory { folder in
                let installed = try installedApp(in: folder)
                let release = try publish(version: "9.9.0", in: folder)
                let updater = Updater(currentVersion: "1.0.0", appURL: installed, requirement: try requirement("app.tactile.mac"),
                                      latest: release)
                updater.check()
                try expect(waitUntil { if case .available = updater.state { true } else { false } }, "offered: \(updater.state)")

                var reopened: URL?
                updater.onInstalled = { reopened = $0 }
                updater.install()
                try expect(waitUntil(timeout: 20) { reopened != nil }, "installed: \(updater.state)")
                try expectEqual(reopened, installed, "reopens where it was")
                try expectEqual(Bundle(url: installed)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                                "9.9.0", "new version in place")
                let leftovers = try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path)
                try expectEqual(leftovers, ["Tactile.app"], "only the app")
            }
        }

        checks.run("updates: the same version isn't offered") {
            try withTemporaryDirectory { folder in
                let updater = Updater(currentVersion: "9.9.0", appURL: try installedApp(in: folder),
                                      requirement: try requirement("app.tactile.mac"), latest: try publish(version: "9.9.0", in: folder))
                updater.check()
                try expect(waitUntil { if case .upToDate = updater.state { true } else { false } }, "up to date: \(updater.state)")
            }
        }

        checks.run("updates: a bad checksum, a tampered app or another signer installs nothing") {
            let cases: [(String, (URL) throws -> Void, String)] = [
                ("checksum", { zip in try Data("0000  x".utf8).write(to: zip.appendingPathExtension("sha256")) }, "app.tactile.mac"),
                ("tampered", { _ in }, "app.tactile.mac"),
                ("signer", { _ in }, "com.example.other"),
            ]
            for (name, spoil, signer) in cases {
                try withTemporaryDirectory { folder in
                    let installed = try installedApp(in: folder)
                    let release = try publish(version: "9.9.0", in: folder, tamper: name == "tampered")
                    try spoil(folder.appendingPathComponent("Tactile-v9.9.0.zip"))
                    let updater = Updater(currentVersion: "1.0.0", appURL: installed, requirement: try requirement(signer), latest: release)
                    var reopened = false
                    updater.onInstalled = { _ in reopened = true }
                    updater.check()
                    try expect(waitUntil { if case .available = updater.state { true } else { false } }, "\(name): offered")
                    updater.install()
                    try expect(waitUntil(timeout: 20) { if case .failed = updater.state { true } else { false } },
                               "\(name): refused, got \(updater.state)")
                    try expect(!reopened, "\(name): not installed")
                    try expectEqual(Bundle(url: installed)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                                    "1.0.0", "\(name): old version untouched")
                }
            }
        }
    }

    // MARK: Fixtures

    private static func requirement(_ identifier: String) throws -> SecRequirement {
        var requirement: SecRequirement?
        try expect(SecRequirementCreateWithString("identifier \"\(identifier)\"" as CFString, [], &requirement) == errSecSuccess,
                   "requirement")
        return try require(requirement, "requirement")
    }

    /// A minimal app bundle, signed ad hoc as Tactile.
    private static func makeApp(at app: URL, version: String) throws {
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appendingPathComponent("Tactile"))
        let info: [String: Any] = ["CFBundleIdentifier": "app.tactile.mac", "CFBundleExecutable": "Tactile",
                                   "CFBundleShortVersionString": version, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try shell("/usr/bin/codesign", "--force", "--sign", "-", "--identifier", "app.tactile.mac", app.path)
    }

    private static func installedApp(in folder: URL) throws -> URL {
        let apps = folder.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let app = apps.appendingPathComponent("Tactile.app")
        try makeApp(at: app, version: "1.0.0")
        return app
    }

    /// A release as the workflow publishes one, described the way GitHub's
    /// API does; returns the description's URL.
    private static func publish(version: String, in folder: URL, tamper: Bool = false) throws -> URL {
        let build = folder.appendingPathComponent("build")
        let app = build.appendingPathComponent("Tactile.app")
        try makeApp(at: app, version: version)
        if tamper {
            let executable = app.appendingPathComponent("Contents/MacOS/Tactile")
            let handle = try FileHandle(forWritingTo: executable)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data([0]))
            try handle.close()
        }
        let zip = folder.appendingPathComponent("Tactile-v\(version).zip")
        try shell("/usr/bin/ditto", "-c", "-k", "--keepParent", app.path, zip.path)
        try shell("/bin/sh", "-c", "cd '\(folder.path)' && shasum -a 256 '\(zip.lastPathComponent)' > '\(zip.lastPathComponent).sha256'")
        let release: [String: Any] = [
            "tag_name": "v\(version)", "html_url": "https://example.com/releases/v\(version)",
            "assets": [
                ["name": zip.lastPathComponent, "browser_download_url": zip.absoluteString, "size": 1000],
                ["name": "\(zip.lastPathComponent).sha256", "browser_download_url": zip.appendingPathExtension("sha256").absoluteString, "size": 90],
            ],
        ]
        let description = folder.appendingPathComponent("latest.json")
        try JSONSerialization.data(withJSONObject: release).write(to: description)
        return description
    }

    private static func shell(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try expectEqual(process.terminationStatus, 0, "\(tool) \(arguments.first ?? "")")
    }
}
