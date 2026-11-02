// W05 browser tests (real Chromium): onboarding S-01..S-04, the mandatory safety question S-02/S-02b, the gate
// cover for people added later, and an axe audit. Each test starts from an empty browser profile.
import { test, expect, type Browser, type BrowserContext, type Page } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";


const TITLE_SAFETY = "Does anyone have an allergy or something they must avoid?";
let context: BrowserContext | undefined;

async function fresh(browser: Browser, opts: { bypassCSP?: boolean } = {}): Promise<Page> {
  await context?.close();
  context = await browser.newContext(opts);
  const page = await context.newPage();
  await page.goto("/index.html");
  await expect(page.locator("html")).toHaveAttribute("data-ready", "true", { timeout: 120_000 });
  return page;
}
const screen = (page: Page, name: string) => expect(page.locator("main#onboarding")).toHaveAttribute("data-screen", name);
const noShell = async (page: Page) => {
  await expect(page.getByRole("tab")).toHaveCount(0);
  await expect(page.getByRole("tablist")).toHaveCount(0);
};
async function toSafety(page: Page, adults = 2, children = 0): Promise<void> {
  await screen(page, "size");
  for (let n = 2; n < adults; n++) await page.locator("#adults-plus").click();
  for (let n = 2; n > adults; n--) await page.locator("#adults-minus").click();
  for (let n = 0; n < children; n++) await page.locator("#children-plus").click();
  await page.locator("#size-continue").click();
  await screen(page, "safety");
}
async function snapshotHousehold(page: Page): Promise<{ members: any[]; rules: any[] } | undefined> {
  return page.evaluate(() => new Promise((resolve, reject) => {
    const req = indexedDB.open("omp", 1);
    req.onsuccess = () => {
      const g = req.result.transaction("kv").objectStore("kv").get("snapshot");
      g.onsuccess = () => { req.result.close(); resolve(g.result?.snapshot?.household); };
      g.onerror = () => reject(g.error);
    };
    req.onerror = () => reject(req.error);
  }));
}
async function addChip(page: Page, id: string) { await page.locator(`[data-chip="${id}"]`).click(); }
async function finishNobody(page: Page) {
  await page.locator("#nobody").click();
  await screen(page, "cuisines");
}

test("S-01: defaults, minimum and maximum household size (AC-1.1, 1.3)", async ({ browser }) => {
  const page = await fresh(browser);
  await screen(page, "size");
  await expect(page.locator("#adults-count")).toHaveText("2");
  await expect(page.locator("#children-count")).toHaveText("0");
  await expect(page.locator("#size-foot")).toHaveText("Teens count as adults for portions.");
  await expect(page.getByRole("textbox")).toHaveCount(0);                       // no name, e-mail or account fields
  await page.locator("#adults-minus").click(); await page.locator("#adults-minus").click();
  await expect(page.locator("#size-continue")).toBeDisabled();
  await expect(page.locator("#size-foot")).toHaveText("Add at least one person.");   // text, not only a greyed button
  for (let n = 0; n < 12; n++) await page.locator("#children-plus").click();
  await expect(page.locator("#children-count")).toHaveText("12");
  await expect(page.locator("#children-plus")).toBeDisabled();
  await expect(page.locator("#adults-plus")).toBeDisabled();
  await expect(page.locator("#size-foot")).toContainText("(12)");
});

test("S-01 to S-04 happy path: 'No, nobody' then Skip reaches a draft plan (AC-1.2, 1.5, 1.6, 2.2)", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page, 2, 1);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(TITLE_SAFETY);
  await expect(page.locator("#safety-reason")).toHaveText("I'll never put these in a plan, so I need to know before I suggest anything.");
  const created = await snapshotHousehold(page);
  expect(created!.members.map((m) => m.safetyStatus)).toEqual(["unasked", "unasked", "unasked"]);
  expect(created!.members.map((m) => `${m.label.role} ${m.label.number}`)).toEqual(["adult 1", "adult 2", "child 1"]);
  await finishNobody(page);
  const after = await snapshotHousehold(page);
  expect(after!.members.map((m) => m.safetyStatus)).toEqual(["confirmedNone", "confirmedNone", "confirmedNone"]);
  expect(after!.rules).toEqual([]);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("What do you usually cook?");
  await page.locator("#cuisines-skip").click();
  await expect(page.getByRole("tab", { name: "Plan", selected: true })).toBeVisible({ timeout: 60_000 });
  await expect(page.locator("#panel")).toContainText("You have a plan in progress.");
});

