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
                               expires: expiry(ofPEM: certificates[0]))
        } catch {
            Log.warn("Couldn't use the Tailscale certificate (\(error)); using the local certificate only.")
            return nil
        }
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
