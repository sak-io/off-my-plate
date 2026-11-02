// W05: first-run onboarding (S-01 who is eating, S-02 safety question, S-02b check, S-03 cuisines, S-04 planning)
// and the safety "gate cover" for people added later. Rules this file enforces (tests/onboarding.spec.ts):
//  - While the core says safety is unanswered, NOTHING else in the app is drawn: no tabs, no close, no skip.
//    The decision comes from the core's gate on every render (so reload / Back / deep links cannot skip it).
//  - Escape does nothing here; the browser Back button is trapped (history entry re-pushed); Tab cannot leave
//    because there is nothing else on the page.
//  - Chips and typed text are only candidates in memory. They reach the core only from the "Yes, save this" click.
//  - An item the parser could not map has to be resolved (pick the closest match) or removed first.
//  - This code never creates or requests an approval (that is W06 and the facade's single bridge).
// All core calls go through host.op (-> Core.call with an explicit ctx built per call).
import type { Reply } from "../core.js";
import { attrs, el, stepHeading } from "./dom.js";
import { buildEntry } from "./onboarding-entry.js";
import {
  CUISINES, EVERYONE, MAX_PEOPLE, activeMembers, memberName, summarise, toApiItems, unresolved,
  type HouseholdJson, type Item, type MemberJson,
} from "./onboarding-model.js";

export interface Host {
  root: HTMLElement;
  op(name: string, args?: Record<string, any>): Promise<Reply>;
  /** Re-reads the core and draws whatever comes next. */
  refresh(): Promise<void>;
  /** Leaves onboarding for the Plan tab. */
  showPlan(): Promise<void>;
}

type Step = "size" | "cuisines" | "planning";
const SAVE_FAILED = "Something went wrong saving that. Your other information is safe. Please try again.";

const S = {
  step: undefined as Step | undefined,
  adults: 2, children: 0,
  items: [] as Item[], keys: 0,
  subject: "", review: false,
  coverTotal: 0,
  cuisines: new Set<string>(),
  error: "", busy: false, planFailed: false, generating: false,
  drawn: "",
  guarded: false, blocking: false,
};

/** True while a screen from this file must own the page. */
export function isBlocking(): boolean { return S.blocking; }

function installGuards(): void {
  if (S.guarded) return;
  S.guarded = true;
  // Browser Back: stay on this page. A history entry is always kept ahead of the current one.
  history.pushState({ omp: "gate" }, "");
  window.addEventListener("popstate", () => { if (S.blocking) history.pushState({ omp: "gate" }, ""); });
  // Escape never closes or skips anything here (the only dialog, the remove confirmation, handles its own key first).
  window.addEventListener("keydown", (e) => { if (S.blocking && e.key === "Escape") e.preventDefault(); }, true);
}

/** Decides from the core's answer whether an onboarding / safety screen must be shown. Returns true if it drew one. */
export async function gateScreen(host: Host, house: Reply): Promise<boolean> {
  if (!house.ok) { S.blocking = true; return drawFatal(host); }   // fail closed: no shell without a readable gate
  const household: HouseholdJson | undefined = house.result.household;
  const gate = house.result.gate as { status: string; reason?: string; memberIds?: string[] } | undefined;
  // Whitelist: anything but the three known statuses keeps the question on screen (fail closed).
  if (!gate || !["noHousehold", "open", "refused"].includes(gate.status)) { S.blocking = true; return drawFatal(host); }
  const members = activeMembers(household);
  const blocking = gate.status === "noHousehold" || (gate.status === "refused" && gate.reason === "safetyUnanswered");
  if (!blocking && S.step === undefined) { S.blocking = false; S.coverTotal = 0; S.drawn = ""; return false; }
  S.blocking = true;
  installGuards();
  if (gate.status === "noHousehold" || S.step === "size") return drawSize(host, household, members);
  if (blocking) {
    const ids = gate.memberIds ?? [];
    const unasked = members.filter((m) => ids.includes(m.id));
    if (unasked.length === 0) return drawFatal(host);   // the core says "unanswered" but names nobody: do not guess
    S.coverTotal = Math.max(S.coverTotal, unasked.length);
    if (unasked.length === members.length) return drawSafety(host, members, undefined, 1, 1);
    return drawSafety(host, members, unasked[0]!, S.coverTotal - unasked.length + 1, S.coverTotal);
  }
  if (S.step === "cuisines") return drawCuisines(host);
  return drawPlanning(host);
}

