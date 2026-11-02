// Small DOM helpers for the plan screens (W06). Text only ever goes in through textContent / text nodes:
// no innerHTML, outerHTML or insertAdjacentHTML anywhere in this app (scripts/lint-web-approval.sh).

type Props = { [key: string]: unknown };

export function h<K extends keyof HTMLElementTagNameMap>(tag: K, props: Props = {}, ...kids: (Node | string | null | false)[]): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (value === undefined || value === null || value === false) continue;
    if (key === "class") node.className = String(value);
    else if (key.startsWith("aria-") || key === "role" || key === "data-id") node.setAttribute(key, String(value));
    else (node as unknown as Props)[key] = value;
  }
  for (const kid of kids) if (kid !== null && kid !== false) node.append(kid);
  return node;
}

/** A button that never submits anything. */
export function button(label: string, props: Props = {}): HTMLButtonElement {
  return h("button", { type: "button", textContent: label, ...props });
}

/** Marks a button as unavailable but still focusable; its click explains why (C-081). */
export function softDisable(b: HTMLButtonElement, explain: () => void): void {
  b.setAttribute("aria-disabled", "true");
  b.classList.add("soft-disabled");
  b.onclick = (e) => { e.preventDefault(); explain(); };
}

let sheetCounter = 0;

export interface Sheet { root: HTMLElement; close: () => void }

/**
 * A modal dialog inside `host`. Focus starts on the dialog heading (never on an action button, so a stray
 * Enter cannot activate anything), Tab stays inside, Escape closes, and the rest of the page is inert.
 */
export function openSheet(host: HTMLElement, title: string, body: Node[], opts: { role?: "dialog" | "alertdialog"; onClose?: () => void; returnFocus?: HTMLElement | null } = {}): Sheet {
  const id = `sheet-${++sheetCounter}`;
  const heading = h("h2", { id: `${id}-title`, tabIndex: -1, textContent: title });
  const root = h("div", { class: "dialog sheet", role: opts.role ?? "dialog", "aria-modal": "true", "aria-labelledby": heading.id }, heading, ...body);
  const siblings = Array.from(host.children).filter((c) => c !== root) as HTMLElement[];
  const wasInert = siblings.map((s) => s.inert);
  siblings.forEach((s) => { s.inert = true; });
  host.append(root);
  let closed = false;
  const close = (): void => {
    if (closed) return;
    closed = true;
    siblings.forEach((s, i) => { s.inert = wasInert[i] ?? false; });
    root.remove();
    opts.onClose?.();
    opts.returnFocus?.focus();
  };
  root.onkeydown = (e) => {
    if (e.key === "Escape") { e.preventDefault(); close(); return; }
    if (e.key !== "Tab") return;
    const items = Array.from(root.querySelectorAll<HTMLElement>("button:not([disabled]), [href], input:not([disabled]), [tabindex]:not([tabindex='-1'])"));
    if (items.length === 0) return;
    const first = items[0]!, last = items[items.length - 1]!;
    const active = document.activeElement;
    if (e.shiftKey && (active === first || active === heading)) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && active === last) { e.preventDefault(); first.focus(); }
  };
  heading.focus();
  return { root, close };
}
