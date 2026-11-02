import Foundation
import SQLite3
import TactileCore

/// The Touch Bar's agent activity, read from made-up Claude and Codex files.
enum AgentChecks {
    static func run(_ checks: Checks) {
        checks.run("agents: a Claude chat's status, plan and current step") {
            try withTemporaryDirectory { home in
                let now = Date()
                let claude = home.appendingPathComponent(".claude")
                try session(claude, file: "1", id: "aaa", status: "busy", since: now.addingTimeInterval(-360), cwd: "/work/web-app",
                            name: "Add dark mode to settings")
                try transcript(claude, cwd: "/work/web-app", id: "aaa", [
                    // Request logs repeat old turns; they must not count.
                    ["type": "api-request-blob", "message": ["content": [tool("Bash", ["description": "Old step"])]]],
                    assistant([tool("mcp__ccd_turn__update_plan", ["items": [
                        ["content": "Read the settings code", "status": "in_progress"],
                        ["content": "Add the dark palette", "status": "pending"],
                        ["content": "Run the web checks", "status": "pending"],
                    ]])]),
                    assistant([tool("mcp__ccd_turn__update_plan", ["advance": true]),
                               tool("Bash", ["description": "Run the web checks", "command": "npm test"])]),
                ])

                let tasks = try claudeTasks(home, at: now)
                try expectEqual(tasks.count, 1, "tasks")
                let task = tasks[0]
                try expectEqual(task["title"] as? String, "Add dark mode to settings", "title")
                try expectEqual(task["project"] as? String, "web-app", "project")
                try expectEqual(task["state"] as? String, "working", "state")
                try expectEqual(task["app"] as? String, "com.anthropic.claudefordesktop", "app")
                try expectEqual(task["now"] as? String, "Run the web checks", "now")
                let steps = (task["steps"] as? [[String: String]] ?? []).map { "\($0["state"]!) \($0["text"]!)" }
                try expectEqual(steps, ["done Read the settings code", "current Add the dark palette", "todo Run the web checks"], "steps")
            }
        }

        checks.run("agents: Claude waiting, finished long ago, and closed chats") {
            try withTemporaryDirectory { home in
                let now = Date()
                let claude = home.appendingPathComponent(".claude")
                try session(claude, file: "1", id: "wait", status: "waiting", since: now, cwd: "/work/api", name: "Fix flaky login test")
                try transcript(claude, cwd: "/work/api", id: "wait", [
                    assistant([tool("Bash", ["command": "npm test -- login"])]),
                ])
                try session(claude, file: "2", id: "old", status: "idle", since: now.addingTimeInterval(-4 * 3600), cwd: "/work/api", name: "Old")
                try transcript(claude, cwd: "/work/api", id: "old", [assistant([tool("Read", [:])])])
                try session(claude, file: "3", id: "gone", status: "busy", since: now, cwd: "/work/api", name: "Closed", pid: 99_999_999)
                try transcript(claude, cwd: "/work/api", id: "gone", [assistant([tool("Read", [:])])])
                try session(claude, file: "4", id: "fresh", status: "idle", since: now, cwd: "/work/api", name: "Nothing sent yet")

                let tasks = try claudeTasks(home, at: now)
                try expectEqual(tasks.map { $0["title"] as? String }, ["Fix flaky login test"], "tasks shown")
                try expectEqual(tasks[0]["state"] as? String, "waiting", "state")
                try expectEqual(tasks[0]["ask"] as? String, "npm test -- login", "what it's waiting to run")
            }
        }

        checks.run("agents: a finished Claude task list is all done; terminal chats keep their to-dos") {
            try withTemporaryDirectory { home in
                let now = Date()
                let claude = home.appendingPathComponent(".claude")
                try session(claude, file: "1", id: "app", status: "idle", since: now, cwd: "/work/docs", name: "Write release notes")
                try transcript(claude, cwd: "/work/docs", id: "app", [
                    assistant([tool("mcp__ccd_turn__update_plan", ["items": [
                        ["content": "Draft", "status": "in_progress"], ["content": "Proofread", "status": "pending"],
                    ]])]),
                    assistant([tool("mcp__ccd_turn__wrap_up", ["recap": "Done."])]),
                ])
                try session(claude, file: "2", id: "cli", status: "busy", since: now, cwd: "/work/docs", name: "Tidy",
                            entrypoint: "cli")
                try transcript(claude, cwd: "/work/docs", id: "cli", [
                    assistant([tool("TodoWrite", ["todos": [
                        ["content": "Sort imports", "status": "completed"], ["content": "Fix lint", "status": "in_progress"],
                    ]])]),
                ])

                let tasks = try claudeTasks(home, at: now)
                let byTitle = Dictionary(uniqueKeysWithValues: tasks.map { ($0["title"] as! String, $0) })
                let states = { (title: String) in (byTitle[title]?["steps"] as? [[String: String]] ?? []).map { $0["state"]! } }
                try expectEqual(states("Write release notes"), ["done", "done"], "after wrap-up")
                try expectEqual(byTitle["Write release notes"]?["state"] as? String, "done", "finished")
                try expectEqual(states("Tidy"), ["done", "current"], "to-dos")
                try expect(byTitle["Tidy"]?["app"] == nil, "a terminal chat has no app to open")

                // A new message after a finished plan starts afresh.
                let file = claude.appendingPathComponent("projects/-work-docs/app.jsonl")
                let prompt = try JSONSerialization.data(withJSONObject: ["type": "user", "message": ["role": "user", "content": "Now the blog post"]])
                let handle = try FileHandle(forWritingTo: file)
                try handle.seekToEnd()
                try handle.write(contentsOf: prompt + Data("\n".utf8))
                try handle.close()
                let after = try claudeTasks(home, at: now).first { $0["title"] as? String == "Write release notes" }
                try expect(after?["steps"] == nil, "finished plan cleared")
            }
        }

        checks.run("agents: opening a task opens its own chat, and nothing else") {
            try withTemporaryDirectory { home in
                let now = Date()
                let claude = home.appendingPathComponent(".claude")
                try session(claude, file: "1", id: "chat", status: "busy", since: now, cwd: "/work/app", name: "Chat",
                            host: "local_1a2b-3c")
                try transcript(claude, cwd: "/work/app", id: "chat", [assistant([tool("Read", [:])])])
                try session(claude, file: "2", id: "odd", status: "busy", since: now, cwd: "/work/app", name: "Odd",
                            host: "local_x&open=evil")
                try transcript(claude, cwd: "/work/app", id: "odd", [assistant([tool("Read", [:])])])
                let monitor = AgentMonitor(home: home)
                _ = monitor.readNow(AgentInterest(apps: ["claude"], usage: false), at: now)

                let opened = { (id: String) -> String? in
                    waitFor(timeout: 2) { done in
                        monitor.open(id, link: { done("link \($0.absoluteString)") }, app: { done("app \($0)") })
                    }
                }
                try expectEqual(opened("claude-chat"), "link claude://code/continue?session=local_1a2b-3c", "the chat itself")
                try expectEqual(opened("claude-odd"), "app com.anthropic.claudefordesktop", "an ID that isn't the app's: just the app")
                try expect(opened("claude-unknown") == nil, "a task the Mac never showed opens nothing")
            }
        }

        checks.run("agents: transcripts are read as they grow, a line at a time") {
            try withTemporaryDirectory { home in
                let claude = home.appendingPathComponent(".claude")
                let now = Date()
                try session(claude, file: "1", id: "grow", status: "busy", since: now, cwd: "/work/app", name: "Grow")
                let file = try transcript(claude, cwd: "/work/app", id: "grow", [assistant([tool("Bash", ["description": "First"])])])
                let monitor = AgentMonitor(home: home)
                let now1 = (try tasks(monitor, "claude", at: now)).first?["now"] as? String
                try expectEqual(now1, "First", "first read")

                // Half a line, then the rest.
                let line = try JSONSerialization.data(withJSONObject: assistant([tool("Bash", ["description": "Second"])]))
                let handle = try FileHandle(forWritingTo: file)
                try handle.seekToEnd()
                try handle.write(contentsOf: line.prefix(20))
                try expectEqual((try tasks(monitor, "claude", at: now)).first?["now"] as? String, "First", "half a line")
                try handle.write(contentsOf: line.dropFirst(20) + Data("\n".utf8))
                try handle.close()
                try expectEqual((try tasks(monitor, "claude", at: now)).first?["now"] as? String, "Second", "whole line")
            }
        }

        checks.run("agents: Codex threads, turns and plan usage") {
            try withTemporaryDirectory { home in
                let now = Date()
                let codex = home.appendingPathComponent(".codex")
                try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
                let working = codex.appendingPathComponent("working.jsonl")
                let finished = codex.appendingPathComponent("finished.jsonl")
                try codexDatabase(codex.appendingPathComponent("state_5.sqlite"), [
                    ("t1", working.path, "/work/api", "Refactor billing webhooks", "vscode", now),
                    ("t2", finished.path, "/work/cli-tool", "Bump dependencies", "cli", now.addingTimeInterval(-60)),
                    ("t3", finished.path, "/work/api", "Review", #"{"subagent":{"other":"guardian"}}"#, now),
                ])
                let started = now.timeIntervalSince1970 - 840
                try lines(working, [
                    event(now, ["type": "task_started", "started_at": started]),
                    event(now, ["type": "token_count", "rate_limits": [
                        "primary": ["used_percent": 23.4, "window_minutes": 300, "resets_at": now.timeIntervalSince1970 + 3600],
                        "secondary": ["used_percent": 8, "window_minutes": 10080, "resets_at": now.timeIntervalSince1970 + 86400],
                    ]]),
                ])
                try lines(finished, [
                    event(now, ["type": "task_started", "started_at": started]),
                    event(now, ["type": "task_complete", "completed_at": now.timeIntervalSince1970 - 60]),
                ])

                let monitor = AgentMonitor(home: home)
                let entry = try require(monitor.readNow(AgentInterest(apps: ["codex"], usage: true), at: now)["codex"] as? [String: Any], "codex")
                let tasks = entry["tasks"] as? [[String: Any]] ?? []
                try expectEqual(tasks.map { $0["title"] as? String }, ["Refactor billing webhooks", "Bump dependencies"], "threads")
                try expectEqual(tasks.map { $0["state"] as? String }, ["working", "done"], "states")
                try expectEqual(tasks[0]["since"] as? Int, Int(started * 1000), "working since the turn started")
                try expectEqual(tasks[0]["app"] as? String, "com.openai.codex", "app thread")
                try expect(tasks[1]["app"] == nil, "terminal thread")
                let usage = (entry["usage"] as? [[String: Any]] ?? []).map { "\($0["label"]!) \($0["percent"]!)" }
                try expectEqual(usage, ["5-hour 23", "Week 8"], "usage")

                try lines(working, [event(now, ["type": "task_complete", "completed_at": now.timeIntervalSince1970])], append: true)
                let after = (monitor.readNow(AgentInterest(apps: ["codex"], usage: false), at: now)["codex"] as? [String: Any])
                try expectEqual((after?["tasks"] as? [[String: Any]])?.first?["state"] as? String, "done", "after the turn ends")
                try expect(after?["usage"] == nil, "no usage unless asked")
            }
        }

        checks.run("agents: Claude plan usage from Claude Code's reply") {
            let reply: [String: Any] = ["rate_limits_available": true, "rate_limits": ["limits": [
                ["kind": "session", "group": "session", "percent": 42, "resets_at": "2026-11-01T22:00:00.141292+00:00"],
                ["kind": "weekly_scoped", "group": "weekly", "percent": 3, "resets_at": "2026-11-02T16:00:00+00:00",
                 "scope": ["model": ["display_name": "Opus"]]],
            ]]]
            let limits = try require(AgentMonitor.claudeLimits(reply), "limits")
            try expectEqual(limits.map { "\($0["label"]!) \($0["percent"]!)" }, ["5-hour 42", "Week · Opus 3"], "limits")
            try expectEqual(limits[0]["resets"] as? Int, 1_793_570_400_141, "reset time")
            try expect(AgentMonitor.claudeLimits(["rate_limits_available": false]) == nil, "none with an API key")
        }
    }

    // MARK: Fixtures

    private static func tasks(_ monitor: AgentMonitor, _ app: String, at now: Date) throws -> [[String: Any]] {
        (monitor.readNow(AgentInterest(apps: [app], usage: false), at: now)[app] as? [String: Any])?["tasks"] as? [[String: Any]] ?? []
    }

    private static func claudeTasks(_ home: URL, at now: Date) throws -> [[String: Any]] {
        try tasks(AgentMonitor(home: home), "claude", at: now)
    }

    private static func session(_ claude: URL, file: String, id: String, status: String, since: Date, cwd: String, name: String,
                                pid: Int32 = getpid(), entrypoint: String = "claude-desktop", host: String? = nil) throws {
        let folder = claude.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claude.appendingPathComponent("projects"), withIntermediateDirectories: true)
        let ms = Int(since.timeIntervalSince1970 * 1000)
        var json: [String: Any] = ["pid": pid, "sessionId": id, "cwd": cwd, "kind": "interactive", "entrypoint": entrypoint,
                                   "name": name, "status": status, "statusUpdatedAt": ms, "updatedAt": ms]
        if let host { json["hostSessionId"] = host }
        try JSONSerialization.data(withJSONObject: json).write(to: folder.appendingPathComponent("\(file).json"))
    }

