// Floating keyboard (keyboard-only layout, "Floating" size), modelled on the
// iPad's own floating keyboard: drag the handle under it to move it, drag the
// corner grip to resize, double-tap the handle to reset. Only the handle and
// grip respond, so typing never moves it by accident.
//
// The frame is stored per orientation as fractions of the available space:
// { cx, cy } for the centre and w for the width.

const DEFAULT_FRAME = { cx: 0.5, cy: 0.6, w: 0.75 };
const SNAP = 18;
const DOUBLE_TAP = 300;
// Room below the keyboard for the handle.
export const HANDLE_SPACE = 40;

export function createFloating({ deck, settings, feedback, onLiveFrame, minWidth }) {
  const handle = document.createElement('div');
  handle.className = 'float-handle';
  handle.setAttribute('role', 'button');
  handle.setAttribute('aria-label', 'Move keyboard. Double-tap to reset.');
  handle.append(document.createElement('span'));

  const grip = document.createElement('div');
  grip.className = 'float-grip';
  grip.setAttribute('role', 'button');
  grip.setAttribute('aria-label', 'Resize keyboard');
  grip.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M17 7 7 17M17 12l-5 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';

  deck.append(handle, grip);

  const orientation = () => (innerWidth >= innerHeight ? 'landscape' : 'portrait');

  function frame() {
    return { ...DEFAULT_FRAME, ...(settings.get('floatingFrame')?.[orientation()] ?? {}) };
  }

  function save(next) {
    settings.set('floatingFrame', { ...(settings.get('floatingFrame') ?? {}), [orientation()]: next });
  }

  /** The stage's inner box (in viewport coordinates), which frames are measured against. */
  function bounds() {
    const stage = deck.parentElement;
    const style = getComputedStyle(stage);
    const r = stage.getBoundingClientRect();
    const left = r.left + parseFloat(style.paddingLeft);
    const top = r.top + parseFloat(style.paddingTop);
    return {
      left,
      top,
      width: r.width - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight),
      height: r.height - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom),
    };
  }

  const clamp = (value, low, high) => Math.min(Math.max(value, low), Math.max(low, high));

  // One gesture at a time: moving (handle) or resizing (grip).
  let gesture = null;
  let lastTap = 0;
  let snapped = '';

  function begin(kind, event) {
    event.preventDefault();
    event.stopPropagation();
    try { event.currentTarget.setPointerCapture(event.pointerId); } catch { /* touch already ended */ }
    // Start from where the keyboard really is on screen, not the saved frame,
    // which may have been clamped to fit.
    const area = bounds();
    const r = deck.getBoundingClientRect();
    gesture = {
      kind,
      pointerId: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      width: area.width,
      height: area.height,
      left: r.left - area.left,
      top: r.top - area.top,
      deckWidth: r.width,
      deckHeight: r.height,
      moved: false,
      live: frame(),
    };
    deck.classList.add('adjusting');
  }

  function move(event) {
    if (!gesture || event.pointerId !== gesture.pointerId) return;
    event.preventDefault();
    const dx = event.clientX - gesture.x;
    const dy = event.clientY - gesture.y;
    if (Math.hypot(dx, dy) > 4) gesture.moved = true;
    const { width, height, deckWidth, deckHeight } = gesture;
    const bottom = height - deckHeight - HANDLE_SPACE;

    if (gesture.kind === 'move') {
      let left = clamp(gesture.left + dx, 0, width - deckWidth);
      let top = clamp(gesture.top + dy, 0, bottom);
      // Gentle snapping to the centre line and the top and bottom edges.
      let snap = '';
      if (Math.abs(left + deckWidth / 2 - width / 2) < SNAP) { left = width / 2 - deckWidth / 2; snap += 'center'; }
      if (top < SNAP) { top = 0; snap += 'top'; }
      if (Math.abs(top - bottom) < SNAP) { top = Math.max(0, bottom); snap += 'bottom'; }
      if (snap && snap !== snapped) feedback.click();
      snapped = snap;
      gesture.live = {
        cx: (left + deckWidth / 2) / width,
        cy: (top + deckHeight / 2) / height,
        w: deckWidth / width,
      };
    } else {
      // Scale evenly from the top-left corner, between the smallest keys
      // allowed and whatever still fits on screen.
      const scale = Math.max((deckWidth + dx) / deckWidth, (deckHeight + dy) / deckHeight);
      const aspect = deckHeight / deckWidth;
      const fitsWidth = Math.min(width, (height - HANDLE_SPACE) / aspect);
      const newWidth = clamp(deckWidth * scale, Math.min(minWidth(), fitsWidth), fitsWidth);
      const newHeight = newWidth * aspect;
      const left = clamp(gesture.left, 0, width - newWidth);
      const top = clamp(gesture.top, 0, height - newHeight - HANDLE_SPACE);
      gesture.live = {
        cx: (left + newWidth / 2) / width,
        cy: (top + newHeight / 2) / height,
        w: newWidth / width,
      };
    }
    onLiveFrame(gesture.live);
  }

  function end(event) {
    if (!gesture || event.pointerId !== gesture.pointerId) return;
    const finished = gesture;
    gesture = null;
    snapped = '';
    deck.classList.remove('adjusting');

    // Double-tap the handle to put the keyboard back where it started.
    if (finished.kind === 'move' && !finished.moved && event.type === 'pointerup') {
      const now = performance.now();
      if (now - lastTap < DOUBLE_TAP) {
        lastTap = 0;
        feedback.click();
        save({ ...DEFAULT_FRAME });
        onLiveFrame(null);
        return;
      }
      lastTap = now;
    }
    if (finished.moved) save(finished.live);
    onLiveFrame(null);
  }

  handle.addEventListener('pointerdown', (event) => begin('move', event));
  grip.addEventListener('pointerdown', (event) => begin('resize', event));
  for (const el of [handle, grip]) {
    el.addEventListener('pointermove', move);
    el.addEventListener('pointerup', end);
    el.addEventListener('pointercancel', end);
  }

  return { frame, bounds };
}
