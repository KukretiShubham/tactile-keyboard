import Foundation

/// How much of a Claude subscription has been used, asked of Claude Code
/// itself: it's started without a prompt (so nothing is sent to Claude, no
/// chat is made and nothing counts against the plan) and asked for usage, as
/// the Claude app asks it. Claude Code signs in on its own; Tactile never
/// touches its sign-in. Not available with an API key.
enum ClaudeUsage {
    /// Where Claude Code is usually installed.
    static func executable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = [home.appendingPathComponent(".local/bin/claude"),
                          home.appendingPathComponent(".claude/local/claude"),
                          URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
                          URL(fileURLWithPath: "/usr/local/bin/claude")]
        // The copy the Claude app keeps, newest version first.
        let bundled = home.appendingPathComponent("Library/Application Support/Claude/claude-code")
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: bundled.path)) ?? []
        candidates += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { bundled.appendingPathComponent($0).appendingPathComponent("claude") }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// The plan's limits, or nil if Claude Code isn't installed, isn't signed
    /// in to a plan, or doesn't answer in time. Blocks for a few seconds.
    static func read(timeout: TimeInterval = 30) -> [PlanLimit]? {
        guard let executable = executable(),
              let folder = try? Paths.temporaryDirectory() else { return nil }
        defer { try? FileManager.default.removeItem(at: folder) }

        let process = Process()
        process.executableURL = executable
        // No MCP servers or hooks: this run only answers one question.
        process.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                             "--strict-mcp-config", "--settings", #"{"disableAllHooks": true}"#]
        process.currentDirectoryURL = folder
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer {
            watchdog.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        func ask(_ id: String, _ subtype: String) -> [String: Any]? {
            let request: [String: Any] = ["type": "control_request", "request_id": id, "request": ["subtype": subtype]]
            guard var line = try? JSONSerialization.data(withJSONObject: request) else { return nil }
            line.append(UInt8(ascii: "\n"))
            do { try input.fileHandleForWriting.write(contentsOf: line) } catch { return nil }
            return reply(to: id, from: output.fileHandleForReading)
        }

        guard ask("init", "initialize") != nil, let usage = ask("usage", "get_usage") else { return nil }
        return limits(usage)
    }

    /// Reads lines until the control response for `id` (nil at end of output).
    private static func reply(to id: String, from handle: FileHandle) -> [String: Any]? {
        var pending = Data()
        while true {
            if let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = pending[..<newline]
                pending = Data(pending[(newline + 1)...])
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      message["type"] as? String == "control_response",
                      let response = message["response"] as? [String: Any],
                      response["request_id"] as? String == id else { continue }
                return response["response"] as? [String: Any] ?? [:]
            }
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            pending.append(chunk)
        }
    }

    /// The limits in a `get_usage` response: the 5-hour session first, then
    /// weekly ones. Nil without a subscription.
    static func limits(_ usage: [String: Any]) -> [PlanLimit]? {
        guard usage["rate_limits_available"] as? Bool == true,
              let rateLimits = usage["rate_limits"] as? [String: Any] else { return nil }
        if let limits = rateLimits["limits"] as? [[String: Any]] {
            let parsed = limits.compactMap { limit -> PlanLimit? in
                guard let percent = (limit["percent"] as? NSNumber)?.doubleValue else { return nil }
                let model = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                let label = switch limit["group"] as? String {
                case "session": "5-hour"
                case "weekly": model.map { "Week · \($0)" } ?? "Week"
                default: model ?? "Limit"
                }
                return PlanLimit(label: label, percent: Int(percent.rounded()), resets: Timestamps.parse(limit["resets_at"]))
            }
            if !parsed.isEmpty { return parsed }
        }
        // Older Claude Code: fixed windows.
        let windows = [("five_hour", "5-hour"), ("seven_day", "Week")].compactMap { key, label -> PlanLimit? in
            guard let window = rateLimits[key] as? [String: Any],
                  let used = (window["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return PlanLimit(label: label, percent: Int(used.rounded()), resets: Timestamps.parse(window["resets_at"]))
        }
        return windows.isEmpty ? nil : windows
    }
}
