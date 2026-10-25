// Multi-touch trackpad modelled on macOS gestures:
//   one finger — move · tap — click · hold still, then move — drag
//   two fingers — scroll (with momentum) · pinch — zoom · tap — secondary click
//   three fingers — swipe left/right between Spaces, up for Mission Control,
//     down for App Exposé; with Three-Finger Drag on, three fingers drag and
//     the swipes take four
import { el as element } from './util.js';

const TAP_TIME = 240;
const TAP_SLOP = 10;
const HOLD_TO_DRAG = 380;
const SWIPE_DISTANCE = 70;
// Two fingers either scroll or pinch; whichever moves this far first wins.
const SCROLL_START = 12;
const PINCH_START = 24;
// Each step of pinching this far zooms in or out once (⌘= or ⌘-).
const PINCH_STEP = 60;

// The display's frame clock; tests pass their own, since a page that isn't
// on screen gets no frames.
const FRAMES = { request: (fn) => requestAnimationFrame(fn), cancel: (id) => cancelAnimationFrame(id) };

export function createTrackpad(el, { send, feedback, settings, onClick, isCongested, frames = FRAMES }) {
  const touches = new Map();
  let gesture = null;
  let dragging = false;
  let holdTimer = 0;
  let frame = 0;
  const pending = { mx: 0, my: 0, sx: 0, sy: 0 };
  const velocity = { x: 0, y: 0, at: 0 };
  let glide = 0;

  // Coalesce pointer events into one message per display frame. While the
  // network is backed up (Wi-Fi waking from sleep), keep adding up movement and
  // send it as one move once it drains, rather than a burst of stale ones.
  function flush() {
    frame = 0;
    if (isCongested()) {
      schedule();
      return;
    }
    if (pending.mx || pending.my) {
      send({ t: 'mv', x: +pending.mx.toFixed(1), y: +pending.my.toFixed(1) });
      pending.mx = pending.my = 0;
    }
    const sx = Math.trunc(pending.sx);
    const sy = Math.trunc(pending.sy);
    if (sx || sy) {
      send({ t: 'sc', x: sx, y: sy });
      pending.sx -= sx;
      pending.sy -= sy;
    }
  }
  const schedule = () => { frame ||= frames.request(flush); };

  function click(button) {
    send({ t: 'md', b: button });
    send({ t: 'mu', b: button });
    feedback.click();
    onClick();
  }

  function startDrag() {
    if (dragging) return;
    dragging = true;
    gesture.kind = 'drag';
    el.classList.add('dragging');
    send({ t: 'md', b: 'l' });
    feedback.click();
  }

  function startHoldDrag() {
    if (touches.size === 1 && gesture.travel <= TAP_SLOP) startDrag();
  }

  const distance = () => {
    const [a, b] = touches.values();
    return Math.hypot(a.x - b.x, a.y - b.y);
  };

  function stopGlide() {
    frames.cancel(glide);
    glide = 0;
  }

  function startGlide() {
    let last = performance.now();
    const step = (now) => {
      const dt = Math.min(32, now - last);
      last = now;
      const decay = Math.pow(0.95, dt / 16.7);
      velocity.x *= decay;
      velocity.y *= decay;
      pending.sx += velocity.x * dt;
      pending.sy += velocity.y * dt;
      schedule();
      glide = Math.hypot(velocity.x, velocity.y) > 0.03 ? frames.request(step) : 0;
    };
    if (Math.hypot(velocity.x, velocity.y) > 0.15) glide = frames.request(step);
  }

  function showTouch(id, x, y) {
    const rect = el.getBoundingClientRect();
    let dot = el.querySelector(`[data-touch="${id}"]`);
    if (!dot) {
      dot = element('div', { className: 'touch-dot', attrs: { 'data-touch': id } });
      el.append(dot);
    }
    dot.style.transform = `translate(${x - rect.left}px, ${y - rect.top}px)`;
  }

  el.addEventListener('pointerdown', (event) => {
    event.preventDefault();
    try { el.setPointerCapture(event.pointerId); } catch { /* touch already ended */ }
    stopGlide();
    // The first finger of a new touch is "primary" only when no other finger
    // is down. Anything still remembered is a finger whose lift Safari never
    // reported; left in place, it would turn one-finger moves into scrolling.
    if (event.isPrimary && touches.size > 0) forgetTouches();
    touches.set(event.pointerId, { x: event.clientX, y: event.clientY, t: event.timeStamp });
    showTouch(event.pointerId, event.clientX, event.clientY);

    if (touches.size === 1) {
      gesture = { start: event.timeStamp, fingers: 1, travel: 0, kind: 'move', swipe: { x: 0, y: 0 }, swiped: false };
      velocity.x = velocity.y = 0;
      holdTimer = setTimeout(startHoldDrag, HOLD_TO_DRAG);
    } else if (gesture) {
      gesture.fingers = Math.max(gesture.fingers, touches.size);
      if (!dragging) clearTimeout(holdTimer);
      if (touches.size === 2) Object.assign(gesture, { pinch: distance(), zoomed: 0, pan: { x: 0, y: 0 }, held: { x: 0, y: 0 } });
    }
  });

  el.addEventListener('pointermove', (event) => {
    const touch = touches.get(event.pointerId);
    if (!touch || !gesture) return;
    const dx = event.clientX - touch.x;
    const dy = event.clientY - touch.y;
    const dt = Math.max(1, event.timeStamp - touch.t);
    Object.assign(touch, { x: event.clientX, y: event.clientY, t: event.timeStamp });
    showTouch(event.pointerId, event.clientX, event.clientY);

    gesture.travel += Math.hypot(dx, dy);
    if (gesture.travel > TAP_SLOP && !dragging) clearTimeout(holdTimer);

    const threeFingerDrag = settings.get('threeFingerDrag');
    if (threeFingerDrag && touches.size === 3 && gesture.fingers === 3 && gesture.travel > TAP_SLOP) startDrag();

    if (touches.size === 1 || dragging) {
      // Pointer acceleration: slow strokes stay precise, fast flicks cross the
      // screen. Every finger reports its own moves, so a three-finger drag
      // moves by their average.
      const speed = Math.hypot(dx, dy) / dt;
      const gain = (settings.get('tracking') * (1 + 1.6 * Math.min(speed, 2.5))) / Math.max(1, touches.size);
      pending.mx += dx * gain;
      pending.my += dy * gain;
      schedule();
    } else if (touches.size === 2) {
      twoFingers(dx, dy, dt, event.timeStamp);
    } else if (!gesture.swiped && touches.size >= (threeFingerDrag ? 4 : 3)) {
      gesture.kind = 'swipe';
      gesture.swipe.x += dx / touches.size;
      gesture.swipe.y += dy / touches.size;
      const { x, y } = gesture.swipe;
      if (Math.max(Math.abs(x), Math.abs(y)) > SWIPE_DISTANCE) {
        gesture.swiped = true;
        const action = Math.abs(x) > Math.abs(y)
          ? (x < 0 ? 'spaceRight' : 'spaceLeft')
          : (y < 0 ? 'missionControl' : 'appExpose');
        send({ t: 'sys', k: action });
        feedback.click();
      }
    }
  });

  // Two fingers scroll or pinch. Until one is clear, scrolling is held back
  // rather than sent, so a pinch never scrolls the page first.
  function twoFingers(dx, dy, dt, at) {
    const direction = settings.get('naturalScroll') ? 1 : -1;
    const speed = 1.6 * settings.get('scrollSpeed') * direction;
    const sx = (dx / 2) * speed;
    const sy = (dy / 2) * speed;
    gesture.pan.x += dx / 2;
    gesture.pan.y += dy / 2;
    const spread = distance() - gesture.pinch;

    if (gesture.kind !== 'scroll' && gesture.kind !== 'pinch') {
      if (settings.get('pinchZoom') && Math.abs(spread) > PINCH_START) {
        gesture.kind = 'pinch';
      } else if (Math.hypot(gesture.pan.x, gesture.pan.y) > SCROLL_START) {
        gesture.kind = 'scroll';
        pending.sx += gesture.held.x;
        pending.sy += gesture.held.y;
      } else {
        gesture.held.x += sx;
        gesture.held.y += sy;
        return;
      }
    }

    if (gesture.kind === 'pinch') {
      const steps = Math.trunc(spread / PINCH_STEP);
      for (; gesture.zoomed < steps; gesture.zoomed++) zoom('Equal');
      for (; gesture.zoomed > steps; gesture.zoomed--) zoom('Minus');
      return;
    }
    pending.sx += sx;
    pending.sy += sy;
    velocity.x = velocity.x * 0.6 + (sx / dt) * 0.4;
    velocity.y = velocity.y * 0.6 + (sy / dt) * 0.4;
    velocity.at = at;
    schedule();
  }

  function zoom(key) {
    send({ t: 'combo', ks: ['MetaLeft', key] });
    feedback.click();
  }

  const end = (event) => {
    if (!touches.delete(event.pointerId)) return;
    el.querySelector(`[data-touch="${event.pointerId}"]`)?.remove();
    if (touches.size > 0 || !gesture) return;

    clearTimeout(holdTimer);
    const quick = event.timeStamp - gesture.start < TAP_TIME;
    if (dragging) {
      dragging = false;
      el.classList.remove('dragging');
      send({ t: 'mu', b: 'l' });
      onClick();
    } else if (event.type === 'pointerup' && quick && gesture.travel < TAP_SLOP * gesture.fingers) {
      if (gesture.fingers === 1) click('l');
      else if (gesture.fingers === 2) click('r');
    } else if (gesture.kind === 'scroll' && event.timeStamp - velocity.at < 80) {
      // Only glide if the fingers were still moving when they lifted.
      startGlide();
    }
    gesture = null;
  };
  el.addEventListener('pointerup', end);
  el.addEventListener('pointercancel', end);
  // Losing the touch (for example to a system gesture) counts as lifting it.
  el.addEventListener('lostpointercapture', end);

  /** Drops every remembered finger, letting go of a drag in progress. */
  function forgetTouches() {
    if (dragging) send({ t: 'mu', b: 'l' });
    clearTimeout(holdTimer);
    touches.clear();
    gesture = null;
    dragging = false;
    el.classList.remove('dragging');
    el.querySelectorAll('.touch-dot').forEach((dot) => dot.remove());
  }

  return {
    reset() {
      stopGlide();
      frames.cancel(frame);
      frame = 0;
      pending.mx = pending.my = pending.sx = pending.sy = 0;
      forgetTouches();
    },
  };
}