test("S-02 has no skip, close or navigation away; shows reason, chips, disclaimer (AC-2.1, 2.5, 2.6)", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page);
  await noShell(page);
  await expect(page.locator("#nobody")).toBeVisible();
  await expect(page.locator("[data-chip]")).toHaveText([
    "Peanuts", "Tree nuts", "Dairy/milk", "Egg", "Wheat/gluten", "Soy", "Sesame", "Mustard", "Fish", "Shellfish", "Beef", "Pork", "Vegetarian", "Jain (no onion, garlic, root veg)"]);
  await expect(page.locator("#disclaimer")).toContainText("OffMyPlate isn't medical advice. Always check ingredients and labels.");
  const names = await page.locator("main#onboarding button, main#onboarding a").allInnerTexts();
  for (const n of names) expect(n).not.toMatch(/skip|close|later|dismiss|cancel|plan|list|pantry|household/i);
  await expect(page.getByRole("button", { name: /skip|close|dismiss/i })).toHaveCount(0);
  await expect(page.locator("main#onboarding a")).toHaveCount(0);
  await expect(page.locator('main#onboarding [aria-modal], dialog')).toHaveCount(0);   // nothing to dismiss
  await expect(page.locator("#safety-continue")).toBeHidden();                         // Continue appears once an item exists
});

test("Escape cannot skip or close the safety question", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page);
  for (const target of ["body", "#nobody", '[data-chip="beef"]', "#avoid-text"]) {
    await page.locator(target).focus().catch(() => undefined);
    for (let n = 0; n < 3; n++) await page.keyboard.press("Escape");
  }
  await screen(page, "safety");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(TITLE_SAFETY);
  await noShell(page);
  // also while building an answer and on the check screen
  await addChip(page, "beef");
  await page.locator("#safety-continue").click();
  await screen(page, "review");
  await page.keyboard.press("Escape");
  await screen(page, "review");
  await noShell(page);
  const h = await snapshotHousehold(page);
  expect(h!.members.every((m) => m.safetyStatus === "unasked")).toBe(true);
});

test("Tab and Shift+Tab never reach anything outside the question", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page);
  for (let n = 0; n < 60; n++) {
    await page.keyboard.press(n % 2 === 0 ? "Tab" : n % 5 === 0 ? "Shift+Tab" : "Tab");
    const where = await page.evaluate(() => {
      const a = document.activeElement;
      return a === document.body || a === document.documentElement ? "body" : a!.closest("main#onboarding") ? "inside" : "outside";
    });
    expect(where).not.toBe("outside");
  }
  await screen(page, "safety");
  await noShell(page);
  await expect(page.locator('[role="tab"]')).toHaveCount(0);
});

test("browser Back does not leave or skip the safety question", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page);
  const url = page.url();
  for (let n = 0; n < 3; n++) {
    await page.goBack().catch(() => null);
    await page.waitForTimeout(150);
    expect(page.url()).toBe(url);
    await screen(page, "safety");
  }
  await noShell(page);
  await addChip(page, "soy");
  await page.locator("#safety-continue").click();
  await screen(page, "review");
  await page.goBack().catch(() => null);
  await page.waitForTimeout(150);
  await screen(page, "review");
  await noShell(page);
});

test("reload keeps the question: after S-02, after typing, and on the check screen", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page, 2, 1);
  await addChip(page, "peanuts");
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-ready", "true");
  await screen(page, "safety");                                  // household already stored, still unasked
  await expect(page.locator("#avoid-list li")).toHaveCount(0);   // the unsaved candidate is gone, not saved
  await noShell(page);
  await addChip(page, "peanuts");
  await page.locator("#safety-continue").click();
  await screen(page, "review");
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-ready", "true");
  await screen(page, "safety");
  await noShell(page);
  const h = await snapshotHousehold(page);
  expect(h!.rules).toEqual([]);
  expect(h!.members.map((m) => m.safetyStatus)).toEqual(["unasked", "unasked", "unasked"]);
});