    @discardableResult
    private static func transcript(_ claude: URL, cwd: String, id: String, _ entries: [[String: Any]]) throws -> URL {
        let folder = claude.appendingPathComponent("projects").appendingPathComponent(cwd.replacingOccurrences(of: "/", with: "-"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(id).jsonl")
        try lines(url, entries)
        return url
    }

    private static func lines(_ url: URL, _ entries: [[String: Any]], append: Bool = false) throws {
        var data = Data()
        for entry in entries {
            data += try JSONSerialization.data(withJSONObject: entry)
            data += Data("\n".utf8)
        }
        if append, let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url)
        }
    }

    private static func tool(_ name: String, _ input: [String: Any]) -> [String: Any] {
        ["type": "tool_use", "name": name, "input": input]
    }

    private static func assistant(_ content: [[String: Any]]) -> [String: Any] {
        ["type": "assistant", "isSidechain": false, "message": ["content": content]]
    }

    private static func event(_ at: Date, _ payload: [String: Any]) -> [String: Any] {
        ["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: at), "payload": payload]
    }

    private static func codexDatabase(_ url: URL, _ threads: [(String, String, String, String, String, Date)]) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        try expect(sqlite3_open(url.path, &db) == SQLITE_OK, "database opens")
        var sql = """
            CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT, cwd TEXT, title TEXT, name TEXT,
              first_user_message TEXT DEFAULT '', source TEXT, archived INTEGER DEFAULT 0, updated_at_ms INTEGER);
            """
        for (id, rollout, cwd, title, source, updated) in threads {
            sql += "INSERT INTO threads (id, rollout_path, cwd, title, source, updated_at_ms) VALUES "
                + "('\(id)', '\(rollout)', '\(cwd)', '\(title)', '\(source)', \(Int(updated.timeIntervalSince1970 * 1000)));"
        }
        try expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "database is set up")
    }
}
