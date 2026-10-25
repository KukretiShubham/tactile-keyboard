import { storage } from './settings.js';

const TOKEN_KEY = 'tactile.token';

// Talks to the Mac. States: connecting → pairing | ready, and offline between retries.
export class Connection extends EventTarget {
  #socket = null;
  #url = null;
  #retry = 500;
  state = 'connecting';
  macName = '';

  async start() {
    try {
      const response = await fetch('config.json', { cache: 'no-store' });
      const { socketPort } = await response.json();
      const host = location.hostname.includes(':') ? `[${location.hostname}]` : location.hostname;
      this.#url = `ws://${host}:${socketPort}`;
      this.#open();
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

  pair(code) {
    this.#raw({ t: 'pair', code });
  }

  forget() {
    storage.remove(TOKEN_KEY);
    this.#socket?.close();
  }

  #raw(message) {
    if (this.#socket?.readyState === WebSocket.OPEN) this.#socket.send(JSON.stringify(message));
  }

  #open() {
    this.#setState('connecting');
    const socket = new WebSocket(this.#url);
    this.#socket = socket;

    socket.onopen = () => {
      this.#retry = 500;
      this.#raw({ t: 'hello', token: storage.get(TOKEN_KEY) ?? undefined });
    };

    socket.onmessage = (event) => {
      let message;
      try { message = JSON.parse(event.data); } catch { return; }
      if (message.t === 'ready') {
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
