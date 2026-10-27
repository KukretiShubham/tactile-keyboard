// One-tap Mac shortcuts and app hotkeys. In landscape with the trackpad
// showing, they're keys on the palm rests either side of the trackpad: general
// shortcuts on the left, and on the right the hotkeys for one app, picked from
// a row of app tabs (following the app in front on the Mac). Otherwise the
// general shortcuts are a bar along the top. Which general shortcuts show,
// and your own hotkeys, are set in Settings.
import { canReverse, glyphOf, hotkeyMessages, isCustomHotkey, reverseMessages, sendInSteps } from './hotkeys.js';
import { ICONS } from './icons.js';
import { iconApps, packForApp, PACKS, TERMINALS } from './packs.js';
import { el } from './util.js';

export const SHORTCUTS = [
  { id: 'undo', name: 'Undo', keys: ['MetaLeft', 'z'] },
  { id: 'redo', name: 'Redo', keys: ['MetaLeft', 'ShiftLeft', 'z'] },
  { id: 'cut', name: 'Cut', keys: ['MetaLeft', 'x'] },
  { id: 'copy', name: 'Copy', keys: ['MetaLeft', 'c'] },
  { id: 'paste', name: 'Paste', keys: ['MetaLeft', 'v'] },
  { id: 'selectAll', name: 'Select All', keys: ['MetaLeft', 'a'] },
  { id: 'find', name: 'Find', keys: ['MetaLeft', 'f'] },
  { id: 'save', name: 'Save', keys: ['MetaLeft', 's'] },
  { id: 'newTab', name: 'New Tab', keys: ['MetaLeft', 't'] },
  { id: 'switchApp', name: 'Switch App', keys: ['MetaLeft', 'Tab'] },
  { id: 'screenshot', name: 'Screenshot', keys: ['MetaLeft', 'ShiftLeft', 'Digit5'] },
  { id: 'missionControl', name: 'Mission Control', icon: ICONS.missionControl, sys: 'missionControl' },
  { id: 'spotlight', name: 'Spotlight', icon: ICONS.spotlight, sys: 'spotlight' },
];

export const DEFAULT_SHORTCUTS = ['undo', 'redo', 'copy', 'paste', 'switchApp', 'spotlight'];

/** Every app bundle ID whose icon the packs might show (asked of the Mac). */
export const PACK_ICON_APPS = [...new Set(PACKS.flatMap(iconApps))];

