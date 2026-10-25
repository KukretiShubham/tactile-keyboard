import CryptoKit
import Foundation
import Network
import Security

/// A certificate and private key the servers present to the iPad.
struct TLSIdentity {
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

    /// Loads a PEM certificate (plus any chain in the same file) and its key.
    /// They're bundled as PKCS#12 in memory, the form the Security framework imports.
    static func load(certificate: URL, key: URL, extraChain: URL? = nil) throws -> TLSIdentity {
        let work = try OpenSSL.workDirectory()
        defer { try? FileManager.default.removeItem(at: work) }
        let p12 = work.appendingPathComponent("identity.p12")

        // The bundle's password never touches argv.
        let password = OpenSSL.randomHex(24)
        var arguments = ["pkcs12", "-export", "-inkey", key.path, "-in", certificate.path,
                         "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1",
                         "-passout", "env:TACTILE_P12", "-out", p12.path]
        if let extraChain { arguments += ["-certfile", extraChain.path] }
        try OpenSSL.run(arguments, environment: ["TACTILE_P12": password])

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
        return TLSIdentity(identity: identity)
    }

    /// A new options object per listener; all share the same certificate.
    func options() -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, identity)
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        return options
    }
}

/// A private certificate authority for this Mac, plus a fresh HTTPS certificate
/// issued on every launch for the Mac's current name and addresses. Used when
/// the iPad isn't on Tailscale; it has to trust the CA once.
///
/// The CA is name-constrained to `.local` names and private IPv4 ranges, so even
/// if its key leaked it could not be used to impersonate public websites on the
/// iPad that trusts it. Certificates are made with the LibreSSL that ships with
/// macOS, so there is nothing extra to install or keep patched.
struct LocalAuthority {
    let identity: TLSIdentity
    let caDER: Data
    let caName: String
    let fingerprint: String

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

    static func prepare(hostName: String?, addresses: [String]) throws -> LocalAuthority {
        let fm = FileManager.default
        let dir = directory
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let caKey = dir.appendingPathComponent("ca.key")
        let caCert = dir.appendingPathComponent("ca.crt")
        if !fm.fileExists(atPath: caKey.path) || !fm.fileExists(atPath: caCert.path) {
            try createAuthority(key: caKey, cert: caCert)
        }

        let work = try OpenSSL.workDirectory()
        defer { try? fm.removeItem(at: work) }

        let names = ["localhost"] + [hostName].compactMap { $0 }
        let ips = ["127.0.0.1"] + addresses.filter(isPermitted)
        let san = (names.map { "DNS:\($0)" } + ips.map { "IP:\($0)" }).joined(separator: ", ")

        let key = work.appendingPathComponent("server.key")
        let csr = work.appendingPathComponent("server.csr")
        let cert = work.appendingPathComponent("server.crt")
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

        try OpenSSL.run(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", key.path])
        try OpenSSL.run(["req", "-new", "-key", key.path, "-subj", "/CN=\(names.last!)", "-out", csr.path])
        try OpenSSL.run(["x509", "-req", "-in", csr.path, "-CA", caCert.path, "-CAkey", caKey.path,
                         "-set_serial", "0x\(OpenSSL.randomHex(16))", "-days", "397", "-sha256",
                         "-extfile", ext.path, "-extensions", "v3", "-out", cert.path])

        let identity = try TLSIdentity.load(certificate: cert, key: key, extraChain: caCert)
        let caDER = try OpenSSL.derFromPEM(Data(contentsOf: caCert))
        // Same format iOS uses under the profile's More Details.
        let fingerprint = SHA256.hash(data: caDER).map { String(format: "%02X", $0) }.joined(separator: " ")
        return LocalAuthority(identity: identity, caDER: caDER, caName: authorityName, fingerprint: fingerprint)
    }

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

        try OpenSSL.run(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", key.path])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
        try OpenSSL.run(["req", "-x509", "-new", "-key", key.path, "-sha256", "-days", "3650",
                         "-config", config.path, "-out", cert.path])
        Log.info("Created a new certificate authority for this Mac.")
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
}

/// The LibreSSL command-line tool that ships with macOS.
enum OpenSSL {
    static func run(_ arguments: [String], environment: [String: String] = [:]) throws {
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
            throw TLSIdentity.Failure.openssl(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// A private scratch folder that callers delete when done.
    static func workDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tactile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }

    static func randomHex(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            fatalError("Secure random generator unavailable")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func derFromPEM(_ pem: Data) throws -> Data {
        let body = String(decoding: pem, as: UTF8.self)
            .split(separator: "\n")
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: body) else { throw TLSIdentity.Failure.openssl("unreadable certificate") }
        return der
    }
}
