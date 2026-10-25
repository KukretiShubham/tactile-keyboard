// Keeps the iPad's screen on while you're using Tactile, so it doesn't dim
// mid-sentence and drop the connection. After a stretch with no touches the
// screen is allowed to sleep again as usual, to save battery; the next touch
// keeps it awake once more.

const IDLE_TIME = 10 * 60 * 1000;

export function keepScreenAwake(settings) {
  let lock = null;
  let requesting = false;
  let idleTimer = 0;

  async function release() {
    const held = lock;
    lock = null;
    try { await held?.release(); } catch { /* already released */ }
  }

  async function acquire() {
    if (!settings.get('keepAwake')) return release();
    // Safari drops the lock whenever the page is hidden, so it's requested
    // again when the page comes back.
    if (requesting || document.hidden || !('wakeLock' in navigator) || (lock && !lock.released)) return;
    requesting = true;
    try {
      lock = await navigator.wakeLock.request('screen');
    } catch {
      // Refused (for example in Low Power Mode); the iPad just sleeps as usual.
    } finally {
      requesting = false;
    }
  }

  function activity() {
    clearTimeout(idleTimer);
    idleTimer = setTimeout(release, IDLE_TIME);
    acquire();
  }

  document.addEventListener('visibilitychange', () => { if (!document.hidden) activity(); });
  for (const type of ['pointerdown', 'keydown']) window.addEventListener(type, activity, { capture: true });
  settings.subscribe((key) => { if (key === 'keepAwake') activity(); });
  activity();
}
