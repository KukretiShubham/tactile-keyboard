// One-tap Mac shortcuts. In landscape with the trackpad showing they're keys
// on either side of the trackpad, like a MacBook's palm rests; otherwise
// they're a bar along the top. Which ones show is chosen in Settings.
import { ICONS } from './icons.js';
import { codeForCharacter } from './keys.js';
import { el } from './util.js';

// `keys` are pressed together, in order. Letters are given as characters and
// found on the Mac's keyboard layout, so ⌘Z is still ⌘Z on AZERTY.
export const SHORTCUTS = [
  { id: 'undo', name: 'Undo', glyph: '⌘Z', keys: ['MetaLeft', 'z'] },
  { id: 'redo', name: 'Redo', glyph: '⇧⌘Z', keys: ['MetaLeft', 'ShiftLeft', 'z'] },
  { id: 'cut', name: 'Cut', glyph: '⌘X', keys: ['MetaLeft', 'x'] },
  { id: 'copy', name: 'Copy', glyph: '⌘C', keys: ['MetaLeft', 'c'] },
  { id: 'paste', name: 'Paste', glyph: '⌘V', keys: ['MetaLeft', 'v'] },
  { id: 'selectAll', name: 'Select All', glyph: '⌘A', keys: ['MetaLeft', 'a'] },
  { id: 'find', name: 'Find', glyph: '⌘F', keys: ['MetaLeft', 'f'] },
  { id: 'save', name: 'Save', glyph: '⌘S', keys: ['MetaLeft', 's'] },
  { id: 'newTab', name: 'New Tab', glyph: '⌘T', keys: ['MetaLeft', 't'] },
  { id: 'switchApp', name: 'Switch App', glyph: '⌘⇥', keys: ['MetaLeft', 'Tab'] },
  { id: 'screenshot', name: 'Screenshot', glyph: '⇧⌘5', keys: ['MetaLeft', 'ShiftLeft', 'Digit5'] },
  { id: 'missionControl', name: 'Mission Control', icon: ICONS.missionControl, sys: 'missionControl' },
  { id: 'spotlight', name: 'Spotlight', icon: ICONS.spotlight, sys: 'spotlight' },
];

export const DEFAULT_SHORTCUTS = ['undo', 'redo', 'copy', 'paste', 'switchApp', 'screenshot', 'missionControl', 'spotlight'];

/** The message that performs `shortcut` on the Mac's current layout. */
export function shortcutMessage(shortcut, labels = {}) {
  if (shortcut.sys) return { t: 'sys', k: shortcut.sys };
  return { t: 'combo', ks: shortcut.keys.map((key) => (key.length === 1 ? codeForCharacter(labels, key) : key)) };
}

/**
 * Shows the chosen shortcuts in `bar`, or split between `left` and `right`
 * beside the trackpad, and keeps them in step with Settings.
 */
export function createShortcuts({ bar, left, right }, { send, feedback, settings, beforeSend }) {
  let labels = {};
  let besideTrackpad = false;

  // `position` is where the key sits, from -1 (left) to 1 (right), for its sound.
  function button(shortcut, position) {
    const chip = el('button', {
      className: besideTrackpad ? 'shortcut' : 'shortcut glass',
      attrs: { 'aria-label': shortcut.name, title: shortcut.name },
    },
    shortcut.icon
      ? el('span', { className: 'shortcut-glyph shortcut-icon', html: shortcut.icon })
      : el('span', { className: 'shortcut-glyph', text: shortcut.glyph }),
    el('span', { className: 'shortcut-name', text: shortcut.name }));
    chip.addEventListener('click', () => {
      beforeSend();
      send(shortcutMessage(shortcut, labels));
      if (besideTrackpad) feedback.key('key', position);
      else feedback.click();
    });
    return chip;
  }

  function render() {
    const chosen = new Set(settings.get('shortcuts'));
    const shown = settings.get('shortcutBar') ? SHORTCUTS.filter(({ id }) => chosen.has(id)) : [];
    const half = Math.ceil(shown.length / 2);
    const place = (list, position) => (besideTrackpad ? list.map((shortcut) => button(shortcut, position)) : []);
    left.replaceChildren(...place(shown.slice(0, half), -0.9));
    right.replaceChildren(...place(shown.slice(half), 0.9));
    bar.replaceChildren(...(besideTrackpad ? [] : shown.map((shortcut) => button(shortcut, 0))));
    bar.hidden = besideTrackpad || shown.length === 0;
  }

  settings.subscribe((key) => { if (key === 'shortcuts' || key === 'shortcutBar') render(); });
  render();
  return {
    /** The Mac's keyboard layout changed (see keys.js `applyLabels`). */
    setLabels: (next) => { labels = next; },
    /** Moves the shortcuts beside the trackpad, or back to the top bar. */
    placeBesideTrackpad(on) {
      if (on === besideTrackpad) return;
      besideTrackpad = on;
      render();
    },
  };
}
