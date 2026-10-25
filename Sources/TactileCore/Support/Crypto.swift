import CryptoKit
import Foundation
import Security

enum SecureRandom {
    /// `count` random bytes from the system's secure generator, as lowercase hex.
    static func hex(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            fatalError("Secure random generator unavailable")
        }
        return bytes.hex()
    }

    /// A string of `count` random decimal digits.
    static func digits(_ count: Int) -> String {
        (0..<count).map { _ in String(Int.random(in: 0...9)) }.joined()
    }
}

extension Sequence<UInt8> {
    /// Lowercase hex, e.g. "0d2957".
    func hex() -> String { map { String(format: "%02x", $0) }.joined() }

    /// Uppercase byte pairs, e.g. "0D 29 57", as macOS and iOS show fingerprints.
    func fingerprint() -> String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}

extension Data {
    var sha256: SHA256.Digest { SHA256.hash(data: self) }
}

/// Compares secrets in constant time, so timing reveals nothing about them.
func constantTimeEqual(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8), y = Array(b.utf8)
    guard x.count == y.count else { return false }
    return zip(x, y).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
}