function shown(host: Host, name: string, variant: string, ...kids: (Node | string)[]): void {
  const main = el("main", { id: "onboarding", class: "onboarding" }, ...kids);
  main.dataset.screen = name; main.dataset.variant = variant;
  host.root.replaceChildren(main);
  const key = `${name}|${variant}`;
  if (S.drawn !== key) { S.drawn = key; (document.getElementById("step-title") as HTMLElement | null)?.focus(); }
}
function errorLine(): HTMLElement {
  const text = S.error; S.error = "";
  return el("p", { id: "ob-error", role: "alert", class: "error", textContent: text });
}
function fail(host: Host): Promise<void> { S.error = SAVE_FAILED; S.busy = false; return redraw(host); }
async function redraw(host: Host): Promise<void> { await host.refresh(); }
function drawFatal(host: Host): boolean {
  host.root.replaceChildren(el("main", { id: "onboarding" }, stepHeading("Something went wrong"),
    el("p", { role: "alert", textContent: "I couldn't open your safety answers. Please reload the page." })));
  return true;
}

// ---------------------------------------------------------------- S-01
function drawSize(host: Host, household: HouseholdJson | undefined, members: MemberJson[]): boolean {
  if (S.drawn.startsWith("size|") === false && household) {
    S.adults = members.filter((m) => m.label.role === "adult").length;
    S.children = members.filter((m) => m.label.role === "child").length;
  }
  const title = stepHeading("Who's eating?");
  const foot = el("p", { id: "size-foot", class: "muted" });
  const mk = (id: "adults" | "children", word: string) => {
    const value = el("output", { id: `${id}-count`, class: "count" });
    const minus = el("button", { type: "button", id: `${id}-minus`, class: "step", textContent: "−" });
    const plus = el("button", { type: "button", id: `${id}-plus`, class: "step", textContent: "+" });
    attrs(minus, { "aria-label": `Fewer ${word}` }); attrs(plus, { "aria-label": `More ${word}` });
    const row = el("div", { class: "stepper-row" }, el("span", { id: `${id}-label`, textContent: id === "adults" ? "Adults" : "Children" }), minus, value, plus);
    attrs(value, { "aria-labelledby": `${id}-label` });
    minus.onclick = () => { if (S[id] > 0) { S[id]--; paint(); } };
    plus.onclick = () => { if (S.adults + S.children < MAX_PEOPLE) { S[id]++; paint(); } };
    return { row, value, minus, plus };
  };
  const a = mk("adults", "adults"), c = mk("children", "children");
  const go = el("button", { type: "button", id: "size-continue", class: "primary", textContent: "Continue" });
  const paint = () => {
    const total = S.adults + S.children;
    a.value.textContent = String(S.adults); c.value.textContent = String(S.children);
    a.minus.disabled = S.adults <= 0; c.minus.disabled = S.children <= 0;
    a.plus.disabled = c.plus.disabled = total >= MAX_PEOPLE;
    go.disabled = total < 1 || S.busy;
    foot.textContent = total < 1 ? "Add at least one person." : total >= MAX_PEOPLE ? "That's the most I can plan for right now (12)." : "Teens count as adults for portions.";
  };
  go.onclick = async () => {
    S.busy = true; paint();
    const ok = await applyCounts(host, household, members);
    S.busy = false;
    if (ok) { S.step = undefined; S.error = ""; } else { S.error = SAVE_FAILED; }
    await redraw(host);
  };
  paint();
  shown(host, "size", "onboarding", title,
    el("p", { textContent: "No names needed. You can add them later." }), a.row, c.row, foot, errorLine(), go);
  return true;
}

/** Creates the household, or reconciles it with the counts: more = new `unasked` people, fewer = the highest
 *  numbered people go together with rules tagged only to them (same as the iPhone app, F1 edge paths). */
async function applyCounts(host: Host, household: HouseholdJson | undefined, members: MemberJson[]): Promise<boolean> {
  if (!household) return (await host.op("household.create", { adults: S.adults, children: S.children })).ok;
  for (const [role, wanted] of [["adult", S.adults], ["child", S.children]] as const) {
    const current = members.filter((m) => m.label.role === role).sort((x, y) => x.label.number - y.label.number);
    if (wanted > current.length) {
      for (let n = current.length; n < wanted; n++) if (!(await host.op("household.addMember", { role })).ok) return false;
    } else if (wanted < current.length) {
      for (const m of current.slice(wanted).reverse()) {
        if (!(await host.op("household.removeMember", { memberId: m.id, removeOwnRules: true })).ok) return false;
      }
    }
  }
  return true;
}

