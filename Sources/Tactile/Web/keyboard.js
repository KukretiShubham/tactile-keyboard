// Multi-touch typing on the keys drawn by keys.js. Modifiers behave like the
// iPad's own keyboard: hold for a chord, tap to apply to the next key,
// double-tap to lock.
import { applyLabels, buildKeys, characterOf, FN_LAYER, soundKind } from './keys.js';
import { pickKey } from './typing-model.js';
import { clamp, el } from './util.js';

const NO_REPEAT = new Set(['Escape', 'Enter', 'Tab']);
const REPEAT_DELAY = 450;
const REPEAT_INTERVAL = 55;
// A held key never repeats longer than this, even if its finger-lift is lost.
const REPEAT_LIMIT = 10000;
const DOUBLE_TAP = 350;
// With "Rest Fingers on Keys", a touch held longer than this is a resting
// finger, not a keystroke.
const REST_TIME = 350;
// A key deleted this soon after it was typed was probably a miss, so typing
// learning forgets that touch.
const UNDO_WINDOW = 1200;

const isCharacter = (def) => def.kind === 'letter' || def.kind === 'pair';

/**
 * Builds the keyboard in `root` and handles typing on it. `model` (a
 * TypingModel) is optional; with it and "Adapt to My Typing" on, each key's
 * touch area follows where you actually press it.
 */
