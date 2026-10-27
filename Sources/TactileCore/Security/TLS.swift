import Foundation
import Network
import Security

/// A certificate and private key the servers present to the iPad.
public struct TLSIdentity {
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
        let work = try Paths.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: work) }
        let p12 = work.appendingPathComponent("identity.p12")

        // The bundle's password never touches argv.
        let password = SecureRandom.hex(bytes: 24)
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
/// issued on every start for the Mac's current name and addresses. Used when
/// the iPad isn't on Tailscale; it has to trust the CA once.
///
/// The CA is name-constrained to `.local` names and private IPv4 ranges, so even
/// if its key leaked it could not be used to impersonate public websites on the
/// iPad that trusts it.
public struct LocalAuthority {
    let identity: TLSIdentity
    public let caDER: Data
    /// The HTTPS certificate issued this time (DER), for checks.
    public let certificateDER: Data
    let caName: String
    public let fingerprint: String

    /// Private ranges the CA may issue for (RFC 1918, Tailscale/CGNAT, loopback).
    static let permittedRanges: [(base: UInt32, mask: UInt32)] = [
        (0x0A00_0000, 0xFF00_0000), // 10.0.0.0/8
        (0xAC10_0000, 0xFFF0_0000), // 172.16.0.0/12
        (0xC0A8_0000, 0xFFFF_0000), // 192.168.0.0/16
        (0x6440_0000, 0xFFC0_0000), // 100.64.0.0/10
        (0x7F00_0000, 0xFF00_0000), // 127.0.0.0/8
    ]

    /// - Parameter directory: Where the CA lives. Tests pass a temporary folder.
    public static func prepare(hostName: String?, addresses: [String], directory: URL = Paths.tls) throws -> LocalAuthority {
        try Paths.makePrivateDirectory(directory)
        let caKey = directory.appendingPathComponent("ca.key")
        let caCert = directory.appendingPathComponent("ca.crt")
        let fm = FileManager.default
        if !fm.fileExists(atPath: caKey.path) || !fm.fileExists(atPath: caCert.path) {
            try createAuthority(key: caKey, cert: caCert)
        }

        let work = try Paths.temporaryDirectory()
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
        // Browsers check the names listed above, not the common name; a fixed
        // one keeps within OpenSSL's 64-character limit for any host name.
        try OpenSSL.run(["req", "-new", "-key", key.path, "-subj", "/CN=Tactile", "-out", csr.path])
        try OpenSSL.run(["x509", "-req", "-in", csr.path, "-CA", caCert.path, "-CAkey", caKey.path,
                         "-set_serial", "0x\(SecureRandom.hex(bytes: 16))", "-days", "397", "-sha256",
                         "-extfile", ext.path, "-extensions", "v3", "-out", cert.path])

        let caDER = try OpenSSL.derFromPEM(Data(contentsOf: caCert))
        return LocalAuthority(identity: try TLSIdentity.load(certificate: cert, key: key, extraChain: caCert),
                              caDER: caDER, certificateDER: try OpenSSL.derFromPEM(Data(contentsOf: cert)),
                              caName: authorityName,
                              // Same format iOS uses under the profile's More Details.
                              fingerprint: caDER.sha256.fingerprint())
    }

    private static var authorityName: String { authorityName(for: HostInfo.computerName) }

    /// The CA's name as the iPad shows it, e.g. "Tactile CA - Studio Mac":
    /// letters, digits, spaces and hyphens only, and within OpenSSL's
    /// 64-character limit however long the Mac's name is.
    public static func authorityName(for computerName: String) -> String {
        let prefix = "Tactile CA - "
        let kept = computerName.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" }
        let mac = String(String.UnicodeScalarView(kept)).prefix(64 - prefix.count).trimmingCharacters(in: .whitespaces)
        return prefix + (mac.isEmpty ? "Mac" : mac)
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

    /// Whether the CA may vouch for `address` (an IPv4 address in a private range).
    public static func isPermitted(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { return false }
        let value = parts.reduce(0) { $0 << 8 | $1 }
        return permittedRanges.contains { value & $0.mask == $0.base }
    }

    private static func dotted(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String((value >> $0) & 0xFF) }.joined(separator: ".")
    }
}

/// The LibreSSL command-line tool that ships with macOS, so there's nothing
/// extra to install or keep patched.
enum OpenSSL {
    static func run(_ arguments: [String], environment: [String: String] = [:]) throws {
        guard let result = Shell.run("/usr/bin/openssl", arguments, environment: environment) else {
            throw TLSIdentity.Failure.openssl("couldn't run /usr/bin/openssl")
        }
        guard result.succeeded else { throw TLSIdentity.Failure.openssl(result.errors) }
    }

    static func derFromPEM(_ pem: Data) throws -> Data {
        let body = String(decoding: pem, as: UTF8.self)
            .split(separator: "\n")
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: body) else { throw TLSIdentity.Failure.openssl("unreadable certificate") }
        return der
    }

    /// Splits PEM text into its certificate blocks and its private key block.
    static func split(_ pem: String) -> (certificates: [String], key: String?) {
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
}
