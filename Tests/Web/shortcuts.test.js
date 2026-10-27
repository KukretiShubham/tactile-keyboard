import { glyphOf, hotkeyMessages, isCustomHotkey } from '../../Sources/Tactile/Web/hotkeys.js';
import { codeForCharacter } from '../../Sources/Tactile/Web/keys.js';
import { createShortcuts, SHORTCUTS } from '../../Sources/Tactile/Web/shortcuts.js';
import { expect, expectEqual, fakeSettings, silentFeedback, test, wait } from './harness.js';

const byId = (id) => SHORTCUTS.find((s) => s.id === id);
const AZERTY = { KeyQ: ['a', 'A'], KeyW: ['z', 'Z'], KeyA: ['q', 'Q'], KeyZ: ['w', 'W'] };

test('shortcuts press their keys together', () => {
  expectEqual(hotkeyMessages(byId('copy')), [{ t: 'combo', ks: ['MetaLeft', 'KeyC'] }], 'copy');
  expectEqual(hotkeyMessages(byId('redo')), [{ t: 'combo', ks: ['MetaLeft', 'ShiftLeft', 'KeyZ'] }], 'redo');
  expectEqual(hotkeyMessages(byId('spotlight')), [{ t: 'sys', k: 'spotlight' }], 'spotlight');
});

test('hotkeys can press twice, or type text and press Return', () => {
  expectEqual(hotkeyMessages({ keys: ['Escape'], times: 2 }), [{ t: 'combo', ks: ['Escape'] }, { t: 'combo', ks: ['Escape'] }], 'esc esc');
  expectEqual(hotkeyMessages({ text: '/clear', enter: true }), [{ t: 'txt', s: '/clear' }, { t: 'combo', ks: ['Enter'] }], '/clear');
  expectEqual(hotkeyMessages({ text: 'hi' }), [{ t: 'txt', s: 'hi' }], 'text without Return');
});

test('hotkeys are written the Mac way', () => {
  expectEqual(glyphOf({ keys: ['MetaLeft', 'ShiftLeft', 'p'] }), '⇧⌘P', 'command palette');
  expectEqual(glyphOf({ keys: ['ControlLeft', 'Backquote'] }), '⌃`', 'terminal');
  expectEqual(glyphOf({ keys: ['Escape'], times: 2 }), 'esc esc', 'double escape');
  expectEqual(glyphOf({ keys: ['ShiftLeft'], times: 2 }), '⇧⇧', 'double shift');
  expectEqual(glyphOf({ keys: ['AltLeft', 'Enter'] }), '⌥↩', 'context actions');
  expectEqual(glyphOf({ text: '/compact' }), '/compact', 'text');
});

test('letter shortcuts follow the Mac layout', () => {
  expectEqual(codeForCharacter(AZERTY, 'z'), 'KeyW', 'z on AZERTY');
  expectEqual(hotkeyMessages(byId('undo'), AZERTY), [{ t: 'combo', ks: ['MetaLeft', 'KeyW'] }], 'undo on AZERTY');
});

test('every hotkey sends at most five keys at once', async () => {
  const { PACKS } = await import('../../Sources/Tactile/Web/packs.js');
  for (const hotkey of [...SHORTCUTS, ...PACKS.flatMap((pack) => pack.hotkeys)]) {
    for (const message of hotkeyMessages(hotkey)) {
      if (message.ks) expect(message.ks.length <= 5, `${hotkey.name} sends ${message.ks.length} keys`);
    }
  }
});

test('only well-formed hotkeys of your own are used', () => {
  const ok = { id: 'mine-1', name: 'Rerun', pack: 'all', keys: ['MetaLeft', 'ShiftLeft', 'KeyR'] };
  expect(isCustomHotkey(ok), 'keys hotkey');
  expect(isCustomHotkey({ id: 'mine-2', name: 'Review', pack: 'claude', text: '/review', enter: true }), 'text hotkey');
  expect(!isCustomHotkey({ ...ok, name: '' }), 'no name');
  expect(!isCustomHotkey({ ...ok, keys: [] }), 'no keys');
  expect(!isCustomHotkey({ ...ok, keys: ['a', 'b', 'c', 'd', 'e', 'f'] }), 'too many keys');
  expect(!isCustomHotkey({ ...ok, keys: ['<img>'] }), 'odd key name');
  expect(!isCustomHotkey('hello'), 'not an object');
});

function setup(overrides = {}) {
  const parts = Object.fromEntries(['bar', 'left', 'right', 'tabs', 'title', 'add'].map((name) => [name, document.createElement('div')]));
  const sent = [];
  const settings = fakeSettings({
    shortcutBar: true, shortcuts: ['undo', 'copy', 'spotlight'], pack: 'claude', terminalPack: 'claude',
    lastTerminal: 'com.apple.Terminal', agentHomes: {}, hiddenPacks: [],
    followMacApp: true, customHotkeys: [], ...overrides,
  });
  const shortcuts = createShortcuts(parts, {
    send: (m) => sent.push(m), feedback: silentFeedback, settings, beforeSend() {}, onAddHotkey() {},
  });
  const names = (el) => [...el.children].map((child) => child.getAttribute('aria-label'));
  return { ...parts, sent, settings, shortcuts, names };
}