// ---------------------------------------------------------------- S-02 / S-02b
function drawSafety(host: Host, members: MemberJson[], about: MemberJson | undefined, n: number, total: number): boolean {
  const subject = about ? about.id : "all";
  if (S.subject !== subject) { S.subject = subject; S.items = []; S.review = false; S.error = ""; }
  const cover = about !== undefined;
  const name = about ? memberName(about) : "";
  const scopeMembers = about ? [about] : members;
  const variant = cover ? "cover" : "onboarding";
  if (S.review) return drawReview(host, scopeMembers, about, variant);

  const title = stepHeading(cover ? `Does ${name} have an allergy or something they must avoid?` : "Does anyone have an allergy or something they must avoid?");
  const reason = el("p", { id: "safety-reason", textContent: "I'll never put these in a plan, so I need to know before I suggest anything." });
  const nobody = el("button", { type: "button", id: "nobody", class: "primary big", textContent: cover ? "No, nothing" : "No, nobody" });
  attrs(nobody, { "aria-label": cover ? `No, ${name} has nothing to avoid` : "No, nobody has allergies or foods to avoid" });
  const nobodyHint = el("p", { id: "nobody-hint", class: "muted", textContent: "You've added things to avoid. Remove them to choose “No, nobody”." });
  const cont = el("button", { type: "button", id: "safety-continue", class: "primary", textContent: "Continue" });
  const contHint = el("p", { id: "continue-hint", class: "muted", textContent: "Sort out the item above to continue." });

  const entry = buildEntry({
    op: (name, args) => host.op(name, args), members: scopeMembers,
    defaultScope: cover ? about!.id : EVERYONE, showWho: !cover && members.length > 1,
    items: S.items, nextKey: () => ++S.keys, onChange: () => sync(),
  });
  const sync = () => {
    const has = S.items.length > 0, bad = unresolved(S.items).length > 0;
    const typed = entry.pending() !== "";      // text in the field that was not added is an unsaved answer
    nobody.disabled = has || typed || S.busy;
    if (has || typed) nobody.setAttribute("aria-describedby", "nobody-hint"); else nobody.removeAttribute("aria-describedby");
    nobodyHint.hidden = !(has || typed);
    nobodyHint.textContent = has ? "You've added things to avoid. Remove them to choose \u201CNo, nobody\u201D." : "You've typed something. Add it, or clear the field, to choose \u201CNo, nobody\u201D.";
    cont.hidden = !has;
    cont.disabled = bad || typed || S.busy;
    contHint.hidden = !(has && (bad || typed));
    contHint.textContent = bad ? "Sort out the item above to continue." : "Add the text you typed, or clear the field, to continue.";
    if (cont.disabled && (bad || typed)) cont.setAttribute("aria-describedby", "continue-hint"); else cont.removeAttribute("aria-describedby");
  };
  nobody.onclick = async () => {
    if (S.items.length > 0 || entry.pending() !== "" || S.busy) return;
    S.busy = true; sync();
    const r = cover ? await host.op("safety.confirmMember", { memberId: about!.id, items: [] })
      : await host.op("safety.confirmNobody", { pendingItemCount: S.items.length });
    S.busy = false;
    if (!r.ok) { await fail(host); return; }
    S.error = ""; if (!cover) S.step = "cuisines";
    await redraw(host);
  };
  cont.onclick = () => { if (unresolved(S.items).length > 0 || entry.pending() !== "") return; S.review = true; S.error = ""; void redraw(host); };

  const kids: (Node | string)[] = [];
  if (!cover) {
    const back = el("button", { type: "button", id: "ob-back", class: "link", textContent: "‹ Back" });
    back.onclick = () => { S.step = "size"; S.review = false; void redraw(host); };
    kids.push(back);
  } else if (total > 1) {
    kids.push(el("p", { id: "cover-progress", class: "muted", textContent: `${n} of ${total}` }));
  }
  kids.push(title, reason, nobody, nobodyHint, el("p", { class: "divider", textContent: "or tell me what to avoid" }), entry.root, errorLine(),
    el("p", { id: "disclaimer", class: "disclaimer" }, attrs(el("span", { textContent: "ⓘ " }), { "aria-hidden": "true" }),
      "OffMyPlate isn't medical advice. Always check ingredients and labels."),
    cont, contHint);
  if (cover) {
    const rm = el("button", { type: "button", id: "remove-member", class: "link", textContent: `Added by mistake? Remove ${name}` });
    rm.onclick = () => confirmRemove(host, about!, members.length, rm);
    kids.push(rm);
  }
  shown(host, "safety", variant, ...kids);
  sync();
  return true;
}

function confirmRemove(host: Host, m: MemberJson, count: number, opener: HTMLElement): void {
  const main = document.getElementById("onboarding")!;
  main.querySelector("#remove-dialog")?.remove();
  const name = memberName(m);
  const yes = el("button", { type: "button", id: "remove-yes", class: "danger", textContent: "Remove" });
  const no = el("button", { type: "button", id: "remove-no", textContent: "Cancel" });
  const msg = el("p", { id: "remove-msg", textContent: count <= 1 ? `${name} is the only person in the household, so they can't be removed.` : `Remove ${name}?` });
  const dialog = el("div", { id: "remove-dialog", class: "dialog", role: "alertdialog" }, el("h2", { id: "remove-title", textContent: `Remove ${name}?` }), msg, ...(count <= 1 ? [no] : [yes, no]));
  attrs(dialog, { "aria-modal": "true", "aria-labelledby": "remove-title", "aria-describedby": "remove-msg" });
  const close = () => { dialog.remove(); opener.focus(); };
  no.textContent = count <= 1 ? "OK" : "Cancel";
  no.onclick = close;
  dialog.onkeydown = (e) => { if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); close(); } };   // closes only this question
  yes.onclick = async () => {
    const r = await host.op("household.removeMember", { memberId: m.id });
    if (!r.ok) { S.error = SAVE_FAILED; }
    S.subject = ""; await redraw(host);
  };
  main.append(dialog);
  no.focus();
}

