import Foundation

/// Plain console logging. Inside Tactile.app, standard output is redirected to
/// the log file (see `Paths.logFile`).
public enum Log {
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // Colors only when a person is watching in Terminal, never in the log file.
    private static let colored = isatty(STDOUT_FILENO) != 0
    private static func styled(_ text: String, _ code: String) -> String { colored ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text }
    private static var now: String { clock.string(from: Date()) }

    public static func info(_ message: String) { print("\(now)  \(message)") }
    public static func warn(_ message: String) { print(styled("\(now)  ⚠︎ \(message)", "33")) }
    public static func input(_ message: String) { print(styled("\(now)  \(message)", "2")) }
}

/// How unrecoverable errors reach the user: printed in Terminal by default, or
/// an alert in the menu bar app (which installs its own handler).
public enum Fatal {
    public static var handler: (String) -> Void = { message in
        fputs("\(message)\n", stderr)
        exit(1)
    }

    public static func report(_ message: String) { handler(message) }
}