export function createKeyboard(root, { send, feedback, settings, model = null }) {
  const keys = buildKeys(root);
  const { defs, elements } = keys;
  const presses = new Map(); // pointerId → active press
  const mods = new Map(); // code → { state: 'held' | 'latched' | 'locked', used, tappedAt }
  let capsLock = false;
  let pressOrder = 0;
  let learnedAt = 0;

  // Typing keys wait for the finger to lift; delete and arrows stay immediate
  // so holding them still repeats.
  const typesOnLift = (def) =>
    settings.get('restFingers') &&
    ['letter', 'pair', 'space', 'word'].includes(def.kind) &&
    def.code !== 'Backspace';

  const isOn = (code) => mods.has(code);
  const fnActive = () => isOn('Fn');
  const shiftActive = () => isOn('ShiftLeft') || isOn('ShiftRight');
  const learning = () => model && settings.get('adaptiveTyping');

  function paintModifier(code) {
    const key = elements.get(code);
    const state = mods.get(code)?.state;
    key?.classList.toggle('on', Boolean(state));
    key?.classList.toggle('locked', state === 'locked');
  }

  function engage(def) {
    mods.set(def.code, { state: 'held', used: false, tappedAt: 0 });
    if (!def.local) send({ t: 'kd', k: def.code });
    paintModifier(def.code);
  }

  function release(code) {
    if (!mods.delete(code)) return;
    if (code !== 'Fn') send({ t: 'ku', k: code });
    paintModifier(code);
  }

  function releaseLatched() {
    for (const [code, mod] of mods) if (mod.state === 'latched') release(code);
  }

  function modifierDown(def) {
    const mod = mods.get(def.code);
    if (!mod) return engage(def);
    if (mod.state === 'latched' && performance.now() - mod.tappedAt < DOUBLE_TAP) {
      mod.state = 'locked';
      paintModifier(def.code);
      return;
    }
    release(def.code);
  }

  function modifierUp(def) {
    const mod = mods.get(def.code);
    if (mod?.state !== 'held') return;
    if (mod.used) {
      release(def.code);
    } else {
      mod.state = 'latched';
      mod.tappedAt = performance.now();
      paintModifier(def.code);
    }
  }

  function keyDown(def, { repeat = true } = {}) {
    for (const mod of mods.values()) mod.used = true;

    if (def.sys && !fnActive()) {
      send({ t: 'sys', k: def.sys });
      return {};
    }
    const code = (fnActive() && FN_LAYER[def.code]) || def.code;
    if (code === 'Backspace' && performance.now() - learnedAt < UNDO_WINDOW) model?.forgetLast();
    const addShift = capsLock && def.kind === 'letter' && !shiftActive();
    if (addShift) send({ t: 'kd', k: 'ShiftLeft' });
    send({ t: 'kd', k: code });

    const press = { code, addShift, stopRepeat() {} };
    if (repeat && !NO_REPEAT.has(code) && def.kind !== 'fkey') {
      // Repeats only while this exact press is still held (see `isHeld`), and
      // never for longer than REPEAT_LIMIT, so a lost finger-lift can't leave a
      // key repeating forever.
      const started = performance.now();
      let interval = 0;
      const delay = setTimeout(() => {
        interval = setInterval(() => {
          if (!isHeld(press) || performance.now() - started > REPEAT_LIMIT) return press.stopRepeat();
          send({ t: 'kd', k: code, r: true });
        }, REPEAT_INTERVAL);
      }, REPEAT_DELAY);
      press.stopRepeat = () => {
        clearTimeout(delay);
        clearInterval(interval);
      };
    }
    return press;
  }

  const isHeld = (press) => [...presses.values()].includes(press);

  function keyUp(press) {
    press.stopRepeat();
    send({ t: 'ku', k: press.code });
    if (press.addShift) send({ t: 'ku', k: 'ShiftLeft' });
    releaseLatched();
  }

  // Where a key sits across the keyboard, from -1 (left) to 1 (right), so its
  // sound comes from that side.
  function positionOf(key) {
    const deck = root.getBoundingClientRect();
    const r = key.getBoundingClientRect();
    return ((r.left + r.width / 2 - deck.left) / deck.width) * 2 - 1;
  }

  // Remembers where on a character key the finger landed.
  function learn(press) {
    if (!learning() || !isCharacter(press.def)) return;
    const r = press.el.getBoundingClientRect();
    model.record(press.def.code, (press.x - r.left) / r.width - 0.5, (press.y - r.top) / r.height - 0.5);
    learnedAt = performance.now();
  }

  // A bubble above the finger showing the character, since the finger covers
  // the key itself. Letters and symbols only, like the iPhone keyboard.
  const popups = new Map(); // pointerId → element
  function showPopup(pointerId, key, def) {
    if (!settings.get('keyPopups') || !isCharacter(def)) return;
    const r = key.getBoundingClientRect();
    const width = Math.max(r.width * 1.25, 52);
    const height = Math.max(r.height * 1.15, 56);
    const popup = el('div', {
      className: 'key-popup',
      text: characterOf(def, { shifted: shiftActive() || (capsLock && def.kind === 'letter') }),
      style: {
        width: `${width}px`,
        height: `${height}px`,
        left: `${clamp(r.left + r.width / 2 - width / 2, 4, innerWidth - width - 4)}px`,
        top: `${Math.max(r.top - height - 8, 4)}px`,
      },
    });
    document.body.append(popup);
    hidePopup(pointerId);
    popups.set(pointerId, popup);
  }
  function hidePopup(pointerId) {
    popups.get(pointerId)?.remove();
    popups.delete(pointerId);
  }

  // Types a key that was waiting for its finger to lift.
  function commit(press) {
    press.committed = true;
    const kind = soundKind(press.def);
    const position = positionOf(press.el);
    feedback.key(kind, position);
    feedback.keyUp(kind, position, 0.045);
    learn(press);
    const sent = keyDown(press.def, { repeat: false });
    if (sent.code) keyUp(sent);
    else releaseLatched();
  }

  // When fingers roll from one key to the next, the earlier key can lift
  // second. Type any shorter-held keys pressed before this one first, so
  // letters come out in the order they were pressed.
  function commitEarlier(press, now) {
    const earlier = [...presses.values()]
      .filter((other) => other.deferred && !other.committed && other.order < press.order && now - other.at < REST_TIME)
      .sort((a, b) => a.order - b.order);
    earlier.forEach(commit);
  }

  // The key a touch means. A touch in the gap between keys (or on the frame)
  // goes to the closest key, so near-misses still type. With learning on,
  // every key's area is shifted toward where you usually press it.
  function keyAt(event) {
    const direct = event.target.closest('.key');
    if (direct && !learning()) return direct;
    const candidates = [...elements].map(([code, key]) => ({ code, rect: key.getBoundingClientRect() }));
    const offsetOf = (code) => (learning() && isCharacter(defs.get(elements.get(code))) ? model.offset(code) : { x: 0, y: 0 });
    const code = pickKey(event.clientX, event.clientY, candidates, offsetOf);
    return code ? elements.get(code) : null;
  }

  root.addEventListener('pointerdown', (event) => {
    // The floating keyboard's handle and grip move it; they never type.
    if (event.target.closest('.float-handle, .float-grip')) return;
    const key = keyAt(event);
    if (!key) return;
    event.preventDefault();
    // Safari can reuse a touch's ID; finish anything still recorded under it.
    if (presses.has(event.pointerId)) end(event);
    try { key.setPointerCapture(event.pointerId); } catch { /* touch already ended */ }
    const def = defs.get(key);
    key.classList.add('pressed');
    showPopup(event.pointerId, key, def);
    const touch = { el: key, def, x: event.clientX, y: event.clientY };

    if (typesOnLift(def)) {
      presses.set(event.pointerId, { ...touch, deferred: true, at: performance.now(), order: ++pressOrder });
      return;
    }

    const kind = soundKind(def);
    const position = positionOf(key);
    feedback.key(kind, position);
    let press;
    if (def.kind === 'mod') {
      modifierDown(def);
      press = { modifier: def };
    } else if (def.kind === 'caps') {
      capsLock = !capsLock;
      key.classList.toggle('locked', capsLock);
      press = {};
    } else {
      learn(touch);
      press = keyDown(def);
    }
    // Store this same object (not a copy): its repeat checks it's still held.
    presses.set(event.pointerId, Object.assign(press, touch, { sound: { kind, position } }));
  });

  function end(event) {
    const press = presses.get(event.pointerId);
    if (!press) return;
    presses.delete(event.pointerId);
    press.el.classList.remove('pressed');
    hidePopup(event.pointerId);
    if (press.sound) feedback.keyUp(press.sound.kind, press.sound.position);
    if (press.deferred) {
      const now = performance.now();
      if (!press.committed && event.type === 'pointerup' && now - press.at < REST_TIME) {
        commitEarlier(press, now);
        commit(press);
      }
    } else if (press.modifier) modifierUp(press.modifier);
    else if (press.code) keyUp(press);
    else if (press.def.kind !== 'caps') releaseLatched();
  }
  // Listen on the whole window, so a finger that slides off the keyboard
  // before lifting still ends its key; losing the touch counts as lifting it.
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
    window.addEventListener(type, end, { capture: true });
  }

  // A hardware keyboard attached to the iPad is forwarded as-is.
  const typingInField = (event) => event.target.closest?.('input, textarea');
  for (const [type, t, pressed] of [['keydown', 'kd', true], ['keyup', 'ku', false]]) {
    document.addEventListener(type, (event) => {
      if (typingInField(event) || !event.code) return;
      event.preventDefault();
      send({ t, k: event.code, r: (pressed && event.repeat) || undefined });
      elements.get(event.code)?.classList.toggle('pressed', pressed);
    });
  }

  return {
    releaseLatched,
    /** Shows the Mac's keyboard layout on the keys (see keys.js `applyLabels`). */
    setLabels: (labels) => applyLabels(keys, labels),
    /** Forget all local key state; the Mac side is released separately. */
    reset() {
      for (const press of presses.values()) {
        press.stopRepeat?.();
        press.el.classList.remove('pressed');
      }
      presses.clear();
      [...popups.keys()].forEach(hidePopup);
      const codes = [...mods.keys()];
      mods.clear();
      codes.forEach(paintModifier);
      root.querySelectorAll('.pressed').forEach((key) => key.classList.remove('pressed'));
    },
  };
}
