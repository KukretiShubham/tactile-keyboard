import { comboRecorder } from '../../Sources/Tactile/Web/hotkey-editor.js';
import { createShortcuts } from '../../Sources/Tactile/Web/shortcuts.js';
import { stateAfterPress, voiceKeyLabel } from '../../Sources/Tactile/Web/voice-key.js';
import { expect, expectEqual, fakeSettings, silentFeedback, test, wait } from './harness.js';

test('the Voice Typing key mirrors Granola: hold, double-tap, press to stop', () => {
  expectEqual(stateAfterPress('idle', 800, Infinity), 'idle', 'held to talk, then released');
  expectEqual(stateAfterPress('idle', 120, Infinity), 'idle', 'a lone tap');
  expectEqual(stateAfterPress('idle', 120, 250), 'handsfree', 'a second quick tap');
  expectEqual(stateAfterPress('idle', 120, 900), 'idle', 'a second tap, too late');
  expectEqual(stateAfterPress('handsfree', 100, Infinity), 'idle', 'pressing again stops hands-free');
});

test('the key is named the way Granola names it', () => {
  expectEqual(voiceKeyLabel(['Fn']), 'fn', 'default');
  expectEqual(voiceKeyLabel(['ControlLeft']), 'control', 'control');
  expectEqual(voiceKeyLabel(['AltLeft', 'Space']), '⌥space', 'a combination');
});

test('setting the key accepts a lone modifier', () => {
  const recorder = comboRecorder({ modifiersAlone: true });
  expectEqual(recorder.capture({ t: 'kd', k: 'ControlLeft' }), ['ControlLeft'], 'control');
  expectEqual(recorder.capture({ t: 'kd', k: 'KeyD' }), ['ControlLeft', 'KeyD'], 'control-D');
  expectEqual(comboRecorder().capture({ t: 'kd', k: 'ControlLeft' }), null, 'new hotkeys still need a key');
});

function setup(overrides = {}) {
  const parts = Object.fromEntries(['bar', 'left', 'middle', 'right', 'tabs', 'title', 'add'].map((name) => [name, document.createElement('div')]));
  const sent = [];
  const settings = fakeSettings({
    shortcutBar: true, shortcuts: ['undo'], pack: 'claude', terminalPack: 'claude', lastTerminal: 'com.apple.Terminal',
    agentHomes: {}, hiddenPacks: [], followMacApp: true, customHotkeys: [], voiceTypingKeys: ['Fn'], voiceTypingLeft: true, ...overrides,
  });
  const shortcuts = createShortcuts(parts, {
    send: (m) => sent.push(m), feedback: silentFeedback, settings, beforeSend() {}, onAddHotkey() {},
  });
  shortcuts.placeOnPalmRests(overrides.layout === 'keyboard' ? 'shelf' : 'beside');
  return { ...parts, sent, settings, shortcuts };
}

const GRANOLA = { 'com.granola.app': 'data:image/png;base64,AA==' };
const touch = (el, type, pointerId = 9) => el.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, pointerId, pointerType: 'touch' }));

test('with Granola installed, Voice Typing sits with the general shortcuts', () => {
  const { left, right, shortcuts, settings } = setup();
  expect(!left.querySelector('.voice-key'), 'not without Granola');
  shortcuts.setIcons(GRANOLA);
  expect(left.querySelector('.voice-key'), 'with Granola');
  shortcuts.setFrontApp({ id: 'com.granola.app', name: 'Granola' });
  expect(left.querySelector('.voice-key'), "stays put while Granola's tab shows");
  expect(!right.querySelector('.voice-key'), "not twice: Granola's tab leaves it out");
  settings.set('voiceTypingLeft', false);
  expect(!left.querySelector('.voice-key'), 'switched off');
  expect(right.querySelector('.voice-key'), "back on Granola's tab");
});

const labels = (row) => [...row.children].map((key) => key.getAttribute('aria-label'));

