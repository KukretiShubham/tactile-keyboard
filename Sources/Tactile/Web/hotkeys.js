// What a hotkey does and how it's drawn. A hotkey is one of:
//   { keys: ['MetaLeft', 'p'] }                pressed together
//   { keys: ['Escape'], times: 2 }             pressed twice (Esc Esc)
//   { text: '/clear', enter: true }            typed, then Return
//   { sys: 'spotlight' }                       a Mac system action
//   { start: true }                            a terminal agent's command, run
//                                              in a new window (see shortcuts.js)
// Single characters in `keys` follow the Mac's keyboard layout.
import { codeForCharacter, comboGlyph } from './keys.js';

// Pause between the steps of a hotkey, so apps see separate presses.
const STEP_GAP = 70;

/** How the hotkey is written on its key, e.g. "⇧⌘P", "esc esc" or "/clear". */
export function glyphOf(hotkey) {
  if (hotkey.glyph) return hotkey.glyph;
  if (hotkey.text) return hotkey.text;
  if (!hotkey.keys) return '';
  const once = comboGlyph(hotkey.keys);
  return Array(hotkey.times ?? 1).fill(once).join(once.length > 1 ? ' ' : '');
}

/** The messages that perform `hotkey` on the Mac's current layout. */
export function hotkeyMessages(hotkey, labels = {}) {
  if (hotkey.sys) return [{ t: 'sys', k: hotkey.sys }];
  if (hotkey.text) return [{ t: 'txt', s: hotkey.text }, ...(hotkey.enter ? [{ t: 'combo', ks: ['Enter'] }] : [])];
  if (!hotkey.keys) return [];
  const combo = { t: 'combo', ks: hotkey.keys.map((key) => (key.length === 1 ? codeForCharacter(labels, key) : key)) };
  return Array(hotkey.times ?? 1).fill(combo);
}

/** Whether a second tap undoes the hotkey (see packs.js). */
export const canReverse = (hotkey) => Boolean(hotkey.toggle || hotkey.reverse);

/** The messages that undo `hotkey`: the same keys again, or its `reverse`. */
export function reverseMessages(hotkey, labels = {}) {
  return hotkey.reverse ? hotkeyMessages({ keys: hotkey.reverse }, labels) : hotkeyMessages(hotkey, labels);
}

/**
 * Sends `steps` one after another, a moment apart. A number among them is an
 * extra pause, in milliseconds, e.g. to let a window open.
 */
export function sendInSteps(send, steps) {
  let at = 0;
  for (const step of steps) {
    if (typeof step === 'number') {
      at += step;
      continue;
    }
    if (at === 0) send(step);
    else setTimeout(() => send(step), at);
    at += STEP_GAP;
  }
}

/** Whether `value` is a well-formed hotkey you made (they're kept in Settings). */
export function isCustomHotkey(value) {
  if (!value || typeof value !== 'object' || typeof value.id !== 'string' || typeof value.pack !== 'string') return false;
  if (typeof value.name !== 'string' || !value.name.trim() || value.name.length > 40) return false;
  if (typeof value.text === 'string') return value.text.length > 0 && value.text.length <= 500;
  return Array.isArray(value.keys) && value.keys.length >= 1 && value.keys.length <= 5
    && value.keys.every((key) => typeof key === 'string' && /^[A-Za-z0-9]{1,20}$/.test(key));
}
