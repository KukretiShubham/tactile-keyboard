import CryptoKit
import Foundation
import Security

/// Pairs iPads with a one-time code and remembers them with long random tokens.
/// Only SHA-256 hashes of tokens are stored on disk.
final class Pairing {
    let code: String

    private var trusted: Set<String>
    private var failures: [String: (count: Int, lockedUntil: Date?)] = [:]
    private let maxAttempts = 5
    private let lockDuration: TimeInterval = 60

    init() {
        code = (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
        // Tokens issued before HTTPS existed crossed the network unencrypted.
        try? FileManager.default.removeItem(at: Self.legacyStoreURL)
        trusted = Self.load()
    }

    func isTrusted(token: String) -> Bool {
        guard token.count == 64, token.allSatisfy(\.isHexDigit) else { return false }
        return trusted.contains(Self.hash(token))
    }

    func isLocked(_ address: String) -> Bool {
        guard let until = failures[address]?.lockedUntil else { return false }
        if until > Date() { return true }
        failures[address] = nil
        return false
    }

    /// Returns a new device token when the code matches.
    func redeem(code attempt: String, from address: String) -> String? {
        guard !isLocked(address) else { return nil }
        if Self.constantTimeEqual(attempt, code) {
            failures[address] = nil
            let token = Self.randomToken()
            trusted.insert(Self.hash(token))
            save()
            return token
        }
        var entry = failures[address] ?? (0, nil)
        entry.count += 1
        if entry.count >= maxAttempts {
            entry = (0, Date().addingTimeInterval(lockDuration))
        }
        failures[address] = entry
        return nil
    }

    static func forgetAll() {
        try? FileManager.default.removeItem(at: storeURL)
    }

    // MARK: Storage

    private static var supportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tactile", isDirectory: true)
    }

    private static var storeURL: URL { supportURL.appendingPathComponent("paired-devices.json") }
    private static var legacyStoreURL: URL { supportURL.appendingPathComponent("trusted-devices.json") }

    private static func load() -> Set<String> {
        guard let data = try? Data(contentsOf: storeURL),
              let hashes = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(hashes)
    }

    private func save() {
        let url = Self.storeURL
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(trusted.sorted()).write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Log.warn("Could not save paired devices: \(error.localizedDescription)")
        }
    }

    // MARK: Crypto helpers

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            fatalError("Secure random generator unavailable")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
