// The Plan tab (S-10 week, S-11 meal detail, S-12 swap, regenerate, blocked-by-safety and update cards).
// Approval lives in plan-approval.ts / plan-approve-button.ts; nothing in this file can approve a plan.
// Every core call goes through host.op, which supplies an explicit ctx (main.ts).
import type { Reply } from "../core.js";
import { RECIPES } from "../recipes-data.js";
import {
  COPY, REROLL_REASONS, SLOT_NAME, approvedOn, dayHeader, dayName, ingredientName, memberName, portionText, quantityText,
  rangeText, reasonText, recipeMinutes, recipeTitle, slotKey,
  type Current, type Member, type Meal, type PlanView,
} from "./plan-data.js";
import { openApprovalSheet } from "./plan-approval.js";
import { button, h, openSheet, softDisable } from "./plan-dom.js";

export interface PlanHost {
  op: (name: string, args?: Record<string, any>) => Promise<Reply>;
  goTo: (tab: string) => void;
}

const SLOT_ORDER = ["breakfast", "lunch", "lunchbox", "dinner", "snack"];

interface Ui { detail?: string; bannerDismissed: boolean; toast?: string; error?: string }
const ui: Ui = { bannerDismissed: false };

interface Model {
  cur: Current; display: PlanView; approved?: PlanView; members: Member[]; names: Map<string, string>;
  pending: boolean; status: "draft" | "pending" | "approved"; blocked: boolean; blockedName: string;
}

/** Entry point from main.ts: draws the whole Plan tab into `panel`. */
export async function renderPlanTab(panel: HTMLElement, host: PlanHost): Promise<void> {
  const redraw = async (toast?: string): Promise<void> => {
    if (toast !== undefined) ui.toast = toast;
    await draw(panel, host, redraw);
    // A sheet that closed took the focus with it: move it to the heading instead of the page top.
    if (document.activeElement === document.body || document.activeElement === null) panel.querySelector<HTMLElement>("h2")?.focus();
  };
  await redraw();
}

async function draw(panel: HTMLElement, host: PlanHost, redraw: (toast?: string) => Promise<void>): Promise<void> {
  const house = await host.op("household.get");
  const curR = await host.op("plan.current");
  panel.replaceChildren(h("h2", { textContent: "Plan", tabIndex: -1 }));
  const live = h("div", { id: "toast", role: "status", "aria-live": "polite" });
  if (ui.toast) { live.append(h("p", { class: "toast", textContent: ui.toast })); const t = ui.toast; setTimeout(() => { if (live.textContent === t) live.replaceChildren(); }, 8000); ui.toast = undefined; }
  panel.append(live);

  const gate = house.ok ? house.result.gate : { status: "error" };
  if (gate.status === "noHousehold") { panel.append(h("p", { textContent: "Add your household first (Household tab)." })); return; }
  if (!curR.ok || !house.ok) { panel.append(errorCard(redraw)); return; }
  const cur = curR.result as Current;
  const members: Member[] = (house.result.household?.members ?? []).filter((m: Member) => !m.deletedAt);
  const names = new Map(members.map((m) => [m.id, memberName(m)]));
  const blocked = cur.gate.status === "refused";
  const blockedName = (cur.gate.memberIds ?? []).map((id) => names.get(id) ?? "someone").join(" and ") || "someone";
  const shown = cur.working ?? cur.approved;

  if (blocked) panel.append(blockedCard(blockedName, host));
  if (ui.error) panel.append(errorCard(redraw, ui.error));

  if (!shown) {
    if (blocked) return;
    panel.append(h("section", { class: "card", id: "plan-empty" },
      h("h3", { textContent: COPY.noPlan }),
      makePlanButton(host, redraw)));
    return;
  }
  const pending = shown.plan.status === "draft" && shown.plan.basedOn !== undefined;
  const status = shown.plan.status === "approved" ? "approved" : pending ? "pending" : "draft";
  const m: Model = { cur, display: shown, approved: cur.approved, members, names, pending, status, blocked, blockedName };

  const detail = ui.detail ? shown.plan.meals.find((x) => x.id === ui.detail) : undefined;
  if (detail) { drawDetail(panel, host, redraw, m, detail); return; }
  ui.detail = undefined;
  drawWeek(panel, host, redraw, m);
}

