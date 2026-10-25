import { createTrackpad } from '../../Sources/Tactile/Web/trackpad.js';
import { expect, expectEqual, fakeSettings, silentFeedback, test, touch, wait } from './harness.js';

function setup(sandbox, settings = {}) {
  const sent = [];
  const pad = document.createElement('section');
  pad.style.cssText = 'position: absolute; left: 0; top: 0; width: 800px; height: 500px;';
  sandbox.append(pad);
  createTrackpad(pad, {
    send: (m) => sent.push(m), feedback: silentFeedback, settings: fakeSettings(settings),
    onClick() {}, isCongested: () => false,
    frames: { request: (fn) => setTimeout(() => fn(performance.now()), 16), cancel: (id) => clearTimeout(id) },
  });
  const finger = (type, id, dx, dy = 0) => touch(pad, type, id, { primary: id === 1, dx, dy });
  return { sent, finger };
}

// Movement is sent once per frame.
const frame = () => wait(50);
const total = (sent, t, axis) => sent.filter((m) => m.t === t).reduce((sum, m) => sum + m[axis], 0);

test('two fingers moving together scroll, faster with a higher speed', async (sandbox) => {
  const scrolled = [];
  for (const scrollSpeed of [1, 2]) {
    const { sent, finger } = setup(sandbox, { scrollSpeed });
    finger('pointerdown', 1, -40);
    finger('pointerdown', 2, 40);
    for (let y = 5; y <= 50; y += 5) {
      finger('pointermove', 1, -40, y);
      finger('pointermove', 2, 40, y);
    }
    await frame();
    scrolled.push(total(sent, 'sc', 'y'));
    expect(!sent.some((m) => m.t === 'combo'), 'scrolling must not zoom');
    sandbox.replaceChildren();
  }
  expect(scrolled[0] > 60, `scrolled ${scrolled[0]}`);
  expect(Math.abs(scrolled[1] - 2 * scrolled[0]) <= 2, `double speed scrolled ${scrolled[1]}`);
});

test('pinching out zooms in, and pinching in zooms out', async (sandbox) => {
  const { sent, finger } = setup(sandbox);
  finger('pointerdown', 1, -50);
  finger('pointerdown', 2, 50);
  for (let x = 60; x <= 180; x += 10) finger('pointermove', 2, x);
  for (let x = 170; x >= -10; x -= 10) finger('pointermove', 2, x);
  await frame();
  const zooms = sent.filter((m) => m.t === 'combo').map((m) => m.ks[1]);
  expectEqual(zooms, ['Equal', 'Equal', 'Minus', 'Minus', 'Minus'], 'zoom steps');
  expectEqual(total(sent, 'sc', 'y') + total(sent, 'sc', 'x'), 0, 'scrolled');
});

test('with Three-Finger Drag on, three fingers drag', async (sandbox) => {
  const { sent, finger } = setup(sandbox, { threeFingerDrag: true });
  for (const id of [1, 2, 3]) finger('pointerdown', id, id * 40);
  for (let x = 4; x <= 40; x += 4) for (const id of [1, 2, 3]) finger('pointermove', id, id * 40 + x);
  await frame();
  for (const id of [1, 2, 3]) finger('pointerup', id, id * 40 + 40);
  expectEqual(sent[0], { t: 'md', b: 'l' }, 'first message');
  expect(total(sent, 'mv', 'x') > 30, 'pointer moved right');
  expectEqual(sent.at(-1), { t: 'mu', b: 'l' }, 'last message');
  expect(!sent.some((m) => m.t === 'sys'), 'no swipe');
});

test('without it, three fingers swipe between spaces', async (sandbox) => {
  const { sent, finger } = setup(sandbox);
  for (const id of [1, 2, 3]) finger('pointerdown', id, id * 40);
  for (let x = 10; x <= 100; x += 10) for (const id of [1, 2, 3]) finger('pointermove', id, id * 40 - x);
  expectEqual(sent.filter((m) => m.t === 'sys'), [{ t: 'sys', k: 'spaceRight' }], 'swipes');
});
