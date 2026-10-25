import Foundation

/// Where Tactile keeps its files. Everything lives under the user's own
/// Application Support and Logs folders.
public enum Paths {
    public static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tactile", isDirectory: true)
    }

    /// Hashes of paired devices' tokens, with names and last-used times.
    public static var pairedDevices: URL { support.appendingPathComponent("paired-devices.json") }

    /// The local certificate authority.
    public static var tls: URL { support.appendingPathComponent("tls", isDirectory: true) }

    public static var logFile: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Tactile.log")
    }

    /// Creates `url` (a folder) readable only by this user.
    static func makePrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    /// Writes `data` atomically, readable only by this user.
    static func writePrivate(_ data: Data, to url: URL) throws {
        try makePrivateDirectory(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// A private scratch folder; the caller deletes it when done.
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tactile-\(UUID().uuidString)", isDirectory: true)
        try makePrivateDirectory(url)
        return url
    }
}
