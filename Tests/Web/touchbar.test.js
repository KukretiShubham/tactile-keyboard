import { upgrade } from '../../Sources/Tactile/Web/settings.js';
import { countTasks, createTouchBar, longAge, shortAge } from '../../Sources/Tactile/Web/touchbar.js';
import { expect, expectEqual, fakeSettings, silentFeedback, test, wait } from './harness.js';

const NOW = Date.UTC(2026, 10, 2, 12, 0);
const minutes = (n) => NOW - n * 60000;
const ACTIVITY = {
  t: 'agents', now: NOW, apps: {
    claude: {
      usage: [{ label: '5-hour', percent: 42, resets: NOW + 3600000 }, { label: 'Week', percent: 18 }],
      tasks: [
        { id: 'c1', title: 'Fix flaky login test', project: 'web-app', state: 'waiting', since: minutes(1), ask: 'npm test', app: 'com.anthropic.claudefordesktop' },
        { id: 'c2', title: 'Add dark mode', project: 'web-app', state: 'working', since: minutes(6), now: 'Run the checks', app: 'com.anthropic.claudefordesktop',
          steps: [{ text: 'Read', state: 'done' }, { text: 'Build', state: 'current' }, { text: 'Check', state: 'todo' }] },
        { id: 'c3', title: 'Release notes', project: 'docs', state: 'done', since: minutes(22) },
      ],
    },
    codex: { tasks: [{ id: 'x1', title: 'Bump dependencies', project: 'cli', state: 'working', since: minutes(3) }] },
  },
};

function setup(overrides = {}) {
  // Each Touch Bar adds its card's scrim to the page when first opened.
  document.querySelectorAll('.tb-scrim').forEach((scrim) => scrim.remove());
  const sent = [];
  const settings = fakeSettings({ functionRow: 'touchbar', agentClaude: true, agentCodex: true, agentUsage: true, ...overrides });
  const bar = createTouchBar({ send: (m) => sent.push(m), feedback: silentFeedback, settings, isReady: () => true });
  return { bar, sent, settings };
}
const labels = (root, selector) => [...root.querySelectorAll(selector)].map((node) => node.getAttribute('aria-label'));

test('older saved settings: the function row switch becomes the Touch Bar or Off', () => {
  expectEqual(upgrade({ functionRow: true }).functionRow, 'touchbar', 'on');
  expectEqual(upgrade({ functionRow: false }).functionRow, 'off', 'off');
  expectEqual(upgrade({ functionRow: 'touchbar' }).functionRow, 'touchbar', 'already new');
});

test('ages and counts read the way the Touch Bar shows them', () => {
  expectEqual([shortAge(20000), shortAge(6 * 60000), shortAge(130 * 60000)], ['now', '6m', '2h'], 'short');
  expectEqual([longAge(6 * 60000), longAge(65 * 60000), longAge(120 * 60000)], ['6 min', '1 hr 5 min', '2 hr'], 'long');
  expectEqual(countTasks(ACTIVITY.apps.claude.tasks), { working: 1, waiting: 1, done: 1 }, 'counts');
});

test('the Touch Bar asks the Mac only for the agents it shows', () => {
  const { bar, sent, settings } = setup();
  bar.setInstalled(['claude']);
  expectEqual(sent.at(-1), { t: 'agents', ks: ['claude'], r: true }, 'Claude only: Codex is not on the Mac');
  settings.set('agentUsage', false);
  expectEqual(sent.at(-1), { t: 'agents', ks: ['claude'], r: false }, 'without plan usage');
  settings.set('functionRow', 'keys');
  expectEqual(sent.at(-1), { t: 'agents', ks: [], r: false }, 'nothing once the Touch Bar is off');
});

