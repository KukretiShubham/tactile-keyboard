import Foundation

/// Plain console logging. Inside Tactile.app, standard output is redirected to
/// the log file (see `Paths.logFile`).
public enum Log {
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    public static func info(_ message: String) { print("\(clock.string(from: Date()))  \(message)") }
    public static func warn(_ message: String) { print("\u{1B}[33m⚠︎ \(message)\u{1B}[0m") }
    public static func input(_ message: String) { print("\u{1B}[2m\(clock.string(from: Date()))  \(message)\u{1B}[0m") }
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
