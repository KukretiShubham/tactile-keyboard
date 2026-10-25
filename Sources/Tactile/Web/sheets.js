import { ICONS } from './icons.js';
import { settings } from './settings.js';

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
  const preview = document.createElement('div');
  preview.className = 'mini-deck';
  preview.dataset.skin = skin;
  for (const count of [7, 6, 4]) {
    const row = document.createElement('div');
    row.className = 'mini-row';
    for (let i = 0; i < count; i++) {
      const key = document.createElement('i');
      if (count === 4 && i === 1) key.className = 'wide';
      row.append(key);
    }
    preview.append(row);
  }
  return preview;
}

export function setupSheets({ connection, feedback }) {
  const open = (sheet) => {
    sheet.hidden = false;
    requestAnimationFrame(() => sheet.classList.add('shown'));
  };
  const close = (sheet) => {
    sheet.classList.remove('shown');
    setTimeout(() => { sheet.hidden = true; }, 220);
  };

  document.querySelectorAll('[data-icon]').forEach((el) => { el.innerHTML = ICONS[el.dataset.icon]; });

  // Settings
  const settingsSheet = document.getElementById('settingsSheet');
  document.getElementById('settingsButton').addEventListener('click', () => open(settingsSheet));

  const skinGrid = document.getElementById('skinGrid');
  for (const skin of SKINS) {
    const card = document.createElement('button');
    card.className = 'skin-card';
    card.dataset.value = skin.id;
    card.setAttribute('aria-label', skin.name);
    const preview = skin.id === 'auto'
      ? Object.assign(document.createElement('div'), { className: 'mini-split' })
      : miniKeyboard(skin.id);
    if (skin.id === 'auto') preview.append(miniKeyboard('silver'), miniKeyboard('midnight'));
    const name = Object.assign(document.createElement('span'), { className: 'skin-name', textContent: skin.name });
    const note = Object.assign(document.createElement('span'), { className: 'skin-note', textContent: skin.note });
    const check = Object.assign(document.createElement('span'), { className: 'skin-check', innerHTML: ICONS.check });
    card.append(preview, name, note, check);
    card.addEventListener('click', () => settings.set('skin', skin.id));
    skinGrid.append(card);
  }

  const swatches = document.getElementById('glowSwatches');
  for (const [name, color] of GLOWS) {
    const swatch = document.createElement('button');
    swatch.className = 'swatch';
    swatch.setAttribute('role', 'radio');
    swatch.setAttribute('aria-label', name);
    swatch.dataset.value = color;
    swatch.style.setProperty('--swatch', color);
    swatch.addEventListener('click', () => settings.set('glow', color));
    swatches.append(swatch);
  }

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
    const glowing = document.documentElement.dataset.skin === 'midnight';
    document.getElementById('glowGroup').hidden = !glowing;

    // Only offer what applies to the current layout.
    const layout = settings.get('layout');
    document.getElementById('positionRow').hidden = layout === 'trackpad';
    document.getElementById('sizeRow').hidden = layout !== 'keyboard';
    document.getElementById('sizeNote').hidden = layout !== 'keyboard';
    settingsSheet.querySelector('[data-setting="keyboardPosition"] [data-value="middle"]').hidden = layout !== 'keyboard';
  }
  settings.subscribe(sync);
  sync();

  document.getElementById('forgetButton').addEventListener('click', () => {
    close(settingsSheet);
    connection.forget();
  });

  // Text entry through the iPad's own keyboard (dictation, emoji, autocorrect).
  const textSheet = document.getElementById('textSheet');
  const textField = document.getElementById('textField');
  document.getElementById('textButton').addEventListener('click', () => {
    open(textSheet);
    textField.focus();
  });
  document.getElementById('textSend').addEventListener('click', () => {
    if (textField.value) connection.send({ t: 'txt', s: textField.value });
    textField.value = '';
    textField.blur();
    close(textSheet);
  });

  for (const sheet of [settingsSheet, textSheet]) {
    sheet.addEventListener('click', (event) => {
      if (event.target === sheet || event.target.closest('[data-close]')) {
        document.activeElement?.blur();
        close(sheet);
      }
    });
  }

  // Pairing
  const pairSheet = document.getElementById('pairSheet');
  const pairCode = document.getElementById('pairCode');
  const pairError = document.getElementById('pairError');
  const submit = () => {
    const code = pairCode.value.replace(/\D/g, '');
    if (code.length !== 6) {
      pairError.textContent = 'The code has six digits.';
      return;
    }
    pairError.textContent = '';
    connection.pair(code);
  };
  pairCode.addEventListener('input', () => {
    pairCode.value = pairCode.value.replace(/\D/g, '').slice(0, 6);
    if (pairCode.value.length === 6) submit();
  });
  pairCode.addEventListener('keydown', (event) => { if (event.key === 'Enter') submit(); });
  document.getElementById('pairButton').addEventListener('click', submit);

  return {
    sync,
    showPairing() {
      if (!pairSheet.hidden) return;
      pairCode.value = '';
      pairError.textContent = '';
      open(pairSheet);
      pairCode.focus();
    },
    hidePairing() {
      if (pairSheet.hidden) return;
      pairCode.blur();
      close(pairSheet);
    },
    pairingDenied(reason) {
      pairCode.value = '';
      pairError.textContent = {
        locked: 'Too many tries. Wait a minute, then try again.',
        expired: 'That QR code has expired. Enter the code shown in Terminal now.',
      }[reason] ?? "That code didn't match. Check Terminal on your Mac.";
    },
  };
}