function drawReview(host: Host, scopeMembers: MemberJson[], about: MemberJson | undefined, variant: string): boolean {
  const rows = summarise(S.items, scopeMembers);
  const title = stepHeading("Check this is right");
  const list = el("dl", { id: "summary", class: "summary" });
  for (const r of rows) list.append(el("dt", { textContent: r.who }), el("dd", { textContent: r.what }));
  const save = el("button", { type: "button", id: "save-yes", class: "primary", textContent: "Yes, save this" });
  const change = el("button", { type: "button", id: "save-change", textContent: "Change" });
  // A double-tap on Continue must not also hit Save: the button wakes up a moment after the screen appears.
  save.disabled = true;
  setTimeout(() => { save.disabled = S.busy; }, 500);
  change.onclick = () => { S.review = false; S.error = ""; void redraw(host); };
  save.onclick = async () => {
    if (S.busy) return;
    let items;
    try { items = toApiItems(S.items, scopeMembers.map((m) => m.id)); } catch { S.review = false; await redraw(host); return; }
    S.busy = true; save.disabled = true;
    // The only place candidates become rules. The person has just read them back and pressed this button.
    const r = about ? await host.op("safety.confirmMember", { memberId: about.id, items }) : await host.op("safety.confirm", { items });
    S.busy = false;
    if (!r.ok) { await fail(host); return; }
    S.items = []; S.review = false; S.error = "";
    if (!about) S.step = "cuisines";
    await redraw(host);
  };
  shown(host, "review", variant, title, list, errorLine(), el("div", { class: "actions" }, save, change));
  return true;
}

// ---------------------------------------------------------------- S-03
function drawCuisines(host: Host): boolean {
  const back = el("button", { type: "button", id: "ob-back", class: "link", textContent: "‹ Back" });
  back.onclick = () => { S.step = "size"; void redraw(host); };
  const chips = el("div", { class: "chips", role: "group" });
  attrs(chips, { "aria-label": "Cuisines" });
  for (const c of CUISINES) {
    const b = el("button", { type: "button", class: "chip", textContent: c });
    b.setAttribute("aria-pressed", String(S.cuisines.has(c)));
    b.onclick = () => { if (S.cuisines.has(c)) S.cuisines.delete(c); else S.cuisines.add(c); b.setAttribute("aria-pressed", String(S.cuisines.has(c))); };
    chips.append(b);
  }
  const next = () => { S.step = "planning"; S.planFailed = false; void redraw(host); };
  const skip = el("button", { type: "button", id: "cuisines-skip", class: "link", textContent: "Skip" });
  skip.onclick = () => { S.cuisines.clear(); next(); };
  const go = el("button", { type: "button", id: "cuisines-go", class: "primary", textContent: "Make my plan" });
  go.onclick = next;
  shown(host, "cuisines", "onboarding", el("div", { class: "toolbar" }, back, skip), stepHeading("What do you usually cook?"),
    el("p", { textContent: "Pick a few, or skip. I'll learn as we go." }), chips, go);
  return true;
}

// ---------------------------------------------------------------- S-04
function drawPlanning(host: Host): boolean {
  if (S.planFailed) {
    const again = el("button", { type: "button", id: "plan-again", class: "primary", textContent: "Try again" });
    again.onclick = () => { S.planFailed = false; void redraw(host); };
    shown(host, "planning-error", "onboarding", stepHeading("I couldn't make a plan just now. Please try again."), again);
    return true;
  }
  const status = el("p", { id: "planning-status", role: "status", textContent: "Planning your week…" });
  shown(host, "planning", "onboarding", stepHeading("Planning your week…"), status);
  if (S.generating) return true;
  S.generating = true;
  const slow = setTimeout(() => { status.textContent = "Still working…"; }, 5000);
  // Let the page paint first: the core call is synchronous.
  setTimeout(async () => {
    const r = await host.op("plan.generate", {});
    clearTimeout(slow);
    S.generating = false;
    if (r.ok) { S.step = undefined; S.cuisines.clear(); S.blocking = false; await host.showPlan(); }
    else { S.planFailed = true; await redraw(host); }
  }, 30);
  return true;
}
