// The Voice Typing key, for Granola's voice typing: it holds your dictation
// key down on the Mac for as long as your finger is on it. Granola does the
// rest (hold to talk, double-tap for hands-free, press again to stop), and the
// key mirrors that so you can see what Granola is doing.
import { comboGlyph } from './keys.js';
import { el } from './util.js';

/** Granola's default dictation key. People who changed it set theirs in Settings. */
export const DEFAULT_VOICE_KEYS = ['Fn'];

// A press shorter than this is a tap; two taps this close together start
// hands-free, as in Granola.
const TAP = 300;
const DOUBLE_TAP = 400;

const KEY_WORDS = {
  Fn: 'fn', ControlLeft: 'control', ControlRight: 'control', AltLeft: 'option', AltRight: 'option',
  MetaLeft: 'command', MetaRight: 'command', ShiftLeft: 'shift', ShiftRight: 'shift',
};

/** How the key is named on the Voice Typing key, e.g. "fn", "control" or "⌥Space". */
export function voiceKeyLabel(keys) {
  return keys.length === 1 && KEY_WORDS[keys[0]] ? KEY_WORDS[keys[0]] : comboGlyph(keys.filter((key) => key !== 'Fn'));
}

/**
 * Granola's state after a press: `pressedIn` is the state when the finger
 * went down, `duration` how long it stayed, `sinceLastTap` how long since the
 * previous tap ended. Returns 'idle' or 'handsfree'.
 */
export function stateAfterPress(pressedIn, duration, sinceLastTap) {
  if (pressedIn === 'handsfree') return 'idle'; // pressing again stops hands-free
  return duration < TAP && sinceLastTap < DOUBLE_TAP ? 'handsfree' : 'idle';
}

const WAVE = [0, 0, 1, 0, 2, 3, 1, 2, 4, 2, 1, 0, 3, 1, 0, 0];
const WORDS = {
  idle: ['Voice Typing', 'Hold to talk · double-tap for hands-free'],
  listening: ['Listening…', 'Release to paste'],
  handsfree: ['Hands-free', 'Tap to stop'],
};

/**
 * What Granola is doing, shared by every Voice Typing key on screen, so the
 * state survives the keys being redrawn. `onSettled` runs when a finger lifts.
 */
export function createVoiceState(send) {
  return {
    send,
    state: 'idle',
    press: null, // { held, at, pressedIn, pointerId } while a finger is down
    lastTapEnded: -Infinity,
    onSettled: () => {},
    /** Lets go of the dictation key, e.g. when the iPad looks away. */
    release() {
      if (!this.press) return;
      [...this.press.held].reverse().forEach((code) => this.send({ t: 'ku', k: code }));
      this.press = null;
      this.state = 'idle';
      this.onSettled();
    },
  };
}

/**
 * Draws a Voice Typing key. `keys()` gives the dictation key to hold (from
 * Settings), `logo` is Granola's icon from the Mac, if known, and `position`
 * places its sound (-1 left to 1 right).
 */
export function createVoiceKey(voice, { feedback, keys, logo, position = 0 }) {
  const title = el('span', { className: 'voice-title' });
  const hint = el('span', { className: 'voice-hint' });
  const cap = el('span', { className: 'voice-cap' });
  const wave = el('span', { className: 'voice-wave', attrs: { 'aria-hidden': 'true' } },
    ...WAVE.map((height, index) => el('i', { className: height ? '' : 'dot', style: { '--h': height, '--i': index } })));
  const key = el('button', { className: 'shortcut voice-key', attrs: { 'aria-label': 'Voice Typing (Granola)' } },
    el('span', { className: 'voice-logo' }, ...(logo ? [el('img', { attrs: { src: logo, alt: '' } })] : [])),
    wave, el('span', { className: 'voice-words' }, title, hint), cap);

  function show() {
    const shown = voice.press ? (voice.press.pressedIn === 'handsfree' ? 'idle' : 'listening') : voice.state;
    key.dataset.state = shown;
    title.textContent = WORDS[shown][0];
    hint.textContent = WORDS[shown][1];
    cap.textContent = voiceKeyLabel(keys());
    key.setAttribute('aria-pressed', shown !== 'idle');
  }

  key.addEventListener('pointerdown', (event) => {
    event.preventDefault();
    if (voice.press) return;
    try { key.setPointerCapture(event.pointerId); } catch { /* touch already ended */ }
    voice.press = { held: keys(), at: performance.now(), pressedIn: voice.state, pointerId: event.pointerId };
    voice.press.held.forEach((code) => voice.send({ t: 'kd', k: code }));
    feedback.key('mod', position);
    show();
  });

  const up = (event) => {
    const press = voice.press;
    if (!press || event.pointerId !== press.pointerId) return;
    voice.press = null;
    [...press.held].reverse().forEach((code) => voice.send({ t: 'ku', k: code }));
    feedback.keyUp('mod', position);
    const now = performance.now();
    const duration = now - press.at;
    voice.state = stateAfterPress(press.pressedIn, duration, now - voice.lastTapEnded);
    // A lone tap may be the first of a double-tap.
    voice.lastTapEnded = duration < TAP && press.pressedIn === 'idle' && voice.state === 'idle' ? now : -Infinity;
    show();
    voice.onSettled();
  };
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) key.addEventListener(type, up);

  show();
  return key;
}
