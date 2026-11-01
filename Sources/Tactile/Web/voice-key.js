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
 * state survives the keys being redrawn. `onSettled` runs when a finger lifts;
 * each function in `watchers` runs whenever the state shown changes.
 */
export function createVoiceState(send) {
  return {
    send,
    state: 'idle',
    press: null, // { held, at, pressedIn, pointerId, overCancel, cancelled } while a finger is down
    lastTapEnded: -Infinity,
    onSettled: () => {},
    watchers: new Set(),
    changed() {
      this.watchers.forEach((watch) => watch());
    },
    /** What the keys show: 'idle', 'listening' or 'handsfree'. */
    shown() {
      if (!this.press || this.press.cancelled) return this.state;
      return this.press.pressedIn === 'handsfree' ? 'idle' : 'listening';
    },
    /** Esc was pressed (here or on the keyboard), which stops Granola listening. */
    cancelled() {
      this.lastTapEnded = -Infinity;
      if (this.press) this.press.cancelled = true;
      else if (this.state === 'idle') return;
      this.state = 'idle';
      this.changed();
    },
    /** Lets go of the dictation key, e.g. when the iPad looks away. */
    release() {
      if (!this.press) return;
      [...this.press.held].reverse().forEach((code) => this.send({ t: 'ku', k: code }));
      this.press = null;
      this.state = 'idle';
      this.changed();
      this.onSettled();
    },
  };
}

/**
 * Draws a Voice Typing key. `keys()` gives the dictation key to hold (from
 * Settings), `logo` is Granola's icon from the Mac, if known, `target()` names
 * the app the words will go into, and `position` places its sound (-1 left to
 * 1 right). With `slideToCancel`, a Cancel key sits nearby (see shortcuts.js):
 * letting go over it presses Esc before the dictation key lifts, so Granola
 * throws the words away instead of pasting them.
 */
export function createVoiceKey(voice, { feedback, keys, logo, target = () => null, slideToCancel = false, position = 0 }) {
  const title = el('span', { className: 'voice-title' });
  const hint = el('span', { className: 'voice-hint' });
  const cap = el('span', { className: 'voice-cap' });
  const wave = el('span', { className: 'voice-wave', attrs: { 'aria-hidden': 'true' } },
    ...WAVE.map((height, index) => el('i', { className: height ? '' : 'dot', style: { '--h': height, '--i': index } })));
  const key = el('button', { className: 'shortcut voice-key', attrs: { 'aria-label': 'Voice Typing (Granola)' } },
    el('span', { className: 'voice-logo' }, ...(logo ? [el('img', { attrs: { src: logo, alt: '' } })] : [])),
    wave, el('span', { className: 'voice-words' }, title, hint), cap);

  // The hint names the app the words will land in, when the Mac has said.
  function showHint(shown) {
    const app = target();
    const named = (before, after = '') => hint.replaceChildren(before, el('b', { className: 'voice-target', text: app }), after);
    if (shown === 'idle' && app) named('Hold to talk · into ');
    else if (shown === 'listening' && app) named('Release to paste into ', slideToCancel ? ' · slide to ✕ to cancel' : '');
    else hint.textContent = WORDS[shown][1];
  }

  function show() {
    const shown = voice.shown();
    key.dataset.state = shown;
    title.textContent = WORDS[shown][0];
    showHint(shown);
    cap.textContent = voiceKeyLabel(keys());
    key.setAttribute('aria-pressed', shown !== 'idle');
  }
  voice.watchers.add(show);

  key.addEventListener('pointerdown', (event) => {
    event.preventDefault();
    if (voice.press) return;
    try { key.setPointerCapture(event.pointerId); } catch { /* touch already ended */ }
    voice.press = { held: keys(), at: performance.now(), pressedIn: voice.state, pointerId: event.pointerId };
    voice.press.held.forEach((code) => voice.send({ t: 'kd', k: code }));
    feedback.key('mod', position);
    voice.changed();
  });

  // Sliding onto the Cancel key arms it; sliding back off disarms it.
  key.addEventListener('pointermove', (event) => {
    const press = voice.press;
    if (!slideToCancel || !press || event.pointerId !== press.pointerId) return;
    const over = Boolean(document.elementFromPoint(event.clientX, event.clientY)?.closest('[data-voice-cancel]'));
    if (over === Boolean(press.overCancel)) return;
    press.overCancel = over;
    voice.changed();
  });

  const up = (event) => {
    const press = voice.press;
    if (!press || event.pointerId !== press.pointerId) return;
    voice.press = null;
    const cancel = press.overCancel && event.type === 'pointerup';
    if (cancel) voice.send({ t: 'combo', ks: ['Escape'] });
    [...press.held].reverse().forEach((code) => voice.send({ t: 'ku', k: code }));
    feedback.keyUp('mod', position);
    const now = performance.now();
    const duration = now - press.at;
    if (cancel || press.cancelled) {
      voice.state = 'idle';
      voice.lastTapEnded = -Infinity;
    } else {
      voice.state = stateAfterPress(press.pressedIn, duration, now - voice.lastTapEnded);
      // A lone tap may be the first of a double-tap.
      voice.lastTapEnded = duration < TAP && press.pressedIn === 'idle' && voice.state === 'idle' ? now : -Infinity;
    }
    voice.changed();
    voice.onSettled();
  };
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) key.addEventListener(type, up);

  show();
  return key;
}
