// The shortcut bar: one tap for the Mac shortcuts you use most. Which ones
// show is chosen in Settings.
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

/** Fills `bar` with the chosen shortcuts and keeps it in step with Settings. */
export function createShortcutBar(bar, { send, feedback, settings, beforeSend }) {
  let labels = {};

  function render() {
    const chosen = new Set(settings.get('shortcuts'));
    const shown = settings.get('shortcutBar') ? SHORTCUTS.filter(({ id }) => chosen.has(id)) : [];
    bar.hidden = shown.length === 0;
    bar.replaceChildren(...shown.map((shortcut) => {
      const chip = el('button', {
        className: 'shortcut glass',
        attrs: { 'aria-label': shortcut.name, title: shortcut.name },
      },
      shortcut.icon
        ? el('span', { className: 'shortcut-glyph shortcut-icon', html: shortcut.icon })
        : el('span', { className: 'shortcut-glyph', text: shortcut.glyph }),
      el('span', { className: 'shortcut-name', text: shortcut.name }));
      chip.addEventListener('click', () => {
        beforeSend();
        send(shortcutMessage(shortcut, labels));
        feedback.click();
      });
      return chip;
    }));
  }

  settings.subscribe((key) => { if (key === 'shortcuts' || key === 'shortcutBar') render(); });
  render();
  return {
    /** The Mac's keyboard layout changed (see keys.js `applyLabels`). */
    setLabels: (next) => { labels = next; },
  };
}
