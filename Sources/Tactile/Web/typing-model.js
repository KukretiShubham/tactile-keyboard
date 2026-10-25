// Learns where your fingers actually land on each key and shifts each key's
// touch area toward that spot, like Apple's own keyboard does. Offsets are
// fractions of a key's size, so they survive resizing and rotation.

const STORAGE_KEY = 'tactile.typing.v1';
// How quickly the model adapts (weight of each new touch).
const RATE = 0.08;
// Touches needed on a key before its offset is used.
const MIN_SAMPLES = 6;
// Never move a key's centre more than this far (a fraction of its size).
const MAX_OFFSET = 0.3;

export class TypingModel {
  #keys;
  #storage;
  #last = null;

  /** `storage` has get(key) and set(key, value); tests pass an in-memory one. */
  constructor(storage) {
    this.#storage = storage;
    try {
      this.#keys = JSON.parse(storage.get(STORAGE_KEY) || '{}');
    } catch {
      this.#keys = {};
    }
  }

  /** Where `code`'s touch area is centred, relative to the key's middle. */
  offset(code) {
    const key = this.#keys[code];
    return key && key.n >= MIN_SAMPLES ? { x: key.x, y: key.y } : { x: 0, y: 0 };
  }

  /** Records that a touch at (`fx`, `fy`) from the key's middle typed `code`. */
  record(code, fx, fy) {
    const before = this.#keys[code] ?? { x: 0, y: 0, n: 0 };
    const clampOffset = (value) => Math.max(-MAX_OFFSET, Math.min(MAX_OFFSET, value));
    // Average the first few touches evenly, then follow habits gradually.
    const weight = Math.max(RATE, 1 / (before.n + 1));
    this.#keys[code] = {
      x: clampOffset(before.x + (fx - before.x) * weight),
      y: clampOffset(before.y + (fy - before.y) * weight),
      n: before.n + 1,
    };
    this.#last = { code, before };
    this.#save();
  }

  /** Takes back the latest touch, e.g. when it was immediately deleted. */
  forgetLast() {
    if (!this.#last) return;
    const { code, before } = this.#last;
    if (before.n === 0) delete this.#keys[code];
    else this.#keys[code] = before;
    this.#last = null;
    this.#save();
  }

  reset() {
    this.#keys = {};
    this.#last = null;
    this.#save();
  }

  #save() {
    this.#storage.set(STORAGE_KEY, JSON.stringify(this.#keys));
  }
}

/**
 * The key a touch at (`x`, `y`) means. Each key's distance is measured in
 * units of its own half-size from its (learned) centre, so a touch inside a
 * key always picks that key until learning shifts it, and a touch in a gap
 * picks the nearest key. Returns null when no key is close.
 */
export function pickKey(x, y, candidates, offsetOf) {
  let best = null;
  let bestScore = Infinity;
  for (const { code, rect } of candidates) {
    const offset = offsetOf(code);
    const cx = rect.left + rect.width * (0.5 + offset.x);
    const cy = rect.top + rect.height * (0.5 + offset.y);
    const score = Math.max(Math.abs(x - cx) / (rect.width / 2), Math.abs(y - cy) / (rect.height / 2));
    if (score < bestScore) {
      bestScore = score;
      best = code;
    }
  }
  // Within the key, or in the gap just around it.
  return bestScore <= 1.6 ? best : null;
}