test('beside the trackpad: general shortcuts left, the chosen app right', () => {
  const { bar, left, right, tabs, names, shortcuts } = setup();
  expectEqual(names(bar), ['Undo', 'Copy', 'Spotlight'], 'top bar');
  shortcuts.placeBesideTrackpad(true);
  expectEqual(names(bar), [], 'top bar beside the trackpad');
  expectEqual(names(left), ['Undo', 'Copy', 'Spotlight'], 'left side');
  expectEqual(names(right), ['Start', 'Stop', 'Rewind', 'Switch Mode', 'Search History', 'Background', 'Clear', 'Compact'], 'right side');
  expectEqual(names(tabs), ['Claude Code', 'Codex'], 'tabs before the Mac reports its apps');
  shortcuts.setIcons({ 'com.microsoft.VSCode': 'data:image/png;base64,AA==' });
  expectEqual(names(tabs), ['Claude Code', 'Codex', 'VS Code'], 'tabs once VS Code is found');
});

test('the app in front on the Mac picks its hotkeys', () => {
  const { right, tabs, title, settings, shortcuts } = setup();
  shortcuts.placeBesideTrackpad(true);
  shortcuts.setIcons({ 'com.microsoft.VSCode': 'data:image/png;base64,AA==' });
  shortcuts.setFrontApp({ id: 'com.microsoft.VSCode', name: 'Code' });
  expectEqual(right.firstChild.getAttribute('aria-label'), 'Quick Open', 'VS Code hotkeys');
  expect(tabs.querySelector('[data-pack="vscode"] .pack-following'), 'following dot');
  expect(title.textContent.includes('following your Mac'), `title: ${title.textContent}`);

  settings.set('terminalPack', 'codex');
  shortcuts.setFrontApp({ id: 'com.googlecode.iterm2', name: 'iTerm2' });
  expectEqual(settings.get('pack'), 'codex', 'back to the last terminal agent');
  expect(title.textContent.includes('in iTerm2'), `title: ${title.textContent}`);

  settings.set('followMacApp', false);
  shortcuts.setFrontApp({ id: 'com.microsoft.VSCode', name: 'Code' });
  expectEqual(settings.get('pack'), 'codex', 'not following when switched off');
});

test('your hotkeys appear with their app, or with the general ones', async () => {
  const { left, right, sent, names, shortcuts, settings } = setup();
  shortcuts.placeBesideTrackpad(true);
  settings.set('customHotkeys', [
    { id: 'mine-1', name: 'Review', pack: 'claude', text: '/review', enter: true },
    { id: 'mine-2', name: 'Rerun', pack: 'all', keys: ['MetaLeft', 'ShiftLeft', 'KeyR'] },
    { id: 'broken', name: '', pack: 'all', keys: [] },
  ]);
  expectEqual(names(left).at(-1), 'Rerun', 'general side');
  expectEqual(names(right).at(-1), 'Review', 'Claude Code side');
  expectEqual(names(left).length, 4, 'broken hotkey left out');
  right.lastChild.click();
  await wait(120);
  expectEqual(sent, [{ t: 'txt', s: '/review' }, { t: 'combo', ks: ['Enter'] }], 'sent');
});

test('tapping a tab brings its app to the front on the Mac', () => {
  const { tabs, sent, settings, shortcuts } = setup();
  shortcuts.placeBesideTrackpad(true);
  shortcuts.setIcons({ 'com.microsoft.VSCode': 'data:image/png;base64,AA==' });
  tabs.querySelector('[data-pack="vscode"]').click();
  expectEqual(sent.at(-1), { t: 'focus', k: 'com.microsoft.VSCode' }, 'VS Code tab');
  expectEqual(settings.get('pack'), 'vscode', 'VS Code hotkeys chosen');

  // Terminal agents bring back the terminal used last.
  shortcuts.setFrontApp({ id: 'com.mitchellh.ghostty', name: 'Ghostty' });
  shortcuts.setFrontApp({ id: 'com.microsoft.VSCode', name: 'Code' });
  tabs.querySelector('[data-pack="claude"]').click();
  expectEqual(sent.at(-1), { t: 'focus', k: 'com.mitchellh.ghostty', s: 'claude' }, 'Claude Code tab: the window running claude');
});

