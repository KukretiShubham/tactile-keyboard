// Key sounds are synthesized with Web Audio (no audio files). A real keystroke
// is mostly short noise, not a tone: a sharp tick as the switch actuates, a
// brief resonance from the plastic keycap, and a dull, pitchless thud as the
// key bottoms out. Each sound below is a few such layers of filtered noise
// with fast-decaying envelopes. (A pitched tone that slides down is how drum
// synths make a kick, which is what to avoid.) iPads have no vibration motor,
// so sound is the primary tactile cue; vibration is used where supported.

/**
 * A layer is noise through one filter with a fast decay:
 *   { filter: 'highpass' | 'bandpass' | 'lowpass', freq, q, gain, decay, delay? }
 * `freq` scales with the key's pitch; `delay` (seconds) offsets the layer.
 */
const PROFILES = {
  // Low-travel scissor keys, like a Magic Keyboard: a light tick and a muted body.
  soft: [
    { filter: 'highpass', freq: 2600, q: 0.7, gain: 0.55, decay: 0.004 },
    { filter: 'bandpass', freq: 1900, q: 5, gain: 0.32, decay: 0.016 },
    { filter: 'lowpass', freq: 520, q: 0.7, gain: 0.22, decay: 0.011 },
  ],
  // Clicky mechanical switch: a bright snap with a second click as it trips.
  crisp: [
    { filter: 'highpass', freq: 4200, q: 0.8, gain: 0.7, decay: 0.0025 },
    { filter: 'bandpass', freq: 3500, q: 7, gain: 0.38, decay: 0.012 },
    { filter: 'highpass', freq: 3200, q: 0.8, gain: 0.32, decay: 0.002, delay: 0.009 },
    { filter: 'lowpass', freq: 700, q: 0.7, gain: 0.18, decay: 0.009 },
  ],
  // Deep, muted mechanical keyboard: soft attack, low keycap ring, round thud.
  thock: [
    { filter: 'highpass', freq: 1800, q: 0.7, gain: 0.25, decay: 0.003 },
    { filter: 'bandpass', freq: 1050, q: 3.5, gain: 0.42, decay: 0.03 },
    { filter: 'lowpass', freq: 330, q: 0.8, gain: 0.45, decay: 0.024 },
  ],
};

// The quieter sound of a key coming back up.
const RELEASE = {
  soft: [{ filter: 'highpass', freq: 3200, q: 0.7, gain: 0.14, decay: 0.003 }],
  crisp: [
    { filter: 'highpass', freq: 4600, q: 0.8, gain: 0.34, decay: 0.002 },
    { filter: 'bandpass', freq: 3800, q: 6, gain: 0.16, decay: 0.008 },
  ],
  thock: [
    { filter: 'bandpass', freq: 1400, q: 3, gain: 0.2, decay: 0.014 },
    { filter: 'lowpass', freq: 450, q: 0.7, gain: 0.14, decay: 0.01 },
  ],
};

// A trackpad click, like a MacBook's: short, dry and dull, with no keycap ring.
const TRACKPAD_CLICK = [
  { filter: 'bandpass', freq: 1150, q: 1.4, gain: 0.55, decay: 0.006 },
  { filter: 'highpass', freq: 4500, q: 0.7, gain: 0.2, decay: 0.0015 },
  { filter: 'lowpass', freq: 260, q: 0.8, gain: 0.3, decay: 0.008 },
];

/**
 * Plays `layers` into `destination` at time `t`. Exported so the same sounds
 * can be rendered offline (for listening tests) as well as played live.
 */
export function voice(ctx, destination, noise, layers, t, pitch = 1) {
  const jitter = 1 + (Math.random() - 0.5) * 0.08;
  for (const layer of layers) {
    const start = t + (layer.delay ?? 0);
    const source = ctx.createBufferSource();
    source.buffer = noise;
    // Each key press uses a different stretch of noise, so repeats aren't identical.
    const offset = Math.random() * Math.max(0, noise.duration - 0.06);
    const filter = ctx.createBiquadFilter();
    filter.type = layer.filter;
    filter.frequency.value = layer.freq * pitch * jitter;
    filter.Q.value = layer.q;
    const envelope = ctx.createGain();
    envelope.gain.setValueAtTime(0.0001, start);
    envelope.gain.linearRampToValueAtTime(layer.gain, start + 0.0004);
    envelope.gain.exponentialRampToValueAtTime(0.0001, start + 0.0004 + layer.decay * 2.5);
    source.connect(filter).connect(envelope).connect(destination);
    source.start(start, offset);
    source.stop(start + layer.decay * 2.5 + 0.01);
  }
}

/** One buffer of white noise that every layer draws from. */
export function makeNoise(ctx) {
  const length = Math.floor(ctx.sampleRate * 0.5);
  const noise = ctx.createBuffer(1, length, ctx.sampleRate);
  const samples = noise.getChannelData(0);
  for (let i = 0; i < length; i++) samples[i] = Math.random() * 2 - 1;
  return noise;
}

