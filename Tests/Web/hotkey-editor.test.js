import { createKeyboard } from '../../Sources/Tactile/Web/keyboard.js';
import { comboRecorder } from '../../Sources/Tactile/Web/hotkey-editor.js';
import { expectEqual, fakeSettings, silentFeedback, test, touch } from './harness.js';

test('recording keeps the modifiers held when a key goes down', () => {
  const recorder = comboRecorder();
  const steps = [
    { t: 'kd', k: 'ShiftLeft' }, { t: 'kd', k: 'MetaLeft' }, { t: 'kd', k: 'KeyR' },
  ].map((message) => recorder.capture(message));
  expectEqual(steps, [null, null, ['ShiftLeft', 'MetaLeft', 'KeyR']], 'shift, command, R');
  recorder.capture({ t: 'ku', k: 'ShiftLeft' });
  expectEqual(recorder.capture({ t: 'kd', k: 'KeyT' }), ['MetaLeft', 'KeyT'], 'after letting go of shift');
  expectEqual(recorder.capture({ t: 'kd', k: 'KeyT', r: true }), null, 'a repeat');
});

test('while recording, typing on the keyboard sends nothing to the Mac', (sandbox) => {
  // The same routing app.js uses: a recorder, when set, gets the keyboard's messages.
  const toMac = [];
  const recorder = comboRecorder();
  let recorded = null;
  let recording = (message) => { recorded = recorder.capture(message) ?? recorded; };
  const deck = document.createElement('section');
  deck.className = 'deck';
  sandbox.append(deck);
  createKeyboard(deck, {
    send: (message) => (recording ? recording(message) : toMac.push(message)),
    feedback: silentFeedback, settings: fakeSettings(),
  });
  const key = (code) => deck.querySelector(`[data-code="${code}"]`);
  touch(key('MetaLeft'), 'pointerdown', 1);
  touch(key('MetaLeft'), 'pointerup', 1);
  touch(key('KeyK'), 'pointerdown', 2);
  touch(key('KeyK'), 'pointerup', 2);
  expectEqual(recorded, ['MetaLeft', 'KeyK'], 'recorded');
  expectEqual(toMac, [], 'sent to the Mac');
  recording = null;
  touch(key('KeyK'), 'pointerdown', 3);
  expectEqual(toMac.map((m) => m.k), ['KeyK'], 'typing reaches the Mac again afterwards');
});
