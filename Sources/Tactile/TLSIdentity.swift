import CryptoKit
import Foundation
import Network
import Security

/// A private certificate authority for this Mac, plus a fresh HTTPS certificate
/// issued on every launch for the Mac's current name and addresses.
///
/// The CA is name-constrained to `.local` names and private IPv4 ranges, so even
/// if its key leaked it could not be used to impersonate public websites on the
/// iPad that trusts it. Certificates are made with the LibreSSL that ships with
/// macOS, so there is nothing extra to install or keep patched.
struct TLSIdentity {
    let caDER: Data
    let caName: String
    let fingerprint: String
    private let identity: sec_identity_t

    enum Failure: Error, CustomStringConvertible {
        case openssl(String)
        case importFailed(OSStatus)

        var description: String {
            switch self {
            case .openssl(let message): return "openssl failed: \(message)"
            case .importFailed(let status): return "could not load the HTTPS certificate (OSStatus \(status))"
            }
        }
    }

    /// Private ranges the CA may issue for (RFC 1918, Tailscale/CGNAT, loopback).
    private static let permittedRanges: [(base: UInt32, mask: UInt32)] = [
        (0x0A00_0000, 0xFF00_0000), // 10.0.0.0/8
        (0xAC10_0000, 0xFFF0_0000), // 172.16.0.0/12
        (0xC0A8_0000, 0xFFFF_0000), // 192.168.0.0/16
        (0x6440_0000, 0xFFC0_0000), // 100.64.0.0/10
        (0x7F00_0000, 0xFF00_0000), // 127.0.0.0/8
    ]

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tactile/tls", isDirectory: true)
    }

    static func prepare(hostName: String?, addresses: [String]) throws -> TLSIdentity {
        let fm = FileManager.default
        let dir = directory
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let caKey = dir.appendingPathComponent("ca.key")
        let caCert = dir.appendingPathComponent("ca.crt")
        if !fm.fileExists(atPath: caKey.path) || !fm.fileExists(atPath: caCert.path) {
            try createAuthority(key: caKey, cert: caCert)
        }

        let work = fm.temporaryDirectory.appendingPathComponent("tactile-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: work) }

        let names = ["localhost"] + [hostName].compactMap { $0 }
        let ips = ["127.0.0.1"] + addresses.filter(isPermitted)
        let san = (names.map { "DNS:\($0)" } + ips.map { "IP:\($0)" }).joined(separator: ", ")

        let key = work.appendingPathComponent("server.key")
        let csr = work.appendingPathComponent("server.csr")
        let cert = work.appendingPathComponent("server.crt")
        let p12 = work.appendingPathComponent("server.p12")
        let ext = work.appendingPathComponent("server.cnf")
        try """
        [v3]
        basicConstraints = critical, CA:FALSE
        keyUsage = critical, digitalSignature
        extendedKeyUsage = serverAuth
        subjectAltName = \(san)
        subjectKeyIdentifier = hash
        authorityKeyIdentifier = keyid
        """.write(to: ext, atomically: true, encoding: .utf8)

        try openssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", key.path)
        try openssl("req", "-new", "-key", key.path, "-subj", "/CN=\(names.last!)", "-out", csr.path)
        try openssl("x509", "-req", "-in", csr.path, "-CA", caCert.path, "-CAkey", caKey.path,
                    "-set_serial", "0x\(randomHex(16))", "-days", "397", "-sha256",
                    "-extfile", ext.path, "-extensions", "v3", "-out", cert.path)

        // The bundle only lives in memory; its password never touches argv.
        let password = randomHex(24)
        try openssl("pkcs12", "-export", "-inkey", key.path, "-in", cert.path, "-certfile", caCert.path,
                    "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1",
                    "-passout", "env:TACTILE_P12", "-out", p12.path,
                    environment: ["TACTILE_P12": password])

        var items: CFArray?
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password,
            kSecImportToMemoryOnly as String: true,
        ]
        let status = SecPKCS12Import(try Data(contentsOf: p12) as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let entry = (items as? [[String: Any]])?.first,
              let secIdentity = entry[kSecImportItemIdentity as String],
              let identity = sec_identity_create(secIdentity as! SecIdentity) else {
            throw Failure.importFailed(status)
        }

        let caDER = try derFromPEM(Data(contentsOf: caCert))
        // Same format iOS uses under the profile's More Details.
        let fingerprint = SHA256.hash(data: caDER).map { String(format: "%02X", $0) }.joined(separator: " ")
        return TLSIdentity(caDER: caDER, caName: authorityName, fingerprint: fingerprint, identity: identity)
    }

    /// A new options object per listener; all share the same certificate.
    func options() -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, identity)
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        return options
    }

    // MARK: Authority

    private static var authorityName: String {
        let mac = HostInfo.computerName.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" }
        return "Tactile CA - \(String(String.UnicodeScalarView(mac)))"
    }

    private static func createAuthority(key: URL, cert: URL) throws {
        let config = key.deletingLastPathComponent().appendingPathComponent("ca.cnf")
        defer { try? FileManager.default.removeItem(at: config) }
        let ipConstraints = permittedRanges.map { "permitted;IP:\(dotted($0.base))/\(dotted($0.mask))" }
        try """
        [req]
        distinguished_name = dn
        prompt = no
        x509_extensions = v3_ca
        [dn]
        CN = \(authorityName)
        O = Tactile
        [v3_ca]
        basicConstraints = critical, CA:TRUE, pathlen:0
        keyUsage = critical, keyCertSign, cRLSign
        subjectKeyIdentifier = hash
        nameConstraints = critical, permitted;DNS:local, permitted;DNS:localhost, \(ipConstraints.joined(separator: ", "))
        """.write(to: config, atomically: true, encoding: .utf8)

        try openssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", key.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
        try openssl("req", "-x509", "-new", "-key", key.path, "-sha256", "-days", "3650",
                    "-config", config.path, "-out", cert.path)
        Log.info("Created a new certificate authority for this Mac.")
    }

    // MARK: Helpers

    private static func openssl(_ arguments: String..., environment: [String: String] = [:]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw Failure.openssl(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func isPermitted(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { return false }
        let value = parts.reduce(0) { $0 << 8 | $1 }
        return permittedRanges.contains { value & $0.mask == $0.base }
    }

    private static func dotted(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String((value >> $0) & 0xFF) }.joined(separator: ".")
    }

    private static func randomHex(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            fatalError("Secure random generator unavailable")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func derFromPEM(_ pem: Data) throws -> Data {
        let body = String(decoding: pem, as: UTF8.self)
            .split(separator: "\n")
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: body) else { throw Failure.openssl("unreadable CA certificate") }
        return der
    }
}