function errorCard(redraw: (t?: string) => Promise<void>, message: string = COPY.planError): HTMLElement {
  const retry = button(COPY.tryAgain, { id: "plan-retry" });
  retry.onclick = () => { ui.error = undefined; void redraw(); };
  return h("section", { class: "card", id: "plan-error", role: "alert" }, h("p", { textContent: message }), retry);
}

function makePlanButton(host: PlanHost, redraw: (t?: string) => Promise<void>): HTMLButtonElement {
  const b = button(COPY.makePlan, { id: "make-plan" });
  b.onclick = async () => {
    b.disabled = true; b.textContent = COPY.loading;
    const r = await host.op("plan.generate", {});
    ui.error = r.ok ? undefined : r.error.code === "gate_refused" ? undefined : COPY.planError;
    await redraw();
  };
  return b;
}

/** C-080: top card while a safety question is open. Not dismissible. */
function blockedCard(name: string, host: PlanHost): HTMLElement {
  const answer = button("Answer now", { id: "blocked-answer" });
  answer.onclick = () => host.goTo("household");
  return h("section", { class: "card warn", id: "blocked-card" },
    h("p", { textContent: `▲ Answer the safety question for ${name} to keep planning.` }), answer);
}

function say(panel: HTMLElement, text: string): void {
  let box = panel.querySelector<HTMLElement>("#hint");
  if (!box) { box = h("div", { id: "hint", role: "status" }); panel.prepend(box); }
  box.textContent = text;
}
const blockedHint = (name: string): string => `I can't change meals until I know what ${name} must avoid.`;

function sortedMeals(plan: PlanView): Meal[] {
  return [...plan.plan.meals].sort((a, b) => a.date.localeCompare(b.date) || SLOT_ORDER.indexOf(a.slot) - SLOT_ORDER.indexOf(b.slot));
}

// ---------------------------------------------------------------- S-10 week

function drawWeek(panel: HTMLElement, host: PlanHost, redraw: (t?: string) => Promise<void>, m: Model): void {
  const { display } = m;
  const head = h("section", { id: "plan-head" });
  head.append(h("h3", { textContent: COPY.title }), h("p", { id: "plan-range", textContent: rangeText(display.plan.weekStart) }));
  const statusText = m.status === "draft" ? COPY.statusDraft : m.status === "pending" ? COPY.statusPending
    : `Approved ${approvedOn(display.plan.approval?.approvedAt ?? "")}`.trim();
  head.append(h("p", { id: "plan-status", textContent: `${m.status === "approved" ? "✓" : "✎"} ${statusText}` }));

  const regen = button("Regenerate", { id: "regenerate" });
  if (m.blocked) softDisable(regen, () => say(panel, blockedHint(m.blockedName)));
  else regen.onclick = () => confirmRegenerate(panel, host, redraw, display, regen);
  head.append(regen);
  panel.append(head);

  const blockedMeals = display.blockedMealIds.length > 0 || (m.approved?.blockedMealIds.length ?? 0) > 0;
  if (blockedMeals) {
    const update = button(COPY.updatePlan, { id: "update-plan" });
    if (m.blocked) softDisable(update, () => say(panel, blockedHint(m.blockedName)));
    else update.onclick = async () => {
      update.disabled = true;
      const r = await host.op("plan.regenerate", { planId: display.plan.id, keepingLocked: true });
      ui.error = r.ok ? undefined : COPY.saveFailed;
      await redraw();
    };
    panel.append(h("section", { class: "card warn", id: "safety-changed" }, h("p", { textContent: `▲ ${COPY.safetyChanged}` }), update));
  }
  if (m.status === "draft" && !ui.bannerDismissed) {
    const dismiss = button("Dismiss", { id: "banner-dismiss" });
    dismiss.onclick = () => { ui.bannerDismissed = true; void redraw(); };
    panel.append(h("section", { class: "card", id: "first-plan-banner" }, h("p", { textContent: COPY.banner }), dismiss));
  }

  const approvedBySlot = new Map((m.approved?.plan.meals ?? []).map((x) => [slotKey(x), x]));
  const list = h("div", { id: "week" });
  let day = "";
  let ul: HTMLElement | undefined;
  for (const meal of sortedMeals(display)) {
    if (meal.date !== day) {
      day = meal.date;
      list.append(h("h3", { class: "day", textContent: dayHeader(day) }));
      ul = h("ul", { class: "meals", "aria-label": dayName(day) });
      list.append(ul);
    }
    ul!.append(mealRow(panel, host, redraw, m, meal, m.pending ? approvedBySlot.get(slotKey(meal)) : undefined));
  }
  panel.append(list, h("p", { class: "muted", id: "disclaimer", textContent: `(i) ${COPY.disclaimer}` }));
  drawBottomBar(panel, host, redraw, m);
}