export function createShortcuts({ bar, left, right, tabs, title, add }, { send, feedback, settings, beforeSend, onAddHotkey }) {
  let labels = {};
  let besideTrackpad = false;
  let icons = {}; // bundle ID → icon, for apps installed on the Mac
  let frontApp = null; // { id, name }
  // Hotkeys switched on (e.g. a panel opened), so the next tap closes them.
  // Tactile can't see the app, so this is a best guess; it lights the key.
  const switchedOn = new Map(); // key id → hotkey

  const custom = () => (settings.get('customHotkeys') ?? []).filter(isCustomHotkey);
  const general = () => (settings.get('shortcutBar') ? SHORTCUTS.filter(({ id }) => settings.get('shortcuts').includes(id)) : []);
  // Terminal agents are always offered; app packs once their app is found.
  // You can hide any of them in Settings.
  const offeredPacks = () => PACKS.filter((pack) => pack.terminal || pack.apps.some((id) => id in icons));
  const isHidden = (pack) => (settings.get('hiddenPacks') ?? []).includes(pack.id);
  const visiblePacks = () => offeredPacks().filter((pack) => !isHidden(pack));
  const packIcon = (pack) => iconApps(pack).map((id) => icons[id]).find(Boolean);
  const currentPack = () => {
    const shown = visiblePacks();
    return shown.find(({ id }) => id === settings.get('pack')) ?? shown[0];
  };
  const isFollowing = (pack) => Boolean(frontApp) &&
    (pack.apps.includes(frontApp.id) || (pack.terminal && TERMINALS.includes(frontApp.id)));
  // Where each terminal agent was used last: its desktop app or a terminal.
  const homeOf = (pack) => settings.get('agentHomes')?.[pack.id];

  function choose(pack) {
    settings.set('pack', pack.id);
    if (pack.terminal) settings.set('terminalPack', pack.id);
  }

  // Where a pack's hotkeys go, as a focus message for the Mac: for terminal
  // agents, where you used them last (in a terminal, the window running the
  // agent), else their desktop app if installed, else the terminal used last;
  // otherwise the pack's app in front, or else the first installed.
  function focusFor(pack) {
    if (pack.terminal) {
      const id = homeOf(pack)?.id ?? pack.apps.find((app) => app in icons) ?? settings.get('lastTerminal');
      return { t: 'focus', k: id, ...(TERMINALS.includes(id) ? { s: pack.command } : {}) };
    }
    const id = pack.apps.find((app) => app === frontApp?.id) ?? pack.apps.find((app) => app in icons);
    return id ? { t: 'focus', k: id } : null;
  }

  // A terminal agent's Start: the terminal comes forward, opens a new window
  // (⌘N, so it never types into a running agent), then runs the command.
  function startSteps(pack) {
    const home = homeOf(pack)?.id;
    const terminal = TERMINALS.includes(home) ? home : settings.get('lastTerminal');
    return [{ t: 'focus', k: terminal }, 400, { t: 'combo', ks: ['MetaLeft', 'KeyN'] }, 700,
      ...hotkeyMessages({ text: pack.command, enter: true }, labels)];
  }

  function rememberHome(pack, app) {
    settings.set('agentHomes', { ...settings.get('agentHomes'), [pack.id]: { id: app.id, name: app.name } });
  }

  // `position` is where the key sits, from -1 (left) to 1 (right), for its
  // sound. `id` tells keys apart, for remembering which are switched on.
  // `pack` is the app pack the key belongs to, if any.
  function button(hotkey, position, id, pack = null) {
    if (hotkey.start) hotkey = { ...hotkey, text: `$ ${pack.command}` };
    const glyph = hotkey.icon
      ? el('span', { className: 'shortcut-glyph shortcut-icon', html: hotkey.icon })
      : el('span', { className: hotkey.text ? 'shortcut-glyph shortcut-text' : 'shortcut-glyph', text: glyphOf(hotkey) });
    const on = switchedOn.has(id);
    const key = el('button', {
      className: `${besideTrackpad ? 'shortcut' : 'shortcut glass'}${on ? ' on' : ''}`,
      attrs: { 'aria-label': hotkey.name, title: hotkey.name, ...(canReverse(hotkey) ? { 'aria-pressed': on } : {}) },
    }, el('span', { className: 'shortcut-label' }, glyph, el('span', { className: 'shortcut-name', text: hotkey.name })));
    key.addEventListener('click', () => {
      beforeSend();
      if (switchedOn.has(id)) {
        switchedOn.delete(id);
        sendInSteps(send, reverseMessages(hotkey, labels));
      } else {
        if (canReverse(hotkey)) switchedOn.set(id, hotkey);
        sendInSteps(send, hotkey.start ? startSteps(pack) : hotkeyMessages(hotkey, labels));
      }
      key.classList.toggle('on', switchedOn.has(id));
      if (canReverse(hotkey)) key.setAttribute('aria-pressed', switchedOn.has(id));
      if (besideTrackpad) feedback.key('key', position);
      else feedback.click();
    });
    return key;
  }

  function tab(pack, selected) {
    const icon = packIcon(pack);
    const element = el('button', {
      className: `pack-tab${selected ? ' on' : ''}`,
      attrs: { 'aria-label': pack.name, 'aria-pressed': selected, title: pack.name, 'data-pack': pack.id },
    }, icon ? el('img', { attrs: { src: icon, alt: '' } }) : el('span', { className: 'pack-badge', text: pack.badge }));
    if (selected && isFollowing(pack)) element.append(el('span', { className: 'pack-following', attrs: { 'aria-hidden': 'true' } }));
    // Tapping a tab also brings its app to the front on the Mac, since
    // that's where its hotkeys go.
    element.addEventListener('click', () => {
      feedback.click();
      choose(pack);
      const focus = focusFor(pack);
      if (focus) send(focus);
    });
    return element;
  }

  function render() {
    const shown = general().concat(custom().filter((hotkey) => hotkey.pack === 'all'));
    bar.replaceChildren(...(besideTrackpad ? [] : shown.map((hotkey) => button(hotkey, 0, hotkey.id))));
    bar.hidden = besideTrackpad || shown.length === 0;
    left.replaceChildren(...(besideTrackpad ? shown.map((hotkey) => button(hotkey, -0.9, hotkey.id)) : []));

    const pack = currentPack();
    if (!besideTrackpad || !pack) {
      right.replaceChildren();
      tabs.replaceChildren();
      title.replaceChildren();
      return;
    }
    tabs.replaceChildren(...visiblePacks().map((each) => tab(each, each === pack)));
    // Keep the chosen tab in view, without scrolling anything else.
    const chosen = tabs.querySelector('.on');
    if (chosen) {
      const right = chosen.offsetLeft + chosen.offsetWidth;
      if (right > tabs.scrollLeft + tabs.clientWidth) tabs.scrollLeft = right - tabs.clientWidth;
      if (chosen.offsetLeft < tabs.scrollLeft) tabs.scrollLeft = chosen.offsetLeft;
    }

    let where = isFollowing(pack) ? 'following your Mac' : '';
    if (pack.terminal) where = `in ${isFollowing(pack) ? frontApp.name : (homeOf(pack)?.name ?? 'Terminal')}`;
    title.replaceChildren(pack.name, ...(where ? [' ', el('small', { text: where })] : []));
    const hotkeys = pack.hotkeys.concat(custom().filter((hotkey) => hotkey.pack === pack.id));
    right.replaceChildren(...hotkeys.map((hotkey, index) => button(hotkey, 0.9, hotkey.id ?? `${pack.id}:${index}`, pack)));
  }

  add.addEventListener('click', () => onAddHotkey(currentPack()?.id ?? 'all'));
  settings.subscribe((key) => {
    if (['shortcuts', 'shortcutBar', 'customHotkeys', 'pack', 'hiddenPacks'].includes(key)) render();
  });
  render();

  return {
    /** You typed or clicked: palettes opened by a hotkey have closed. */
    noteInput() {
      let changed = false;
      for (const [id, hotkey] of switchedOn) {
        if (hotkey.transient) changed = switchedOn.delete(id) || changed;
      }
      if (changed) render();
    },
    /** The Mac's keyboard layout changed; letter shortcuts follow it (keys.js `codeForCharacter`). */
    setLabels: (next) => { labels = next; },
    /** Moves the shortcuts beside the trackpad, or back to the top bar. */
    placeBesideTrackpad(on) {
      if (on === besideTrackpad) return;
      besideTrackpad = on;
      render();
    },
    /** Icons of the apps installed on the Mac, by bundle ID. */
    setIcons(next) {
      icons = next;
      render();
    },
    /** The app in front on the Mac changed: show its hotkeys. */
    setFrontApp(app) {
      frontApp = app;
      const inTerminal = TERMINALS.includes(app.id);
      if (inTerminal) settings.set('lastTerminal', app.id);
      if (settings.get('followMacApp')) {
        const current = currentPack();
        if (inTerminal) {
          if (!current?.terminal) choose(PACKS.find(({ id }) => id === settings.get('terminalPack')) ?? PACKS[0]);
        } else {
          const pack = packForApp(app.id);
          if (pack && pack !== current && !isHidden(pack)) choose(pack);
        }
      }
      // A terminal agent's tab brings back wherever you used it last.
      const pack = currentPack();
      if (pack?.terminal && isFollowing(pack)) rememberHome(pack, app);
      render();
    },
    /** Packs shown right now, for choosing where a new hotkey goes. */
    packs: () => visiblePacks().map((pack) => ({ id: pack.id, name: pack.name, icon: packIcon(pack) })),
    /** Every pack this Mac offers, shown or hidden, for Settings. */
    offered: () => offeredPacks().map((pack) => ({ id: pack.id, name: pack.name, icon: packIcon(pack), hidden: isHidden(pack) })),
  };
}
