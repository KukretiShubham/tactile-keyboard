import Foundation

/// A task Claude or Codex is working on, has finished, or needs you for, as the
/// iPad's Touch Bar shows it.
struct AgentTask: Equatable {
    enum State: String { case working, waiting, done }

    /// One step of the agent's plan.
    struct Step: Equatable {
        enum State: String { case done, current, todo }
        var text: String
        var state: State
    }

    /// Finished tasks stay on the Touch Bar this long.
    static let keepDone: TimeInterval = 3 * 60 * 60

    var id: String
    var title: String
    /// The project folder's name.
    var project: String
    var state: State
    /// When the task entered this state.
    var since: Date
    /// The task's plan, if the agent made one.
    var steps: [Step] = []
    /// What the agent is doing right now, in its own words.
    var now: String?
    /// What the agent is waiting for you to allow or answer.
    var ask: String?
    /// The bundle ID of the app the task lives in, if it's an app.
    var app: String?
    /// Opens this very task in its app. Stays on the Mac: devices ask for a
    /// task by ID (see `AgentMonitor.open`).
    var link: URL?

    var json: [String: Any] {
        var json: [String: Any] = ["id": id, "title": title, "project": project, "state": state.rawValue,
                                   "since": since.milliseconds]
        if !steps.isEmpty { json["steps"] = steps.map { ["text": $0.text, "state": $0.state.rawValue] } }
        if let now { json["now"] = now }
        if let ask { json["ask"] = ask }
        if let app { json["app"] = app }
        return json
    }

    /// Needs you first, then working, then done; newest first within each.
    static func order(_ a: AgentTask, _ b: AgentTask) -> Bool {
        let rank: [State: Int] = [.waiting: 0, .working: 1, .done: 2]
        if a.state != b.state { return rank[a.state]! < rank[b.state]! }
        return a.since > b.since
    }
}

/// How much of a plan's limit has been used, e.g. 42% of the 5-hour session.
struct PlanLimit: Equatable {
    var label: String
    var percent: Int
    var resets: Date?

    var json: [String: Any] {
        var json: [String: Any] = ["label": label, "percent": percent]
        if let resets { json["resets"] = resets.milliseconds }
        return json
    }
}

/// Where the Touch Bar learns about one agent.
protocol AgentSource: AnyObject {
    /// Its recent tasks, in `AgentTask.order`.
    func tasks(now: Date) -> [AgentTask]
    /// Its plan usage, if known.
    func usage(now: Date) -> [PlanLimit]?
}
