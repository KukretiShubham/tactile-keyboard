import Foundation

/// Lets only your own devices use Tactile over Tailscale: before a device may
/// even try to pair, Tailscale is asked who owns its address, and anything not
/// signed in as the Mac's owner (a device shared into the tailnet by someone
/// else, or a tagged device) is refused. If Tailscale can't say, the
/// connection is refused too.
public final class TailnetGate {
    public enum Verdict {
        case allowed(Tailscale.Peer)
        case refused(reason: String)
    }

    /// The check can be switched off from the menu.
    public var isEnabled: () -> Bool = { true }

    private let ownerID: Int64?
    private let lookups = DispatchQueue(label: "tactile.whois", attributes: .concurrent)
    private let lock = NSLock()
    private var cache: [String: (verdict: Verdict, at: Date)] = [:]
    private let cacheLifetime: TimeInterval = 60

    /// For tests: answers lookups instead of the real `tailscale whois`.
    public var lookUp: (String) -> Tailscale.Peer? = Tailscale.whois

    public init(ownerID: Int64?) {
        self.ownerID = ownerID
    }

    /// Calls `completion` on `queue` with whether `address` may connect.
    public func check(_ address: String, on queue: DispatchQueue, completion: @escaping (Verdict) -> Void) {
        if let cached = lock.withLock({ cache[address] }), Date().timeIntervalSince(cached.at) < cacheLifetime {
            return queue.async { completion(cached.verdict) }
        }
        lookups.async { [self] in
            let verdict = decide(lookUp(address))
            lock.withLock { cache[address] = (verdict, Date()) }
            queue.async { completion(verdict) }
        }
    }

    private func decide(_ peer: Tailscale.Peer?) -> Verdict {
        guard let ownerID else { return .refused(reason: "this Mac's Tailscale account is unknown") }
        guard let peer else { return .refused(reason: "Tailscale couldn't say who owns it") }
        if peer.tagged { return .refused(reason: "\(peer.deviceName) is a tagged device, not one of yours") }
        if peer.userID != ownerID { return .refused(reason: "\(peer.deviceName) belongs to another Tailscale account") }
        return .allowed(peer)
    }
}
