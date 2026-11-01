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
  const parts = Object.fromEntries(['bar', 'left', 'right', 'tabs', 'title', 'add'].map((name) => [name, document.createElement('div')]));
  const sent = [];
  const settings = fakeSettings({
    shortcutBar: true, shortcuts: ['undo'], pack: 'claude', terminalPack: 'claude', lastTerminal: 'com.apple.Terminal',
    agentHomes: {}, hiddenPacks: [], followMacApp: true, customHotkeys: [], voiceTypingKeys: ['Fn'], voiceTypingLeft: true, ...overrides,
  });
  const shortcuts = createShortcuts(parts, {
    send: (m) => sent.push(m), feedback: silentFeedback, settings, beforeSend() {}, onAddHotkey() {},
  });
  shortcuts.placeBesideTrackpad(true);
  return { ...parts, sent, settings, shortcuts };
}

const GRANOLA = { 'com.granola.app': 'data:image/png;base64,AA==' };
const touch = (el, type, pointerId = 9) => el.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, pointerId, pointerType: 'touch' }));

test('with Granola installed, Voice Typing sits with the general shortcuts', () => {
  const { left, shortcuts, settings } = setup();
  expect(!left.querySelector('.voice-key'), 'not without Granola');
  shortcuts.setIcons(GRANOLA);
  expect(left.querySelector('.voice-key'), 'with Granola');
  shortcuts.setFrontApp({ id: 'com.granola.app', name: 'Granola' });
  expect(!left.querySelector('.voice-key'), "not twice while Granola's tab shows it");
  shortcuts.setFrontApp({ id: 'com.google.Chrome', name: 'Chrome' });
  expect(left.querySelector('.voice-key') || settings.get('pack') === 'granola', 'back with the general shortcuts');
  settings.set('voiceTypingLeft', false);
  settings.set('pack', 'claude');
  expect(!left.querySelector('.voice-key'), 'switched off');
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
