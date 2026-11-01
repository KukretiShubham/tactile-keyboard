# App hotkeys

In landscape with the trackpad showing, the right side of the trackpad has a row of app tabs and that app's hotkeys:

| App | Hotkeys |
|---|---|
| Claude Code | Start (`claude`), Stop (esc), Rewind (esc esc), Switch Mode (⇧⇥), Search History (⌃R), Background (⌃B), `/clear`, `/compact` |
| Codex | Start (`codex`), Edit Previous (esc esc), Search History (⌃R), Copy Output (⌃O), `/model`, `/new`, `/diff`, `/review` |
| Granola | Voice Typing (hold), New Note (⇧⌘N), Quick Chat (⌥Space), Cancel Dictation (esc) |
| VS Code | Quick Open (⌘P), Commands (⇧⌘P), Terminal (⌃\`), Comment (⌘/), Sidebar (⌘B), Search (⇧⌘F) |
| Zed | File Finder (⌘P), Commands (⇧⌘P), Terminal (⌃\`), Agent Panel (⌘?), Comment (⌘/), Search (⇧⌘F) |
| Xcode | Build (⌘B), Run (⌘R), Stop (⌘.), Test (⌘U), Open Quickly (⇧⌘O), Clean (⇧⌘K) |
| JetBrains IDEs | Search Everywhere (⇧⇧), Run (⌃R), Recent Files (⌘E), Context Actions (⌥↩), Reformat (⌥⌘L), Rename (⇧F6) |
| Browsers | New Tab, Reopen Tab, Address Bar, Reload, Close Tab, Developer Tools |

- A tab appears when its app is installed on your Mac, with the app's own icon (Tactile doesn't ship any app's logo). Claude Code and Codex can run in a terminal, so their tabs are always there.
- The hotkeys follow the app in front on your Mac; a green dot shows they're following. The Claude and Codex desktop apps pick their packs too. In a terminal, the agent you picked last stays.
- Tapping a tab brings that app to the front on your Mac (opening it if needed), so its hotkeys land in the right place. Claude Code and Codex come back wherever you used them last: their desktop app, or the terminal window running them (found by its title, which shows the running program).
- **Start** opens a new window in your terminal and runs `claude` or `codex` there, so it never types into an agent that's already running.

## Granola Voice Typing

The **Voice Typing** key holds Granola's dictation key down on your Mac for as long as you touch it, so Granola's [voice typing](https://docs.granola.ai/help-center/voice-typing/intro) works from the iPad, in any app:

- **Hold** to talk; let go and Granola pastes your words where you're typing.
- **Double-tap** for hands-free; tap again to stop. Esc (Cancel Dictation) throws the dictation away.
- The key turns into Granola's listening pill while it's on. Tactile can't see inside Granola, so it follows your taps the way Granola does.
- **Your key:** Granola listens for fn unless you changed it in Granola's Settings → Voice typing. If you did, set the same key in Tactile under Settings → Voice Typing Key.
- Dictation works in any app, so with Granola installed the key also sits beside the general shortcuts (switch that off under **Show with Shortcuts**).

New Note (⇧⌘N) and Cancel are from Granola's menu and docs; Quick Chat (⌥Space) is a shortcut Granola's app registers, and may need Quick Chat switched on in Granola.
- Text hotkeys like `/clear` type the command and press Return.
- Keys that open something close it with a second tap, and light up meanwhile: panels like VS Code's or Zed's terminal and Zed's Agent panel, browser developer tools, and palettes like Quick Open (which close with Esc, or by themselves once you type). Tactile can't see inside the app, so if you close a panel another way, the next tap opens it again.
- Tap **+** to make your own: name it, then record keys on Tactile's keyboard (nothing reaches the Mac while recording) or type text, and choose which app it belongs to, or All Apps.

## Adding an app

Packs live in [`Sources/Tactile/Web/packs.js`](../Sources/Tactile/Web/packs.js). Each lists the Mac apps it belongs to by bundle ID (find one with `osascript -e 'id of app "AppName"'`) and its hotkeys. Use the app's documented default shortcuts, and link the source in your pull request. See [CONTRIBUTING.md](../CONTRIBUTING.md).
