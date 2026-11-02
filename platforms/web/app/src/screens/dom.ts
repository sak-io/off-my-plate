// Small DOM helpers for the W05 screens. Data only ever reaches the page through textContent / properties:
// no HTML string is ever parsed (a test scans these sources for the HTML-injection APIs).
export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K, props: Partial<HTMLElementTagNameMap[K]> & { class?: string } = {}, ...kids: (Node | string)[]
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  const { class: cls, ...rest } = props as Record<string, unknown>;
  if (typeof cls === "string" && cls) node.className = cls;
  Object.assign(node, rest);
  for (const k of kids) node.append(k);
  return node;
}

export function attrs<T extends HTMLElement>(node: T, a: Record<string, string>): T {
  for (const [k, v] of Object.entries(a)) node.setAttribute(k, v);
  return node;
}

/** A page heading that receives focus when a step opens, so keyboard and screen-reader users land on it. */
export function stepHeading(text: string, id = "step-title"): HTMLHeadingElement {
  const h = el("h1", { id, textContent: text });
  h.tabIndex = -1;
  return h;
}
