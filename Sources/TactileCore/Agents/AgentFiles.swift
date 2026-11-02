import Foundation

/// An agent's folder in your home, e.g. ~/.claude, unless `variable` (such as
/// CLAUDE_CONFIG_DIR) points elsewhere.
func agentFolder(_ name: String, variable: String, home: URL) -> URL {
    if let custom = ProcessInfo.processInfo.environment[variable], !custom.isEmpty {
        return URL(fileURLWithPath: custom, isDirectory: true)
    }
    return home.appendingPathComponent(name, isDirectory: true)
}

/// Reads a growing JSON Lines file a piece at a time: the first read starts
/// near the end (transcripts grow to hundreds of megabytes), later reads
/// pick up only what was added.
struct JSONLinesTail {
    let url: URL
    private(set) var offset: UInt64?
    /// How far from the end the first read starts.
    let lookBack: UInt64

    init(url: URL, lookBack: UInt64 = 8 << 20) {
        self.url = url
        self.lookBack = lookBack
    }

    /// Complete lines added since the last read.
    mutating func newLines() -> [Data] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        var start = offset ?? (size > lookBack ? size - lookBack : 0)
        if start > size { start = 0 } // replaced by a shorter file
        guard start < size, (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.read(upToCount: Int(size - start)) else { return [] }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        // The last piece has no newline yet unless the file ends with one.
        let partial = lines.removeLast()
        // Starting mid-file, the first piece is the end of a line.
        if offset == nil && start > 0 && !lines.isEmpty { lines.removeFirst() }
        offset = size - UInt64(partial.count)
        return lines.map { Data($0) }
    }
}

extension String {
    /// Trimmed to one line of at most `limit` characters.
    func oneLine(_ limit: Int = 160) -> String {
        let line = split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }
}

extension Date {
    /// Milliseconds since 1970, as the iPad's clock counts.
    var milliseconds: Int { Int(timeIntervalSince1970 * 1000) }
}

/// Times as the agents write them.
enum Timestamps {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain = ISO8601DateFormatter()

    /// ISO 8601 text, with or without fractions of a second.
    static func parse(_ text: Any?) -> Date? {
        guard let text = text as? String else { return nil }
        if let date = withFraction.date(from: text) ?? plain.date(from: text) { return date }
        // Python-style microseconds, e.g. "2026-11-01T22:00:00.141292+00:00".
        if let dot = text.firstIndex(of: "."), let zone = text[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            return plain.date(from: String(text[..<dot]) + String(text[zone...]))
        }
        return nil
    }

    static func milliseconds(_ value: Any?) -> Date? {
        (value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
    }

    static func seconds(_ value: Any?) -> Date? {
        (value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
    }
}
