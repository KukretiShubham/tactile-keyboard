import { codeForCharacter } from '../../Sources/Tactile/Web/keys.js';
import { SHORTCUTS, shortcutMessage } from '../../Sources/Tactile/Web/shortcuts.js';
import { expectEqual, test } from './harness.js';

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
