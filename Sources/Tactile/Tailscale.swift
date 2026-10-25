import Foundation
import Security

/// Gets a publicly trusted HTTPS certificate (Let's Encrypt, via Tailscale) for
/// this Mac's tailnet name. iPads running Tailscale can then open Tactile with
/// no certificate setup at all.
enum Tailscale {
    struct Certificate {
        let identity: TLSIdentity
        let host: String
        let expires: Date?
        /// The Tailscale user this Mac is signed in as.
        let ownerID: Int64?
    }

    /// Who a tailnet address belongs to, according to Tailscale.
    struct Peer {
        let userID: Int64
        let tagged: Bool
        /// Friendly device name, e.g. "iPad Air 13".
        let deviceName: String
    }

    private static let candidates = [
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ]

    /// Returns nil (after explaining why) whenever Tailscale can't provide one,
    /// so Tactile falls back to its local certificate.
    static func certificate() -> Certificate? {
        guard let cli = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else { return nil }

        guard let output = run(cli, ["status", "--json"], timeout: 5),
              let status = try? JSONSerialization.jsonObject(with: output) as? [String: Any] else {
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
        let ownerID = (me["UserID"] as? NSNumber)?.int64Value
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
        guard let pem = run(cli, ["cert", "--min-validity", "720h", "--cert-file", "-", "--key-file", "-", host], timeout: 90) else {
            Log.warn("Tailscale couldn't issue a certificate; using the local certificate only.")
            return nil
        }

        do {
            let work = try OpenSSL.workDirectory()
            defer { try? FileManager.default.removeItem(at: work) }
            let (certificates, key) = split(String(decoding: pem, as: UTF8.self))
            guard !certificates.isEmpty, let key else { throw TLSIdentity.Failure.openssl("unexpected tailscale cert output") }
            let certURL = work.appendingPathComponent("tailscale.crt")
            let keyURL = work.appendingPathComponent("tailscale.key")
            try certificates.joined(separator: "\n").write(to: certURL, atomically: true, encoding: .utf8)
            try key.write(to: keyURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
            return Certificate(identity: try TLSIdentity.load(certificate: certURL, key: keyURL), host: host,
                               expires: expiry(ofPEM: certificates[0]), ownerID: ownerID)
        } catch {
            Log.warn("Couldn't use the Tailscale certificate (\(error)); using the local certificate only.")
            return nil
        }
    }

    /// Asks Tailscale who owns a tailnet address. Nil when it can't say.
    static func whois(_ address: String) -> Peer? {
        guard let cli = candidates.first(where: FileManager.default.isExecutableFile(atPath:)),
              let output = run(cli, ["whois", "--json", address], timeout: 3),
              let info = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
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

    /// "ipad-air-13" → "iPad Air 13".
    static func friendlyName(_ raw: String) -> String {
        let known = ["ipad": "iPad", "iphone": "iPhone", "macbook": "MacBook", "imac": "iMac",
                     "mac": "Mac", "pro": "Pro", "air": "Air", "max": "Max", "mini": "mini", "plus": "Plus"]
        let words = raw.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).map { word -> String in
            let lower = word.lowercased()
            return known[lower] ?? (word.first?.isLetter == true && word == word.lowercased() ? word.capitalized : String(word))
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

    /// Splits PEM output into certificate blocks and the private key block.
    private static func split(_ pem: String) -> (certificates: [String], key: String?) {
        var certificates: [String] = []
        var key: String?
        var block: [Substring] = []
        for line in pem.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("-----BEGIN ") { block = [] }
            block.append(line)
            if line.hasPrefix("-----END ") {
                let text = block.joined(separator: "\n") + "\n"
                if line.contains("PRIVATE KEY") { key = text } else if line.contains("CERTIFICATE") { certificates.append(text) }
            }
        }
        return (certificates, key)
    }

    private static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }
        var data = Data()
        let reading = DispatchGroup()
        reading.enter()
        DispatchQueue.global().async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            reading.leave()
        }

        if reading.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
