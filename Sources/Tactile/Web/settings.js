// Preferences live only on this iPad. Storage can be unavailable (private
// browsing), so every access is guarded and defaults always apply.
import { DEFAULT_SHORTCUTS } from './shortcuts.js';
import { storage } from './util.js';

const KEY = 'tactile.settings.v1';

const DEFAULTS = {
  skin: 'midnight',
  glow: '#0A84FF',
  sound: true,
  soundInSilentMode: false,
  soundProfile: 'soft',
  volume: 0.6,
  vibration: true,
  tracking: 1.4,
  naturalScroll: true,
  scrollSpeed: 1,
  pinchZoom: true,
  threeFingerDrag: false,
  layout: 'both',
  keyHeight: 'standard',
  functionRow: true,
  keyboardPosition: 'top',
  keyboardSize: 'fit',
  floatingFrame: null,
  restFingers: true,
  keyPopups: true,
  adaptiveTyping: true,
  macLabels: true,
  shortcutBar: true,
  shortcuts: DEFAULT_SHORTCUTS,
  pack: 'claude',
  terminalPack: 'claude',
  lastTerminal: 'com.apple.Terminal',
  agentHomes: {},
  hiddenPacks: [],
  followMacApp: true,
  customHotkeys: [],
  keepAwake: true,
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
