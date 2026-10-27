import { ICONS } from './icons.js';
import { glyphOf, isCustomHotkey } from './hotkeys.js';
import { SHORTCUTS } from './shortcuts.js';
import { closeSheet, el, openSheet } from './util.js';

export const SKINS = [
  { id: 'auto', name: 'Automatic', note: 'Follows iPad appearance' },
  { id: 'midnight', name: 'Midnight Glow', note: 'Dark keys, lit edges' },
  { id: 'space-black', name: 'Space Black', note: 'Matte black aluminum' },
  { id: 'silver', name: 'Silver', note: 'White keys, silver frame' },
  { id: 'frosted', name: 'Frosted Glass', note: 'Translucent keys' },
];

const GLOWS = [
  ['Blue', '#0A84FF'], ['Cyan', '#64D2FF'], ['Indigo', '#5E5CE6'], ['Purple', '#BF5AF2'],
  ['Pink', '#FF375F'], ['Orange', '#FF9F0A'], ['Green', '#30D158'], ['White', '#F5F5F7'],
];

function miniKeyboard(skin) {
  const row = (count) => el('div', { className: 'mini-row' },
    ...Array.from({ length: count }, (_, i) => el('i', { className: count === 4 && i === 1 ? 'wide' : '' })));
  return el('div', { className: 'mini-deck', attrs: { 'data-skin': skin } }, row(7), row(6), row(4));
}

