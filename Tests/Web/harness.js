// A tiny, dependency-free test harness for the iPad web app. Test files call
// `test(name, fn)`; `run()` executes them in order and reports the results on
// the page and as `window.__results` (read by `swift run tactile-checks`).

const tests = [];

export function test(name, fn) {
  tests.push({ name, fn });
}

export class AssertionError extends Error {}

export function expect(condition, message) {
  if (!condition) throw new AssertionError(message);
}

export function expectEqual(actual, expected, message) {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new AssertionError(`${message}: expected ${b}, got ${a}`);
}

/**
 * Resolves after `ms`. The timer is started from a fresh task: WebKit slows
 * long chains of timers (each started from the last) to once a second.
 */
export const wait = (ms) => new Promise((resolve) => {
  const channel = new MessageChannel();
  channel.port1.onmessage = () => setTimeout(resolve, ms);
  channel.port2.postMessage(null);
});

/** Dispatches a touch-style pointer event at the centre of `el`. */
export function touch(el, type, pointerId, { primary = true, dx = 0, dy = 0 } = {}) {
  const r = el.getBoundingClientRect();
  el.dispatchEvent(new PointerEvent(type, {
    bubbles: true,
    cancelable: true,
    clientX: r.left + r.width / 2 + dx,
    clientY: r.top + r.height / 2 + dy,
    pointerId,
    pointerType: 'touch',
    isPrimary: primary,
  }));
}

/** Settings stand-in: defaults plus overrides, with no storage. */
export function fakeSettings(overrides = {}) {
  const values = {
    sound: false, restFingers: false, keyPopups: false, adaptiveTyping: false,
    soundProfile: 'soft', volume: 0, vibration: false, tracking: 1, scrollSpeed: 1,
    naturalScroll: true, pinchZoom: true, threeFingerDrag: false, ...overrides,
  };
  const listeners = new Set();
  return {
    get: (key) => values[key],
    set: (key, value) => { values[key] = value; listeners.forEach((listener) => listener(key, value)); },
    subscribe: (listener) => listeners.add(listener),
  };
}

/** Storage stand-in that keeps values in memory. */
export function memoryStorage() {
  const values = new Map();
  return { get: (key) => values.get(key) ?? null, set: (key, value) => values.set(key, value), remove: (key) => values.delete(key) };
}

/** Feedback stand-in that makes no sound. */
export const silentFeedback = { key() {}, keyUp() {}, click() {} };

export async function run() {
  const results = [];
  for (const { name, fn } of tests) {
    const sandbox = document.createElement('div');
    sandbox.className = 'sandbox';
    document.body.append(sandbox);
    try {
      await fn(sandbox);
      results.push({ name, passed: true });
    } catch (error) {
      results.push({ name, passed: false, message: String(error?.message ?? error) });
    } finally {
      sandbox.remove();
    }
  }
  const list = document.getElementById('results');
  for (const r of results) {
    const item = document.createElement('li');
    item.textContent = `${r.passed ? 'PASS' : 'FAIL'}  ${r.name}${r.message ? ` — ${r.message}` : ''}`;
    item.className = r.passed ? 'pass' : 'fail';
    list.append(item);
  }
  window.__results = results;
  return results;
}
