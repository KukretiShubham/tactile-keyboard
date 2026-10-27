// Hotkeys for the apps people code in, shown beside the trackpad. Each pack
// lists the Mac apps it belongs to (by bundle ID): it's shown when one is
// installed, picked when one comes to the front, and its icon comes from
// that app on the Mac. Terminal agents (`terminal: true`) also run inside any
// terminal, so their packs are always offered; in a terminal, the agent you
// picked last stays, and its tab looks for the window titled with `command`
// (terminals show the running program there). Its `start` hotkey runs
// `command` in a new terminal window.
//
// Without the app's icon (it isn't installed), a tab shows the pack's `badge`.
//
// Hotkey format (see hotkeys.js): `keys` pressed together, `times` presses
// (e.g. Esc Esc), or `text` typed (and Return pressed with `enter`). Single
// characters follow the Mac's keyboard layout. A hotkey that opens something
// can be closed with a second tap: `toggle` sends the same keys again,
// `reverse` sends other keys, and `transient` ones (palettes) count as closed
// once you type or click.
// Sources: each app's documented default shortcuts on macOS.

export const TERMINALS = [
  'com.apple.Terminal', 'com.googlecode.iterm2', 'com.mitchellh.ghostty', 'dev.warp.Warp-Stable',
  'net.kovidgoyal.kitty', 'com.github.wez.wezterm', 'org.alacritty',
];

export const PACKS = [
  {
    id: 'claude', name: 'Claude Code', badge: 'CC', terminal: true, command: 'claude', apps: ['com.anthropic.claudefordesktop'],
    hotkeys: [
      { name: 'Start', start: true },
      { name: 'Stop', keys: ['Escape'] },
      { name: 'Rewind', keys: ['Escape'], times: 2 },
      { name: 'Switch Mode', keys: ['ShiftLeft', 'Tab'] },
      { name: 'Search History', keys: ['ControlLeft', 'r'] },
      { name: 'Background', keys: ['ControlLeft', 'b'] },
      { name: 'Clear', text: '/clear', enter: true },
      { name: 'Compact', text: '/compact', enter: true },
    ],
  },
  {
    id: 'codex', name: 'Codex', badge: 'Cx', terminal: true, command: 'codex', apps: ['com.openai.codex'], icons: ['com.openai.codex', 'com.openai.chat'],
    hotkeys: [
      { name: 'Start', start: true },
      { name: 'Edit Previous', keys: ['Escape'], times: 2 },
      { name: 'Search History', keys: ['ControlLeft', 'r'] },
      { name: 'Copy Output', keys: ['ControlLeft', 'o'] },
      { name: 'Model', text: '/model', enter: true },
      { name: 'New Chat', text: '/new', enter: true },
      { name: 'Diff', text: '/diff', enter: true },
      { name: 'Review', text: '/review', enter: true },
    ],
  },
  {
    id: 'vscode', name: 'VS Code', badge: 'VS', apps: ['com.microsoft.VSCode', 'com.microsoft.VSCodeInsiders', 'com.vscodium'],
    hotkeys: [
      { name: 'Quick Open', keys: ['MetaLeft', 'p'], reverse: ['Escape'], transient: true },
      { name: 'Commands', keys: ['MetaLeft', 'ShiftLeft', 'p'], reverse: ['Escape'], transient: true },
      { name: 'Terminal', keys: ['ControlLeft', 'Backquote'], toggle: true },
      { name: 'Comment', keys: ['MetaLeft', 'Slash'] },
      { name: 'Sidebar', keys: ['MetaLeft', 'b'], toggle: true },
      { name: 'Search', keys: ['MetaLeft', 'ShiftLeft', 'f'] },
    ],
  },
  {
    id: 'zed', name: 'Zed', badge: 'Z', apps: ['dev.zed.Zed', 'dev.zed.Zed-Preview'],
    hotkeys: [
      { name: 'File Finder', keys: ['MetaLeft', 'p'], reverse: ['Escape'], transient: true },
      { name: 'Commands', keys: ['MetaLeft', 'ShiftLeft', 'p'], reverse: ['Escape'], transient: true },
      { name: 'Terminal', keys: ['ControlLeft', 'Backquote'], toggle: true },
      // ⌘? only focuses the panel; it lives in the left dock by default, which ⌘B hides.
      { name: 'Agent Panel', keys: ['MetaLeft', 'ShiftLeft', 'Slash'], glyph: '⌘?', reverse: ['MetaLeft', 'b'] },
      { name: 'Comment', keys: ['MetaLeft', 'Slash'] },
      { name: 'Search', keys: ['MetaLeft', 'ShiftLeft', 'f'] },
    ],
  },
  {
    id: 'xcode', name: 'Xcode', badge: 'X', apps: ['com.apple.dt.Xcode'],
    hotkeys: [
      { name: 'Build', keys: ['MetaLeft', 'b'] },
      { name: 'Run', keys: ['MetaLeft', 'r'] },
      { name: 'Stop', keys: ['MetaLeft', 'Period'] },
      { name: 'Test', keys: ['MetaLeft', 'u'] },
      { name: 'Open Quickly', keys: ['MetaLeft', 'ShiftLeft', 'o'] },
      { name: 'Clean', keys: ['MetaLeft', 'ShiftLeft', 'k'] },
    ],
  },
  {
    id: 'jetbrains', name: 'JetBrains', badge: 'JB',
    apps: ['com.jetbrains.intellij', 'com.jetbrains.intellij.ce', 'com.jetbrains.pycharm', 'com.jetbrains.pycharm.ce',
      'com.jetbrains.WebStorm', 'com.jetbrains.goland', 'com.jetbrains.CLion', 'com.jetbrains.rider',
      'com.jetbrains.PhpStorm', 'com.jetbrains.rubymine', 'com.google.android.studio'],
    hotkeys: [
      { name: 'Search Everywhere', keys: ['ShiftLeft'], times: 2, reverse: ['Escape'], transient: true },
      { name: 'Run', keys: ['ControlLeft', 'r'] },
      { name: 'Recent Files', keys: ['MetaLeft', 'e'] },
      { name: 'Context Actions', keys: ['AltLeft', 'Enter'] },
      { name: 'Reformat', keys: ['MetaLeft', 'AltLeft', 'l'] },
      { name: 'Rename', keys: ['ShiftLeft', 'F6'] },
    ],
  },
  {
    id: 'browser', name: 'Browser', badge: 'W',
    apps: ['com.apple.Safari', 'com.google.Chrome', 'company.thebrowser.Browser', 'com.microsoft.edgemac',
      'org.mozilla.firefox', 'com.brave.Browser'],
    hotkeys: [
      { name: 'New Tab', keys: ['MetaLeft', 't'] },
      { name: 'Reopen Tab', keys: ['MetaLeft', 'ShiftLeft', 't'] },
      { name: 'Address Bar', keys: ['MetaLeft', 'l'] },
      { name: 'Reload', keys: ['MetaLeft', 'r'] },
      { name: 'Close Tab', keys: ['MetaLeft', 'w'] },
      { name: 'Developer Tools', keys: ['MetaLeft', 'AltLeft', 'i'], toggle: true },
    ],
  },
];

/** Bundle IDs whose icons the packs use, in order of preference per pack. */
export const iconApps = (pack) => pack.icons ?? pack.apps;

/** The pack for the app in front on the Mac, if any. */
export function packForApp(appID) {
  if (TERMINALS.includes(appID)) return null;
  return PACKS.find((pack) => pack.apps?.includes(appID)) ?? null;
}