test("candidates are saved only after the explicit confirmation (AC-2.3, 2.1 of S-02b)", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page, 2, 0);
  await addChip(page, "peanuts");
  await page.locator("#avoid-text").fill("no beef");
  await page.locator("#avoid-text").press("Enter");
  await expect(page.locator("#avoid-list li")).toHaveCount(2);
  await expect(page.locator("#nobody")).toBeDisabled();
  await expect(page.locator("#nobody-hint")).toHaveText("You've added things to avoid. Remove them to choose “No, nobody”.");
  await page.locator("#avoid-list li", { hasText: "Beef" }).getByRole("combobox").selectOption({ label: "Adult 1" });
  await page.locator("#safety-continue").click();
  await screen(page, "review");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Check this is right");
  await expect(page.locator("#summary")).toContainText("Everyone");
  await expect(page.locator("#summary")).toContainText("Peanuts");
  await expect(page.locator("#summary")).toContainText("Adult 1");
  await expect(page.locator("#summary")).toContainText("Beef");
  let h = await snapshotHousehold(page);
  expect(h!.rules).toEqual([]);                                                       // nothing saved yet
  expect(h!.members.every((m) => m.safetyStatus === "unasked")).toBe(true);
  await page.locator("#save-change").click();                                         // Change keeps the answers
  await screen(page, "safety");
  await expect(page.locator("#avoid-list li")).toHaveCount(2);
  h = await snapshotHousehold(page);
  expect(h!.rules).toEqual([]);
  await page.locator("#safety-continue").click();
  await page.locator("#save-yes").click();
  await screen(page, "cuisines");
  h = await snapshotHousehold(page);
  expect(h!.rules.map((r) => r.restriction).sort()).toEqual(["beef", "peanuts"]);
  expect(h!.rules.every((r) => r.kind === "hard" && r.source === "user")).toBe(true);
  expect(h!.members.map((m) => m.safetyStatus)).toEqual(["stated", "stated"]);
});

test("an item that cannot be mapped must be resolved or removed (AC-2.4)", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page, 1, 0);
  await page.locator("#avoid-text").fill("zzzfood");
  await page.locator("#avoid-add").click();
  const row = page.locator('#avoid-list li[data-kind="unmapped"]');
  await expect(row).toContainText("I can't check recipes for “zzzfood” yet. Pick the closest match, or remove it and check recipes yourself.");
  await expect(page.locator("#safety-continue")).toBeDisabled();
  await expect(page.locator("#continue-hint")).toHaveText("Sort out the item above to continue.");
  await expect(page.locator("#nobody")).toBeDisabled();
  // a forced click on the disabled button changes nothing
  await page.evaluate(() => (document.querySelector("#safety-continue") as HTMLButtonElement).click());
  await screen(page, "safety");
  // removing it returns to the empty state, where only "No, nobody" is possible
  await row.getByRole("button", { name: /Remove/ }).click();
  await expect(page.locator("#avoid-list li")).toHaveCount(0);
  await expect(page.locator("#nobody")).toBeEnabled();
  await expect(page.locator("#safety-continue")).toBeHidden();
  // picking the closest match makes it a normal item
  await page.locator("#avoid-text").fill("zzzfood");
  await page.locator("#avoid-text").press("Enter");
  await page.locator("#avoid-list select.pick").selectOption({ label: "Sesame" });
  await expect(page.locator('#avoid-list li[data-kind="known"]')).toContainText("Sesame");
  await expect(page.locator("#safety-continue")).toBeEnabled();
  const h = await snapshotHousehold(page);
  expect(h!.rules).toEqual([]);
});

test("typed text is data, never markup (no innerHTML)", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page, 1, 0);
  const evil = `<img src=x onerror="window.__xss=1"><b>x</b>`;
  await page.locator("#avoid-text").fill(evil);
  await page.locator("#avoid-add").click();
  // The parser splits the text into unmapped pieces; whatever it keeps is shown as plain text, never as elements.
  expect(await page.locator('#avoid-list li[data-kind="unmapped"]').count()).toBeGreaterThan(0);
  await expect(page.locator("#avoid-list")).toContainText("onerror");
  await expect(page.locator("#avoid-list img, #avoid-list b")).toHaveCount(0);
  expect(await page.evaluate(() => (window as any).__xss)).toBeUndefined();
});