function mealRow(panel: HTMLElement, host: PlanHost, redraw: (t?: string) => Promise<void>, m: Model, meal: Meal, wasMeal: Meal | undefined): HTMLElement {
  const dayLabel = `${dayName(meal.date)} ${SLOT_NAME[meal.slot] ?? meal.slot}`;
  const li = h("li", { class: "meal", "data-id": meal.id });
  const main = h("div", { class: "meal-main" });
  main.append(h("span", { class: "slot", textContent: SLOT_NAME[meal.slot] ?? meal.slot }));
  if (meal.recipeId === undefined) {
    main.append(h("span", { class: "title", textContent: COPY.emptySlot }));
    const why = button(COPY.emptyWhyButton, { class: "link", "aria-expanded": "false", "aria-label": `Why? No safe recipe for ${dayLabel}` });
    const body = h("p", { class: "muted", hidden: true, textContent: COPY.emptyWhy });
    why.onclick = () => { body.hidden = !body.hidden; why.setAttribute("aria-expanded", String(!body.hidden)); };
    main.append(why, body);
  } else {
    const open = button(recipeTitle(meal.recipeId), { class: "link title", "aria-label": `${dayLabel}: ${recipeTitle(meal.recipeId)}. Open details` });
    open.onclick = () => { ui.detail = meal.id; void redraw(); };
    main.append(open);
    const reason = reasonText(meal.reasons, meal.slot);
    if (reason) main.append(h("span", { class: "muted reason", textContent: reason }));
  }
  if (meal.locked) main.append(h("span", { class: "tag", textContent: "🔒 Locked" }));
  if (meal.blockedBySafety) main.append(h("span", { class: "tag warn", textContent: "▲ Needs replacing" }));
  if (wasMeal && wasMeal.recipeId !== meal.recipeId) {
    main.append(h("span", { class: "tag", textContent: "Changed" }),
      h("span", { class: "muted", textContent: `Approved: ${wasMeal.recipeId ? recipeTitle(wasMeal.recipeId) : "empty"}` }),
      h("span", { class: "muted", textContent: `Proposed: ${meal.recipeId ? recipeTitle(meal.recipeId) : "empty"}` }));
  }
  li.append(main);
  if (meal.recipeId !== undefined || meal.locked) {
    const actions = h("div", { class: "row-actions" });
    const swap = button("Swap", { "aria-label": `Swap ${dayLabel}`, class: "swap" });
    if (m.blocked) softDisable(swap, () => say(panel, blockedHint(m.blockedName)));
    else swap.onclick = () => void openSwap(panel, host, redraw, m, meal, swap);
    actions.append(swap, lockButton(host, redraw, m, meal, dayLabel));
    li.append(actions);
  }
  return li;
}

function lockButton(host: PlanHost, redraw: (t?: string) => Promise<void>, m: Model, meal: Meal, dayLabel: string): HTMLButtonElement {
  const b = button(meal.locked ? "Unlock" : "Lock", { "aria-label": `${meal.locked ? "Unlock" : "Lock"} ${dayLabel}`, class: "lock" });
  b.onclick = async () => {
    b.disabled = true;
    const r = await host.op(meal.locked ? "plan.unlock" : "plan.lock", { planId: m.display.plan.id, mealId: meal.id });
    ui.error = r.ok ? undefined : COPY.saveFailed;
    await redraw();
  };
  return b;
}

