import Foundation

/// Runs command-line tools Tactile relies on (the system's `openssl` and the
/// `tailscale` CLI).
enum Shell {
    struct Result {
        let status: Int32
        let output: Data
        let errors: String

        var succeeded: Bool { status == 0 }
    }

    /// Runs `path` with `arguments` and waits for it, up to `timeout` seconds.
    /// Returns nil if it can't be started or doesn't finish in time.
    static func run(_ path: String, _ arguments: [String], environment: [String: String] = [:],
                    timeout: TimeInterval = 30) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() } catch { return nil }

        // Read both pipes while the process runs so neither can fill up and stall it.
        var outputData = Data(), errorData = Data()
        let reading = DispatchGroup()
        for (pipe, assign) in [(output, { outputData = $0 }), (errors, { errorData = $0 })] as [(Pipe, (Data) -> Void)] {
            reading.enter()
            DispatchQueue.global().async {
                assign(pipe.fileHandleForReading.readDataToEndOfFile())
                reading.leave()
            }
        }
        if reading.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: outputData,
                      errors: String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
