// Preferences live only on this iPad. Storage can be unavailable (private
// browsing), so every access is guarded and defaults always apply.
import { DEFAULT_SHORTCUTS } from './shortcuts.js';
import { storage } from './util.js';
import { DEFAULT_VOICE_KEYS } from './voice-key.js';

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
  // 'touchbar', 'keys' (F1–F12) or 'off'.
  functionRow: 'touchbar',
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
  voiceTypingKeys: DEFAULT_VOICE_KEYS,
  voiceTypingLeft: true,
  followMacApp: true,
  customHotkeys: [],
  keepAwake: true,
  // What the Touch Bar shows.
  agentClaude: true,
  agentCodex: true,
  agentUsage: true,
};


/** Saved settings from older versions, in today's form. */
export function upgrade(saved) {
  // The function row used to be on or off; on becomes the Touch Bar, which
  // still has F1–F12 under fn.
  if (typeof saved.functionRow === 'boolean') saved.functionRow = saved.functionRow ? 'touchbar' : 'off';
  return saved;
}

function load() {
  try {
    return { ...DEFAULTS, ...upgrade(JSON.parse(storage.get(KEY) || '{}')) };
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