test("keyboard only: chips with Space, text with Enter, answer with Enter", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page, 1, 0);
  await page.locator('[data-chip="egg"]').focus();
  await page.keyboard.press("Space");
  await expect(page.locator('[data-chip="egg"]')).toHaveAttribute("aria-pressed", "true");
  await page.locator("#avoid-text").focus();
  await page.keyboard.type("no pork");
  await page.keyboard.press("Enter");
  await expect(page.locator("#avoid-list li")).toHaveCount(2);
  await page.locator("#safety-continue").focus();
  await page.keyboard.press("Enter");
  await screen(page, "review");
  await expect(page.locator("#save-yes")).toBeEnabled();      // wakes up shortly after the screen appears (double-tap guard)
  await page.locator("#save-yes").focus();
  await page.keyboard.press("Enter");
  await screen(page, "cuisines");
});

test("Back from S-02 returns to S-01 with answers kept; fewer people removes their own rules", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page, 2, 0);
  await page.locator("#ob-back").click();
  await screen(page, "size");
  await expect(page.locator("#adults-count")).toHaveText("2");
  await page.locator("#adults-plus").click();
  await page.locator("#size-continue").click();
  await screen(page, "safety");                                  // 3 adults, all still unasked: back on S-02
  let h = await snapshotHousehold(page);
  expect(h!.members).toHaveLength(3);
  // Adult 3 gets a rule of their own, then we shrink to 2 adults: the rule goes with them.
  await page.locator("#avoid-text").fill("no beef");
  await page.locator("#avoid-text").press("Enter");
  await page.locator("#avoid-list li").getByRole("combobox").selectOption({ label: "Adult 3" });
  await page.locator("#safety-continue").click();
  await page.locator("#save-yes").click();
  await screen(page, "cuisines");
  h = await snapshotHousehold(page);
  expect(h!.rules).toHaveLength(1);
  await page.locator("#ob-back").click();
  await screen(page, "size");
  await page.locator("#adults-minus").click();
  await page.locator("#size-continue").click();
  await expect(page.locator("main#onboarding, #panel").first()).toBeVisible();
  await expect.poll(async () => (await snapshotHousehold(page))!.rules.length).toBe(0);
  h = await snapshotHousehold(page);
  expect(h!.members.filter((m) => !m.deletedAt)).toHaveLength(2);
});

test("a person added later gets the safety question first, one page each, with no way past it (AC-3.2)", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page, 2, 0);
  await finishNobody(page);
  await page.locator("#ob-back").click();
  await screen(page, "size");
  await page.locator("#adults-plus").click();
  await page.locator("#children-plus").click();
  await page.locator("#size-continue").click();
  await screen(page, "safety");
  await expect(page.locator("main#onboarding")).toHaveAttribute("data-variant", "cover");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Does Adult 3 have an allergy or something they must avoid?");
  await expect(page.locator("#cover-progress")).toHaveText("1 of 2");
  await expect(page.locator("#ob-back")).toHaveCount(0);                 // no Back on the cover
  await expect(page.locator(".who")).toHaveCount(0);                     // no Who? on the cover
  await expect(page.locator("#nobody")).toHaveText("No, nothing");
  await noShell(page);
  await page.keyboard.press("Escape");
  await page.goBack().catch(() => null);
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-ready", "true");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Does Adult 3 have an allergy or something they must avoid?");
  await page.locator("#nobody").click();
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Does Child 1 have an allergy or something they must avoid?");
  await expect(page.locator("#cover-progress")).toHaveText("2 of 2");
  await addChip(page, "fish");
  await page.locator("#safety-continue").click();
  await expect(page.locator("#summary")).toContainText("Child 1");
  await page.locator("#save-yes").click();
  await expect(page.getByRole("tab", { name: "Plan" })).toBeVisible();    // gate open: the app appears
  const h = await snapshotHousehold(page);
  expect(h!.members.every((m) => m.safetyStatus !== "unasked")).toBe(true);
  expect(h!.rules).toHaveLength(1);
  expect(JSON.stringify(h!.rules[0]!.scope)).toContain(h!.members[3]!.id);   // the rule belongs to Child 1 only
});