function drawBottomBar(panel: HTMLElement, host: PlanHost, redraw: (t?: string) => Promise<void>, m: Model): void {
  const bar = h("section", { class: "bar", id: "plan-bar" });
  if (m.status === "approved") return;
  const label = m.status === "pending" ? `Review ${m.cur.pendingDiff?.listedCount ?? 0} ${(m.cur.pendingDiff?.listedCount ?? 0) === 1 ? "change" : "changes"}` : COPY.approveWeek;
  // This button only OPENS the approval sheet. Approving needs the confirm button inside the sheet.
  const open = button(label, { id: "open-approval", class: "primary" });
  if (m.blocked) softDisable(open, () => say(panel, blockedHint(m.blockedName)));
  else open.onclick = () => {
    void openApprovalSheet({
      panel, op: (n, a) => host.op(n, a), opener: open, blockedText: () => (m.blocked ? `Answer the safety question for ${m.blockedName} to keep planning.` : undefined),
      done: (toast) => { void redraw(toast); },
    }, m.display);
  };
  bar.append(open);
  if (m.status === "draft") bar.append(h("p", { class: "muted", textContent: COPY.approveCaption }));
  panel.append(bar);
}

function confirmRegenerate(panel: HTMLElement, host: PlanHost, redraw: (t?: string) => Promise<void>, plan: PlanView, opener: HTMLElement): void {
  const yes = button("Replace", { id: "regenerate-yes" });
  const no = button("Cancel", { id: "regenerate-cancel" });
  const sheet = openSheet(panel, COPY.regenerateTitle, [h("p", { textContent: COPY.regenerateBody }), h("div", { class: "actions" }, yes, no)], { role: "alertdialog", returnFocus: opener });
  no.onclick = () => sheet.close();
  yes.onclick = async () => {
    yes.disabled = true; yes.textContent = COPY.loading;
    const r = await host.op("plan.regenerate", { planId: plan.plan.id, keepingLocked: true });
    ui.error = r.ok ? undefined : COPY.saveFailed;
    sheet.close();
    await redraw();
  };
}

// ---------------------------------------------------------------- S-12 swap

async function openSwap(panel: HTMLElement, host: PlanHost, redraw: (t?: string) => Promise<void>, m: Model, meal: Meal, opener: HTMLElement): Promise<void> {
  const planId = m.display.plan.id;
  const wasApproved = m.display.plan.status === "approved";
  let reason: string | undefined;
  const list = h("div", { id: "swap-options", "aria-live": "polite" });
  const chips = h("div", { class: "chips", role: "group", "aria-label": "Why change it? (optional)" });
  const cancel = button("Cancel", { id: "swap-cancel" });
  const pick = button("Pick for me", { id: "swap-pick" });
  const title = `Swap ${dayName(meal.date)} ${(SLOT_NAME[meal.slot] ?? meal.slot).toLowerCase()}`;
  const sheet = openSheet(panel, title, [chips, h("h3", { textContent: "Pick one" }), list, h("div", { class: "actions" }, pick, cancel)], { returnFocus: opener });
  cancel.onclick = () => sheet.close();

  const apply = async (r: Reply): Promise<void> => {
    if (!r.ok) {
      if (r.error.code === "gate_refused") { sheet.close(); say(panel, blockedHint(m.blockedName)); return; }
      list.replaceChildren(h("p", { role: "alert", textContent: COPY.saveFailed })); return;
    }
    sheet.close();
    await redraw(wasApproved ? COPY.swapped : undefined);
  };
  const load = async (): Promise<void> => {
    list.replaceChildren(h("p", { textContent: COPY.loading }));
    const r = await host.op("plan.alternatives", { planId, mealId: meal.id, limit: 3, ...(reason ? { reason } : {}) });
    if (!r.ok) { list.replaceChildren(h("p", { role: "alert", textContent: COPY.saveFailed })); return; }
    const alts: { recipeId: string; reasons: Record<string, any>[] }[] = r.result.alternatives;
    if (alts.length === 0) { list.replaceChildren(h("p", { id: "swap-empty", textContent: COPY.swapEmpty })); return; }
    const ul = h("ul", { class: "options" });
    for (const a of alts) {
      const mins = recipeMinutes(a.recipeId);
      const b = button(`${recipeTitle(a.recipeId)}${mins ? ` · ${mins} min` : ""}`, { class: "option", "data-id": a.recipeId });
      b.onclick = async () => { b.disabled = true; await apply(await host.op("plan.swap", { planId, mealId: meal.id, recipeId: a.recipeId })); };
      const why = reasonText(a.reasons, meal.slot);
      ul.append(h("li", {}, b, why ? h("span", { class: "muted", textContent: why }) : false));
    }
    list.replaceChildren(ul);
  };
  for (const [key, label] of REROLL_REASONS) {
    const chip = button(label, { class: "chip", "aria-pressed": "false" });
    chip.onclick = () => {
      reason = reason === key ? undefined : key;
      chips.querySelectorAll("button").forEach((c) => c.setAttribute("aria-pressed", String(c === chip && reason === key)));
      void load();
    };
    chips.append(chip);
  }
  pick.onclick = async () => { pick.disabled = true; await apply(await host.op("plan.reroll", { planId, mealId: meal.id, ...(reason ? { reason } : {}) })); };
  await load();
}

