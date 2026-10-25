// Key sounds are synthesized with Web Audio (no audio files): a filtered noise
// "click" for the switch plus a short pitched "body" for the keycap. iPads have
// no vibration motor, so sound is the primary tactile cue; vibration is used
// where the browser supports it.

const PROFILES = {
  soft: { click: { freq: 2600, q: 0.9, decay: 0.022, gain: 0.55 }, body: { freq: 210, decay: 0.035, gain: 0.3 } },
  crisp: { click: { freq: 4800, q: 1.6, decay: 0.014, gain: 0.65 }, body: { freq: 340, decay: 0.022, gain: 0.18 } },
  thock: { click: { freq: 1300, q: 0.7, decay: 0.03, gain: 0.45 }, body: { freq: 120, decay: 0.07, gain: 0.6 } },
};

// The softer second click a mechanical switch makes as the key comes back up.
const RELEASE = {
  soft: { click: { freq: 3400, q: 1.2, decay: 0.01, gain: 0.12 } },
  crisp: { click: { freq: 6200, q: 2, decay: 0.009, gain: 0.32 } },
  thock: { click: { freq: 1900, q: 0.9, decay: 0.016, gain: 0.26 }, body: { freq: 180, decay: 0.02, gain: 0.15 } },
};

const TRACKPAD_CLICK = { click: { freq: 1900, q: 1.3, decay: 0.012, gain: 0.5 }, body: { freq: 150, decay: 0.025, gain: 0.35 } };

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

    const length = Math.floor(ctx.sampleRate * 0.12);
    const noise = ctx.createBuffer(1, length, ctx.sampleRate);
    const samples = noise.getChannelData(0);
    for (let i = 0; i < length; i++) samples[i] = Math.random() * 2 - 1;

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

  #play(profile, pitch, position = 0, delay = 0) {
    const ctx = this.#ctx;
    const volume = this.settings.get('volume');
    if (!this.settings.get('sound') || !ctx || ctx.state !== 'running' || volume <= 0) return;

    const t = ctx.currentTime + delay;
    const jitter = 1 + (Math.random() - 0.5) * 0.1;
    this.#out.gain.setValueAtTime(volume * MAKEUP_GAIN, ctx.currentTime);

    // Place the sound left-to-right like the key on the keyboard.
    let destination = this.#out;
    if (ctx.createStereoPanner && position) {
      const pan = ctx.createStereoPanner();
      pan.pan.value = Math.max(-1, Math.min(1, position)) * STEREO_WIDTH;
      pan.connect(this.#out);
      destination = pan;
    }

    const { click, body } = profile;
    const noise = ctx.createBufferSource();
    noise.buffer = this.#noise;
    const band = ctx.createBiquadFilter();
    band.type = 'bandpass';
    band.frequency.value = click.freq * pitch * jitter;
    band.Q.value = click.q;
    const clickGain = ctx.createGain();
    clickGain.gain.setValueAtTime(click.gain, t);
    clickGain.gain.exponentialRampToValueAtTime(0.0001, t + click.decay);
    noise.connect(band).connect(clickGain).connect(destination);
    noise.start(t);
    noise.stop(t + click.decay + 0.02);

    if (!body) return;
    const tone = ctx.createOscillator();
    tone.type = 'sine';
    tone.frequency.setValueAtTime(body.freq * pitch * jitter, t);
    tone.frequency.exponentialRampToValueAtTime(body.freq * pitch * 0.55, t + body.decay);
    const toneGain = ctx.createGain();
    toneGain.gain.setValueAtTime(body.gain, t);
    toneGain.gain.exponentialRampToValueAtTime(0.0001, t + body.decay);
    tone.connect(toneGain).connect(destination);
    tone.start(t);
    tone.stop(t + body.decay + 0.02);
  }
}
