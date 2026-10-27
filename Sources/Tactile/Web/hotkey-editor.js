// The New Hotkey sheet: name a hotkey, then either record a key combination on
// Tactile's own keyboard (which stays usable above the sheet, and sends
// nothing to the Mac meanwhile) or type text to send. Hotkeys are kept in
// Settings and shown with an app's pack, or with the general shortcuts.
import { comboGlyph, isModifier } from './keys.js';
import { closeSheet, el, openSheet } from './util.js';

const ORDER = ['Control', 'Alt', 'Shift', 'Meta'];
const byAppleOrder = (a, b) => ORDER.findIndex((m) => a.startsWith(m)) - ORDER.findIndex((m) => b.startsWith(m));

/**
 * Turns the keyboard's messages into a key combination: the modifiers held
 * when a key goes down, plus that key. `capture(message)` returns the
 * combination when one is complete (else null); nothing is sent anywhere.
 */
export function comboRecorder() {
  const held = new Set();
  return {
    capture(message) {
      if (message.t !== 'kd' && message.t !== 'ku') return null;
      if (isModifier(message.k)) {
        if (message.t === 'kd') held.add(message.k);
        else held.delete(message.k);
        return null;
      }
      return message.t === 'kd' && !message.r ? [...held].sort(byAppleOrder).concat(message.k) : null;
    },
    reset: () => held.clear(),
  };
}

/**
 * `record(handler)` routes the keyboard's messages to `handler` instead of
 * the Mac (or back to the Mac with null). `packs()` lists the packs offered.
 */
export function createHotkeyEditor({ settings, feedback, deck, record, packs }) {
  const sheet = document.getElementById('hotkeySheet');
  const name = document.getElementById('hotkeyName');
  const kind = document.getElementById('hotkeyKind');
  const recordBox = document.getElementById('hotkeyRecord');
  const recorded = document.getElementById('hotkeyKeys');
  const textRow = document.getElementById('hotkeyTextRow');
  const text = document.getElementById('hotkeyText');
  const enter = document.getElementById('hotkeyEnter');
  const apps = document.getElementById('hotkeyApps');
  const add = document.getElementById('hotkeyAdd');

  let state = null; // { kind, keys, pack }
  const recorder = comboRecorder();

  function capture(message) {
    const keys = recorder.capture(message);
    if (!keys) return;
    state.keys = keys;
    feedback.click();
    update();
  }

  function update() {
    for (const button of kind.querySelectorAll('button')) button.setAttribute('aria-pressed', button.dataset.value === state.kind);
    recordBox.hidden = state.kind !== 'keys';
    textRow.hidden = state.kind !== 'text';
    recorded.replaceChildren(...(state.keys.length
      ? comboGlyph(state.keys).match(/[⌃⌥⇧⌘]|.+$/gu).map((part) => el('span', { className: 'record-cap', text: part }))
      : []));
    recordBox.classList.toggle('empty', state.keys.length === 0);
    for (const chip of apps.querySelectorAll('[data-pack]')) chip.setAttribute('aria-checked', chip.dataset.pack === state.pack);
    const ready = name.value.trim() && (state.kind === 'keys' ? state.keys.length : text.value.length);
    add.disabled = !ready;
    record(state.kind === 'keys' ? capture : null);
  }

  function appChip(id, label, icon) {
    const chip = el('button', { className: 'hotkey-app', attrs: { role: 'radio', 'data-pack': id } },
      ...(icon ? [el('img', { attrs: { src: icon, alt: '' } })] : []), label);
    chip.addEventListener('click', () => { state.pack = id; update(); });
    return chip;
  }

  // Keep the keyboard uncovered: the sheet sits on the side away from it.
  function placeAwayFromKeyboard() {
    const keys = deck.getBoundingClientRect();
    const keyboardOnTop = keys.top + keys.height / 2 < innerHeight / 2;
    sheet.style.top = keyboardOnTop ? `${Math.round(keys.bottom)}px` : '0px';
    sheet.style.bottom = keyboardOnTop ? '0px' : `${Math.round(innerHeight - keys.top)}px`;
  }

  function close() {
    record(null);
    recorder.reset();
    document.activeElement?.blur();
    closeSheet(sheet);
    state = null;
  }

  kind.addEventListener('click', (event) => {
    const button = event.target.closest('button');
    if (!button || !state) return;
    state.kind = button.dataset.value;
    update();
  });
  for (const input of [name, text]) input.addEventListener('input', () => state && update());
  sheet.addEventListener('click', (event) => {
    if (event.target === sheet || event.target.closest('[data-close]')) close();
  });
  add.addEventListener('click', () => {
    if (add.disabled) return;
    const hotkey = { id: `mine-${Date.now().toString(36)}`, name: name.value.trim(), pack: state.pack };
    if (state.kind === 'keys') hotkey.keys = state.keys;
    else Object.assign(hotkey, { text: text.value, enter: enter.checked });
    settings.set('customHotkeys', [...(settings.get('customHotkeys') ?? []), hotkey]);
    feedback.click();
    close();
  });

  return {
    /** Opens the sheet, with the hotkey going to `pack` unless changed. */
    open(pack = 'all') {
      state = { kind: 'keys', keys: [], pack };
      name.value = '';
      text.value = '';
      enter.checked = true;
      apps.replaceChildren(el('span', { className: 'hotkey-apps-label', text: 'Show for' }),
        appChip('all', 'All Apps'), ...packs().map((each) => appChip(each.id, each.name, each.icon)));
      placeAwayFromKeyboard();
      update();
      openSheet(sheet);
    },
  };
}