export const SOUNDS = { PROFILES, RELEASE, TRACKPAD_CLICK };

// Bigger keys sound lower, like the stabilised keys on a real keyboard.
const PITCH = { key: 1, mod: 1.1, wide: 0.86, space: 0.7 };

// How far left/right a key at the keyboard's edge sounds (-1…1).
const STEREO_WIDTH = 0.55;

// Clicks this short are quiet on iPad speakers; a compressor lets them be
// louder without distorting when several keys sound at once.
const MAKEUP_GAIN = 2.2;

/**
 * Safari lets audio start only inside certain user actions: a finger lifting
 * (pointerup/touchend), a click, or a key press — not a finger touching down.
 * Call `unlock()` from those; the `state` event reports when sound is ready
 * (or still waiting for a tap).
 */
export class Feedback extends EventTarget {
  #ctx = null;
  #out = null;
  #noise = null;

  constructor(settings) {
    super();
    this.settings = settings;
    settings.subscribe((key) => {
      if (key === 'soundInSilentMode') this.#applySession();
      if (key === 'sound') this.#announce();
    });
  }

  get canVibrate() {
    return typeof navigator.vibrate === 'function';
  }

  /** True when sound is on but Safari hasn't let it start yet. */
  get needsTap() {
    return Boolean(this.settings.get('sound')) && this.#ctx?.state !== 'running';
  }

  unlock() {
    if (!this.#ctx) this.#create();
    const ctx = this.#ctx;
    if (!ctx || ctx.state === 'running') return;
    ctx.resume().then(() => this.#announce(), () => this.#announce());
    // Starting a (silent) sound inside the user action is what actually
    // unlocks audio on older iOS versions.
    const primer = ctx.createBufferSource();
    primer.buffer = ctx.createBuffer(1, 1, ctx.sampleRate);
    primer.connect(ctx.destination);
    primer.start();
  }

  /**
   * A key going down. `position` is where the key sits across the keyboard,
   * from -1 (left edge) to 1 (right edge), so its sound comes from that side.
   */
  key(kind = 'key', position = 0) {
    this.#vibrate(8);
    this.#play(PROFILES[this.settings.get('soundProfile')] ?? PROFILES.soft, PITCH[kind] ?? 1, position);
  }

  /** The key coming back up; `delay` (seconds) for keys typed on release. */
  keyUp(kind = 'key', position = 0, delay = 0) {
    this.#play(RELEASE[this.settings.get('soundProfile')] ?? RELEASE.soft, PITCH[kind] ?? 1, position, delay);
  }

  click() {
    this.#vibrate(12);
    this.#play(TRACKPAD_CLICK, 1);
  }

  /** Plays a sample key sound; call from a tap (it also unlocks audio). */
  preview() {
    this.unlock();
    const play = () => this.key('key');
    if (this.#ctx?.state === 'running') play();
    else this.#ctx?.resume().then(play, () => {});
  }

  #create() {
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return;
    this.#applySession();

    const ctx = new AudioContext({ latencyHint: 'interactive' });
    const compressor = ctx.createDynamicsCompressor();
    compressor.threshold.value = -12;
    compressor.ratio.value = 6;
    compressor.attack.value = 0.001;
    compressor.release.value = 0.08;
    const out = ctx.createGain();
    out.connect(compressor).connect(ctx.destination);

    const noise = makeNoise(ctx);

    ctx.addEventListener('statechange', () => this.#announce());
    this.#ctx = ctx;
    this.#out = out;
    this.#noise = noise;
  }

  // "ambient" mixes with music already playing but follows Silent Mode;
  // "playback" plays in Silent Mode but pauses other audio.
  #applySession() {
    try {
      if (navigator.audioSession) {
        navigator.audioSession.type = this.settings.get('soundInSilentMode') ? 'playback' : 'ambient';
      }
    } catch { /* not supported by this Safari */ }
  }

  #announce() {
    this.dispatchEvent(new Event('state'));
  }

  #vibrate(ms) {
    if (this.settings.get('vibration') && this.canVibrate) navigator.vibrate(ms);
  }

  #play(layers, pitch, position = 0, delay = 0) {
    const ctx = this.#ctx;
    const volume = this.settings.get('volume');
    if (!this.settings.get('sound') || !ctx || ctx.state !== 'running' || volume <= 0) return;
    this.#out.gain.setValueAtTime(volume * MAKEUP_GAIN, ctx.currentTime);

    // Place the sound left-to-right like the key on the keyboard.
    let destination = this.#out;
    if (ctx.createStereoPanner && position) {
      const pan = ctx.createStereoPanner();
      pan.pan.value = Math.max(-1, Math.min(1, position)) * STEREO_WIDTH;
      pan.connect(this.#out);
      destination = pan;
    }
    voice(ctx, destination, this.#noise, layers, ctx.currentTime + delay, pitch);
  }
}
