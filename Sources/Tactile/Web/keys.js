// The keyboard's layout and how each key is drawn. Typing behaviour lives in
// keyboard.js; this file is data and DOM only.
import { ICONS } from './icons.js';
import { el } from './util.js';

// Magic Keyboard (US, with Touch ID) layout. Widths are in key units; every
// row adds up to 14.5 units so the edges line up like the real thing.
const letter = (ch) => ({ code: `Key${ch}`, kind: 'letter', label: ch });
const letters = (row) => [...row].map(letter);
const pair = (code, label, shifted) => ({ code, kind: 'pair', label, shifted });
const fkey = (n, sys = null) => ({ code: `F${n}`, kind: 'fkey', label: `F${n}`, sys, icon: sys && ICONS[sys] });
const word = (code, text, w, wordAt) => ({ code, kind: 'word', word: text, w, wordAt });
const modifier = (code, text, sym, w, symAt, wordAt) => ({ code, kind: 'mod', word: text, sym, w, symAt, wordAt });

const ROWS = [
  [
    word('Escape', 'esc', 1.5, 'bl'),
    fkey(1, 'brightnessDown'), fkey(2, 'brightnessUp'), fkey(3, 'missionControl'), fkey(4, 'spotlight'),
    fkey(5), fkey(6), fkey(7, 'previous'), fkey(8, 'playPause'), fkey(9, 'next'),
    fkey(10, 'mute'), fkey(11, 'volumeDown'), fkey(12, 'volumeUp'),
    { code: 'Lock', kind: 'fkey', sys: 'lockScreen', icon: ICONS.lockScreen, aria: 'Lock Screen' },
  ],
  [
    pair('Backquote', '`', '~'),
    ...[...'1234567890'].map((d, i) => pair(`Digit${d}`, d, '!@#$%^&*()'[i])),
    pair('Minus', '-', '_'), pair('Equal', '=', '+'),
    word('Backspace', 'delete', 1.5, 'br'),
  ],
  [
    word('Tab', 'tab', 1.5, 'bl'),
    ...letters('QWERTYUIOP'),
    pair('BracketLeft', '[', '{'), pair('BracketRight', ']', '}'), pair('Backslash', '\\', '|'),
  ],
  [
    { code: 'CapsLock', kind: 'caps', word: 'caps lock', w: 1.75, wordAt: 'bl' },
    ...letters('ASDFGHJKL'),
    pair('Semicolon', ';', ':'), pair('Quote', "'", '"'),
    word('Enter', 'return', 1.75, 'br'),
  ],
  [
    modifier('ShiftLeft', 'shift', '⇧', 2.25, 'tl', 'bl'),
    ...letters('ZXCVBNM'),
    pair('Comma', ',', '<'), pair('Period', '.', '>'), pair('Slash', '/', '?'),
    modifier('ShiftRight', 'shift', '⇧', 2.25, 'tr', 'br'),
  ],
  [
    { code: 'Fn', kind: 'mod', local: true, word: 'fn', icon: ICONS.globe, aria: 'Function' },
    modifier('ControlLeft', 'control', '⌃', 1, 'tr', 'bl'),
    modifier('AltLeft', 'option', '⌥', 1, 'tr', 'bl'),
    modifier('MetaLeft', 'command', '⌘', 1.25, 'tr', 'bl'),
    { code: 'Space', kind: 'space', w: 5, aria: 'Space' },
    modifier('MetaRight', 'command', '⌘', 1.25, 'tl', 'br'),
    modifier('AltRight', 'option', '⌥', 1, 'tl', 'br'),
    { kind: 'arrows' },
  ],
];

const ARROWS = [
  { code: 'ArrowLeft', kind: 'arrow', icon: ICONS.arrowLeft, aria: 'Left Arrow', area: 'left' },
  { code: 'ArrowUp', kind: 'arrow', icon: ICONS.arrowUp, aria: 'Up Arrow', area: 'up' },
  { code: 'ArrowDown', kind: 'arrow', icon: ICONS.arrowDown, aria: 'Down Arrow', area: 'down' },
  { code: 'ArrowRight', kind: 'arrow', icon: ICONS.arrowRight, aria: 'Right Arrow', area: 'right' },
];

// What each character key types on a US layout, in the form the Mac sends
// for its own layout (see `applyLabels`).
const US_LABELS = Object.fromEntries(ROWS.flat()
  .filter((def) => def.kind === 'letter' || def.kind === 'pair')
  .map((def) => [def.code, def.kind === 'letter' ? [def.label.toLowerCase(), def.label] : [def.label, def.shifted]]));

