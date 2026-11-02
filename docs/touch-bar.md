# How the Touch Bar works

The Touch Bar shows what Claude and Codex are doing on your Mac: their tasks, each task's steps, and how much of your plan you've used. Neither tool has a public API for this, so Tactile reads the files they already keep on your Mac. This page says which files, what can break, and how to add another agent.

## The pieces

| Where | What it does |
|---|---|
| `Sources/TactileCore/Agents/AgentMonitor.swift` | Reads the agents every 2 seconds while a device's Touch Bar shows them, and sends devices the result when it changes. |
| `Sources/TactileCore/Agents/ClaudeActivity.swift` | Claude's tasks, from Claude Code's files. |
| `Sources/TactileCore/Agents/ClaudeUsage.swift` | Claude's plan usage, asked of Claude Code itself. |
| `Sources/TactileCore/Agents/CodexActivity.swift` | Codex's tasks and plan usage, from Codex's files. |
| `Sources/TactileCore/Agents/AgentTask.swift`, `AgentFiles.swift` | The task model, and helpers for reading files that grow. |
| `Sources/Tactile/Web/touchbar.js` | The strip, task chips and task cards on the iPad. |

Nothing is read until a device shows the Touch Bar, and everything stays between the Mac and its paired devices.

## Messages

| From | Message | Meaning |
|---|---|---|
| Mac | `{ t: 'agentApps', apps: ['claude', 'codex'] }` | Which agents are on this Mac (sent on connecting), so Settings offers only those. |
| iPad | `{ t: 'agents', ks: ['claude'], r: true }` | Which agents the Touch Bar shows (`ks`, empty to stop) and whether it shows plan usage (`r`). |
| Mac | `{ t: 'agents', now, apps: { claude: { tasks, usage } } }` | The tasks and usage, sent whenever they change. `now` is the Mac's clock, so ages read right on the iPad. |
| iPad | `{ t: 'openTask', k: 'claude-…' }` | Open a task the Mac sent. The Mac opens only links it made itself (see below). |

## Where the data comes from

**Claude** (`~/.claude`, or `CLAUDE_CONFIG_DIR`)

- `sessions/<pid>.json`: one per open chat, in the Claude app or a terminal. Tactile uses `sessionId`, `pid` (a chat whose process has gone is skipped), `kind`, `name` (the title), `cwd`, `status` (`busy`, `waiting` or `idle`), `statusUpdatedAt`, `entrypoint` and `hostSessionId`.
- `projects/<folder>/<sessionId>.jsonl`: the chat's transcript. Tactile replays the calls that keep its task list (the Claude app's `update_plan` and `wrap_up`, Claude Code's `TodoWrite`) and takes the latest tool call's description as what it's doing now. Transcripts grow to hundreds of megabytes, so only the end is read, and then only what's added.
- **Plan usage:** Claude Code is started without a prompt (`claude -p --input-format stream-json …`) and sent the `initialize` and `get_usage` control requests, as the Claude app does. No MCP servers or hooks start, nothing is sent as a chat, and it never counts against the plan. This runs every 5 minutes, and only while usage is shown.
- **Opening a chat:** `claude://code/continue?session=<hostSessionId>`, the link the Claude app's Dock menu uses.

**Codex** (`~/.codex`, or `CODEX_HOME`)

- `state_<n>.sqlite`, table `threads`: titles, folders and where each thread's log is. Codex's own helper threads (whose `source` is JSON) are left out.
- Each thread's rollout (`.jsonl`): `task_started`, `task_complete` and `turn_aborted` say whether it's working, and approval requests say it needs you. With a ChatGPT sign-in, `token_count` events carry plan usage.

## When the agents change their files

These are each tool's own files, so an update can change them. Tactile reads them defensively: anything missing or unexpected means that detail isn't shown (no steps, no usage, or no task), never an error. If an agent stops showing up, its file in `Sources/TactileCore/Agents` is the place to look, and `Tests/TactileChecks/AgentChecks.swift` has made-up files in the shape each reader expects.

## Trying it

`swift run tactile-checks` covers the readers with made-up files. To see the Touch Bar against real activity without touching your paired devices, run a dry run with a throwaway home, and link your agents' folders into it (Tactile only reads them):

```sh
home="$(mktemp -d)"
ln -s ~/.claude "$home/.claude"; ln -s ~/.codex "$home/.codex"
CFFIXED_USER_HOME="$home" swift run Tactile --dry-run
```

Then open `http://127.0.0.1:8425` and pair with the code it prints.

## Adding another agent

1. Write a class that conforms to `AgentSource` (`tasks(now:)` and `usage(now:)`), next to the others in `Sources/TactileCore/Agents`.
2. Add it to `AgentMonitor`: its name in `names`, its check in `installed(home:)`, and the source itself in `sources`.
3. Add it to `AGENTS` in `touchbar.js`, give it a setting in `settings.js`, and a switch in the Touch Bar group in `index.html`.
4. Add checks with made-up files to `AgentChecks.swift`, and a line to the README's Touch Bar section.
