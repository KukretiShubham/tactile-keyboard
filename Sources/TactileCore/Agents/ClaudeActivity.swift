import Foundation

/// Claude's tasks, from Claude Code's own files: each open chat (in the Claude
/// app or a terminal) keeps a status file in ~/.claude/sessions, and its
/// transcript in ~/.claude/projects records its plan and what it's doing.
final class ClaudeActivity: AgentSource {
    static func root(home: URL) -> URL { agentFolder(".claude", variable: "CLAUDE_CONFIG_DIR", home: home) }

    static func isInstalled(home: URL) -> Bool {
        FileManager.default.fileExists(atPath: root(home: home).appendingPathComponent("projects").path)
    }

    static let appID = "com.anthropic.claudefordesktop"

    let root: URL
    /// Plan usage, as last read from Claude Code (see `ClaudeUsage`).
    var planUsage: [PlanLimit]?
    private var transcripts: [String: Transcript] = [:]

    init(root: URL) { self.root = root }

    func usage(now: Date) -> [PlanLimit]? { planUsage }

    func tasks(now: Date) -> [AgentTask] {
        let folder = root.appendingPathComponent("sessions", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var tasks: [AgentTask] = []
        var seen: Set<String> = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = session["sessionId"] as? String,
                  let pid = (session["pid"] as? NSNumber)?.int32Value, Self.isRunning(pid) else { continue }
            // Only chats, not one-off `claude -p` runs (such as the plan usage
            // check in `ClaudeUsage`).
            if let kind = session["kind"] as? String, kind != "interactive" { continue }
            seen.insert(id)
            guard let task = task(id, session, now: now) else { continue }
            tasks.append(task)
        }
        transcripts = transcripts.filter { seen.contains($0.key) }
        return tasks.sorted(by: AgentTask.order)
    }