/** Settings, and Type on iPad. Returns `sync`, to redraw after outside changes. */
export function setupSheets({ connection, feedback, settings, typingModel, onNewHotkey, packChoices }) {
  document.querySelectorAll('[data-icon]').forEach((node) => { node.innerHTML = ICONS[node.dataset.icon]; });

  // Settings
  const settingsSheet = document.getElementById('settingsSheet');
  document.getElementById('settingsButton').addEventListener('click', () => {
    renderPackChoices();
    openSheet(settingsSheet);
  });

  // A switch per app tab beside the trackpad, to hide the ones you don't use.
  const packList = document.getElementById('packChoices');
  function renderPackChoices() {
    const packs = packChoices();
    packList.replaceChildren(...packs.map((pack) => {
      const toggle = el('input', { className: 'switch', attrs: { type: 'checkbox', 'aria-label': `Show ${pack.name}` } });
      toggle.checked = !pack.hidden;
      toggle.addEventListener('change', () => {
        const hidden = new Set(settings.get('hiddenPacks') ?? []);
        if (toggle.checked) hidden.delete(pack.id);
        else hidden.add(pack.id);
        settings.set('hiddenPacks', [...hidden]);
      });
      return el('label', { className: 'row' },
        el('span', { className: 'row-label pack-choice' },
          ...(pack.icon ? [el('img', { attrs: { src: pack.icon, alt: '' } })] : []), pack.name),
        toggle);
    }));
  }

  const skinGrid = document.getElementById('skinGrid');
  for (const skin of SKINS) {
    const preview = skin.id === 'auto'
      ? el('div', { className: 'mini-split' }, miniKeyboard('silver'), miniKeyboard('midnight'))
      : miniKeyboard(skin.id);
    const card = el('button', { className: 'skin-card', attrs: { 'data-value': skin.id, 'aria-label': skin.name } },
      preview,
      el('span', { className: 'skin-name', text: skin.name }),
      el('span', { className: 'skin-note', text: skin.note }),
      el('span', { className: 'skin-check', html: ICONS.check }));
    card.addEventListener('click', () => settings.set('skin', skin.id));
    skinGrid.append(card);
  }

  const swatches = document.getElementById('glowSwatches');
  for (const [name, color] of GLOWS) {
    const swatch = el('button', {
      className: 'swatch',
      attrs: { role: 'radio', 'aria-label': name, 'data-value': color },
      style: { '--swatch': color },
    });
    swatch.addEventListener('click', () => settings.set('glow', color));
    swatches.append(swatch);
  }

  // One switch per shortcut; the bar shows them in this list's order.
  const shortcutList = document.getElementById('shortcutList');
  for (const shortcut of SHORTCUTS) {
    const toggle = el('input', { className: 'switch', attrs: { type: 'checkbox', 'data-shortcut': shortcut.id } });
    toggle.addEventListener('change', () => {
      const chosen = new Set(settings.get('shortcuts'));
      if (toggle.checked) chosen.add(shortcut.id);
      else chosen.delete(shortcut.id);
      settings.set('shortcuts', SHORTCUTS.map(({ id }) => id).filter((id) => chosen.has(id)));
    });
    shortcutList.append(el('label', { className: 'row' },
      el('span', { className: 'row-label', text: shortcut.name }),
      el('span', { className: 'row-detail', text: shortcut.sys ? '' : glyphOf(shortcut) }),
      toggle));
  }

  // Hotkeys you made, each with a way to delete it.
  const customList = document.getElementById('customHotkeyList');
  function renderCustomHotkeys() {
    const hotkeys = (settings.get('customHotkeys') ?? []).filter(isCustomHotkey);
    customList.hidden = hotkeys.length === 0;
    customList.replaceChildren(...hotkeys.map((hotkey) => {
      const remove = el('button', { className: 'row-action destructive', text: 'Delete', attrs: { 'aria-label': `Delete ${hotkey.name}` } });
      remove.addEventListener('click', () => {
        settings.set('customHotkeys', settings.get('customHotkeys').filter(({ id }) => id !== hotkey.id));
      });
      return el('div', { className: 'row' },
        el('span', { className: 'row-label', text: hotkey.name }),
        el('span', { className: 'row-detail', text: glyphOf(hotkey) }),
        remove);
    }));
  }
  settings.subscribe((key) => { if (key === 'customHotkeys') renderCustomHotkeys(); });
  renderCustomHotkeys();
  document.getElementById('newHotkeyButton').addEventListener('click', () => {
    closeSheet(settingsSheet);
    onNewHotkey();
  });

  const resetTyping = document.getElementById('resetTyping');
  resetTyping.addEventListener('click', () => {
    typingModel.reset();
    resetTyping.textContent = 'Typing Learning Reset';
    setTimeout(() => { resetTyping.textContent = 'Reset Typing Learning'; }, 1600);
  });

  for (const input of settingsSheet.querySelectorAll('input[data-setting]')) {
    const key = input.dataset.setting;
    const isSwitch = input.type === 'checkbox';
    input.addEventListener(isSwitch ? 'change' : 'input', () => {
      settings.set(key, isSwitch ? input.checked : Number(input.value));
      if (key === 'volume' || key === 'sound') feedback.preview();
    });
  }
  for (const group of settingsSheet.querySelectorAll('.segmented')) {
    group.addEventListener('click', (event) => {
      const button = event.target.closest('button');
      if (!button) return;
      settings.set(group.dataset.setting, button.dataset.value);
      if (group.dataset.setting === 'soundProfile') feedback.preview();
    });
  }

  document.getElementById('testSound').addEventListener('click', () => feedback.preview());

  const vibrationSwitch = document.getElementById('vibrationSwitch');
  if (!feedback.canVibrate) {
    vibrationSwitch.disabled = true;
    document.getElementById('vibrationNote').textContent =
      "This iPad doesn't have a vibration motor, so each key plays a sound instead.";
  }

  function sync() {
    for (const input of settingsSheet.querySelectorAll('input[data-setting]')) {
      const value = settings.get(input.dataset.setting);
      if (input.type === 'checkbox') input.checked = Boolean(value) && !input.disabled;
      else input.value = value;
    }
    for (const group of settingsSheet.querySelectorAll('.segmented')) {
      const value = settings.get(group.dataset.setting);
      group.querySelectorAll('button').forEach((b) => b.setAttribute('aria-pressed', b.dataset.value === value));
    }
    skinGrid.querySelectorAll('.skin-card').forEach((card) => {
      card.setAttribute('aria-pressed', card.dataset.value === settings.get('skin'));
    });
    swatches.querySelectorAll('.swatch').forEach((swatch) => {
      swatch.setAttribute('aria-checked', swatch.dataset.value === settings.get('glow'));
    });
    const chosen = new Set(settings.get('shortcuts'));
    shortcutList.querySelectorAll('[data-shortcut]').forEach((toggle) => {
      toggle.checked = chosen.has(toggle.dataset.shortcut);
    });
    shortcutList.hidden = !settings.get('shortcutBar');
    const glowing = document.documentElement.dataset.skin === 'midnight';
    document.getElementById('glowGroup').hidden = !glowing;

    // Only offer what applies to the current layout.
    const layout = settings.get('layout');
    const floats = layout === 'keyboard' && settings.get('keyboardSize') === 'floating';
    document.getElementById('positionRow').hidden = layout === 'trackpad' || floats;
    document.getElementById('sizeRow').hidden = layout !== 'keyboard';
    document.getElementById('sizeNote').hidden = layout !== 'keyboard';
    settingsSheet.querySelector('[data-setting="keyboardPosition"] [data-value="middle"]').hidden = layout !== 'keyboard';
  }
  settings.subscribe(sync);
  sync();

  document.getElementById('forgetButton').addEventListener('click', () => {
    closeSheet(settingsSheet);
    connection.forget();
  });

  // Text entry through the iPad's own keyboard (dictation, emoji, autocorrect).
  const textSheet = document.getElementById('textSheet');
  const textField = document.getElementById('textField');
  document.getElementById('textButton').addEventListener('click', () => {
    openSheet(textSheet);
    textField.focus();
  });
  document.getElementById('textSend').addEventListener('click', () => {
    if (textField.value) connection.send({ t: 'txt', s: textField.value });
    textField.value = '';
    textField.blur();
    closeSheet(textSheet);
  });

  for (const sheet of [settingsSheet, textSheet]) {
    sheet.addEventListener('click', (event) => {
      if (event.target === sheet || event.target.closest('[data-close]')) {
        document.activeElement?.blur();
        closeSheet(sheet);
      }
    });
  }

  return { sync };
}
