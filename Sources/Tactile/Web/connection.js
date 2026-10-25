import { storage } from './settings.js';

const TOKEN_KEY = 'tactile.token';

// How this device is listed in the Mac's Paired Devices menu. iPadOS Safari
// reports itself as a Mac, so a touch screen gives it away.
function deviceName() {
  const ua = navigator.userAgent;
  if (/iPhone/.test(ua)) return 'iPhone';
  if (/iPad/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return 'iPad';
  if (/Android/.test(ua)) return 'Android device';
  if (/Macintosh/.test(ua)) return 'Mac';
  return 'Browser';
}

// Talks to the Mac. States: connecting → pairing | ready, and offline between retries.
export class Connection extends EventTarget {
  #socket = null;
  #url = null;
  #retry = 500;
  #held = false;
  state = 'connecting';
  macName = '';

  async start() {
    try {
      const response = await fetch('config.json', { cache: 'no-store' });
      const { socketPort } = await response.json();
      const host = location.hostname.includes(':') ? `[${location.hostname}]` : location.hostname;
      // Always wss:// in real use; ws:// only for the dry-run copy on this Mac.
      const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
      this.#url = `${scheme}://${host}:${socketPort}`;
      this.#open();
      this.#watch();
    } catch {
      this.#setState('offline');
      setTimeout(() => this.start(), 2000);
    }
  }

  send(message) {
    if (this.state === 'ready' && this.#socket?.readyState === WebSocket.OPEN) {
      this.#socket.send(JSON.stringify(message));
    }
  }

  /** True while earlier messages are still waiting to leave the iPad. */
  get congested() {
    return (this.#socket?.bufferedAmount ?? 0) > 0;
  }

  // A socket can look open after the iPad sleeps even though the connection is
  // gone. Ping on wake (and every few seconds) and start over if the Mac
  // doesn't answer quickly, instead of waiting for the browser to notice.
  #lastPong = 0;
  #probe = 0;

  #ping(timeout) {
    if (this.state !== 'ready') return;
    const sentAt = performance.now();
    this.#raw({ t: 'ping' });
    clearTimeout(this.#probe);
    this.#probe = setTimeout(() => {
      if (this.#lastPong < sentAt) this.#reconnect();
    }, timeout);
  }

  #reconnect() {
    const old = this.#socket;
    this.#socket = null;
    if (old) {
      old.onclose = null;
      old.onmessage = null;
      try { old.close(); } catch { /* already gone */ }
    }
    this.#retry = 500;
    this.#open();
  }

  #watch() {
    setInterval(() => this.#ping(4000), 5000);
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) return;
      if (this.state === 'ready') this.#ping(1500);
      else if (this.state === 'offline') this.#reconnect();
    });
  }

  pair(code) {
    this.#raw({ t: 'pair', code, name: deviceName() });
  }

  forget() {
    storage.remove(TOKEN_KEY);
    this.#socket?.close();
  }

  #raw(message) {
    if (this.#socket?.readyState === WebSocket.OPEN) this.#socket.send(JSON.stringify(message));
  }

  #open() {
    if (!this.#held) this.#setState('connecting');
    const socket = new WebSocket(this.#url);
    this.#socket = socket;

    socket.onopen = () => {
      this.#retry = 500;
      this.#raw({ t: 'hello', token: storage.get(TOKEN_KEY) ?? undefined, name: deviceName() });
    };

    socket.onmessage = (event) => {
      let message;
      try { message = JSON.parse(event.data); } catch { return; }
      if (message.t === 'pong') {
        this.#lastPong = performance.now();
      } else if (message.t === 'probe') {
        // The Mac times this round trip to show connection quality.
        this.#raw({ t: 'probe', n: message.n });
      } else if (message.t === 'denied' && message.reason === 'foreign') {
        // Over Tailscale, only devices signed in as the Mac's owner may connect.
        this.#held = true;
        this.#setState('refused');
      } else if (message.t === 'denied' && message.reason === 'held') {
        // Disconnected from the Mac's menu: wait quietly until it's allowed again.
        this.#held = true;
        this.#setState('held');
      } else if (message.t === 'ready') {
        this.#held = false;
        if (message.token) storage.set(TOKEN_KEY, message.token);
        this.macName = message.name || 'Mac';
        this.#setState('ready');
      } else if (message.t === 'pair') {
        storage.remove(TOKEN_KEY);
        this.#setState('pairing');
      } else if (message.t === 'denied') {
        this.dispatchEvent(new CustomEvent('denied', { detail: message.reason }));
      }
    };

    socket.onclose = () => {
      if (this.#socket !== socket) return;
      if (this.#held) {
        setTimeout(() => this.#open(), 10000);
        return;
      }
      this.#setState('offline');
      setTimeout(() => this.#open(), this.#retry);
      this.#retry = Math.min(this.#retry * 2, 5000);
    };
  }

  #setState(state) {
    if (this.state === state) return;
    this.state = state;
    this.dispatchEvent(new CustomEvent('state', { detail: state }));
  }
}
