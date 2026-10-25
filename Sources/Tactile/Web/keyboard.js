import { ICONS } from './icons.js';

// Magic Keyboard (US, with Touch ID) layout. Widths are in key units; every
// row adds up to 14.5 units so the edges line up like the real thing.
const letter = (ch) => ({ code: `Key${ch}`, kind: 'letter', label: ch });
const letters = (row) => [...row].map(letter);
const pair = (code, label, shifted) => ({ code, kind: 'pair', label, shifted });
const fkey = (n, sys = null) => ({ code: `F${n}`, kind: 'fkey', label: `F${n}`, sys, icon: sys && ICONS[sys] });
const word = (code, text, w, wordAt) => ({ code, kind: 'word', word: text, w, wordAt });
const modifier = (code, text, sym, w, symAt, wordAt) => ({ code, kind: 'mod', word: text, sym, w, symAt, wordAt });

const ROWS = [
  [
    word('Escape', 'esc', 1.5, 'bl'),
    fkey(1, 'brightnessDown'), fkey(2, 'brightnessUp'), fkey(3, 'missionControl'), fkey(4, 'spotlight'),
    fkey(5), fkey(6), fkey(7, 'previous'), fkey(8, 'playPause'), fkey(9, 'next'),
    fkey(10, 'mute'), fkey(11, 'volumeDown'), fkey(12, 'volumeUp'),
    { code: 'Lock', kind: 'fkey', sys: 'lockScreen', icon: ICONS.lockScreen, aria: 'Lock Screen' },
  ],
  [
    pair('Backquote', '`', '~'),
    ...[...'1234567890'].map((d, i) => pair(`Digit${d}`, d, '!@#$%^&*()'[i])),
    pair('Minus', '-', '_'), pair('Equal', '=', '+'),
    word('Backspace', 'delete', 1.5, 'br'),
  ],
  [
    word('Tab', 'tab', 1.5, 'bl'),
    ...letters('QWERTYUIOP'),
    pair('BracketLeft', '[', '{'), pair('BracketRight', ']', '}'), pair('Backslash', '\\', '|'),
  ],
  [
    { code: 'CapsLock', kind: 'caps', word: 'caps lock', w: 1.75, wordAt: 'bl' },
    ...letters('ASDFGHJKL'),
    pair('Semicolon', ';', ':'), pair('Quote', "'", '"'),
    word('Enter', 'return', 1.75, 'br'),
  ],
  [
    modifier('ShiftLeft', 'shift', '⇧', 2.25, 'tl', 'bl'),
    ...letters('ZXCVBNM'),
    pair('Comma', ',', '<'), pair('Period', '.', '>'), pair('Slash', '/', '?'),
    modifier('ShiftRight', 'shift', '⇧', 2.25, 'tr', 'br'),
  ],
  [
    { code: 'Fn', kind: 'mod', local: true, word: 'fn', icon: ICONS.globe, aria: 'Function' },
    modifier('ControlLeft', 'control', '⌃', 1, 'tr', 'bl'),
    modifier('AltLeft', 'option', '⌥', 1, 'tr', 'bl'),
    modifier('MetaLeft', 'command', '⌘', 1.25, 'tr', 'bl'),
    { code: 'Space', kind: 'space', w: 5, aria: 'Space' },
    modifier('MetaRight', 'command', '⌘', 1.25, 'tl', 'br'),
    modifier('AltRight', 'option', '⌥', 1, 'tl', 'br'),
    { kind: 'arrows' },
  ],
];

const ARROWS = [
  { code: 'ArrowLeft', kind: 'arrow', icon: ICONS.arrowLeft, aria: 'Left Arrow', area: 'left' },
  { code: 'ArrowUp', kind: 'arrow', icon: ICONS.arrowUp, aria: 'Up Arrow', area: 'up' },
  { code: 'ArrowDown', kind: 'arrow', icon: ICONS.arrowDown, aria: 'Down Arrow', area: 'down' },
  { code: 'ArrowRight', kind: 'arrow', icon: ICONS.arrowRight, aria: 'Right Arrow', area: 'right' },
];

// Holding fn turns these keys into their navigation twins, as on a Mac.
const FN_LAYER = { Backspace: 'Delete', ArrowUp: 'PageUp', ArrowDown: 'PageDown', ArrowLeft: 'Home', ArrowRight: 'End' };
const NO_REPEAT = new Set(['Escape', 'Enter', 'Tab']);
const REPEAT_DELAY = 450;
const REPEAT_INTERVAL = 55;
const DOUBLE_TAP = 350;
// With "Rest Fingers on Keys", a touch held longer than this is a resting
// finger, not a keystroke.
const REST_TIME = 350;