test('each agent shows plan usage and how many tasks are where', (sandbox) => {
  const { bar } = setup();
  sandbox.append(bar.element);
  bar.setInstalled(['claude', 'codex']);
  bar.setActivity(ACTIVITY);
  expectEqual(labels(bar.element, '.tb-agent'), ['Claude: 42% of plan used 1 needs you 1 working 1 done', 'Codex: 1 working'], 'agents');
  expect(bar.element.querySelector('.tb-agent').classList.contains('needs'), 'a task needing you tints Claude');
  expect(bar.element.querySelector('[aria-label="Escape"]'), 'esc');
  expect(bar.element.querySelector('[aria-label="Show All Controls"]'), 'Control Strip');
});

test('tapping an agent lists its tasks; tapping a task shows its steps', (sandbox) => {
  const { bar, sent } = setup();
  sandbox.append(bar.element);
  bar.setInstalled(['claude', 'codex']);
  bar.setActivity(ACTIVITY);
  bar.element.querySelector('.tb-agent').click();
  expectEqual([...bar.element.querySelectorAll('.tb-chip .tb-title')].map((t) => t.textContent),
    ['Fix flaky login test', 'Add dark mode', 'Release notes'], 'chips');
  expect(!bar.element.querySelector('.tb-strip'), 'the tasks take the Control Strip’s room');

  bar.element.querySelector('[data-task="c2"]').click();
  const card = document.querySelector('.tb-card');
  expectEqual(card.querySelector('.card-step-count').textContent, 'Step 2 of 3', 'progress');
  expectEqual([...card.querySelectorAll('.card-steps li')].map((li) => li.className), ['done', 'current', 'todo'], 'steps');
  expect(card.querySelector('.card-now').textContent.includes('Run the checks'), 'what it’s doing now');
  expect(card.querySelector('.card-button').classList.contains('tinted'), 'a quiet button while it works');
  card.querySelector('.card-button').click();
  expectEqual(sent.at(-1), { t: 'openTask', k: 'c2' }, 'Open in Claude');
  expect(document.querySelector('.tb-scrim').hidden, 'closed');

  bar.element.querySelector('[data-task="c1"]').click();
  expect(card.querySelector('.card-ask code').textContent === 'npm test', 'what it’s waiting to run');
  expectEqual(card.querySelector('.card-button').textContent, 'Answer in Claude', 'answer button');
  expect(!card.querySelector('.card-button').classList.contains('tinted'), 'a solid button when it needs you');
  bar.element.querySelector('[data-task="c3"]').click();
  expect(!card.querySelector('.card-button'), 'no app to open, no button');

  bar.element.querySelector('[aria-label="Close"]').click();
  expect(bar.element.querySelector('.tb-strip'), 'back to the Control Strip');
  expect(document.querySelector('.tb-scrim').hidden, 'and the card closed');
});

test('tapping the task again closes its card; another task opens its own', (sandbox) => {
  const { bar } = setup();
  sandbox.dataset.functionRow = 'touchbar'; // laid out, so taps land on tasks
  sandbox.append(bar.element);
  bar.setInstalled(['claude']);
  bar.setActivity(ACTIVITY);
  bar.element.querySelector('.tb-agent').click();
  // A tap on the screen over a task: iPad then clicks whatever is there.
  const tapOver = (selector) => {
    const target = bar.element.querySelector(selector);
    const r = target.getBoundingClientRect();
    document.querySelector('.tb-scrim').dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true, cancelable: true, pointerType: 'touch', clientX: r.left + r.width / 2, clientY: r.top + r.height / 2,
    }));
    target.click();
  };
  const scrim = () => document.querySelector('.tb-scrim');
  const title = () => document.querySelector('.tb-card .card-title').textContent;

  bar.element.querySelector('[data-task="c2"]').click();
  tapOver('[data-task="c3"]');
  expect(!scrim().hidden, 'another task: still open');
  expectEqual(title(), 'Release notes', 'with that task');
  tapOver('[data-task="c3"]');
  expect(scrim().hidden, 'the same task again: closed, and it stays closed');
});

