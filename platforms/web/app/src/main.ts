// App shell: four tabs, engine loading, snapshot persistence, Delete all data.
import { Core, makeCtx, type Reply } from "./core.js";
import { loadCore, registerWorker, type LoadStats } from "./engine.js";
import { deleteEverything, loadSnapshot, saveSnapshot } from "./store.js";

import { classify } from "./ops.js";

class App {
  core!: Core;
  bytes!: ArrayBuffer;
  stats!: LoadStats;
  tab = "plan";
  note = "";

  /** All core access goes through here: explicit ctx, then persist after a state-changing op. */
  async op(name: string, args?: Record<string, any>): Promise<Reply> {
    const kind = classify(name);
    if (kind === "unknown") throw new Error(`op ${name} is not classified in ops.ts`);
    const reply = this.core.call(name, args, makeCtx());
    if (reply.ok && kind === "persisted") {
      const exp = this.core.call("state.export", {}, makeCtx());
      if (exp.ok) await saveSnapshot(exp.result.snapshot);
    }
    return reply;
  }

  async restore(): Promise<string> {
    const snap = await loadSnapshot();
    if (snap === undefined) return "fresh";
    const r = this.core.call("state.import", { snapshot: snap as any }, makeCtx());
    return r.ok ? "restored" : `unreadable (${r.error.code})`;
  }
}

const app = new App();
const root = document.getElementById("app")!;
const TABS: [string, string][] = [["plan", "Plan"], ["list", "List"], ["pantry", "Pantry"], ["household", "Household"]];

function el<K extends keyof HTMLElementTagNameMap>(tag: K, props: Partial<HTMLElementTagNameMap[K]> & { class?: string } = {}, ...kids: (Node | string)[]): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  const { class: cls, ...rest } = props as any;
  if (cls) node.className = cls;
  Object.assign(node, rest);
  for (const k of kids) node.append(k);
  return node;
}

function shell(): { panel: HTMLElement } {
  root.replaceChildren();
  const tablist = el("div", { role: "tablist", class: "tabs" });
  tablist.setAttribute("aria-label", "Sections");
  const panel = el("main", { id: "panel", role: "tabpanel", tabIndex: 0 });
  TABS.forEach(([id, label], i) => {
    const b = el("button", { type: "button", role: "tab", id: `tab-${id}`, textContent: label });
    b.setAttribute("aria-selected", String(app.tab === id));
    b.setAttribute("aria-controls", "panel");
    b.tabIndex = app.tab === id ? 0 : -1;
    b.onclick = () => { app.tab = id; void render(); };
    b.onkeydown = (e) => {
      const d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (!d) return;
      app.tab = TABS[(i + d + TABS.length) % TABS.length]![0];
      void render().then(() => document.getElementById(`tab-${app.tab}`)?.focus());
    };
    tablist.append(b);
  });
  panel.setAttribute("aria-labelledby", `tab-${app.tab}`);
  root.append(el("header", {}, el("h1", { textContent: "OffMyPlate" })), tablist, panel);
  return { panel };
}

