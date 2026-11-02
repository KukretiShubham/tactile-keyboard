// The Touch Bar: a MacBook-style strip in place of the function row. Esc on
// the left, the Control Strip on the right, and in between what Claude and
// Codex are doing on the Mac (see AgentMonitor on the Mac). Tap an agent to
// see its tasks; tap a task to see its steps. Holding fn shows F1–F12 instead
// (styles.css), as on a Mac.
import { ICONS } from './icons.js';
import { clamp, el } from './util.js';

export const AGENTS = [
  { id: 'claude', name: 'Claude', setting: 'agentClaude', icon: 'com.anthropic.claudefordesktop' },
  { id: 'codex', name: 'Codex', setting: 'agentCodex', icon: 'com.openai.codex' },
];

const CONTROLS = ['brightnessDown', 'brightnessUp', 'missionControl', 'spotlight', 'previous', 'playPause', 'next',
  'mute', 'volumeDown', 'volumeUp', 'lockScreen'];
const CONTROL_NAMES = {
  brightnessDown: 'Brightness Down', brightnessUp: 'Brightness Up', missionControl: 'Mission Control', spotlight: 'Spotlight',
  previous: 'Previous', playPause: 'Play or Pause', next: 'Next', mute: 'Mute', volumeDown: 'Volume Down',
  volumeUp: 'Volume Up', lockScreen: 'Lock Screen',
};
const svg = (body, size = 18) => `<svg viewBox="0 0 24 24" width="${size}" height="${size}" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
const CHEVRON = svg('<path d="M15 5l-7 7 7 7"/>');
const CLOSE = svg('<path d="M7 7l10 10M17 7L7 17"/>', 16);
// Task states, in the order the Touch Bar counts them.
const STATES = ['waiting', 'working', 'done'];
const STATE_WORDS = { working: 'Working', waiting: 'Needs you', done: 'Done' };
// A task card is popover-sized; a title longer than this gets a wider one.
const LONG_TITLE = 38;

/** Minutes or hours, short: "now", "6m", "2h". */
export function shortAge(ms) {
  const minutes = Math.floor(Math.max(0, ms) / 60000);
  if (minutes < 1) return 'now';
  if (minutes < 60) return `${minutes}m`;
  return `${Math.floor(minutes / 60)}h`;
}

/** "6 min", "1 hr 5 min". */
export function longAge(ms) {
  const minutes = Math.max(1, Math.round(Math.max(0, ms) / 60000));
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  return minutes % 60 ? `${hours} hr ${minutes % 60} min` : `${hours} hr`;
}

/** When a limit resets: a time today, or a weekday and time after today. */
export function resetTime(at, now = Date.now()) {
  const date = new Date(at);
  const time = date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  if (date.toDateString() === new Date(now).toDateString()) return time;
  return `${date.toLocaleDateString([], { weekday: 'short' })} ${time}`;
}

/** Working, waiting and done counts, for the agent's button. */
export function countTasks(tasks = []) {
  const counts = { working: 0, waiting: 0, done: 0 };
  for (const task of tasks) counts[task.state] = (counts[task.state] ?? 0) + 1;
  return counts;
}

export function createTouchBar({ send, feedback, settings, isReady }) {
  const bar = el('div', { className: 'touchbar', attrs: { role: 'toolbar', 'aria-label': 'Touch Bar' } });
  let icons = {};
  let installed = []; // agents on the Mac; empty until it says (older Macs never do)
  let activity = {}; // agent → { tasks, usage }
  let clockOffset = 0; // the Mac's clock minus this iPad's
  let view = 'home'; // 'home' | 'controls' | an agent's id
  let card = null; // { kind: 'task' | 'usage', agent, id }

  const macNow = () => Date.now() + clockOffset;
  const isOn = () => settings.get('functionRow') === 'touchbar';
  const shown = () => AGENTS.filter((agent) => installed.includes(agent.id) && settings.get(agent.setting));
  // The limit the bar shows (the 5-hour session comes first), if usage is on.
  const headline = (agent) => (settings.get('agentUsage') ? activity[agent.id]?.usage?.[0] : null);

  // Touches make a soft key sound; the button acts when the finger lifts.
  bar.addEventListener('pointerdown', (event) => {
    if (event.target.closest('button')) feedback.key('mod');
  });

  // Updates from the Mac redraw the strip, which would pull a task out from
  // under a finger mid-swipe, so they wait while a finger is down (here or on
  // a card, see `scrim`) and until the tasks stop gliding.
  let touching = false;
  let scrolledAt = 0;
  let deferred = 0;
  bar.addEventListener('pointerdown', () => { touching = true; });
  for (const type of ['pointerup', 'pointercancel']) addEventListener(type, () => { touching = false; }, true);
  bar.addEventListener('scroll', () => { scrolledAt = performance.now(); }, true);
  function update() {
    clearTimeout(deferred);
    if (touching || performance.now() - scrolledAt < 300) deferred = setTimeout(update, 300);
    else render();
  }

  // ── Pieces

  function button(className, label, onClick, ...children) {
    const node = el('button', { className: `tb ${className}`, attrs: { 'aria-label': label } }, ...children);
    node.addEventListener('click', onClick);
    return node;
  }
  const icon = (markup) => el('span', { html: markup });
  const glyph = (state) => el('span', { className: `tb-glyph ${state}`, attrs: { 'aria-hidden': 'true' }, text: state === 'waiting' ? '!' : state === 'done' ? '✓' : '' });
  const meter = (percent, wide = false) => el('span', { className: `tb-meter${wide ? ' wide' : ''}`, style: { '--p': clamp(percent, 0, 100) } }, el('i'));
  const percent = (limit) => el('span', { className: 'tb-percent', text: `${limit.percent}%` });
  const appIcon = (agent) => (icons[agent.icon]
    ? el('img', { className: 'tb-icon', attrs: { src: icons[agent.icon], alt: '' } })
    : el('span', { className: 'tb-name', text: agent.name }));

  const esc = () => button('tb-esc', 'Escape', () => send({ t: 'combo', ks: ['Escape'] }), el('span', { text: 'esc' }));
  const close = () => button('tb-close', 'Close', () => show('home'), icon(CLOSE));
  const control = (sys, extra = '') => button(`tb-control ${extra}`, CONTROL_NAMES[sys], () => send({ t: 'sys', k: sys }), icon(ICONS[sys]));

  // The Control Strip: ‹ opens every control; brightness and volume open them
  // too (as on a Mac, where they become sliders); mute and lock act at once.
  function controlStrip() {
    const open = () => show('controls');
    return el('div', { className: 'tb-strip' },
      button('tb-chevron', 'Show All Controls', open, icon(CHEVRON)),
      button('tb-control tb-optional', 'Brightness', open, icon(ICONS.brightnessUp)),
      button('tb-control', 'Volume', open, icon(ICONS.volumeUp)),
      control('mute'),
      control('lockScreen', 'tb-optional'));
  }

  // An agent at rest: its icon, plan usage and how many tasks are where.
  function agentButton(agent) {
    const counts = countTasks(activity[agent.id]?.tasks);
    const states = STATES.filter((state) => counts[state]);
    const limit = headline(agent);
    const parts = [appIcon(agent)];
    if (limit) parts.push(meter(limit.percent), percent(limit));
    parts.push(...states.map((state) => el('span', { className: 'tb-count' }, glyph(state), el('span', { text: String(counts[state]) }))));
    if (parts.length === 1 && activity[agent.id]) parts.push(el('span', { className: 'tb-quiet', text: 'No tasks' }));
    const label = [`${agent.name}:`, limit && `${limit.percent}% of plan used`,
      ...states.map((state) => `${counts[state]} ${STATE_WORDS[state].toLowerCase()}`)].filter(Boolean).join(' ');
    return button(`tb-agent${counts.waiting ? ' needs' : ''}`, label, () => show(agent.id), ...parts);
  }

  function taskChip(agent, task) {
    const chip = button(`tb-chip ${task.state}`, `${task.title}, ${STATE_WORDS[task.state]}`,
      () => openCard({ kind: 'task', agent, id: task.id }),
      glyph(task.state), el('span', { className: 'tb-title', text: task.title }),
      el('span', { className: 'tb-age', text: shortAge(macNow() - task.since) }));
    chip.dataset.task = task.id;
    return chip;
  }

  // An agent opened: its plan usage (tap for every limit), then its tasks.
  function agentView(agent) {
    const tasks = activity[agent.id]?.tasks ?? [];
    const limit = headline(agent);
    const lead = limit
      ? [button('tb-usage', `${agent.name} plan usage: ${limit.percent}%`, () => openCard({ kind: 'usage', agent }),
        appIcon(agent), meter(limit.percent, true), percent(limit),
        limit.resets ? el('span', { className: 'tb-reset', text: `resets ${resetTime(limit.resets, macNow())}` }) : ''),
      el('span', { className: 'tb-divider' })]
      : [el('span', { className: 'tb-label' }, appIcon(agent))];
    const empty = el('span', { className: 'tb-quiet', text: activity[agent.id] ? 'No tasks in the last few hours' : 'Connecting…' });
    const chips = tasks.length ? tasks.map((task) => taskChip(agent, task)) : [empty];
    return [...lead, el('div', { className: 'tb-scroll' }, ...chips)];
  }

  function render() {
    const scrolled = bar.querySelector('.tb-scroll')?.scrollLeft ?? 0;
    const agent = AGENTS.find((a) => a.id === view);
    let middle;
    if (view === 'controls') middle = [close(), ...CONTROLS.map((sys) => control(sys))];
    else if (agent) middle = [close(), ...agentView(agent)];
    else middle = shown().map(agentButton);
    bar.dataset.view = view;
    bar.replaceChildren(esc(), el('div', { className: 'tb-middle' }, ...middle), ...(view === 'home' ? [controlStrip()] : []));
    const scroller = bar.querySelector('.tb-scroll');
    if (scroller) scroller.scrollLeft = scrolled;
    if (card) renderCard();
  }

  /** 'home', 'controls' or an agent's tasks (home if that agent is hidden). */
  function show(next) {
    if (next !== view) closeCard();
    const hiddenAgent = AGENTS.some((a) => a.id === next) && !shown().some((a) => a.id === next);
    view = hiddenAgent ? 'home' : next;
    render();
  }

  // ── Task and usage cards: a popover under what was tapped. Tapping the
  // task again closes it, another Touch Bar button works as usual, and a tap
  // anywhere else only closes it (it never types), as with popovers on iPad.

  const scrim = el('div', { className: 'tb-scrim', attrs: { hidden: '' } });
  const popover = el('div', { className: 'tb-card', attrs: { role: 'dialog', 'aria-modal': 'true' } });
  scrim.append(popover);
  scrim.addEventListener('pointerdown', (event) => {
    touching = true;
    if (popover.contains(event.target)) return;
    event.preventDefault();
    event.stopPropagation();
    scrim.hidden = true;
    const under = document.elementFromPoint(event.clientX, event.clientY)?.closest('.touchbar button');
    const same = under?.classList.contains('selected');
    closeCard();
    if (under && !same) under.click();
    swallowClick();
  });

  // Once the card is gone, iPad sends the tap's click to whatever was under
  // it, which would open the card again (or press a button by surprise).
  function swallowClick() {
    const swallow = (event) => {
      event.preventDefault();
      event.stopPropagation();
    };
    addEventListener('click', swallow, { capture: true, once: true });
    setTimeout(() => removeEventListener('click', swallow, { capture: true }), 600);
  }

  function openCard(next) {
    card = next;
    scrim.hidden = false;
    if (!scrim.isConnected) document.body.append(scrim);
    renderCard();
  }

  function closeCard() {
    if (!card) return;
    card = null;
    scrim.hidden = true;
    select(null);
  }

  // Outlines what the card points at.
  function select(anchor) {
    bar.querySelectorAll('.selected').forEach((node) => node.classList.remove('selected'));
    anchor?.classList.add('selected');
  }

  // Drawn again with every update, so it follows its task, and closes once
  // the task is gone. What hasn't changed is left alone, so a button being
  // pressed isn't swapped out from under the finger.
  function renderCard() {
    const { agent, kind, id } = card;
    const entry = activity[agent.id] ?? {};
    let content;
    let anchor;
    let wide = false;
    if (kind === 'usage') {
      if (!entry.usage?.length || !settings.get('agentUsage')) return closeCard();
      content = usageCard(agent, entry.usage);
      anchor = bar.querySelector('.tb-usage');
    } else {
      const task = entry.tasks?.find((t) => t.id === id);
      if (!task) return closeCard();
      content = taskCard(agent, task);
      anchor = bar.querySelector(`[data-task="${CSS.escape(id)}"]`);
      wide = task.title.length > LONG_TITLE;
    }
    popover.classList.toggle('wide', wide);
    const next = el('div', {}, ...content);
    if (next.innerHTML !== popover.innerHTML) popover.replaceChildren(...next.childNodes);
    select(anchor);
    place(anchor ?? bar);
  }

  // Under `target`, with the arrow pointing at it; above if there's no room.
  function place(target) {
    const anchor = target.getBoundingClientRect();
    const width = popover.offsetWidth;
    const left = clamp(anchor.left + anchor.width / 2 - width / 2, 12, innerWidth - width - 12);
    popover.style.left = `${left}px`;
    popover.style.setProperty('--arrow', `${anchor.left + anchor.width / 2 - left}px`);
    const height = popover.offsetHeight;
    const below = anchor.bottom + 12 + height <= innerHeight - 12 || anchor.top - 12 - height < 12;
    popover.classList.toggle('above', !below);
    popover.style.top = `${below ? anchor.bottom + 12 : anchor.top - 12 - height}px`;
  }

  function taskCard(agent, task) {
    const age = longAge(macNow() - task.since);
    const status = task.state === 'done' ? `Done ${age} ago` : `${STATE_WORDS[task.state]} · ${age}`;
    const parts = [
      el('h3', { className: 'card-title', text: task.title }),
      el('p', { className: 'card-meta' }, glyph(task.state), el('span', { text: [task.project, status].filter(Boolean).join(' · ') })),
    ];
    if (task.state === 'waiting') {
      parts.push(el('div', { className: 'card-ask' },
        el('b', { text: `${agent.name} needs your OK` }),
        task.ask ? el('code', { text: task.ask }) : ''));
    }
    if (task.steps?.length) parts.push(...stepList(task.steps));
    if (task.now && task.state === 'working') {
      parts.push(el('p', { className: 'card-now' }, el('b', { text: 'Now: ' }), el('span', { text: task.now })));
    }
    if (task.app) {
      // Solid only when the agent needs you; tinted otherwise, so the steps lead.
      const waiting = task.state === 'waiting';
      const open = el('button', { className: `card-button${waiting ? '' : ' tinted'}`, text: `${waiting ? 'Answer' : 'Open'} in ${agent.name}` });
      // The Mac opens the task's own chat where the app allows it.
      open.addEventListener('click', () => {
        send({ t: 'openTask', k: task.id });
        closeCard();
      });
      parts.push(open);
    }
    return parts;
  }

  // "Step 2 of 4" and the steps, ticked off as they're done.
  function stepList(steps) {
    const finished = steps.filter((step) => step.state === 'done').length;
    const current = steps.findIndex((step) => step.state === 'current');
    const heading = finished === steps.length
      ? `All ${steps.length} steps done`
      : `Step ${(current >= 0 ? current : finished) + 1} of ${steps.length}`;
    return [
      el('div', { className: 'card-step-count', text: heading }),
      el('ol', { className: 'card-steps' }, ...steps.map((step) => el('li', { className: step.state },
        el('span', { className: 'step-mark', attrs: { 'aria-hidden': 'true' }, text: step.state === 'done' ? '✓' : '' }),
        el('span', { text: step.text })))),
    ];
  }

  function usageCard(agent, limits) {
    return [
      el('h3', { className: 'card-title', text: `${agent.name} Plan Usage` }),
      ...limits.map((limit) => el('div', { className: 'card-limit' },
        el('div', { className: 'card-limit-top' },
          el('b', { text: `${limit.label} · ${limit.percent}%` }),
          el('span', { text: limit.resets ? `Resets ${resetTime(limit.resets, macNow())}` : '' })),
        meter(limit.percent, true))),
      el('p', { className: 'card-meta', text: 'How much of your plan you’ve used, read from your Mac every few minutes.' }),
    ];
  }

  // ── Talking to the Mac

  // Asks the Mac for the agents the bar shows; none once it's off.
  function subscribe() {
    if (!isReady()) return;
    const agents = isOn() ? shown().map((a) => a.id) : [];
    send({ t: 'agents', ks: agents, r: settings.get('agentUsage') });
  }

  settings.subscribe((key) => {
    if (!['functionRow', 'agentClaude', 'agentCodex', 'agentUsage'].includes(key)) return;
    subscribe();
    if (!isOn()) closeCard();
    show(view);
  });
  addEventListener('resize', () => { if (card) renderCard(); });
  // Ages tick over while the bar shows them.
  setInterval(() => { if (isOn() && bar.isConnected) update(); }, 30000);
  render();

  return {
    element: bar,
    subscribe,
    setIcons(next) {
      icons = next;
      render();
    },
    /** The agents on the Mac (from its welcome message). */
    setInstalled(apps) {
      installed = apps;
      subscribe();
      show(view);
    },
    /** Agent activity from the Mac: `{ now, apps: { claude: { tasks, usage } } }`. */
    setActivity(message) {
      clockOffset = (message.now ?? Date.now()) - Date.now();
      activity = message.apps ?? {};
      update();
    },
    /** Disconnected: forget what the Mac said. */
    reset() {
      activity = {};
      installed = [];
      closeCard();
      view = 'home';
      render();
    },
  };
}