test('Esc, Delete and Send sit under the Voice Typing key', () => {
  const { left, sent, shortcuts, settings } = setup({ layout: 'both' });
  expect(!left.querySelector('.send-row'), 'Both without Granola: the keyboard has Return');
  shortcuts.setIcons(GRANOLA);
  const row = left.querySelector('.voice-key + .send-row');
  expectEqual(labels(row), ['Escape', 'Delete', 'Send'], 'keys');
  row.querySelector('[aria-label="Send"]').click();
  row.querySelector('[aria-label="Escape"]').click();
  expectEqual(sent, [{ t: 'combo', ks: ['Enter'] }, { t: 'combo', ks: ['Escape'] }], 'sent');
  settings.set('voiceTypingLeft', false);
  settings.set('layout', 'trackpad');
  expect(left.querySelector('.send-row'), 'Trackpad only always has it');
});

test('many shortcuts under the keyboard go three to a row', () => {
  const { left, shortcuts, settings } = setup({ layout: 'both', shortcuts: ['undo', 'redo', 'copy', 'paste', 'switchApp', 'spotlight'] });
  shortcuts.setIcons(GRANOLA);
  expect(!left.classList.contains('three-up'), 'six fit two to a row');
  settings.set('shortcuts', ['undo', 'redo', 'copy', 'paste', 'selectAll', 'find', 'save', 'switchApp', 'spotlight']);
  expect(left.classList.contains('three-up'), 'nine go three to a row');
  settings.set('layout', 'trackpad');
  expect(!left.classList.contains('three-up'), 'Trackpad only has the height for two');
  const { left: noVoice } = setup({ layout: 'both', shortcuts: ['undo', 'redo', 'copy', 'paste', 'selectAll', 'find', 'save', 'switchApp', 'spotlight'] });
  expect(!noVoice.classList.contains('three-up'), 'without Voice Typing and Send, nine fit two to a row');
});

test('Delete under the Voice Typing key repeats while held', async () => {
  const { left, sent, shortcuts } = setup({ layout: 'trackpad' });
  shortcuts.setIcons(GRANOLA);
  const del = left.querySelector('[aria-label="Delete"]');
  touch(del, 'pointerdown', 3);
  await wait(700);
  touch(del, 'pointerup', 3);
  expectEqual(sent[0], { t: 'kd', k: 'Backspace' }, 'pressed');
  expect(sent.some((m) => m.r), 'repeated');
  expectEqual(sent.at(-1), { t: 'ku', k: 'Backspace' }, 'released');
});

test("Keyboard only's shelf: Voice Typing and Send left, shortcuts in the middle", () => {
  const { left, middle, shortcuts } = setup({ layout: 'keyboard', shortcuts: ['undo', 'copy'] });
  shortcuts.setIcons(GRANOLA);
  expectEqual(labels(left), ['Voice Typing (Granola)', null], 'left');
  expect(left.querySelector('.send-row'), 'Send row');
  expectEqual(labels(middle), ['Undo', 'Copy'], 'middle');
  shortcuts.placeOnPalmRests(null);
  expectEqual(labels(middle), [], 'empty with the top bar');
});

test('while Granola listens, Esc is Cancel, and any Esc stops it', async () => {
  const { left, sent, shortcuts } = setup({ layout: 'both' });
  shortcuts.setIcons(GRANOLA);
  shortcuts.setFrontApp({ id: 'com.mitchellh.ghostty', name: 'Ghostty' });
  const voice = () => left.querySelector('.voice-key');
  const escape = () => left.querySelector('[data-voice-cancel]');
  expect(voice().textContent.includes('into Ghostty'), `names the app: ${voice().textContent}`);
  for (let i = 0; i < 2; i++) {
    touch(voice(), 'pointerdown');
    touch(voice(), 'pointerup');
    await wait(60);
  }
  expectEqual(voice().dataset.state, 'handsfree', 'hands-free');
  expectEqual(escape().getAttribute('aria-label'), 'Cancel Voice Typing', 'Esc became Cancel');
  sent.length = 0;
  escape().click();
  expectEqual(sent, [{ t: 'combo', ks: ['Escape'] }], 'Esc sent');
  expectEqual(voice().dataset.state, 'idle', 'stopped');
  expectEqual(escape().getAttribute('aria-label'), 'Escape', 'Esc again');

  for (let i = 0; i < 2; i++) {
    touch(voice(), 'pointerdown');
    touch(voice(), 'pointerup');
    await wait(60);
  }
  shortcuts.noteInput({ t: 'kd', k: 'Escape' }); // Esc on the keyboard
  expectEqual(voice().dataset.state, 'idle', 'Esc on the keyboard stops it too');
});

