import { createKeyboard } from '../../Sources/Tactile/Web/keyboard.js';
import { TypingModel } from '../../Sources/Tactile/Web/typing-model.js';
import { expect, expectEqual, fakeSettings, memoryStorage, silentFeedback, test, touch, wait } from './harness.js';

/** A keyboard wired to a recorder instead of the network. */
function setup(sandbox, settings = {}, model = null) {
  const sent = [];
  const deck = document.createElement('section');
  deck.className = 'deck';
  sandbox.append(deck);
  const keyboard = createKeyboard(deck, { send: (m) => sent.push(m), feedback: silentFeedback, settings: fakeSettings(settings), model });
  const key = (code) => deck.querySelector(`[data-code="${code}"]`);
  const repeats = (code) => sent.filter((m) => m.t === 'kd' && m.k === code && m.r).length;
  return { keyboard, sent, key, repeats };
}

test('a held key repeats, and stops as soon as it is released', async (sandbox) => {
  const { key, repeats, sent } = setup(sandbox);
  touch(key('Backspace'), 'pointerdown', 1);
  await wait(800);
  touch(key('Backspace'), 'pointerup', 1);
  const whileHeld = repeats('Backspace');
  await wait(500);
  expect(whileHeld > 0, 'delete should repeat while held');
  expectEqual(repeats('Backspace'), whileHeld, 'repeats after release');
  expectEqual(sent.at(-1), { t: 'ku', k: 'Backspace' }, 'last message');
});

test('tapping delete quickly, many times, never leaves it repeating', async (sandbox) => {
  const { key, repeats } = setup(sandbox);
  for (let i = 0; i < 12; i++) {
    touch(key('Backspace'), 'pointerdown', 1);
    await wait(i % 3 === 0 ? 520 : 40); // some taps last long enough to start repeating
    touch(key('Backspace'), 'pointerup', 1);
    await wait(30);
  }
  const afterTapping = repeats('Backspace');
  await wait(500);
  expectEqual(repeats('Backspace'), afterTapping, 'repeats after the last tap');
});

test('a finger lifted off the keyboard still ends its key', async (sandbox) => {
  const { key, repeats } = setup(sandbox);
  touch(key('Backspace'), 'pointerdown', 2);
  await wait(600);
  // The lift happens outside the keyboard (a window-level event).
  window.dispatchEvent(new PointerEvent('pointerup', { pointerId: 2, pointerType: 'touch' }));
  const count = repeats('Backspace');
  await wait(400);
  expectEqual(repeats('Backspace'), count, 'repeats after an off-keyboard lift');
});

test('a reused touch ID ends the stale press first', async (sandbox) => {
  const { key, repeats, sent } = setup(sandbox);
  touch(key('Backspace'), 'pointerdown', 3);
  await wait(600);
  touch(key('KeyA'), 'pointerdown', 3); // the lift for the first touch never arrived
  const count = repeats('Backspace');
  touch(key('KeyA'), 'pointerup', 3);
  await wait(400);
  expectEqual(repeats('Backspace'), count, 'delete repeats after its touch ID was reused');
  expect(sent.some((m) => m.t === 'ku' && m.k === 'Backspace'), 'delete was released');
});

test('Shift latches for exactly one key', async (sandbox) => {
  const { key, sent } = setup(sandbox);
  touch(key('ShiftLeft'), 'pointerdown', 4);
  touch(key('ShiftLeft'), 'pointerup', 4);
  touch(key('KeyG'), 'pointerdown', 5);
  touch(key('KeyG'), 'pointerup', 5);
  expectEqual(sent.map((m) => `${m.t}:${m.k}`), ['kd:ShiftLeft', 'kd:KeyG', 'ku:KeyG', 'ku:ShiftLeft'], 'messages');
});

test('with Rest Fingers on, a resting finger types nothing', async (sandbox) => {
  const { key, sent } = setup(sandbox, { restFingers: true });
  touch(key('KeyS'), 'pointerdown', 6);
  await wait(500);
  touch(key('KeyS'), 'pointerup', 6);
  expectEqual(sent, [], 'messages');
});

test('with Rest Fingers on, rolled keys keep their order', async (sandbox) => {
  const { key, sent } = setup(sandbox, { restFingers: true });
  touch(key('KeyT'), 'pointerdown', 7);
  await wait(40);
  touch(key('KeyH'), 'pointerdown', 8);
  await wait(40);
  touch(key('KeyH'), 'pointerup', 8); // H lifts first
  touch(key('KeyT'), 'pointerup', 7);
  expectEqual(sent.filter((m) => m.t === 'kd').map((m) => m.k), ['KeyT', 'KeyH'], 'typed');
});

test('with Adapt to My Typing on, a key learns where it is pressed', async (sandbox) => {
  const model = new TypingModel(memoryStorage());
  const { key, sent } = setup(sandbox, { adaptiveTyping: true }, model);
  const width = key('KeyF').getBoundingClientRect().width;
  // Always pressing F near its right edge...
  for (let i = 0; i < 12; i++) {
    touch(key('KeyF'), 'pointerdown', 20 + i, { dx: width * 0.42 });
    touch(key('KeyF'), 'pointerup', 20 + i, { dx: width * 0.42 });
  }
  sent.length = 0;
  // ...moves F's area right, so a touch just past F's edge still types F.
  touch(key('KeyF'), 'pointerdown', 40, { dx: width * 0.56 });
  touch(key('KeyF'), 'pointerup', 40, { dx: width * 0.56 });
  expectEqual(sent.filter((m) => m.t === 'kd').map((m) => m.k), ['KeyF'], 'typed');
});

test('a key deleted right away is not learned from', async (sandbox) => {
  const model = new TypingModel(memoryStorage());
  const { key } = setup(sandbox, { adaptiveTyping: true }, model);
  for (let i = 0; i < 8; i++) {
    touch(key('KeyJ'), 'pointerdown', 50 + i, { dx: 20 });
    touch(key('KeyJ'), 'pointerup', 50 + i, { dx: 20 });
    touch(key('Backspace'), 'pointerdown', 60 + i);
    touch(key('Backspace'), 'pointerup', 60 + i);
  }
  expectEqual(model.offset('KeyJ'), { x: 0, y: 0 }, 'learned offset');
});

test('keys show the Mac layout, and US labels again without it', async (sandbox) => {
  const { keyboard, key } = setup(sandbox);
  keyboard.setLabels({ KeyQ: ['a', 'A'], Digit2: ['é', '2'], Semicolon: ['m', 'M'] });
  expectEqual(key('KeyQ').textContent, 'A', 'Q on AZERTY');
  expectEqual(key('Digit2').textContent, '2é', 'digit row on AZERTY');
  expectEqual(key('Semicolon').textContent, 'M', 'semicolon key on AZERTY');
  keyboard.setLabels({});
  expectEqual(key('KeyQ').textContent, 'Q', 'Q on US');
  expectEqual(key('Semicolon').textContent, ':;', 'semicolon key on US');
});
