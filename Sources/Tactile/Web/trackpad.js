// Multi-touch trackpad modelled on macOS gestures:
//   one finger — move · tap — click · hold still, then move — drag
//   two fingers — scroll (with momentum) · tap — secondary click
//   three fingers — swipe left/right between Spaces, up for Mission Control, down for App Exposé

const TAP_TIME = 240;
const TAP_SLOP = 10;
const HOLD_TO_DRAG = 380;
const SWIPE_DISTANCE = 70;

export function createTrackpad(el, { send, feedback, settings, onClick }) {
  const touches = new Map();
  let gesture = null;
  let dragging = false;
  let holdTimer = 0;
  let frame = 0;
  const pending = { mx: 0, my: 0, sx: 0, sy: 0 };
  const velocity = { x: 0, y: 0, at: 0 };
  let glide = 0;

  // Coalesce pointer events into one message per display frame.
  function flush() {
    frame = 0;
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
  const schedule = () => { frame ||= requestAnimationFrame(flush); };

  function click(button) {
    send({ t: 'md', b: button });
    send({ t: 'mu', b: button });
    feedback.click();
    onClick();
  }

  function startDrag() {
    if (touches.size !== 1 || gesture.travel > TAP_SLOP) return;
    dragging = true;
    gesture.kind = 'drag';
    el.classList.add('dragging');
    send({ t: 'md', b: 'l' });
    feedback.click();
  }

  function stopGlide() {
    cancelAnimationFrame(glide);
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
      glide = Math.hypot(velocity.x, velocity.y) > 0.03 ? requestAnimationFrame(step) : 0;
    };
    if (Math.hypot(velocity.x, velocity.y) > 0.15) glide = requestAnimationFrame(step);
  }

  function showTouch(id, x, y) {
    const rect = el.getBoundingClientRect();
    let dot = el.querySelector(`[data-touch="${id}"]`);
    if (!dot) {
      dot = document.createElement('div');
      dot.className = 'touch-dot';
      dot.dataset.touch = id;
      el.append(dot);
    }
    dot.style.transform = `translate(${x - rect.left}px, ${y - rect.top}px)`;
  }

  el.addEventListener('pointerdown', (event) => {
    event.preventDefault();
    el.setPointerCapture(event.pointerId);
    stopGlide();
    touches.set(event.pointerId, { x: event.clientX, y: event.clientY, t: event.timeStamp });
    showTouch(event.pointerId, event.clientX, event.clientY);

    if (touches.size === 1) {
      gesture = { start: event.timeStamp, fingers: 1, travel: 0, kind: 'move', swipe: { x: 0, y: 0 }, swiped: false };
      velocity.x = velocity.y = 0;
      holdTimer = setTimeout(startDrag, HOLD_TO_DRAG);
    } else if (gesture) {
      gesture.fingers = Math.max(gesture.fingers, touches.size);
      if (!dragging) clearTimeout(holdTimer);
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

    if (touches.size === 1 || dragging) {
      // Pointer acceleration: slow strokes stay precise, fast flicks cross the screen.
      const speed = Math.hypot(dx, dy) / dt;
      const gain = settings.get('tracking') * (1 + 1.6 * Math.min(speed, 2.5));
      pending.mx += dx * gain;
      pending.my += dy * gain;
      schedule();
    } else if (touches.size === 2) {
      gesture.kind = 'scroll';
      const direction = settings.get('naturalScroll') ? 1 : -1;
      const sx = (dx / 2) * 1.6 * direction;
      const sy = (dy / 2) * 1.6 * direction;
      pending.sx += sx;
      pending.sy += sy;
      velocity.x = velocity.x * 0.6 + (sx / dt) * 0.4;
      velocity.y = velocity.y * 0.6 + (sy / dt) * 0.4;
      velocity.at = event.timeStamp;
      schedule();
    } else if (!gesture.swiped) {
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

  return {
    reset() {
      stopGlide();
      clearTimeout(holdTimer);
      touches.clear();
      gesture = null;
      dragging = false;
      el.classList.remove('dragging');
      el.querySelectorAll('.touch-dot').forEach((dot) => dot.remove());
    },
  };
}
