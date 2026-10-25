import { codeForCharacter } from '../../Sources/Tactile/Web/keys.js';
import { createShortcuts, SHORTCUTS, shortcutMessage } from '../../Sources/Tactile/Web/shortcuts.js';
import { expectEqual, fakeSettings, silentFeedback, test } from './harness.js';

const byId = (id) => SHORTCUTS.find((s) => s.id === id);
const AZERTY = { KeyQ: ['a', 'A'], KeyW: ['z', 'Z'], KeyA: ['q', 'Q'], KeyZ: ['w', 'W'] };

test('shortcuts press their keys together', () => {
  expectEqual(shortcutMessage(byId('copy')), { t: 'combo', ks: ['MetaLeft', 'KeyC'] }, 'copy');
  expectEqual(shortcutMessage(byId('redo')), { t: 'combo', ks: ['MetaLeft', 'ShiftLeft', 'KeyZ'] }, 'redo');
  expectEqual(shortcutMessage(byId('spotlight')), { t: 'sys', k: 'spotlight' }, 'spotlight');
});

test('letter shortcuts follow the Mac layout', () => {
  expectEqual(codeForCharacter(AZERTY, 'z'), 'KeyW', 'z on AZERTY');
  expectEqual(shortcutMessage(byId('undo'), AZERTY), { t: 'combo', ks: ['MetaLeft', 'KeyW'] }, 'undo on AZERTY');
  expectEqual(shortcutMessage(byId('selectAll'), AZERTY), { t: 'combo', ks: ['MetaLeft', 'KeyQ'] }, 'select all on AZERTY');
});

test('every shortcut sends at most five keys', () => {
  for (const shortcut of SHORTCUTS) {
    const message = shortcutMessage(shortcut);
    if (message.ks) expectEqual(message.ks.length <= 5, true, shortcut.id);
  }
});

test('beside the trackpad, shortcuts split between the two sides', () => {
  const bar = document.createElement('nav');
  const left = document.createElement('div');
  const right = document.createElement('div');
  const sent = [];
  const settings = fakeSettings({ shortcutBar: true, shortcuts: ['undo', 'copy', 'paste', 'spotlight', 'redo'] });
  const shortcuts = createShortcuts({ bar, left, right }, {
    send: (m) => sent.push(m), feedback: silentFeedback, settings, beforeSend() {},
  });
  const names = (el) => [...el.children].map((chip) => chip.getAttribute('aria-label'));
  expectEqual(names(bar), ['Undo', 'Redo', 'Copy', 'Paste', 'Spotlight'], 'top bar');

  shortcuts.placeBesideTrackpad(true);
  expectEqual(names(bar), [], 'top bar beside the trackpad');
  expectEqual(names(left), ['Undo', 'Redo', 'Copy'], 'left side');
  expectEqual(names(right), ['Paste', 'Spotlight'], 'right side');
  right.children[1].click();
  expectEqual(sent, [{ t: 'sys', k: 'spotlight' }], 'sent');

  shortcuts.placeBesideTrackpad(false);
  expectEqual(names(left).length + names(right).length, 0, 'sides after moving back');
  expectEqual(names(bar).length, 5, 'top bar after moving back');
});