function soundKind(def) {
  if (def.kind === 'space') return 'space';
  if (def.kind === 'mod' || def.kind === 'caps') return 'mod';
  if (def.w >= 1.5) return 'wide';
  return 'key';
}

function span(className, text) {
  const el = document.createElement('span');
  el.className = className;
  if (text) el.textContent = text;
  return el;
}

function iconSpan(className, markup) {
  const el = span(className);
  el.innerHTML = markup;
  return el;
}

function renderKey(def) {
  const el = document.createElement('div');
  el.className = `key key-${def.kind}`;
  el.setAttribute('role', 'button');
  el.setAttribute('aria-label', def.aria || def.word || def.label || def.code);
  el.style.setProperty('--w', def.w ?? 1);
  el.dataset.code = def.code;

  switch (def.kind) {
    case 'letter':
      el.append(span('lg-center', def.label));
      break;
    case 'pair': {
      const stack = span('lg-stack');
      stack.append(span('', def.shifted), span('', def.label));
      el.append(stack);
      break;
    }
    case 'fkey':
      if (def.icon) el.append(iconSpan('lg-icon', def.icon));
      if (def.label) el.append(span('lg-flabel', def.label));
      break;
    case 'word':
      el.append(span(`lg-${def.wordAt}`, def.word));
      break;
    case 'caps':
      el.append(span('led'), span(`lg-${def.wordAt}`, def.word));
      break;
    case 'mod':
      if (def.icon) el.append(iconSpan('lg-bl lg-glyph', def.icon), span('lg-tr', def.word));
      else el.append(span(`lg-${def.symAt} lg-sym`, def.sym), span(`lg-${def.wordAt}`, def.word));
      break;
    case 'arrow':
      el.append(iconSpan('lg-arrow', def.icon));
      el.classList.add(`arrow-${def.area}`);
      break;
  }
  return el;
}

/**
 * Builds the keyboard and handles multi-touch typing. Modifiers behave like
 * iPad's own keyboard: hold for a chord, tap to apply to the next key,
 * double-tap to lock.
 */
