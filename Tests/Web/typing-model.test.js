import { pickKey, TypingModel } from '../../Sources/Tactile/Web/typing-model.js';
import { expect, expectEqual, memoryStorage, test } from './harness.js';

const rect = (left) => ({ left, top: 0, width: 50, height: 50 });
const row = [{ code: 'KeyA', rect: rect(0) }, { code: 'KeyS', rect: rect(56) }];
const none = () => ({ x: 0, y: 0 });

test('a touch picks the key it lands on, or the nearest one in a gap', () => {
  expectEqual(pickKey(25, 25, row, none), 'KeyA', 'inside A');
  expectEqual(pickKey(52, 25, row, none), 'KeyA', 'gap, nearer A');
  expectEqual(pickKey(54, 25, row, none), 'KeyS', 'gap, nearer S');
  expectEqual(pickKey(25, 200, row, none), null, 'far away');
});

test('learned offsets need a few touches, and stay small', () => {
  const model = new TypingModel(memoryStorage());
  for (let i = 0; i < 5; i++) model.record('KeyA', 0.9, 0);
  expectEqual(model.offset('KeyA'), { x: 0, y: 0 }, 'after 5 touches');
  model.record('KeyA', 0.9, 0);
  expectEqual(model.offset('KeyA').x, 0.3, 'after 6 touches (clamped)');
});

test('the model is saved, and forgetting the last touch undoes it', () => {
  const storage = memoryStorage();
  const model = new TypingModel(storage);
  for (let i = 0; i < 6; i++) model.record('KeyA', 0.2, -0.1);
  const learned = model.offset('KeyA');
  model.record('KeyA', -0.3, 0.3);
  model.forgetLast();
  expectEqual(new TypingModel(storage).offset('KeyA'), learned, 'reloaded after forgetLast');
  model.reset();
  expectEqual(new TypingModel(storage).offset('KeyA'), { x: 0, y: 0 }, 'after reset');
});

test('a corrupt saved model starts fresh', () => {
  const storage = memoryStorage();
  storage.set('tactile.typing.v1', '{not json');
  expect(new TypingModel(storage).offset('KeyA').x === 0, 'offset');
});