    /// A status file outlives a chat whose process crashed.
    private static func isRunning(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

    private func task(_ id: String, _ session: [String: Any], now: Date) -> AgentTask? {
        let since = Timestamps.milliseconds(session["statusUpdatedAt"]) ?? Timestamps.milliseconds(session["updatedAt"]) ?? now
        let state: AgentTask.State
        switch session["status"] as? String {
        case "busy": state = .working
        case "waiting": state = .waiting
        default:
            guard now.timeIntervalSince(since) < AgentTask.keepDone else { return nil }
            state = .done
        }
        let cwd = session["cwd"] as? String ?? ""
        // A chat that hasn't been sent anything yet has no transcript.
        guard let transcript = readTranscript(id, cwd: cwd) else { return nil }
        let name = (session["name"] as? String)?.oneLine(120)
        var task = AgentTask(id: "claude-\(id)", title: name.flatMap { $0.isEmpty ? nil : $0 } ?? "New chat",
                             project: URL(fileURLWithPath: cwd).lastPathComponent, state: state, since: since)
        task.steps = transcript.plan.steps
        if state != .done { task.now = transcript.lastAction }
        if state == .waiting { task.ask = transcript.lastAsk }
        if (session["entrypoint"] as? String) == "claude-desktop" {
            task.app = Self.appID
            task.link = Self.link(toChat: session["hostSessionId"] as? String)
        }
        return task
    }

    /// The Claude app's link to one of its chats (by the app's own ID for it,
    /// e.g. "local_…"), as its Dock menu uses to reopen a chat.
    static func link(toChat id: String?) -> URL? {
        guard let id, id.range(of: #"^local_[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "claude://code/continue?session=\(id)")
    }

    private func readTranscript(_ id: String, cwd: String) -> Transcript? {
        if transcripts[id] == nil {
            guard let url = transcriptURL(id, cwd: cwd) else { return nil }
            transcripts[id] = Transcript(tail: JSONLinesTail(url: url))
        }
        transcripts[id]?.update()
        return transcripts[id]
    }

    /// Transcripts live in a folder named after the chat's starting folder,
    /// e.g. /Users/me/app → -Users-me-app. If the chat moved, look around.
    private func transcriptURL(_ id: String, cwd: String) -> URL? {
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let encoded = String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        let expected = projects.appendingPathComponent(encoded).appendingPathComponent("\(id).jsonl")
        if FileManager.default.fileExists(atPath: expected.path) { return expected }
        let folders = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return folders.lazy.map { $0.appendingPathComponent("\(id).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// What a Claude transcript says about its task.
struct Transcript {
    var tail: JSONLinesTail
    var plan = Plan()
    /// The latest thing Claude said it's doing, e.g. "Run the web checks".
    var lastAction: String?
    /// The latest tool call, described, for when Claude is waiting to run it.
    var lastAsk: String?

    mutating func update() {
        guard tail.offset != nil else { return firstRead() }
        read(tail.newLines())
    }

    /// The plan can be far back in a long chat, so a first read that finds
    /// none looks further, up to the whole transcript.
    private mutating func firstRead() {
        let size = (try? FileManager.default.attributesOfItem(atPath: tail.url.path)[.size] as? UInt64) ?? 0
        for window: UInt64 in [8 << 20, 64 << 20, 512 << 20] {
            var attempt = Transcript(tail: JSONLinesTail(url: tail.url, lookBack: window))
            attempt.read(attempt.tail.newLines())
            self = attempt
            if !plan.steps.isEmpty || window >= size { return }
        }
    }

    private mutating func read(_ lines: [Data]) {
        for line in lines {
            if line.range(of: Self.userTurn) != nil && line.range(of: Self.toolResult) == nil { newPrompt(line) }
            // Request logs repeat the whole chat; only Claude's own turns count.
            guard !line.starts(with: Self.requestPrefix), line.range(of: Self.toolUse) != nil,
                  let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  entry["type"] as? String == "assistant", entry["isSidechain"] as? Bool != true,
                  let content = (entry["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
            for block in content where block["type"] as? String == "tool_use" {
                read(tool: block["name"] as? String ?? "", input: block["input"] as? [String: Any] ?? [:])
            }
        }
    }

    private static let requestPrefix = Data(#"{"type":"api-request"#.utf8)
    private static let toolUse = Data(#""tool_use""#.utf8)
    private static let userTurn = Data(#""type":"user""#.utf8)
    private static let toolResult = Data(#""tool_result""#.utf8)

    /// A new message from you starts a new task: a finished plan is cleared
    /// (one still under way stays, as when you add a detail mid-task).
    private mutating func newPrompt(_ line: Data) {
        guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              entry["isSidechain"] as? Bool != true, entry["isMeta"] as? Bool != true,
              (entry["message"] as? [String: Any])?["role"] as? String == "user" else { return }
        if plan.steps.allSatisfy({ $0.state == .done }) { plan = Plan() }
        lastAction = nil
    }

    private mutating func read(tool: String, input: [String: Any]) {
        if plan.apply(tool: tool, input: input) { return }
        let description = (input["description"] as? String)?.oneLine()
        if let description, !description.isEmpty { lastAction = description }
        let question = ((input["questions"] as? [[String: Any]])?.first?["question"] as? String)
        lastAsk = (description ?? (input["command"] as? String) ?? question ?? Self.readable(tool)).oneLine()
    }

    /// "mcp__server__do_thing" → "do thing"; "WebFetch" stays.
    private static func readable(_ tool: String) -> String {
        let last = tool.components(separatedBy: "__").last ?? tool
        return last.replacingOccurrences(of: "_", with: " ")
    }
}

/// A Claude task list, replayed from the calls that keep it: the Claude app's
/// `update_plan` (whole lists, then "advance", "done" and "start"), and
/// Claude Code's `TodoWrite` in a terminal.
struct Plan {
    private(set) var steps: [AgentTask.Step] = []

    /// Applies one tool call; false if it isn't a planning call.
    mutating func apply(tool: String, input: [String: Any]) -> Bool {
        if tool == "TodoWrite", let todos = input["todos"] as? [[String: Any]] {
            steps = Self.steps(todos)
            return true
        }
        if tool.hasSuffix("__wrap_up") {
            steps = steps.map { AgentTask.Step(text: $0.text, state: .done) }
            return true
        }
        guard tool.hasSuffix("__update_plan") else { return false }
        if let items = input["items"] as? [[String: Any]] {
            steps = Self.steps(items)
        }
        for number in input["done"] as? [Int] ?? [] where steps.indices.contains(number - 1) {
            steps[number - 1].state = .done
        }
        if input["advance"] as? Bool == true {
            if let current = steps.firstIndex(where: { $0.state == .current }) { steps[current].state = .done }
            if let next = steps.firstIndex(where: { $0.state == .todo }) { steps[next].state = .current }
        }
        if let start = input["start"] as? Int, steps.indices.contains(start - 1) {
            steps[start - 1].state = .current
        }
        return true
    }

    /// Both tools list steps as `content` with a `status`.
    private static func steps(_ items: [[String: Any]]) -> [AgentTask.Step] {
        items.prefix(20).compactMap { item in
            guard let text = item["content"] as? String else { return nil }
            let state: AgentTask.Step.State = switch item["status"] as? String {
            case "completed": .done
            case "in_progress": .current
            default: .todo
            }
            return AgentTask.Step(text: text.oneLine(), state: state)
        }
    }
}
