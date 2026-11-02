import Foundation
import SQLite3

/// Codex's tasks, from Codex's own files: its thread list (a SQLite database
/// in ~/.codex) and each thread's rollout, which logs every turn starting and
/// finishing. With a ChatGPT sign-in, rollouts also carry plan usage.
final class CodexActivity: AgentSource {
    static func root(home: URL) -> URL { agentFolder(".codex", variable: "CODEX_HOME", home: home) }

    static func isInstalled(home: URL) -> Bool { database(root: root(home: home)) != nil }

    /// The newest thread database, e.g. state_5.sqlite.
    static func database(root: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let versions = files.compactMap { name -> (Int, String)? in
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
                  let version = Int(name.dropFirst(6).dropLast(7)) else { return nil }
            return (version, name)
        }
        return versions.max { $0.0 < $1.0 }.map { root.appendingPathComponent($0.1) }
    }

    static let appID = "com.openai.codex"
    /// A turn that's said nothing for this long is assumed to have stopped.
    static let staleTurn: TimeInterval = 2 * 60 * 60

    let root: URL
    private var rollouts: [String: Rollout] = [:]
    /// The newest plan usage any rollout reported, and when.
    private var latestUsage: (limits: [PlanLimit], at: Date)?

    init(root: URL) { self.root = root }

    func tasks(now: Date) -> [AgentTask] {
        let since = now.addingTimeInterval(-AgentTask.keepDone - Self.staleTurn)
        let threads = Self.recentThreads(root: root, since: since)
        var tasks: [AgentTask] = []
        for thread in threads {
            var rollout = rollouts[thread.id] ?? Rollout(url: URL(fileURLWithPath: thread.rollout))
            rollout.update()
            rollouts[thread.id] = rollout
            if let usage = rollout.usage, usage.at > latestUsage?.at ?? .distantPast { latestUsage = usage }
            guard let turn = rollout.turn else { continue }
            var state = turn.state
            if state != .done && now.timeIntervalSince(thread.updated) > Self.staleTurn { state = .done }
            if state == .done && now.timeIntervalSince(turn.since) > AgentTask.keepDone { continue }
            var task = AgentTask(id: "codex-\(thread.id)", title: thread.title, project: URL(fileURLWithPath: thread.cwd).lastPathComponent,
                                 state: state, since: turn.since)
            if state == .waiting { task.ask = turn.ask }
            // Threads from the Codex app; terminal ones have no app to open.
            if thread.source != "cli" && thread.source != "exec" { task.app = Self.appID }
            tasks.append(task)
        }
        rollouts = rollouts.filter { id, _ in threads.contains { $0.id == id } }
        return tasks.sorted(by: AgentTask.order)
    }

    /// Plan usage from the latest rollout that had it, unless every window
    /// has since reset (the numbers would be stale).
    func usage(now: Date) -> [PlanLimit]? {
        guard let limits = latestUsage?.limits, limits.contains(where: { ($0.resets ?? .distantFuture) > now }) else { return nil }
        return limits
    }

    struct Thread {
        var id: String
        var rollout: String
        var cwd: String
        var title: String
        var source: String
        var updated: Date
    }

    /// Threads people started (not Codex's own helpers) that changed lately.
    static func recentThreads(root: URL, since: Date) -> [Thread] {
        guard let url = database(root: root) else { return [] }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        sqlite3_busy_timeout(db, 200)
        let query = """
            SELECT id, rollout_path, cwd, COALESCE(NULLIF(name, ''), NULLIF(title, ''), first_user_message), source, updated_at_ms
            FROM threads WHERE archived = 0 AND updated_at_ms > ? AND source NOT LIKE '{%'
            ORDER BY updated_at_ms DESC LIMIT 20
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int64(statement, 1, Int64(since.timeIntervalSince1970 * 1000))
        let text = { (column: Int32) in sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
        var threads: [Thread] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let title = text(3).oneLine(120)
            threads.append(Thread(id: text(0), rollout: text(1), cwd: text(2), title: title.isEmpty ? "New thread" : title,
                                  source: text(4), updated: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 5)) / 1000)))
        }
        return threads
    }
}

/// What a Codex rollout says about its latest turn.
struct Rollout {
    struct Turn {
        var state: AgentTask.State
        var since: Date
        var ask: String?
    }

    private var tail: JSONLinesTail
    private(set) var turn: Turn?
    /// The latest plan usage in the rollout, and when it was reported.
    private(set) var usage: (limits: [PlanLimit], at: Date)?

    init(url: URL) { tail = JSONLinesTail(url: url, lookBack: 4 << 20) }

    mutating func update() {
        for line in tail.newLines() {
            guard line.range(of: Self.eventMessage) != nil,
                  let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = entry["payload"] as? [String: Any], let type = payload["type"] as? String else { continue }
            let at = Timestamps.parse(entry["timestamp"]) ?? Date()
            switch type {
            case "task_started":
                turn = Turn(state: .working, since: Timestamps.seconds(payload["started_at"]) ?? at)
            case "task_complete", "turn_aborted":
                turn = Turn(state: .done, since: Timestamps.seconds(payload["completed_at"]) ?? at)
            case _ where type.hasSuffix("approval_request") || type == "request_user_input":
                let command = (payload["command"] as? [String])?.joined(separator: " ")
                let ask = (payload["reason"] as? String) ?? command ?? "Codex needs your OK"
                turn = Turn(state: .waiting, since: at, ask: ask.oneLine())
            case "exec_command_begin", "patch_apply_begin":
                // Running again after an approval.
                if turn?.state == .waiting { turn?.state = .working }
            case "token_count":
                if let limits = Self.limits(payload["rate_limits"] as? [String: Any], at: at) { usage = (limits, at) }
            default: break
            }
        }
    }

    private static let eventMessage = Data(#""event_msg""#.utf8)

    /// Codex's primary (5-hour) and secondary (weekly) windows.
    static func limits(_ limits: [String: Any]?, at: Date) -> [PlanLimit]? {
        guard let limits else { return nil }
        let windows = ["primary", "secondary"].compactMap { limits[$0] as? [String: Any] }
        let parsed = windows.compactMap { window -> PlanLimit? in
            guard let used = (window["used_percent"] as? NSNumber)?.doubleValue else { return nil }
            let minutes = (window["window_minutes"] as? NSNumber)?.intValue
            let label = switch minutes {
            case 300: "5-hour"
            case 10080: "Week"
            case let minutes? where minutes % 1440 == 0: "\(minutes / 1440)-day"
            case let minutes? where minutes % 60 == 0: "\(minutes / 60)-hour"
            default: "Limit"
            }
            let resets = Timestamps.seconds(window["resets_at"])
                ?? (window["resets_in_seconds"] as? NSNumber).map { at.addingTimeInterval($0.doubleValue) }
            return PlanLimit(label: label, percent: Int(used.rounded()), resets: resets)
        }
        return parsed.isEmpty ? nil : parsed
    }
}