test("gate cover: 'Added by mistake? Remove' asks first and removes the person", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page, 1, 0);
  await finishNobody(page);
  await page.locator("#ob-back").click();
  await page.locator("#children-plus").click();
  await page.locator("#size-continue").click();
  await expect(page.locator("#remove-member")).toHaveText("Added by mistake? Remove Child 1");
  await page.locator("#remove-member").click();
  await expect(page.getByRole("alertdialog")).toContainText("Remove Child 1?");
  await page.keyboard.press("Escape");                                    // closes the question only
  await expect(page.getByRole("alertdialog")).toHaveCount(0);
  await screen(page, "safety");
  await page.locator("#remove-member").click();
  await page.locator("#remove-yes").click();
  await expect(page.getByRole("tab", { name: "Plan" })).toBeVisible();
  const h = await snapshotHousehold(page);
  expect(h!.members.filter((m) => !m.deletedAt)).toHaveLength(1);
});

test("the 'Still correct?' re-check card appears when the 180 days are over (AC-3.4)", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page, 1, 0);
  await finishNobody(page);
  await page.locator("#cuisines-skip").click();
  await expect(page.getByRole("tab", { name: "Plan", selected: true })).toBeVisible({ timeout: 60_000 });
  // Age the stored answer by 200 days (a user-owned local file), then restart the app.
  await page.evaluate(() => new Promise<void>((resolve, reject) => {
    const req = indexedDB.open("omp", 1);
    req.onsuccess = () => {
      const db = req.result, store = db.transaction("kv", "readwrite").objectStore("kv");
      const g = store.get("snapshot");
      g.onsuccess = () => {
        const rec = g.result, old = new Date(Date.now() - 200 * 86400_000).toISOString().replace(/\.\d+Z$/, "Z");
        for (const m of rec.snapshot.household.members) m.safetyConfirmedAt = old;
        store.put(rec, "snapshot").onsuccess = () => resolve();
      };
      g.onerror = () => reject(g.error);
    };
  }));
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-ready", "true");
  await expect(page.getByRole("tab", { name: "Plan" })).toBeVisible();       // may be ignored: the app is usable
  await expect(page.locator("#reconfirm")).toContainText("Still correct?");
  await expect(page.locator("#reconfirm")).toContainText("Nobody has anything to avoid");
  // Make changes: what the check dialog shows is exactly what is saved, even if the list is changed behind it.
  await page.locator("#reconfirm-edit").click();
  await addChip(page, "peanuts");
  await page.locator("#reconfirm-add").click();
  await expect(page.locator("#ra-q")).toContainText("Peanuts");
  expect(await page.evaluate(() => (document.querySelector("#reconfirm .entry") as any).inert)).toBe(true);   // page behind is inert
  await page.evaluate(() => (document.querySelector('[data-chip="soy"]') as HTMLButtonElement).click());      // forced edit behind the dialog
  await page.locator("#reconfirm-save").click();
  await expect(page.locator("#reconfirm-save")).toHaveCount(0, { timeout: 30_000 });
  const saved = await snapshotHousehold(page);
  expect(saved!.rules.map((r) => r.restriction)).toEqual(["peanuts"]);                                          // never soy
  if (await page.locator("#reconfirm-yes").count()) await page.locator("#reconfirm-yes").click();
  await expect(page.locator("#reconfirm")).toHaveCount(0);
});

