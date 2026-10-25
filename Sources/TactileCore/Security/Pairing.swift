import Foundation

/// Pairs devices with a one-time code and remembers them with long random
/// tokens. Only SHA-256 hashes of tokens are stored, alongside a name and when
/// each device was last used, so they can be reviewed and revoked from the menu.
public final class Pairing {
    public struct Device: Codable, Identifiable, Equatable, Sendable {
        public let id: String
        let tokenHash: String
        public var name: String
        public let pairedAt: Date
        public var lastSeen: Date

        public init(id: String, tokenHash: String, name: String, pairedAt: Date, lastSeen: Date) {
            self.id = id
            self.tokenHash = tokenHash
            self.name = name
            self.pairedAt = pairedAt
            self.lastSeen = lastSeen
        }
    }

    /// Name for devices paired before Tactile recorded names.
    public static let unnamed = "Earlier pairing"

    /// A device that hasn't connected for this long has to pair again.
    public static let idleExpiry: TimeInterval = 90 * 24 * 60 * 60

    /// Single use: a new code replaces it as soon as a device pairs, so a code
    /// seen on screen or in a scanned link can't be used again.
    public private(set) var code = SecureRandom.digits(6)
    public private(set) var devices: [Device]

    /// Called after the code changes, so the new one can be shown.
    public var onNewCode: (() -> Void)?
    /// Called after a device is paired, renamed, revoked or expires.
    public var onDevicesChanged: (() -> Void)?

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

    private let store: URL

    /// - Parameter store: Where paired devices are saved. Tests pass a temporary file.
    public init(store: URL = Paths.pairedDevices) {
        self.store = store
        devices = Self.load(from: store)
        if removeExpired() { save() }
    }

    /// The paired device a token belongs to, if it's still valid.
    public func device(forToken token: String) -> Device? {
        guard token.count == 64, token.allSatisfy(\.isHexDigit) else { return nil }
        _ = removeExpired()
        let hash = Data(token.utf8).sha256.hex()
        return devices.first { $0.tokenHash == hash }
    }

    func markSeen(_ id: String) {
        update(id, notify: false) { $0.lastSeen = Date() }
    }

    public func isLocked(_ address: String) -> Bool {
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
    public func redeem(code attempt: String, from address: String, name: String) -> (token: String, device: Device)? {
        guard !isLocked(address) else { return nil }
        guard constantTimeEqual(attempt, code) else {
            recordFailure(from: address)
            return nil
        }
        failures[address] = nil
        let token = SecureRandom.hex(bytes: 32)
        let now = Date()
        let device = Device(id: SecureRandom.hex(bytes: 6), tokenHash: Data(token.utf8).sha256.hex(),
                            name: name, pairedAt: now, lastSeen: now)
        devices.append(device)
        save()
        replaceCode()
        onDevicesChanged?()
        return (token, device)
    }

    /// Gives a device a better name. Unnamed devices take any name; devices
    /// named only by their type ("iPad · Tailscale") take a real device name,
    /// such as the one Tailscale knows.
    func improveName(_ id: String, to name: String, isRealName: Bool) {
        guard let current = devices.first(where: { $0.id == id })?.name, current != name else { return }
        let base = current.components(separatedBy: " · ").first ?? current
        let byTypeOnly = DeviceKind.genericNames.contains(base)
        guard current == Self.unnamed || (isRealName && byTypeOnly) else { return }
        update(id) { $0.name = name }
    }

    public func revoke(_ id: String) {
        devices.removeAll { $0.id == id }
        save()
        onDevicesChanged?()
    }

    public func revokeAll() {
        devices.removeAll()
        save()
        onDevicesChanged?()
    }

    public static func forgetAll(store: URL = Paths.pairedDevices) {
        try? FileManager.default.removeItem(at: store)
    }

    // MARK: Internals

    private func update(_ id: String, notify: Bool = true, _ change: (inout Device) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        change(&devices[index])
        save()
        if notify { onDevicesChanged?() }
    }

    private func recordFailure(from address: String) {
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
    }

    private func replaceCode() {
        code = SecureRandom.digits(6)
        onNewCode?()
    }

    private func removeExpired() -> Bool {
        let before = devices.count
        devices.removeAll { Date().timeIntervalSince($0.lastSeen) > Self.idleExpiry }
        return devices.count != before
    }

    private static func load(from store: URL) -> [Device] {
        guard let data = try? Data(contentsOf: store) else { return [] }
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

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try Paths.writePrivate(try encoder.encode(devices), to: store)
        } catch {
            Log.warn("Could not save paired devices: \(error.localizedDescription)")
        }
    }
}

/// What a browser says it is, limited to a few known names.
enum DeviceKind {
    static let genericNames = ["iPad", "iPhone", "Mac", "Browser", "Android device"]

    static func name(claimed: String?) -> String {
        genericNames.first { $0 == claimed } ?? "Browser"
    }
}
