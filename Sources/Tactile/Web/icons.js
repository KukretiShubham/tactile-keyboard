// Line icons drawn in the spirit of SF Symbols (24pt grid, currentColor).
const svg = (body, filled = false) =>
  `<svg viewBox="0 0 24 24" aria-hidden="true" ${filled ? 'fill="currentColor"' : 'fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"'}>${body}</svg>`;

const rays = (inner, outer) =>
  Array.from({ length: 8 }, (_, i) => {
    const a = (i * Math.PI) / 4;
    const p = (r) => [12 + r * Math.cos(a), 12 + r * Math.sin(a)].map((n) => n.toFixed(2));
    const [x1, y1] = p(inner);
    const [x2, y2] = p(outer);
    return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`;
  }).join('');

const speaker = '<path d="M4 9.5h3.2L11.5 6v12l-4.3-3.5H4z" fill="currentColor" stroke="none"/>';

export const ICONS = {
  brightnessDown: svg(`<circle cx="12" cy="12" r="3"/>${rays(5.2, 6.6)}`),
  brightnessUp: svg(`<circle cx="12" cy="12" r="3.6"/>${rays(6, 8.6)}`),
  missionControl: svg('<rect x="3" y="5" width="8" height="6" rx="1.2"/><rect x="13" y="5" width="8" height="6" rx="1.2"/><rect x="3" y="13" width="18" height="6" rx="1.2"/>'),
  spotlight: svg('<circle cx="10.5" cy="10.5" r="5.5"/><line x1="14.6" y1="14.6" x2="19.5" y2="19.5"/>'),
  previous: svg('<path d="M11.5 7v10L4.5 12zM19.5 7v10l-7-5z"/>', true),
  playPause: svg('<path d="M3.5 7v10l7-5z"/><rect x="13.2" y="7" width="2.4" height="10" rx=".6"/><rect x="17.6" y="7" width="2.4" height="10" rx=".6"/>', true),
  next: svg('<path d="M4.5 7v10l7-5zM12.5 7v10l7-5z"/>', true),
  mute: svg(`${speaker}<line x1="15" y1="9.5" x2="20" y2="14.5"/><line x1="20" y1="9.5" x2="15" y2="14.5"/>`),
  volumeDown: svg(`${speaker}<path d="M14.6 9.6a3.4 3.4 0 0 1 0 4.8"/>`),
  volumeUp: svg(`${speaker}<path d="M14.6 9.6a3.4 3.4 0 0 1 0 4.8"/><path d="M17.2 7.2a6.8 6.8 0 0 1 0 9.6"/>`),
  speaker: svg(`${speaker}<path d="M14.6 9.6a3.4 3.4 0 0 1 0 4.8"/><path d="M17.2 7.2a6.8 6.8 0 0 1 0 9.6"/>`),
  lockScreen: svg('<rect x="5.5" y="10.5" width="13" height="9" rx="2"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>'),
  globe: svg('<circle cx="12" cy="12" r="8.5"/><ellipse cx="12" cy="12" rx="3.6" ry="8.5"/><line x1="3.5" y1="12" x2="20.5" y2="12"/>'),
  arrowUp: svg('<path d="M12 8l5 7H7z"/>', true),
  arrowDown: svg('<path d="M12 16l5-7H7z"/>', true),
  arrowLeft: svg('<path d="M8 12l7-5v10z"/>', true),
  arrowRight: svg('<path d="M16 12l-7-5v10z"/>', true),
  settings: svg('<line x1="4" y1="7" x2="20" y2="7"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="17" x2="20" y2="17"/><circle cx="9" cy="7" r="2.1" fill="currentColor"/><circle cx="15" cy="12" r="2.1" fill="currentColor"/><circle cx="7" cy="17" r="2.1" fill="currentColor"/>'),
  compose: svg('<path d="M12 4.5H6.5a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V12"/><path d="M17.8 3.8a1.8 1.8 0 0 1 2.5 2.5L12.5 14l-3.3.8.8-3.3z"/>'),
  keyboard: svg('<rect x="2.5" y="6" width="19" height="12" rx="2.2"/><path d="M6 9.5h.01M9 9.5h.01M12 9.5h.01M15 9.5h.01M18 9.5h.01M6 12.5h.01M9 12.5h.01M12 12.5h.01M15 12.5h.01M18 12.5h.01M8 15.2h8"/>'),
  check: svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),
};