test('an update leaves the card’s button in place while it’s pressed', (sandbox) => {
  const { bar, sent } = setup();
  sandbox.append(bar.element);
  bar.setInstalled(['claude']);
  bar.setActivity(ACTIVITY);
  bar.element.querySelector('.tb-agent').click();
  bar.element.querySelector('[data-task="c2"]').click();
  const open = document.querySelector('.tb-card .card-button');
  bar.setActivity(structuredClone(ACTIVITY));
  expect(open.isConnected, 'same button after an update');
  open.click();
  expectEqual(sent.at(-1), { t: 'openTask', k: 'c2' }, 'Open in Claude');
});

test('a tap outside the card only closes it', (sandbox) => {
  const { bar } = setup();
  sandbox.append(bar.element);
  bar.setInstalled(['claude']);
  bar.setActivity(ACTIVITY);
  bar.element.querySelector('.tb-agent').click();
  bar.element.querySelector('[data-task="c2"]').click();
  const scrim = document.querySelector('.tb-scrim');
  expect(!scrim.hidden, 'open');
  let reached = false;
  const listener = () => { reached = true; };
  document.body.addEventListener('pointerdown', listener);
  scrim.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true, pointerType: 'touch' }));
  document.body.click(); // iPad's click after the tap, which goes nowhere
  document.body.removeEventListener('pointerdown', listener);
  expect(scrim.hidden, 'closed');
  expect(!reached, 'the tap went no further, so no key types');
});

test('a finished task disappearing closes its card; a disconnect clears everything', (sandbox) => {
  const { bar } = setup();
  sandbox.append(bar.element);
  bar.setInstalled(['claude']);
  bar.setActivity(ACTIVITY);
  bar.element.querySelector('.tb-agent').click();
  bar.element.querySelector('[data-task="c3"]').click();
  const later = structuredClone(ACTIVITY);
  later.apps.claude.tasks.pop();
  bar.setActivity(later);
  expect(document.querySelector('.tb-scrim').hidden, 'card closed');
  bar.reset();
  expectEqual(labels(bar.element, '.tb-agent'), [], 'no agents until the Mac says again');
});

test('tasks scroll sideways, and updates wait for a swipe to finish', async (sandbox) => {
  const { bar } = setup();
  sandbox.append(bar.element);
  bar.setInstalled(['claude']);
  bar.setActivity(ACTIVITY);
  bar.element.querySelector('.tb-agent').click();
  const scroller = bar.element.querySelector('.tb-scroll');
  expectEqual(getComputedStyle(scroller.querySelector('.tb-chip')).touchAction, 'pan-x', 'a finger on a task can pan');

  const chip = bar.element.querySelector('[data-task="c2"]');
  chip.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, pointerType: 'touch' }));
  const later = structuredClone(ACTIVITY);
  later.apps.claude.tasks[1].title = 'Add dark mode, renamed';
  bar.setActivity(later);
  expect(chip.isConnected, 'the touched task stays put');
  chip.dispatchEvent(new PointerEvent('pointercancel', { bubbles: true, pointerType: 'touch' }));
  await wait(400);
  expect(!chip.isConnected, 'redrawn once let go');
  expectEqual(bar.element.querySelector('[data-task="c2"] .tb-title').textContent, 'Add dark mode, renamed', 'with the update');
});

test('Esc and the controls reach the Mac', (sandbox) => {
  const { bar, sent } = setup();
  sandbox.append(bar.element);
  bar.element.querySelector('[aria-label="Escape"]').click();
  bar.element.querySelector('[aria-label="Mute"]').click();
  bar.element.querySelector('[aria-label="Show All Controls"]').click();
  expectEqual(labels(bar.element, '.tb-control').length, 11, 'every control');
  bar.element.querySelector('[aria-label="Volume Up"]').click();
  expectEqual(sent, [{ t: 'combo', ks: ['Escape'] }, { t: 'sys', k: 'mute' }, { t: 'sys', k: 'volumeUp' }], 'sent');
});
