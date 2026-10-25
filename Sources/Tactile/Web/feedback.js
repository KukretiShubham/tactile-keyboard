// Key sounds are synthesized with Web Audio (no audio files): a filtered noise
// "click" for the switch plus a short pitched "body" for the keycap. iPads have
// no vibration motor, so sound is the primary tactile cue; vibration is used
// where the browser supports it.

const PROFILES = {
  soft: { click: { freq: 2600, q: 0.9, decay: 0.022, gain: 0.55 }, body: { freq: 210, decay: 0.035, gain: 0.3 } },
  crisp: { click: { freq: 4800, q: 1.6, decay: 0.014, gain: 0.65 }, body: { freq: 340, decay: 0.022, gain: 0.18 } },
  thock: { click: { freq: 1300, q: 0.7, decay: 0.03, gain: 0.45 }, body: { freq: 120, decay: 0.07, gain: 0.6 } },
};

const TRACKPAD_CLICK = { click: { freq: 1900, q: 1.3, decay: 0.012, gain: 0.5 }, body: { freq: 150, decay: 0.025, gain: 0.35 } };

// Bigger keys sound lower, like the stabilised keys on a real keyboard.
const PITCH = { key: 1, mod: 1.1, wide: 0.86, space: 0.7 };

export class Feedback {
  #ctx = null;
  #out = null;
  #noise = null;

  constructor(settings) {
    this.settings = settings;
  }

  get canVibrate() {
    return typeof navigator.vibrate === 'function';
  }

  // Safari only allows audio to start inside a user gesture.
  unlock() {
    if (this.#ctx) {
      if (this.#ctx.state !== 'running') this.#ctx.resume();
      return;
    }
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return;
    try {
      // Mix with music already playing on the iPad instead of interrupting it.
      if (navigator.audioSession) navigator.audioSession.type = 'ambient';
    } catch { /* older Safari */ }

    const ctx = new AudioContext({ latencyHint: 'interactive' });
    const out = ctx.createGain();
    out.connect(ctx.destination);

    const length = Math.floor(ctx.sampleRate * 0.12);
    const noise = ctx.createBuffer(1, length, ctx.sampleRate);
    const samples = noise.getChannelData(0);
    for (let i = 0; i < length; i++) samples[i] = Math.random() * 2 - 1;

    const primer = ctx.createBufferSource();
    primer.buffer = ctx.createBuffer(1, 1, ctx.sampleRate);
    primer.connect(ctx.destination);
    primer.start();

    this.#ctx = ctx;
    this.#out = out;
    this.#noise = noise;
  }

  key(kind = 'key') {
    this.#vibrate(8);
    this.#play(PROFILES[this.settings.get('soundProfile')] ?? PROFILES.soft, PITCH[kind] ?? 1);
  }

  click() {
    this.#vibrate(12);
    this.#play(TRACKPAD_CLICK, 1);
  }

  preview() {
    this.unlock();
    this.key('key');
  }

  #vibrate(ms) {
    if (this.settings.get('vibration') && this.canVibrate) navigator.vibrate(ms);
  }

  #play(profile, pitch) {
    const ctx = this.#ctx;
    const volume = this.settings.get('volume');
    if (!this.settings.get('sound') || !ctx || volume <= 0) return;
    if (ctx.state !== 'running') {
      ctx.resume();
      return;
    }

    const t = ctx.currentTime;
    const jitter = 1 + (Math.random() - 0.5) * 0.1;
    this.#out.gain.setValueAtTime(volume, t);

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
    noise.connect(band).connect(clickGain).connect(this.#out);
    noise.start(t);
    noise.stop(t + click.decay + 0.02);

    const tone = ctx.createOscillator();
    tone.type = 'sine';
    tone.frequency.setValueAtTime(body.freq * pitch * jitter, t);
    tone.frequency.exponentialRampToValueAtTime(body.freq * pitch * 0.55, t + body.decay);
    const toneGain = ctx.createGain();
    toneGain.gain.setValueAtTime(body.gain, t);
    toneGain.gain.exponentialRampToValueAtTime(0.0001, t + body.decay);
    tone.connect(toneGain).connect(this.#out);
    tone.start(t);
    tone.stop(t + body.decay + 0.02);
  }
}