test('agents come back where you used them last: desktop app or terminal', () => {
  const { tabs, title, sent, settings, shortcuts } = setup();
  shortcuts.placeBesideTrackpad(true);

  // Using the Claude desktop app picks Claude Code and remembers it.
  shortcuts.setFrontApp({ id: 'com.anthropic.claudefordesktop', name: 'Claude' });
  expectEqual(settings.get('pack'), 'claude', 'Claude Code chosen');
  expect(title.textContent.includes('in Claude'), `title: ${title.textContent}`);
  shortcuts.setFrontApp({ id: 'com.apple.Safari', name: 'Safari' });
  tabs.querySelector('[data-pack="claude"]').click();
  expectEqual(sent.at(-1), { t: 'focus', k: 'com.anthropic.claudefordesktop' }, 'Claude Code tab after the desktop app');

  // The Codex app picks Codex; later using Codex in a terminal moves its home.
  shortcuts.setFrontApp({ id: 'com.openai.codex', name: 'Codex' });
  expectEqual(settings.get('pack'), 'codex', 'Codex chosen');
  shortcuts.setFrontApp({ id: 'com.googlecode.iterm2', name: 'iTerm2' });
  expectEqual(settings.get('pack'), 'codex', 'Codex stays in the terminal');
  shortcuts.setFrontApp({ id: 'com.apple.Safari', name: 'Safari' });
  tabs.querySelector('[data-pack="codex"]').click();
  expectEqual(sent.at(-1), { t: 'focus', k: 'com.googlecode.iterm2', s: 'codex' }, 'Codex tab after the terminal');
});

test('a second tap closes what the first opened', () => {
  const { right, sent, settings, shortcuts } = setup();
  shortcuts.placeBesideTrackpad(true);
  shortcuts.setIcons({ 'dev.zed.Zed': 'data:image/png;base64,AA==' });
  shortcuts.setFrontApp({ id: 'dev.zed.Zed', name: 'Zed' });
  const key = (name) => right.querySelector(`[aria-label="${name}"]`);

  // The Agent panel opens with ⌘? and closes by hiding its dock (⌘B).
  key('Agent Panel').click();
  expect(key('Agent Panel').classList.contains('on'), 'lit while open');
  key('Agent Panel').click();
  expectEqual(sent.slice(-2), [
    { t: 'combo', ks: ['MetaLeft', 'ShiftLeft', 'Slash'] },
    { t: 'combo', ks: ['MetaLeft', 'KeyB'] },
  ], 'open, then close');
  expect(!key('Agent Panel').classList.contains('on'), 'unlit once closed');

  // A true toggle sends the same keys again.
  key('Terminal').click();
  key('Terminal').click();
  expectEqual(sent.slice(-2), [{ t: 'combo', ks: ['ControlLeft', 'Backquote'] }, { t: 'combo', ks: ['ControlLeft', 'Backquote'] }], 'terminal');

  // A palette closes with Esc, unless you've typed into it since.
  key('File Finder').click();
  key('File Finder').click();
  expectEqual(sent.at(-1), { t: 'combo', ks: ['Escape'] }, 'palette closed with Esc');
  key('File Finder').click();
  shortcuts.noteInput();
  expect(!key('File Finder').classList.contains('on'), 'typing closes the palette');
  key('File Finder').click();
  expectEqual(sent.at(-1), { t: 'combo', ks: ['MetaLeft', 'KeyP'] }, 'opens again after typing');
  expectEqual(settings.get('pack'), 'zed', 'still Zed');
});

test('an agent never used yet opens in its desktop app if installed', () => {
  const { tabs, sent, shortcuts } = setup();
  shortcuts.placeBesideTrackpad(true);
  shortcuts.setIcons({ 'com.openai.codex': 'data:image/png;base64,AA==' });
  tabs.querySelector('[data-pack="codex"]').click();
  expectEqual(sent.at(-1), { t: 'focus', k: 'com.openai.codex' }, 'Codex app');
  tabs.querySelector('[data-pack="claude"]').click();
  expectEqual(sent.at(-1), { t: 'focus', k: 'com.apple.Terminal', s: 'claude' }, 'no Claude app: the terminal');
});

test('Start runs the agent in a new terminal window', async () => {
  const { right, sent, settings, shortcuts } = setup();
  shortcuts.placeBesideTrackpad(true);
  settings.set('pack', 'codex');
  shortcuts.setFrontApp({ id: 'com.googlecode.iterm2', name: 'iTerm2' });
  sent.length = 0;
  right.querySelector('[aria-label="Start"]').click();
  await wait(1400);
  expectEqual(sent, [
    { t: 'focus', k: 'com.googlecode.iterm2' },
    { t: 'combo', ks: ['MetaLeft', 'KeyN'] },
    { t: 'txt', s: 'codex' },
    { t: 'combo', ks: ['Enter'] },
  ], 'sent');
  expectEqual(right.querySelector('[aria-label="Start"] .shortcut-glyph').textContent, '$ codex', 'key label');
});

test('apps you hide get no tab, even in front on the Mac', () => {
  const { tabs, names, settings, shortcuts } = setup();
  shortcuts.placeBesideTrackpad(true);
  shortcuts.setIcons({ 'com.microsoft.VSCode': 'data:image/png;base64,AA==', 'dev.zed.Zed': 'data:image/png;base64,AA==' });
  settings.set('hiddenPacks', ['vscode']);
  expectEqual(names(tabs), ['Claude Code', 'Codex', 'Zed'], 'tabs');
  shortcuts.setFrontApp({ id: 'com.microsoft.VSCode', name: 'Code' });
  expectEqual(settings.get('pack'), 'claude', 'VS Code in front, but hidden');
  expectEqual(shortcuts.offered().map(({ id, hidden }) => `${id}${hidden ? ' (hidden)' : ''}`),
    ['claude', 'codex', 'vscode (hidden)', 'zed'], 'Settings list');
});
