import { Connection } from './connection.js';
import { Feedback } from './feedback.js';
import { createFloating, HANDLE_SPACE } from './floating.js';
import { createKeyboard } from './keyboard.js';
import { settings, storage } from './settings.js';
import { setupSheets } from './sheets.js';
import { createShortcutBar } from './shortcuts.js';
import { createTrackpad } from './trackpad.js';
import { TypingModel } from './typing-model.js';
import { clamp, contentBox } from './util.js';
import { keepScreenAwake } from './wake-lock.js';

const root = document.documentElement;
const app = document.getElementById('app');
const stage = document.getElementById('stage');
const status = document.getElementById('status');
const statusLabel = document.getElementById('statusLabel');
const themeColor = document.querySelector('meta[name="theme-color"]');
const prefersDark = matchMedia('(prefers-color-scheme: dark)');

const connection = new Connection();
const feedback = new Feedback(settings);
const send = (message) => connection.send(message);

// A QR code from the Mac carries the pairing code after the "#", which never
// leaves the iPad. Take it out of the address right away so it isn't saved in
// history or in a Home Screen bookmark.
const pairingLink = new URLSearchParams(location.hash.slice(1)).get('pair');
if (location.hash) history.replaceState(null, '', location.pathname + location.search);
let pairingLinkUsed = false;

const deck = document.getElementById('keyboard');
const typingModel = new TypingModel(storage);
const keyboard = createKeyboard(deck, { send, feedback, settings, model: typingModel });
// While the handle or grip is being dragged, the keyboard follows this frame;
// it's saved when the finger lifts.
let liveFrame = null;
let floatMinWidth = 0;
const floating = createFloating({
  deck, settings, feedback,
  onLiveFrame: (frame) => { liveFrame = frame; fit(); },
  minWidth: () => floatMinWidth,
});
const trackpad = createTrackpad(document.getElementById('trackpad'), {
  send, feedback, settings,
  onClick: () => keyboard.releaseLatched(),
  isCongested: () => connection.congested,
});
const shortcutBar = createShortcutBar(document.getElementById('shortcutBar'), {
  send, feedback, settings,
  beforeSend: () => keyboard.releaseLatched(),
});
const sheets = setupSheets({ connection, feedback, typingModel });

// Key labels and shortcuts follow the Mac's keyboard layout.
let macLabels = {};
function applyLabels() {
  keyboard.setLabels(settings.get('macLabels') ? macLabels : {});
  shortcutBar.setLabels(macLabels);
}
connection.addEventListener('layout', ({ detail }) => {
  macLabels = detail;
  applyLabels();
});

// Appearance
function applySkin() {
  const chosen = settings.get('skin');
  const skin = chosen === 'auto' ? (prefersDark.matches ? 'midnight' : 'silver') : chosen;
  root.dataset.skin = skin;
  root.style.setProperty('--glow', settings.get('glow'));
  themeColor.content = skin === 'silver' ? '#e8e8ed' : '#000000';
  sheets.sync();
}

// Size keys from the space available so the whole keyboard always fits,
// in landscape or portrait, with or without the trackpad.
function fit() {
  const layout = settings.get('layout');
  const functionRow = settings.get('functionRow');
  const size = layout === 'keyboard' ? settings.get('keyboardSize') : 'fit';
  const expanded = size === 'expanded';
  const floats = size === 'floating';
  app.dataset.layout = layout;
  app.dataset.functionRow = functionRow ? 'on' : 'off';
  app.dataset.position = settings.get('keyboardPosition');
  app.dataset.size = size;
  // In landscape, height is what's scarce: with the trackpad showing, the top
  // bar's controls float over the trackpad's top corners instead of taking a
  // row of their own.
  const overlay = layout === 'both' && innerWidth > innerHeight;
  app.dataset.controls = overlay ? 'overlay' : 'bar';
  const { width, height, paddingLeft, paddingTop } = contentBox(stage);

  const gap = clamp(width * 0.0055, 4, 8);
  const pad = clamp(width * 0.012, 8, 18);
  const stageGap = clamp(height * 0.016, 8, 14);
  // Taller keys give fingers more room vertically, where most misses happen.
  // Standard keys are square, like a Mac keyboard's.
  const keyHeightRatio = settings.get('keyHeight') === 'tall' ? 1.2 : 1;
  const rows = functionRow ? 5.55 : 5;
  const rowGaps = functionRow ? 5 : 4;
  const unitFromWidth = (width - 2 * pad - 13.5 * gap) / 14.5;
  const keyboardHeight = layout === 'both' ? height * 0.62 - stageGap / 2 : height;
  const unitFromHeight = (keyboardHeight - 2 * pad - rowGaps * gap) / (rows * keyHeightRatio);
  let unit = Math.max(20, Math.floor(Math.min(unitFromWidth, unitFromHeight) * 10) / 10);

  // Floating: the saved width sets the size, between keys of about 40 pt and
  // the full screen, and never taller than the space left for the handle.
  const frame = floats ? (liveFrame ?? floating.frame()) : null;
  if (floats) {
    const minWidth = Math.min(14.5 * 40 + 13.5 * gap + 2 * pad, width);
    floatMinWidth = minWidth;
    const deckWidth = clamp(frame.w * width, minWidth, width);
    const fromWidth = (deckWidth - 2 * pad - 13.5 * gap) / 14.5;
    const fromHeight = (height - HANDLE_SPACE - 2 * pad - rowGaps * gap) / (rows * keyHeightRatio);
    unit = Math.max(20, Math.floor(Math.min(fromWidth, fromHeight) * 10) / 10);
  }

  // Expanded: keys grow taller to fill the screen (up to 2.2× their width),
  // so there's more to aim at when the trackpad is hidden.
  let keyHeight = unit * keyHeightRatio;
  if (expanded) {
    const fill = (height - 2 * pad - rowGaps * gap) / rows;
    keyHeight = clamp(fill, keyHeight, unit * 2.2);
  }

  root.style.setProperty('--u', `${unit}px`);
  root.style.setProperty('--kh', `${keyHeight.toFixed(1)}px`);
  root.style.setProperty('--g', `${gap.toFixed(1)}px`);
  root.style.setProperty('--deck-pad', `${pad.toFixed(1)}px`);
  root.style.setProperty('--stage-gap', `${stageGap.toFixed(1)}px`);

  if (overlay) {
    const pad = document.getElementById('trackpad').getBoundingClientRect();
    root.style.setProperty('--controls-top', `${Math.round(pad.top + 10)}px`);
    root.style.setProperty('--controls-left', `${Math.round(pad.left + 10)}px`);
    root.style.setProperty('--controls-right', `${Math.round(innerWidth - pad.right + 10)}px`);
  }

  if (floats) {
    // Centre the keyboard on its saved spot, kept fully on screen.
    const deckWidth = deck.offsetWidth;
    const deckHeight = deck.offsetHeight;
    const left = clamp(frame.cx * width - deckWidth / 2, 0, width - deckWidth);
    const top = clamp(frame.cy * height - deckHeight / 2, 0, height - deckHeight - HANDLE_SPACE);
    deck.style.left = `${left + paddingLeft}px`;
    deck.style.top = `${top + paddingTop}px`;
  } else {
    deck.style.left = deck.style.top = '';
  }
}