test("'No, nobody' and Continue are blocked while typed text has not been added (AC-2.4)", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page, 1, 0);
  await page.locator("#avoid-text").fill("peanuts");                       // typed, not added
  await expect(page.locator("#nobody")).toBeDisabled();
  await expect(page.locator("#nobody-hint")).toContainText("You've typed something");
  await page.evaluate(() => (document.querySelector("#nobody") as HTMLButtonElement).click());
  await screen(page, "safety");
  let h = await snapshotHousehold(page);
  expect(h!.members.every((m) => m.safetyStatus === "unasked")).toBe(true);
  await addChip(page, "soy");                                                // an item exists, text still pending
  await expect(page.locator("#safety-continue")).toBeDisabled();
  await expect(page.locator("#continue-hint")).toContainText("Add the text you typed");
  await page.locator("#avoid-add").click();                                  // now parsed into the list
  await expect(page.locator("#avoid-list li")).toHaveCount(2);
  await expect(page.locator("#safety-continue")).toBeEnabled();
  await page.locator("#avoid-text").fill("x");
  await page.locator("#avoid-text").fill("");                                // cleared: no pending text
  await expect(page.locator("#safety-continue")).toBeEnabled();
  h = await snapshotHousehold(page);
  expect(h!.rules).toEqual([]);
});

test("an unreadable stored snapshot fails closed: the question flow, never the app", async ({ browser }) => {
  const page = await fresh(browser);
  await toSafety(page, 1, 0);
  await page.evaluate(() => new Promise<void>((resolve, reject) => {
    const req = indexedDB.open("omp", 1);
    req.onsuccess = () => {
      const t = req.result.transaction("kv", "readwrite");
      t.objectStore("kv").put({ savedAt: "x", snapshot: { format: "garbage" } }, "snapshot");
      t.oncomplete = () => { req.result.close(); resolve(); };
      t.onerror = () => reject(t.error);
    };
  }));
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-ready", "true", { timeout: 30_000 });
  await expect(page.locator("html")).toHaveAttribute("data-restore", /unreadable/);
  await screen(page, "size");
  await noShell(page);
});

test("accessibility: axe finds no violations on every onboarding screen", async ({ browser }) => {
  const page = await fresh(browser, { bypassCSP: true });   // only so axe can inject itself; the app's CSP is tested in e2e.spec.ts
  const audit = async (label: string) => {
    const r = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "best-practice"]).analyze();
    expect(r.violations.map((v) => `${label}: ${v.id} ${v.nodes.map((n) => n.target.join(" ")).join(", ")}`)).toEqual([]);
  };
  await screen(page, "size");
  await audit("S-01");
  await page.locator("#adults-plus").click();
  await page.locator("#size-continue").click();
  await screen(page, "safety");
  await audit("S-02 empty");
  await addChip(page, "peanuts");
  await page.locator("#avoid-text").fill("zzzfood");
  await page.locator("#avoid-add").click();
  await audit("S-02 with items and an unmapped item");
  await page.locator("#avoid-list select.pick").selectOption({ label: "Mustard" });
  await page.locator("#safety-continue").click();
  await screen(page, "review");
  await audit("S-02b");
  await page.locator("#save-yes").click();
  await screen(page, "cuisines");
  await audit("S-03");
  await page.locator("#ob-back").click();
  await page.locator("#children-plus").click();
  await page.locator("#size-continue").click();
  await expect(page.locator("main#onboarding")).toHaveAttribute("data-variant", "cover");
  await audit("gate cover");
  await page.locator("#remove-member").click();
  await audit("gate cover with the remove question");
});

test("source rules: no innerHTML, no approval, every core call through the wrapper", async () => {
  const dir = join("src", "screens");
  const files = readdirSync(dir).filter((f) => f.endsWith(".ts"));
  expect(files.length).toBeGreaterThan(3);
  const approvalType = "User" + "Confirmation";
  for (const f of files) {
    const text = readFileSync(join(dir, f), "utf8");
    expect(text, f).not.toMatch(/innerHTML|outerHTML|insertAdjacentHTML|document\.write|\beval\(|new Function/);
    expect(text, f).not.toContain(approvalType);
    expect(text, f).not.toMatch(/plan\.approve|approvalPreview/);
    expect(text, f).not.toMatch(/\bcore\.call\(|new Core\b|\bCore\.instantiate/);                   // only host.op -> app.op -> Core.call(ctx)
    expect(text, f).not.toMatch(/fetch\(|XMLHttpRequest|WebSocket|sendBeacon/);
  }
  const main = readFileSync(join("src", "main.ts"), "utf8");
  expect(main).toMatch(/this\.core\.call\(name, args, makeCtx\(\)\)/);                                  // explicit ctx on every call
});
