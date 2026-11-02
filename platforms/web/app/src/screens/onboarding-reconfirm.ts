// AC-3.4 / F5: the "Still correct?" card shown on the Plan tab when the 180-day re-confirmation is due.
// It may be ignored (new drafts stay blocked by the core, G3); it is not part of the mandatory first answer.
// "Make changes" is a compact editor: remove a rule (asks first), or add items (candidates, explicit save).
import { attrs, el } from "./dom.js";
import { buildEntry } from "./onboarding-entry.js";
import { EVERYONE, activeMembers, chipLabel, memberName, ruleSummary, summarise, toApiItems, unresolved, type HouseholdJson, type Item } from "./onboarding-model.js";
import type { Host } from "./onboarding.js";

let keys = 0;

export function reconfirmCard(host: Host, household: HouseholdJson, memberIds: string[]): HTMLElement {
  const members = activeMembers(household);
  const card = el("section", { id: "reconfirm", class: "card" });
  attrs(card, { "aria-labelledby": "reconfirm-title" });
  const msg = el("p", { id: "reconfirm-msg", role: "status" });
  const draw = (editing: boolean) => {
    card.replaceChildren(el("h2", { id: "reconfirm-title", textContent: "Still correct?" }),
      el("p", { textContent: `Here's what I avoid for your household: ${ruleSummary(household, members)}.` }));
    const yes = el("button", { type: "button", id: "reconfirm-yes", class: "primary", textContent: "Yes, still correct" });
    yes.onclick = async () => {
      const r = await host.op("safety.reconfirm", { memberIds });
      if (!r.ok) { msg.textContent = "Something went wrong saving that. Your other information is safe. Please try again."; return; }
      await host.refresh();
    };
    if (!editing) {
      const edit = el("button", { type: "button", id: "reconfirm-edit", textContent: "Make changes" });
      edit.onclick = () => draw(true);
      card.append(yes, edit, msg);
      return;
    }
    // Editor: current rules with Remove, then add.
    const ul = el("ul", { id: "reconfirm-rules" });
    for (const rule of household.rules) {
      const scope = rule.scope as Record<string, any>;
      const who = scope && typeof scope === "object" && scope.member ? members.find((m) => m.id === scope.member._0) : undefined;
      if (scope && typeof scope === "object" && scope.member && !who) continue;
      const label = `${chipLabel(rule.restriction ?? "")} (${who ? memberName(who) : "Everyone"})`;
      const rm = el("button", { type: "button", class: "danger", textContent: "Remove" });
      attrs(rm, { "aria-label": `Remove ${label}` });
      rm.onclick = () => {
        const ok = el("button", { type: "button", class: "danger", textContent: "Remove" });
        const cancel = el("button", { type: "button", textContent: "Cancel" });
        const box = el("div", { class: "dialog", role: "alertdialog" }, el("p", { id: "rm-q", textContent: `Remove ${chipLabel(rule.restriction ?? "")} for ${who ? memberName(who) : "everyone"}? Future plans may include ${chipLabel(rule.restriction ?? "")}.` }), ok, cancel);
        attrs(box, { "aria-describedby": "rm-q", "aria-modal": "true" });
        cancel.onclick = () => { box.remove(); rm.focus(); };
        box.onkeydown = (e) => { if (e.key === "Escape") cancel.click(); };
        ok.onclick = async () => {
          const r = await host.op("safety.removeRule", { ruleId: rule.id, confirmed: true });
          if (!r.ok) { msg.textContent = "Something went wrong saving that. Your other information is safe. Please try again."; return; }
          await host.refresh();
        };
        card.append(box); cancel.focus();
      };
      ul.append(el("li", {}, label, " ", rm));
    }
    const items: Item[] = [];
    const entry = buildEntry({ op: (n, a) => host.op(n, a), members, defaultScope: EVERYONE, showWho: members.length > 1,
      items, nextKey: () => ++keys, onChange: () => { add.disabled = items.length === 0 || unresolved(items).length > 0; } });
    const add = el("button", { type: "button", id: "reconfirm-add", textContent: "Review additions" });
    add.disabled = true;
    add.onclick = () => {
      // Freeze exactly what is shown: the summary and the save use this snapshot, never the live list.
      const frozen: Item[] = items.map((i) => ({ ...i }));
      const rows = summarise(frozen, members).map((r) => `${r.who}: ${r.what}`).join("; ");
      const save = el("button", { type: "button", id: "reconfirm-save", class: "primary", textContent: "Yes, save this" });
      const back = el("button", { type: "button", textContent: "Change" });
      const box = el("div", { class: "dialog", role: "alertdialog" }, el("p", { id: "ra-q", textContent: `Check this is right. ${rows}` }), save, back);
      attrs(box, { "aria-describedby": "ra-q", "aria-modal": "true" });
      const lock = (on: boolean) => { entry.root.inert = on; add.inert = on; yes.inert = on; };
      lock(true);
      back.onclick = () => { box.remove(); lock(false); add.focus(); };
      let pending: Item[] = frozen;
      save.onclick = async () => {
        let wire;
        try { wire = toApiItems(pending, members.map((m) => m.id)); } catch { box.remove(); lock(false); return; }
        save.disabled = true;
        for (const item of wire) {
          const r = await host.op("safety.addRule", { item });
          if (!r.ok) { msg.textContent = "Something went wrong saving that. Your other information is safe. Please try again."; save.disabled = false; return; }
          pending = pending.slice(1);          // retry-safe: what was saved is not sent again
        }
        await host.refresh();
      };
      card.append(box); save.focus();
    };
    card.append(ul, entry.root, add, yes, msg);
  };
  draw(false);
  return card;
}