settings.subscribe((key) => {
  if (key === 'skin' || key === 'glow') applySkin();
  if (['layout', 'keyHeight', 'functionRow', 'keyboardPosition', 'keyboardSize', 'floatingFrame'].includes(key)) fit();
  if (key === 'macLabels') applyLabels();
});
prefersDark.addEventListener('change', applySkin);
new ResizeObserver(fit).observe(stage);
applySkin();
fit();

// Connection status
const LABELS = {
  connecting: 'Connecting…',
  pairing: 'Waiting to pair',
  offline: 'Mac not reachable — retrying',
  held: 'Disconnected by your Mac',
  refused: 'Not allowed: sign in to Tailscale as the Mac’s owner',
};
connection.addEventListener('state', ({ detail: state }) => {
  status.dataset.state = state;
  statusLabel.textContent = state === 'ready' ? connection.macName : LABELS[state];
  if (state === 'pairing') {
    if (pairingLink && !pairingLinkUsed) {
      pairingLinkUsed = true;
      connection.pair(pairingLink);
    } else {
      sheets.showPairing();
    }
  }
  if (state === 'ready') sheets.hidePairing();
  if (state !== 'ready') {
    keyboard.reset();
    trackpad.reset();
  }
});
connection.addEventListener('denied', ({ detail }) => {
  // A scanned code that no longer works (Tactile restarted, or another iPad
  // used it) falls back to typing the current code.
  sheets.showPairing();
  sheets.pairingDenied(pairingLinkUsed && detail === 'code' ? 'expired' : detail);
});

keepScreenAwake(settings);

// Safari starts audio only from a finger lifting, a click or a key press
// (not a finger touching down), so try on each of those until it works.
for (const type of ['pointerup', 'touchend', 'click', 'keydown']) {
  window.addEventListener(type, () => { if (feedback.needsTap) feedback.unlock(); }, { capture: true });
}

// If Safari still hasn't allowed sound, say so instead of staying silent.
const soundHint = document.getElementById('soundHint');
const showSoundHint = () => { soundHint.hidden = !feedback.needsTap; };
feedback.addEventListener('state', showSoundHint);
soundHint.addEventListener('click', () => feedback.preview());
setTimeout(showSoundHint, 1500);

// Never leave a key or button held on the Mac when the iPad looks away.
document.addEventListener('visibilitychange', () => {
  if (!document.hidden) return;
  send({ t: 'rel' });
  keyboard.reset();
  trackpad.reset();
});

// Keep Safari from zooming, scrolling or showing callouts while typing. Safari
// ignores user-scalable=no, so several fingers on the keys would pinch-zoom or
// double-tap-zoom the page unless the raw touch events are cancelled here.
// Pointer events (which the keyboard and trackpad use) still fire.
for (const type of ['touchstart', 'touchmove', 'touchend']) {
  stage.addEventListener(type, (event) => event.preventDefault(), { passive: false });
}
for (const type of ['gesturestart', 'gesturechange', 'gestureend']) {
  document.addEventListener(type, (event) => event.preventDefault(), { passive: false });
}
document.addEventListener('contextmenu', (event) => event.preventDefault());
document.addEventListener('touchmove', (event) => {
  if (!event.target.closest('.sheet-scroll, textarea')) event.preventDefault();
}, { passive: false });

connection.start();
