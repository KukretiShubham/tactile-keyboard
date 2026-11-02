import Foundation

/// What a Touch Bar shows: which agents' tasks, and whether plan usage.
public struct AgentInterest: Equatable {
    public var apps: Set<String>
    public var usage: Bool

    public init(apps: Set<String> = [], usage: Bool = false) {
        self.apps = apps.intersection(AgentMonitor.names)
        self.usage = usage
    }

    /// Everything either shows, for watching on behalf of several devices.
    public func union(_ other: AgentInterest) -> AgentInterest {
        AgentInterest(apps: apps.union(other.apps), usage: usage || other.usage)
    }
}

/// Watches what Claude and Codex are doing on this Mac, while a device's Touch
/// Bar asks for it. Everything is read from the agents' own files on this Mac
/// (and Claude Code itself, for plan usage); nothing goes to the internet.
public final class AgentMonitor {
    /// The agents, by the names the iPad uses.
    public static let names: Set = ["claude", "codex"]

    /// The agents whose files are on this Mac.
    public static func installed(home: URL = AgentMonitor.home) -> [String] {
        [("claude", ClaudeActivity.isInstalled(home: home)), ("codex", CodexActivity.isInstalled(home: home))]
            .filter(\.1).map(\.0)
    }

    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static let tick: TimeInterval = 2
    private static let usageInterval: TimeInterval = 5 * 60

    /// The latest message for devices, whenever it changes. Called on the
    /// monitor's own queue.
    public var onUpdate: (([String: Any]) -> Void)?

    private let queue = DispatchQueue(label: "tactile.agents", qos: .utility)
    private let claude: ClaudeActivity
    private let sources: [String: AgentSource]
    private var timer: DispatchSourceTimer?
    private var interest = AgentInterest()
    private var lastSent: Data?
    /// The tasks devices were last told about, by ID.
    private var shownTasks: [String: AgentTask] = [:]
    private var usageReadAt = Date.distantPast
    private var readingUsage = false

    public init(home: URL = AgentMonitor.home) {
        claude = ClaudeActivity(root: ClaudeActivity.root(home: home))
        sources = ["claude": claude, "codex": CodexActivity(root: CodexActivity.root(home: home))]
    }

    /// What devices' Touch Bars show, all together. No agents stops watching.
    public func watch(_ interest: AgentInterest) {
        queue.async {
            self.interest = interest
            self.lastSent = nil // a device that just asked gets the latest
            if interest.apps.isEmpty {
                self.timer?.cancel()
                self.timer = nil
            } else if self.timer == nil {
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now(), repeating: Self.tick, leeway: .milliseconds(500))
                timer.setEventHandler { [weak self] in self?.refresh() }
                timer.resume()
                self.timer = timer
            } else {
                self.refresh()
            }
        }
    }

    /// Reads the agents' files once, right away (for checks). Claude's plan
    /// usage isn't asked for.
    public func readNow(_ interest: AgentInterest, at now: Date = Date()) -> [String: Any] {
        queue.sync { activity(interest, now: now) }
    }

    /// Opens a task a device showed: the chat itself where its app has a link
    /// for it, otherwise the app. Only tasks read from this Mac's files open,
    /// so a device can't have the Mac open anything else.
    public func open(_ taskID: String, link: @escaping (URL) -> Void, app: @escaping (String) -> Void) {
        queue.async {
            guard let task = self.shownTasks[taskID] else { return }
            if let url = task.link { link(url) } else if let id = task.app { app(id) }
        }
    }

    /// Plan limits in a Claude Code `get_usage` reply, as sent to devices.
    public static func claudeLimits(_ reply: [String: Any]) -> [[String: Any]]? {
        ClaudeUsage.limits(reply)?.map(\.json)
    }

    private func refresh() {
        let now = Date()
        if interest.usage && interest.apps.contains("claude") { readClaudeUsageIfDue(now) }
        let payload = activity(interest, now: now)
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: .sortedKeys), data != lastSent else { return }
        lastSent = data
        onUpdate?(["t": "agents", "now": now.milliseconds, "apps": payload])
    }

    /// Each agent's tasks, and plan usage as last read, by agent name.
    private func activity(_ interest: AgentInterest, now: Date) -> [String: Any] {
        shownTasks = [:]
        return sources.filter { interest.apps.contains($0.key) }.mapValues { source in
            let tasks = source.tasks(now: now)
            for task in tasks { shownTasks[task.id] = task }
            var entry: [String: Any] = ["tasks": tasks.map(\.json)]
            if interest.usage, let limits = source.usage(now: now) { entry["usage"] = limits.map(\.json) }
            return entry
        }
    }

    /// Asks Claude Code for plan usage every few minutes, in the background.
    private func readClaudeUsageIfDue(_ now: Date) {
        guard !readingUsage, now.timeIntervalSince(usageReadAt) > Self.usageInterval else { return }
        readingUsage = true
        usageReadAt = now
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let limits = ClaudeUsage.read()
            self?.queue.async {
                guard let self else { return }
                self.readingUsage = false
                // A failed read keeps the last good one until the next try.
                if let limits { self.claude.planUsage = limits }
                self.lastSent = nil
                self.refresh()
            }
        }
    }
}
