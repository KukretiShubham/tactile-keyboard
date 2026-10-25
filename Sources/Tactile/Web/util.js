// Small helpers shared across the web app.

/**
 * Creates an element, e.g. `el('span', { className: 'note', text: 'Hi' })`.
 * `html` is only ever used with Tactile's own constant markup (icons), never
 * with text from elsewhere.
 */
export function el(tag, { className, text, html, attrs = {}, style = {} } = {}, ...children) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  if (html !== undefined) node.innerHTML = html;
  for (const [name, value] of Object.entries(attrs)) node.setAttribute(name, value);
  for (const [name, value] of Object.entries(style)) node.style.setProperty(name, value);
  node.append(...children);
  return node;
}

/** Keeps `value` between `low` and `high` (`low` wins if they cross). */
export const clamp = (value, low, high) => Math.min(Math.max(value, low), Math.max(low, high));

/** An element's inner box (inside its padding), in viewport coordinates. */
export function contentBox(element) {
  const r = element.getBoundingClientRect();
  const style = getComputedStyle(element);
  const padding = (side) => parseFloat(style[`padding${side}`]) || 0;
  return {
    left: r.left + padding('Left'),
    top: r.top + padding('Top'),
    width: r.width - padding('Left') - padding('Right'),
    height: r.height - padding('Top') - padding('Bottom'),
    paddingLeft: padding('Left'),
    paddingTop: padding('Top'),
  };
}
