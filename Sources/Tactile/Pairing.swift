import CryptoKit
import Foundation
import Security

/// Pairs iPads with a one-time code and remembers them with long random tokens.
/// Only SHA-256 hashes of tokens are stored on disk, alongside a name and when
/// each device was last used so it can be reviewed and revoked from the menu.
final class Pairing {
    struct Device: Codable, Identifiable, Equatable {
        let id: String
        let tokenHash: String
        var name: String
        let pairedAt: Date
        var lastSeen: Date
    }

    /// Single use: a new code replaces it as soon as an iPad pairs, so a code
    /// seen on screen or in a scanned link can't be used again.
    private(set) var code = Pairing.newCode()
    private(set) var devices: [Device]

    /// Called after the code changes, so the new one can be shown.
    var onNewCode: (() -> Void)?
    /// Called after a device is paired, revoked or expires.
    var onDevicesChanged: (() -> Void)?

    /// A device that hasn't connected for this long has to pair again.
    static let idleExpiry: TimeInterval = 90 * 24 * 60 * 60

    // Wrong codes: 5 from one address locks that address for a minute. Because
    // an attacker on the network can switch addresses, 20 wrong codes from
    // anywhere within 10 minutes also replaces the code and pauses pairing.
    private var failures: [String: (count: Int, lockedUntil: Date?)] = [:]
    private var recentFailures: [Date] = []
    private var pairingPausedUntil: Date?
    private let maxAttempts = 5
    private let maxGlobalAttempts = 20
    private let globalWindow: TimeInterval = 10 * 60
    private let lockDuration: TimeInterval = 60

    init() {
        // Tokens issued before HTTPS existed crossed the network unencrypted.
        try? FileManager.default.removeItem(at: Self.legacyStoreURL)
        devices = Self.load()
        if removeExpired() { save() }
    }

    /// The paired device a token belongs to, if it's still valid.
    func device(forToken token: String) -> Device? {
        guard token.count == 64, token.allSatisfy(\.isHexDigit) else { return nil }
        _ = removeExpired()
        let hash = Self.hash(token)
        return devices.first { $0.tokenHash == hash }
    }

    func markSeen(_ id: String) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].lastSeen = Date()
        save()
    }

    func isLocked(_ address: String) -> Bool {
        if let until = pairingPausedUntil {
            if until > Date() { return true }
            pairingPausedUntil = nil
        }
        guard let until = failures[address]?.lockedUntil else { return false }
        if until > Date() { return true }
        failures[address] = nil
        return false
    }

    /// Returns a new device token when the code matches.
    func redeem(code attempt: String, from address: String, name: String) -> (token: String, device: Device)? {
        guard !isLocked(address) else { return nil }
        if Self.constantTimeEqual(attempt, code) {
            failures[address] = nil
            let token = Self.randomToken()
            let now = Date()
            let device = Device(id: String(Self.randomToken().prefix(12)), tokenHash: Self.hash(token),
                                name: name, pairedAt: now, lastSeen: now)
            devices.append(device)
            save()
            replaceCode()
            onDevicesChanged?()
            return (token, device)
        }

        var entry = failures[address] ?? (0, nil)
        entry.count += 1
        if entry.count >= maxAttempts {
            entry = (0, Date().addingTimeInterval(lockDuration))
        }
        failures[address] = entry

        let now = Date()
        recentFailures = recentFailures.filter { now.timeIntervalSince($0) < globalWindow } + [now]
        if recentFailures.count >= maxGlobalAttempts {
            recentFailures = []
            pairingPausedUntil = now.addingTimeInterval(lockDuration)
            Log.warn("Many wrong pairing codes were tried. Pairing is paused for a minute and the code has been replaced.")
            replaceCode()
        }
        return nil
    }

    func revoke(_ id: String) {
        devices.removeAll { $0.id == id }
        save()
        onDevicesChanged?()
    }

    func revokeAll() {
        devices.removeAll()
        save()
        onDevicesChanged?()
    }

    private func replaceCode() {
        code = Self.newCode()
        onNewCode?()
    }

    private func removeExpired() -> Bool {
        let before = devices.count
        devices.removeAll { Date().timeIntervalSince($0.lastSeen) > Self.idleExpiry }
        return devices.count != before
    }

    private static func newCode() -> String {
        (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
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

    private static func load() -> [Device] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let devices = try? decoder.decode([Device].self, from: data) { return devices }
        // Earlier versions stored bare token hashes, with no names. Each gets
        // its real name when it next connects; ones that never connect again
        // expire after a week instead of the usual 90 days.
        let hashes = (try? decoder.decode([String].self, from: data)) ?? []
        let lastSeen = Date().addingTimeInterval(-(idleExpiry - 7 * 24 * 60 * 60))
        return hashes.map { Device(id: String($0.prefix(12)), tokenHash: $0, name: unnamed, pairedAt: lastSeen, lastSeen: lastSeen) }
    }

    /// Name for devices paired before Tactile recorded names.
    static let unnamed = "Earlier pairing"

    /// Gives an unnamed device the name its browser reports.
    func nameIfUnnamed(_ id: String, as name: String) {
        guard let index = devices.firstIndex(where: { $0.id == id }), devices[index].name == Self.unnamed else { return }
        devices[index].name = name
        save()
        onDevicesChanged?()
    }

    private func save() {
        let url = Self.storeURL
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try encoder.encode(devices).write(to: url, options: .atomic)
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
