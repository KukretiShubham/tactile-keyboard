// Preferences live only on this iPad. Storage can be unavailable (private
// browsing), so every access is guarded and defaults always apply.
const KEY = 'tactile.settings.v1';

const DEFAULTS = {
  skin: 'midnight',
  glow: '#0A84FF',
  sound: true,
  soundProfile: 'soft',
  volume: 0.6,
  vibration: true,
  tracking: 1.4,
  naturalScroll: true,
  layout: 'both',
  keyHeight: 'standard',
  functionRow: true,
  keyboardPosition: 'top',
  keyboardSize: 'fit',
  restFingers: true,
  keepAwake: true,
};

export const storage = {
  get(key) {
    try { return localStorage.getItem(key); } catch { return null; }
  },
  set(key, value) {
    try { localStorage.setItem(key, value); } catch { /* not persisted */ }
  },
  remove(key) {
    try { localStorage.removeItem(key); } catch { /* nothing stored */ }
  },
};

function load() {
  try {
    return { ...DEFAULTS, ...JSON.parse(storage.get(KEY) || '{}') };
  } catch {
    return { ...DEFAULTS };
  }
}

const values = load();
const listeners = new Set();

export const settings = {
  get: (key) => values[key],
  set(key, value) {
    if (values[key] === value) return;
    values[key] = value;
    storage.set(KEY, JSON.stringify(values));
    listeners.forEach((listener) => listener(key, value));
  },
  subscribe: (listener) => listeners.add(listener),
};