// ---------------------------------------------------------------- S-11 detail

function drawDetail(panel: HTMLElement, host: PlanHost, redraw: (t?: string) => Promise<void>, m: Model, meal: Meal): void {
  const back = button("‹ This week", { id: "detail-back", class: "link" });
  back.onclick = () => { ui.detail = undefined; void redraw(); };
  const dayLabel = `${dayName(meal.date)} ${SLOT_NAME[meal.slot] ?? meal.slot}`;
  const recipe = meal.recipeId ? RECIPES[meal.recipeId] : undefined;
  panel.append(back, h("p", { class: "muted", textContent: `${dayName(meal.date)} · ${SLOT_NAME[meal.slot] ?? meal.slot}` }),
    h("h3", { id: "detail-title", textContent: meal.recipeId ? recipeTitle(meal.recipeId) : COPY.emptySlot }));
  const reason = reasonText(meal.reasons, meal.slot);
  const mins = recipeMinutes(meal.recipeId);
  panel.append(h("p", { class: "muted", textContent: [mins ? `${mins} min` : "", reason ?? ""].filter(Boolean).join(" · ") }));
  if (meal.blockedBySafety) panel.append(h("p", { class: "tag warn", textContent: `▲ ${COPY.safetyChanged}` }));

  const lock = lockButton(host, redraw, m, meal, dayLabel);
  const swap = button("Swap", { id: "detail-swap", "aria-label": `Swap ${dayLabel}` });
  if (m.blocked) softDisable(swap, () => say(panel, blockedHint(m.blockedName)));
  else swap.onclick = () => void openSwap(panel, host, redraw, m, meal, swap);
  panel.append(h("div", { class: "actions" }, lock, swap));

  // Who's eating (AC-6.2, AC-6.3). Read only: the facade has no portion operation yet (W06 report, gaps).
  const eating = h("ul", { id: "eating" });
  for (const s of meal.servings) eating.append(h("li", { textContent: `${m.names.get(s.memberId) ?? "Someone"}: ${portionText(s)}` }));
  panel.append(h("h3", { textContent: "Who's eating" }), eating);

  if (recipe) {
    const total = meal.servings.filter((s) => !s.notEating).reduce((a, s) => a + s.portion, 0);
    const scale = recipe.servings > 0 ? total / recipe.servings : 1;
    panel.append(h("h3", { textContent: `Ingredients (for ${quantityText(total)} portions)` }),
      h("ul", { id: "ingredients" }, ...recipe.ingredients.map(([id, q, unit]) => h("li", { textContent: `${ingredientName(id)} ${quantityText(q * scale)} ${unit}` }))));
    if (recipe.steps.length > 0) panel.append(h("h3", { textContent: "Steps" }), h("ol", { id: "steps" }, ...recipe.steps.map((s) => h("li", { textContent: s }))));
  }
  if (m.status !== "approved") panel.append(h("p", { class: "muted", textContent: COPY.draftCaption }));
  panel.append(h("p", { class: "muted", textContent: `(i) ${COPY.disclaimer}` }));
}
