import Foundation

/// A tiny check runner. The Command Line Tools ship neither XCTest nor Swift
/// Testing, so Tactile's checks are a plain executable: `swift run tactile-checks`.
struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: Bool, _ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) throws {
    if !condition { throw CheckFailure(description: "\(message()) (\(file):\(line))") }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ what: String, file: StaticString = #fileID, line: UInt = #line) throws {
    try expect(actual == expected, "\(what): expected \(expected), got \(actual)", file: file, line: line)
}

/// Unwraps `value`, failing the check when it's nil.
func require<T>(_ value: T?, _ what: String, file: StaticString = #fileID, line: UInt = #line) throws -> T {
    guard let value else { throw CheckFailure(description: "\(what) was nil (\(file):\(line))") }
    return value
}

/// Keeps the main run loop going until `condition` holds or `timeout` passes.
@discardableResult
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return true
}

/// Waits for a callback-style result (delivered on any queue).
func waitFor<T>(timeout: TimeInterval = 5, _ start: (@escaping (T) -> Void) -> Void) -> T? {
    let lock = NSLock()
    var result: T?
    start { value in lock.withLock { result = value } }
    waitUntil(timeout: timeout) { lock.withLock { result != nil } }
    return lock.withLock { result }
}

/// A folder for one check's files, deleted afterwards.
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tactile-checks-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url)
}

final class Checks {
    private var failures: [(name: String, message: String)] = []
    private var count = 0

    func run(_ name: String, _ body: () throws -> Void) {
        count += 1
        do {
            try body()
            print("PASS  \(name)")
        } catch {
            failures.append((name, "\(error)"))
            print("FAIL  \(name) — \(error)")
        }
    }

    /// Records a result worked out elsewhere (the web tests).
    func record(_ name: String, passed: Bool, message: String = "") {
        count += 1
        if passed {
            print("PASS  \(name)")
        } else {
            failures.append((name, message))
            print("FAIL  \(name) — \(message)")
        }
    }

    /// Prints a summary; returns the process exit status.
    func finish() -> Int32 {
        print("\n\(count - failures.count) of \(count) checks passed.")
        for failure in failures { print("  ✗ \(failure.name): \(failure.message)") }
        return failures.isEmpty ? 0 : 1
    }
}