// Holding fn turns these keys into their navigation twins, as on a Mac.
export const FN_LAYER = { Backspace: 'Delete', ArrowUp: 'PageUp', ArrowDown: 'PageDown', ArrowLeft: 'Home', ArrowRight: 'End' };

/** Which key sound a key makes: bigger keys sound lower. */
export function soundKind(def) {
  if (def.kind === 'space') return 'space';
  if (def.kind === 'mod' || def.kind === 'caps') return 'mod';
  if (def.w >= 1.5) return 'wide';
  return 'key';
}

/** The character a letter or symbol key types right now. */
export function characterOf(def, { shifted }) {
  if (def.kind === 'letter') return shifted ? def.label : def.label.toLowerCase();
  if (def.kind === 'pair') return shifted ? def.shifted : def.label;
  return '';
}

const span = (className, text) => el('span', { className, text });
const icon = (className, markup) => el('span', { className, html: markup });

function legend(def) {
  switch (def.kind) {
    case 'letter': return [span('lg-center', def.label)];
    case 'pair': return [el('span', { className: 'lg-stack' }, span('', def.shifted), span('', def.label))];
    case 'fkey': return [def.icon && icon('lg-icon', def.icon), def.label && span('lg-flabel', def.label)].filter(Boolean);
    case 'word': return [span(`lg-${def.wordAt}`, def.word)];
    case 'caps': return [span('led'), span(`lg-${def.wordAt}`, def.word)];
    case 'mod': return def.icon
      ? [icon('lg-bl lg-glyph', def.icon), span('lg-tr', def.word)]
      : [span(`lg-${def.symAt} lg-sym`, def.sym), span(`lg-${def.wordAt}`, def.word)];
    case 'arrow': return [icon('lg-arrow', def.icon)];
    default: return [];
  }
}

function renderKey(def) {
  const key = el('div', {
    className: `key key-${def.kind}${def.area ? ` arrow-${def.area}` : ''}`,
    attrs: { role: 'button', 'aria-label': def.aria || def.word || def.label || def.code, 'data-code': def.code },
    style: { '--w': def.w ?? 1 },
  }, ...legend(def));
  return key;
}

/**
 * Draws the keyboard into `root`. Returns each key's definition (by element)
 * and element (by code). Definitions are copies, so labels can change.
 */
export function buildKeys(root) {
  const defs = new WeakMap();
  const elements = new Map();
  const register = (source) => {
    const def = { ...source };
    const key = renderKey(def);
    defs.set(key, def);
    elements.set(def.code, key);
    return key;
  };
  for (const [index, row] of ROWS.entries()) {
    const keys = row.map((def) => def.kind === 'arrows'
      ? el('div', { className: 'arrows', style: { '--w': 3 } }, ...ARROWS.map(register))
      : register(def));
    root.append(el('div', { className: index === 0 ? 'key-row key-row-function' : 'key-row' }, ...keys));
  }
  return { defs, elements };
}

/**
 * The key that types `character` (unshifted) on the Mac's layout, given the
 * labels from the Mac; falls back to its US position.
 */
export function codeForCharacter(labels, character) {
  const found = Object.entries(labels).find(([, [base]]) => base === character);
  return found ? found[0] : `Key${character.toUpperCase()}`;
}

/**
 * Relabels letter and symbol keys to match the Mac's keyboard layout.
 * `labels` maps a key code to [unshifted, shifted], e.g. KeyQ: ["a", "A"];
 * keys it leaves out (and every key, given {}) show their US labels.
 */
export function applyLabels({ defs, elements }, labels) {
  for (const [code, [base, shifted]] of Object.entries({ ...US_LABELS, ...labels })) {
    const key = elements.get(code);
    const def = key && defs.get(key);
    if (!def || (def.kind !== 'letter' && def.kind !== 'pair')) continue;
    // A key whose shifted character is its capital is drawn like a Mac keycap
    // letter; anything else (digits, symbols, ß, non-Latin scripts) shows both.
    const isLetter = shifted && shifted !== base && shifted.toLowerCase() === base;
    if (isLetter) Object.assign(def, { kind: 'letter', label: shifted, shifted: undefined });
    else Object.assign(def, { kind: 'pair', label: base, shifted: shifted || base });
    key.className = `key key-${def.kind}`;
    key.setAttribute('aria-label', def.label);
    key.replaceChildren(...legend(def));
  }
}