async function render(): Promise<void> {
  const { panel } = shell();
  const house = await app.op("household.get");
  const gate = house.ok ? house.result.gate : { status: "error" };
  if (app.tab === "plan") {
    panel.append(el("h2", { textContent: "Plan" }));
    if (gate.status === "noHousehold") panel.append(el("p", { textContent: "Add your household first (Household tab)." }));
    else if (gate.status === "refused") panel.append(el("p", { textContent: "Planning is paused until everyone's food safety question is answered." }));
    else {
      const plan = await app.op("plan.current");
      panel.append(el("p", { textContent: plan.ok && plan.result.working ? "You have a plan in progress." : "No plan yet." }));
    }
  } else if (app.tab === "household") {
    panel.append(el("h2", { textContent: "Household" }));
    const hh = house.ok ? house.result.household : undefined;
    if (!hh) {
      const adults = el("input", { type: "number", id: "adults", value: "2", min: "1", max: "8" });
      const children = el("input", { type: "number", id: "children", value: "0", min: "0", max: "8" });
      const go = el("button", { type: "button", id: "create-household", textContent: "Create household" });
      go.onclick = async () => {
        const r = await app.op("household.create", { adults: Number(adults.value), children: Number(children.value) });
        app.note = r.ok ? "" : r.error.message;
        await render();
      };
      panel.append(el("label", {}, "Adults ", adults), el("label", {}, "Children ", children), go);
    } else {
      panel.append(el("p", { id: "members", textContent: `${hh.members.length} people in this household.` }));
    }
    if (app.note) panel.append(el("p", { role: "alert", textContent: app.note }));
    panel.append(el("h3", { textContent: "Your data" }),
      el("p", { textContent: "Everything stays in this browser on this device. Nothing is sent anywhere." }));
    const del = el("button", { type: "button", id: "delete-all", class: "danger", textContent: "Delete all data" });
    del.onclick = () => confirmDelete(panel);
    panel.append(del);
    panel.append(el("p", { id: "engine-stats", class: "muted",
      textContent: `Engine ${(app.stats.rawBytes / 1048576).toFixed(1)} MB, ready in ${app.stats.totalMs} ms.` }));
  } else {
    panel.append(el("h2", { textContent: TABS.find((t) => t[0] === app.tab)![1] }),
      el("p", { textContent: "This part arrives in a later update." }));
  }
}

function confirmDelete(panel: HTMLElement): void {
  const dialog = el("div", { role: "alertdialog", id: "confirm-delete", class: "dialog" });
  dialog.setAttribute("aria-modal", "true");
  dialog.setAttribute("aria-labelledby", "cd-title");
  const yes = el("button", { type: "button", id: "confirm-delete-yes", class: "danger", textContent: "Delete everything" });
  const no = el("button", { type: "button", textContent: "Cancel" });
  no.onclick = () => dialog.remove();
  yes.onclick = async () => {
    await deleteEverything();
    app.core = await Core.instantiate(app.bytes);   // drop the in-memory state too
    // Self-check that nothing survived in memory (asserted by the browser test).
    const after = app.core.call("household.get", {}, makeCtx());
    document.documentElement.dataset.memory = after.ok && after.result.household == null ? "empty" : "not-empty";
    app.note = "";
    root.replaceChildren(el("main", { id: "deleted" }, el("h1", { textContent: "Everything was deleted" }),
      el("p", { textContent: "Reload this page while online to start again." })));
    document.documentElement.dataset.deleted = "true";
  };
  dialog.append(el("h2", { id: "cd-title", textContent: "Delete everything?" }),
    el("p", { textContent: "This removes your household, plans, pantry, list and everything I've learned from this device. It can't be undone." }), yes, no);
  panel.append(dialog);
  no.focus();
}

async function start(): Promise<void> {
  root.replaceChildren(el("p", { id: "loading", textContent: "Getting ready..." }));
  try {
    const reg = await registerWorker();
    const loaded = await loadCore(reg);
    app.core = loaded.core; app.bytes = loaded.bytes; app.stats = loaded.stats;
    const restored = await app.restore();
    document.documentElement.dataset.ready = "true";
    document.documentElement.dataset.restore = restored;
    document.documentElement.dataset.rawBytes = String(loaded.stats.rawBytes);
    document.documentElement.dataset.totalMs = String(loaded.stats.totalMs);
    document.documentElement.dataset.fetchMs = String(loaded.stats.fetchMs);
    document.documentElement.dataset.compileMs = String(loaded.stats.compileMs);
    await render();
  } catch (e) {
    root.replaceChildren(el("p", { role: "alert", id: "fatal", textContent: `Could not start: ${e instanceof Error ? e.message : String(e)}` }));
    document.documentElement.dataset.error = "true";
  }
}
void start();