test('sliding from Voice Typing onto Cancel throws the words away', (sandbox) => {
  const { left, sent, shortcuts } = setup({ layout: 'both' });
  Object.assign(left.style, { display: 'grid', gridTemplateColumns: '1fr 1fr', gridAutoRows: '80px', width: '400px' });
  sandbox.append(left);
  shortcuts.setIcons(GRANOLA);
  const voice = left.querySelector('.voice-key');
  const cancel = left.querySelector('[data-voice-cancel]');
  touch(voice, 'pointerdown', 5);
  expectEqual(cancel.getAttribute('aria-label'), 'Cancel Voice Typing', 'Cancel while listening');
  const at = cancel.getBoundingClientRect();
  const over = { bubbles: true, pointerId: 5, pointerType: 'touch', clientX: at.left + at.width / 2, clientY: at.top + at.height / 2 };
  voice.dispatchEvent(new PointerEvent('pointermove', over));
  expect(cancel.classList.contains('armed'), 'Cancel lights up');
  voice.dispatchEvent(new PointerEvent('pointerup', over));
  expectEqual(sent.map((m) => `${m.t}:${m.k ?? m.ks}`), ['kd:Fn', 'combo:Escape', 'ku:Fn'], 'Esc before letting go');
  expectEqual(left.querySelector('.voice-key').dataset.state, 'idle', 'idle');
});

test('holding Voice Typing holds your key on the Mac; double-tap goes hands-free', async () => {
  const { left, sent, shortcuts, settings } = setup({ voiceTypingKeys: ['ControlLeft'] });
  shortcuts.setIcons(GRANOLA);
  const key = () => left.querySelector('.voice-key');
  touch(key(), 'pointerdown');
  expectEqual(key().dataset.state, 'listening', 'while held');
  await wait(350);
  touch(key(), 'pointerup');
  expectEqual(sent, [{ t: 'kd', k: 'ControlLeft' }, { t: 'ku', k: 'ControlLeft' }], 'held, then released');
  expectEqual(key().dataset.state, 'idle', 'after letting go');

  for (let i = 0; i < 2; i++) {
    touch(key(), 'pointerdown');
    touch(key(), 'pointerup');
    await wait(60);
  }
  expectEqual(key().dataset.state, 'handsfree', 'after a double-tap');
  settings.set('shortcuts', ['undo', 'copy']); // a redraw keeps the state
  expectEqual(key().dataset.state, 'handsfree', 'after a redraw');
  touch(key(), 'pointerdown');
  touch(key(), 'pointerup');
  expectEqual(key().dataset.state, 'idle', 'pressed again to stop');
});

test('a redraw while Voice Typing is held never loses the release', () => {
  const { left, sent, shortcuts, settings } = setup();
  shortcuts.setIcons(GRANOLA);
  const held = left.querySelector('.voice-key');
  touch(held, 'pointerdown');
  settings.set('shortcuts', ['undo', 'copy']);
  expect(left.querySelector('.voice-key') === held, 'the held key stays in place');
  touch(held, 'pointerup');
  expectEqual(sent.map((m) => `${m.t}:${m.k}`), ['kd:Fn', 'ku:Fn'], 'sent');
  expect(left.querySelector('.voice-key') !== held, 'redrawn once released');
  touch(left.querySelector('.voice-key'), 'pointerdown');
  shortcuts.releaseVoice();
  expectEqual(sent.at(-1), { t: 'ku', k: 'Fn' }, 'released when the iPad looks away');
});
