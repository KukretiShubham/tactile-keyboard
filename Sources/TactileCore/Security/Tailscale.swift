import Foundation
import Security

/// Talks to the Tailscale command-line tool: a publicly trusted HTTPS
/// certificate (Let's Encrypt) for this Mac's tailnet name, so iPads running
/// Tailscale need no certificate setup, and who owns a tailnet address.
public enum Tailscale {
    struct Certificate {
        let identity: TLSIdentity
        let host: String
        let expires: Date?
        /// The Tailscale user this Mac is signed in as.
        let ownerID: Int64?
    }

    /// Who a tailnet address belongs to, according to Tailscale.
    public struct Peer: Sendable {
        public let userID: Int64
        public let tagged: Bool
        /// Friendly device name, e.g. "iPad Air 13".
        public let deviceName: String

        public init(userID: Int64, tagged: Bool, deviceName: String) {
            self.userID = userID
            self.tagged = tagged
            self.deviceName = deviceName
        }
    }

    private static let candidates = [
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ]

    private static var cli: String? { candidates.first(where: FileManager.default.isExecutableFile(atPath:)) }

    /// Runs the CLI and parses its JSON output.
    private static func json(_ arguments: [String], timeout: TimeInterval) -> [String: Any]? {
        guard let cli, let result = Shell.run(cli, arguments, timeout: timeout), result.succeeded else { return nil }
        return try? JSONSerialization.jsonObject(with: result.output) as? [String: Any]
    }

    /// Returns nil (after explaining why) whenever Tailscale can't provide one,
    /// so Tactile falls back to its local certificate.
    static func certificate() -> Certificate? {
        guard let cli else { return nil }
        guard let status = json(["status", "--json"], timeout: 5) else {
            Log.info("Tailscale isn't responding; using the local certificate only.")
            return nil
        }
        guard status["BackendState"] as? String == "Running",
              let me = status["Self"] as? [String: Any],
              let dnsName = me["DNSName"] as? String, !dnsName.isEmpty else {
            Log.info("Tailscale isn't connected; using the local certificate only.")
            return nil
        }
        let host = dnsName.hasSuffix(".") ? String(dnsName.dropLast()) : dnsName
        guard (status["CertDomains"] as? [String])?.contains(host) == true else {
            Log.warn("""
            Tailscale is connected, but HTTPS certificates are off for your tailnet.
              Turn on "HTTPS Certificates" at https://login.tailscale.com/admin/dns and restart
              Tactile, and iPads on Tailscale won't need the certificate setup.
            """)
            return nil
        }

        // Written to stdout rather than files, which also works for the
        // sandboxed Mac App Store build of Tailscale. Asking for 30 days of
        // validity makes Tailscale renew well before expiry.
        Log.info("Getting an HTTPS certificate for \(host) from Tailscale…")
        guard let result = Shell.run(cli, ["cert", "--min-validity", "720h", "--cert-file", "-", "--key-file", "-", host],
                                     timeout: 90), result.succeeded else {
            Log.warn("Tailscale couldn't issue a certificate; using the local certificate only.")
            return nil
        }

        do {
            let work = try Paths.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: work) }
            let (certificates, key) = OpenSSL.split(String(decoding: result.output, as: UTF8.self))
            guard let leaf = certificates.first, let key else {
                throw TLSIdentity.Failure.openssl("unexpected tailscale cert output")
            }
            let certURL = work.appendingPathComponent("tailscale.crt")
            let keyURL = work.appendingPathComponent("tailscale.key")
            try certificates.joined(separator: "\n").write(to: certURL, atomically: true, encoding: .utf8)
            try Paths.writePrivate(Data(key.utf8), to: keyURL)
            return Certificate(identity: try TLSIdentity.load(certificate: certURL, key: keyURL), host: host,
                               expires: expiry(ofPEM: leaf), ownerID: (me["UserID"] as? NSNumber)?.int64Value)
        } catch {
            Log.warn("Couldn't use the Tailscale certificate (\(error)); using the local certificate only.")
            return nil
        }
    }

    /// Asks Tailscale who owns a tailnet address. Nil when it can't say.
    public static func whois(_ address: String) -> Peer? {
        guard let info = json(["whois", "--json", address], timeout: 3),
              let node = info["Node"] as? [String: Any],
              let userID = (node["User"] as? NSNumber)?.int64Value else { return nil }
        let tags = node["Tags"] as? [String] ?? []
        let computed = node["ComputedName"] as? String ?? ""
        let hostname = (node["Hostinfo"] as? [String: Any])?["Hostname"] as? String ?? ""
        // iPads and iPhones report "localhost" as their host name, so prefer
        // the tailnet's name for the device.
        let raw = !computed.isEmpty ? computed : hostname
        return Peer(userID: userID, tagged: !tags.isEmpty, deviceName: friendlyName(raw))
    }

    /// Turns a tailnet machine name into a display name, e.g.
    /// "ipad-air-13" → "iPad Air 13".
    public static func friendlyName(_ raw: String) -> String {
        let known = ["ipad": "iPad", "iphone": "iPhone", "macbook": "MacBook", "imac": "iMac",
                     "mac": "Mac", "pro": "Pro", "air": "Air", "max": "Max", "mini": "mini", "plus": "Plus"]
        let words = raw.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).map { word -> String in
            known[word.lowercased()] ?? (word.first?.isLetter == true && word == word.lowercased() ? word.capitalized : String(word))
        }
        let name = words.joined(separator: " ")
        return name.isEmpty ? "Tailscale device" : name
    }

    /// When a PEM certificate stops being valid.
    private static func expiry(ofPEM pem: String) -> Date? {
        guard let der = try? OpenSSL.derFromPEM(Data(pem.utf8)),
              let certificate = SecCertificateCreateWithData(nil, der as CFData),
              let values = SecCertificateCopyValues(certificate, [kSecOIDX509V1ValidityNotAfter] as CFArray, nil) as? [CFString: Any],
              let entry = values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any],
              let seconds = entry[kSecPropertyKeyValue] as? NSNumber else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
    }
}
