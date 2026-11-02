// The "what to avoid" entry used by S-02 (all variants) and the re-check editor: chips, a text field, and the
// "To avoid" list. It only edits the caller's in-memory list of candidates; NOTHING here talks to the core
// except `safety.parse` (which saves nothing). Saving happens only after the explicit confirmation step.
import type { Reply } from "../core.js";
import { attrs, el } from "./dom.js";
import { CHIP_LABELS, EVERYONE, chipLabel, hasRestriction, memberName, scopeForHint, type Item, type MemberJson } from "./onboarding-model.js";

export interface EntryConfig {
  op(name: string, args?: Record<string, any>): Promise<Reply>;
  members: MemberJson[];
  /** Scope given to new items (Everyone, or the one person a gate-cover page is about). */
  defaultScope: string;
  /** Show the per-item "Who?" menu (onboarding variant with 2+ people). */
  showWho: boolean;
  items: Item[];
  nextKey(): number;
  /** Called after the list changed (add / remove / resolve) so the caller can update buttons and hints. */
  onChange(): void;
}

export function buildEntry(cfg: EntryConfig): { root: HTMLElement; focusInput(): void } {
  const catalogIds = Object.keys(CHIP_LABELS);
  const chipRow = el("div", { class: "chips", role: "group" });
  chipRow.setAttribute("aria-label", "Common things to avoid");
  const input = el("input", { type: "text", id: "avoid-text", placeholder: "e.g. no beef, one of us can't have nuts", autocomplete: "off", maxLength: 500 });
  const label = el("label", { class: "sr-only", textContent: "Type what to avoid" });
  label.htmlFor = "avoid-text";
  const addBtn = el("button", { type: "button", id: "avoid-add", class: "secondary", textContent: "Add" });
  const status = el("p", { role: "alert", id: "entry-error", class: "error" });
  const list = el("ul", { id: "avoid-list", class: "avoid-list" });
  const listTitle = el("h2", { id: "avoid-title", textContent: "To avoid" });

  const chipButtons = new Map<string, HTMLButtonElement>();
  for (const id of catalogIds) {
    const b = el("button", { type: "button", class: "chip", textContent: chipLabel(id) });
    b.dataset.chip = id;
    b.setAttribute("aria-pressed", "false");
    b.onclick = () => {
      const on = cfg.items.some((i) => i.restriction === id);
      if (on) {
        for (let n = cfg.items.length - 1; n >= 0; n--) if (cfg.items[n]!.restriction === id) cfg.items.splice(n, 1);
      } else {
        cfg.items.push({ key: cfg.nextKey(), restriction: id, scope: cfg.defaultScope });
      }
      paint(); cfg.onChange();
    };
    chipButtons.set(id, b);
    chipRow.append(b);
  }

  function removeItem(key: number): void {
    const n = cfg.items.findIndex((i) => i.key === key);
    if (n >= 0) cfg.items.splice(n, 1);
    paint(); cfg.onChange(); input.focus();
  }

  function paint(): void {
    for (const [id, b] of chipButtons) b.setAttribute("aria-pressed", String(cfg.items.some((i) => i.restriction === id)));
    list.replaceChildren();
    listTitle.hidden = cfg.items.length === 0;
    for (const item of cfg.items) {
      const li = el("li", { class: "avoid-row" });
      li.dataset.key = String(item.key);
      if (item.restriction !== undefined) {
        li.dataset.kind = "known";
        li.append(el("span", { class: "avoid-name", textContent: chipLabel(item.restriction) }));
        if (cfg.showWho) li.append(whoMenu(item));
      } else {
        li.dataset.kind = "unmapped";
        const icon = attrs(el("span", { textContent: "\u25B2! " }), { "aria-hidden": "true" });
        li.append(el("p", { class: "unmapped" }, icon,
          `I can't check recipes for \u201C${item.text ?? ""}\u201D yet. Pick the closest match, or remove it and check recipes yourself.`));
        const pick = el("select", { class: "pick" });
        pick.setAttribute("aria-label", `Pick closest match for ${item.text ?? "this item"}`);
        pick.append(el("option", { value: "", textContent: "Pick closest match" }));
        for (const id of catalogIds) pick.append(el("option", { value: id, textContent: chipLabel(id) }));
        pick.onchange = () => {
          if (pick.value === "") return;
          if (hasRestriction(cfg.items, pick.value, item.scope)) { removeItem(item.key); return; }
          item.restriction = pick.value; delete item.text;
          paint(); cfg.onChange();
        };
        li.append(pick);
      }
      const rm = el("button", { type: "button", class: "danger remove", textContent: "Remove" });
      rm.setAttribute("aria-label", `Remove ${item.restriction !== undefined ? chipLabel(item.restriction) : (item.text ?? "item")}`);
      rm.onclick = () => removeItem(item.key);
      li.append(rm);
      list.append(li);
    }
  }

  function whoMenu(item: Item): HTMLElement {
    const id = `who-${item.key}`;
    const wrap = el("span", { class: "who" });
    const l = el("label", { textContent: "Who? " });
    l.htmlFor = id;
    const sel = el("select", { id });
    sel.append(el("option", { value: EVERYONE, textContent: "Not sure who (everyone)" }));
    for (const m of cfg.members) sel.append(el("option", { value: m.id, textContent: memberName(m) }));
    sel.value = item.scope;
    sel.onchange = () => {
      // Moving an item onto a person who already has it would duplicate the rule: drop the duplicate instead.
      if (hasRestriction(cfg.items.filter((i) => i !== item), item.restriction ?? "", sel.value)) { removeItem(item.key); return; }
      item.scope = sel.value; cfg.onChange();
    };
    wrap.append(l, sel);
    return wrap;
  }

  let parsing = false;
  async function submitText(): Promise<void> {
    const text = input.value.trim();
    if (text === "" || parsing) return;
    parsing = true; status.textContent = "";
    try {
      const reply = await cfg.op("safety.parse", { text });
      if (!reply.ok) { status.textContent = "Something went wrong reading that. Please try again."; return; }
      const found: any[] = reply.result.candidates;
      if (found.length === 0) cfg.items.push({ key: cfg.nextKey(), text, scope: cfg.defaultScope });   // never dropped silently (AC-2.4)
      for (const c of found) {
        const scope = cfg.showWho ? scopeForHint(c.memberHint, cfg.members) : cfg.defaultScope;
        if (c.kind === "restriction") {
          if (!hasRestriction(cfg.items, c.restriction, scope)) cfg.items.push({ key: cfg.nextKey(), restriction: c.restriction, scope });
        } else {
          cfg.items.push({ key: cfg.nextKey(), text: String(c.text), scope });
        }
      }
      input.value = "";
      paint(); cfg.onChange();
    } finally { parsing = false; }
  }
  input.onkeydown = (e) => { if (e.key === "Enter") { e.preventDefault(); void submitText(); } };
  addBtn.onclick = () => void submitText();

  const form = el("div", { class: "text-row" }, label, input, addBtn);
  const root = el("div", { class: "entry" }, chipRow, form, status, listTitle, list);
  attrs(list, { "aria-labelledby": "avoid-title" });
  paint();
  return { root, focusInput: () => input.focus() };
}