export function createKeyboard(root, { send, feedback, settings }) {
  const defs = new WeakMap();
  const elements = new Map();
  const presses = new Map(); // pointerId → active press
  const mods = new Map(); // code → { state: 'held' | 'latched' | 'locked', used, tappedAt }
  let capsLock = false;
  let pressOrder = 0;

  // Typing keys wait for the finger to lift; delete and arrows stay immediate
  // so holding them still repeats.
  const typesOnLift = (def) =>
    settings.get('restFingers') &&
    ['letter', 'pair', 'space', 'word'].includes(def.kind) &&
    def.code !== 'Backspace';

  for (const [index, row] of ROWS.entries()) {
    const rowEl = document.createElement('div');
    rowEl.className = index === 0 ? 'key-row key-row-function' : 'key-row';
    for (const def of row) {
      if (def.kind === 'arrows') {
        const cluster = document.createElement('div');
        cluster.className = 'arrows';
        cluster.style.setProperty('--w', 3);
        for (const arrow of ARROWS) cluster.append(register(arrow));
        rowEl.append(cluster);
      } else {
        rowEl.append(register(def));
      }
    }
    root.append(rowEl);
  }

  function register(def) {
    const el = renderKey(def);
    defs.set(el, def);
    elements.set(def.code, el);
    return el;
  }

  const isOn = (code) => mods.has(code);
  const fnActive = () => isOn('Fn');
  const shiftActive = () => isOn('ShiftLeft') || isOn('ShiftRight');

  function paintModifier(code) {
    const el = elements.get(code);
    const state = mods.get(code)?.state;
    el?.classList.toggle('on', Boolean(state));
    el?.classList.toggle('locked', state === 'locked');
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
    const addShift = capsLock && def.kind === 'letter' && !shiftActive();
    if (addShift) send({ t: 'kd', k: 'ShiftLeft' });
    send({ t: 'kd', k: code });

    const press = { code, addShift };
    if (repeat && !NO_REPEAT.has(code) && def.kind !== 'fkey') {
      press.delay = setTimeout(() => {
        press.repeat = setInterval(() => send({ t: 'kd', k: code, r: true }), REPEAT_INTERVAL);
      }, REPEAT_DELAY);
    }
    return press;
  }

  function keyUp(press) {
    clearTimeout(press.delay);
    clearInterval(press.repeat);
    send({ t: 'ku', k: press.code });
    if (press.addShift) send({ t: 'ku', k: 'ShiftLeft' });
    releaseLatched();
  }

  // Where a key sits across the keyboard, from -1 (left) to 1 (right), so its
  // sound comes from that side.
  function positionOf(el) {
    const deck = root.getBoundingClientRect();
    const key = el.getBoundingClientRect();
    return ((key.left + key.width / 2 - deck.left) / deck.width) * 2 - 1;
  }

  // A bubble above the finger showing the character, since the finger covers
  // the key itself. Letters and symbols only, like the iPhone keyboard.
  const popups = new Map(); // pointerId → element
  function showPopup(pointerId, el, def) {
    if (!settings.get('keyPopups') || (def.kind !== 'letter' && def.kind !== 'pair')) return;
    const shifted = shiftActive();
    const text = def.kind === 'letter'
      ? (shifted || capsLock ? def.label : def.label.toLowerCase())
      : (shifted ? def.shifted : def.label);
    const r = el.getBoundingClientRect();
    const width = Math.max(r.width * 1.25, 52);
    const height = Math.max(r.height * 1.15, 56);
    const popup = document.createElement('div');
    popup.className = 'key-popup';
    popup.textContent = text;
    popup.style.width = `${width}px`;
    popup.style.height = `${height}px`;
    popup.style.left = `${Math.min(Math.max(r.left + r.width / 2 - width / 2, 4), innerWidth - width - 4)}px`;
    popup.style.top = `${Math.max(r.top - height - 8, 4)}px`;
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
    const kind = soundKind(press.deferred);
    const position = positionOf(press.el);
    feedback.key(kind, position);
    feedback.keyUp(kind, position, 0.045);
    const sent = keyDown(press.deferred, { repeat: false });
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

  // A touch in the gap between keys (or on the frame) goes to the closest key,
  // so near-misses still type instead of doing nothing.
  function keyAt(event) {
    const direct = event.target.closest('.key');
    if (direct) return direct;
    let closest = null;
    let best = Infinity;
    for (const el of elements.values()) {
      const r = el.getBoundingClientRect();
      const dx = Math.max(r.left - event.clientX, 0, event.clientX - r.right);
      const dy = Math.max(r.top - event.clientY, 0, event.clientY - r.bottom);
      const distance = Math.hypot(dx, dy);
      if (distance < best) {
        best = distance;
        closest = el;
      }
    }
    const unit = parseFloat(getComputedStyle(root).getPropertyValue('--u')) || 60;
    return best < unit * 0.5 ? closest : null;
  }

  root.addEventListener('pointerdown', (event) => {
    // The floating keyboard's handle and grip move it; they never type.
    if (event.target.closest('.float-handle, .float-grip')) return;
    const el = keyAt(event);
    if (!el) return;
    event.preventDefault();
    try { el.setPointerCapture(event.pointerId); } catch { /* touch already ended */ }
    const def = defs.get(el);
    el.classList.add('pressed');
    showPopup(event.pointerId, el, def);

    if (typesOnLift(def)) {
      presses.set(event.pointerId, { el, deferred: def, at: performance.now(), order: ++pressOrder });
      return;
    }

    const kind = soundKind(def);
    const position = positionOf(el);
    feedback.key(kind, position);
    let press;
    if (def.kind === 'mod') {
      modifierDown(def);
      press = { modifier: def };
    } else if (def.kind === 'caps') {
      capsLock = !capsLock;
      el.classList.toggle('locked', capsLock);
      press = {};
    } else {
      press = keyDown(def);
    }
    presses.set(event.pointerId, { el, sound: { kind, position }, ...press });
  });

  const end = (event) => {
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
    else if (!press.el.classList.contains('key-caps')) releaseLatched();
  };
  root.addEventListener('pointerup', end);
  root.addEventListener('pointercancel', end);

  // A hardware keyboard attached to the iPad is forwarded as-is.
  const typingInField = (event) => event.target.closest?.('input, textarea');
  document.addEventListener('keydown', (event) => {
    if (typingInField(event) || !event.code) return;
    event.preventDefault();
    send({ t: 'kd', k: event.code, r: event.repeat || undefined });
    elements.get(event.code)?.classList.add('pressed');
  });
  document.addEventListener('keyup', (event) => {
    if (typingInField(event) || !event.code) return;
    event.preventDefault();
    send({ t: 'ku', k: event.code });
    elements.get(event.code)?.classList.remove('pressed');
  });

  return {
    releaseLatched,
    /** Forget all local key state; the Mac side is released separately. */
    reset() {
      for (const press of presses.values()) {
        clearTimeout(press.delay);
        clearInterval(press.repeat);
        press.el.classList.remove('pressed');
      }
      presses.clear();
      [...popups.keys()].forEach(hidePopup);
      const codes = [...mods.keys()];
      mods.clear();
      codes.forEach(paintModifier);
      root.querySelectorAll('.pressed').forEach((el) => el.classList.remove('pressed'));
    },
  };
}
