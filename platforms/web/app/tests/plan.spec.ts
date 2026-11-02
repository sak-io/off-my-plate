// W06 browser tests (real Chromium): plan screens, explicit approval, blocked-by-safety, pending revision,
// regenerate keeps locked meals, and an axe audit of every plan state. Browser state is seeded from a Node-side
// copy of the core (plan-seed.ts); approval itself only ever happens here by clicking the confirm button.
import { test, expect, type Browser, type BrowserContext, type Page } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import { blockedByNewMember, draftPlan, householdOnly, withBlockingRule } from "./plan-seed.js";

const ready = (page: Page) => expect(page.locator("html")).toHaveAttribute("data-ready", "true", { timeout: 120_000 });

async function putSnapshot(page: Page, snapshot: unknown): Promise<void> {
  await page.evaluate((snap) => new Promise<void>((resolve, reject) => {
    const q = indexedDB.open("omp", 1);
    q.onerror = () => reject(q.error);
    q.onsuccess = () => {
      const db = q.result;
      const t = db.transaction("kv", "readwrite");
      t.objectStore("kv").put({ savedAt: new Date().toISOString(), snapshot: snap }, "snapshot");
      t.oncomplete = () => { db.close(); resolve(); };
      t.onerror = () => reject(t.error);
    };
  }), snapshot);
}
async function readSnapshot(page: Page): Promise<unknown> {
  return page.evaluate(() => new Promise<unknown>((resolve, reject) => {
    const q = indexedDB.open("omp", 1);
    q.onerror = () => reject(q.error);
    q.onsuccess = () => {
      const db = q.result;
      const r = db.transaction("kv", "readonly").objectStore("kv").get("snapshot");
      r.onsuccess = () => { db.close(); resolve((r.result as { snapshot: unknown }).snapshot); };
      r.onerror = () => reject(r.error);
    };
  }));
}

async function openApp(browser: Browser, snapshot?: unknown): Promise<{ context: BrowserContext; page: Page }> {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto("/index.html");
  await ready(page);
  if (snapshot !== undefined) {
    await putSnapshot(page, snapshot);
    await page.reload();
    await ready(page);
    await expect(page.locator("html")).toHaveAttribute("data-restore", "restored");
  }
  return { context, page };
}

const status = (page: Page) => page.locator("#plan-status");
const rows = (page: Page) => page.locator("#week li.meal");
const sheet = (page: Page) => page.getByRole("dialog");

async function openApprovalSheet(page: Page): Promise<void> {
  await page.locator("#open-approval").click();
  await expect(sheet(page)).toBeVisible();
}

async function approveFirstPlan(page: Page): Promise<void> {
  await openApprovalSheet(page);
  await page.locator("#approve-confirm").click();
  await expect(status(page)).toContainText("Approved");
}

async function expectNoAxeViolations(page: Page, label: string): Promise<void> {
  const result = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
  const summary = result.violations.map((v) => `${v.id} (${v.impact}): ${v.nodes.slice(0, 3).map((n) => n.target.join(" ")).join(" | ")}`);
  expect(summary, `axe violations on ${label}`).toEqual([]);
}

test("no household: asks for the household first", async ({ browser }) => {
  const { context, page } = await openApp(browser);
  await expect(page.getByText("Add your household first")).toBeVisible();
  await context.close();
});

test("household without a plan: Make a plan creates a draft with 3 meals a day", async ({ browser }) => {
  const { context, page } = await openApp(browser, await householdOnly());
  await expect(page.getByText("No plan for this week")).toBeVisible();
  await page.locator("#make-plan").click();
  await expect(status(page)).toHaveText("✎ Draft · not in use yet");
  expect(await rows(page).count()).toBeGreaterThanOrEqual(21);
  await expect(page.locator("#first-plan-banner")).toContainText("A starting point. Swap anything and I'll learn.");
  await expect(page.locator("#open-approval")).toHaveText("Approve week");
  await expect(page.locator("#disclaimer")).toContainText("Not medical advice");
  await context.close();
});

test("a draft is never approved by loading, reloading, opening the sheet or script clicks", async ({ browser }) => {
  const { context, page } = await openApp(browser, await draftPlan());
  await expect(status(page)).toContainText("Draft");
  await openApprovalSheet(page);
  await expect(sheet(page)).toContainText("Approve week?");
  // Focus starts on the heading, not on an action button.
  await expect(page.locator("[role=dialog] h2")).toBeFocused();
  // A script-made click is not a person pressing the button.
  await page.evaluate(() => document.getElementById("approve-confirm")!.click());
  await page.evaluate(() => document.getElementById("approve-confirm")!.dispatchEvent(new MouseEvent("click", { bubbles: true })));
  await page.waitForTimeout(500);
  await expect(sheet(page)).toBeVisible();
  await page.reload();
  await ready(page);
  await expect(status(page)).toContainText("Draft");
  await context.close();
});

test("approve by keyboard Enter on a different control does not approve", async ({ browser }) => {
  const { context, page } = await openApp(browser, await draftPlan());
  // 1. Enter on the bar button only opens the sheet.
  await page.locator("#open-approval").focus();
  await page.keyboard.press("Enter");
  await expect(sheet(page)).toBeVisible();
  await expect(status(page)).toContainText("Draft");
  // 2. Enter and Space with focus on the sheet heading do nothing.
  await expect(page.locator("[role=dialog] h2")).toBeFocused();
  await page.keyboard.press("Enter");
  await page.keyboard.press("Space");
  await page.waitForTimeout(300);
  await expect(sheet(page)).toBeVisible();
  // 3. Enter on "Not yet" closes the sheet and approves nothing.
  await page.locator("#approve-not-yet").focus();
  await page.keyboard.press("Enter");
  await expect(sheet(page)).toHaveCount(0);
  await expect(status(page)).toContainText("Draft");
  await expect(page.locator("#open-approval")).toBeVisible();
  // 4. Escape closes the sheet too.
  await openApprovalSheet(page);
  await page.keyboard.press("Escape");
  await expect(sheet(page)).toHaveCount(0);
  await expect(status(page)).toContainText("Draft");
  // 5. Enter on a meal's Swap button opens swap, never approval.
  await page.locator("#week button.swap").first().focus();
  await page.keyboard.press("Enter");
  await expect(sheet(page)).toContainText("Swap ");
  await expect(status(page)).toContainText("Draft");
  await page.keyboard.press("Escape");
  await context.close();
});

test("approve week: the confirm button approves, the bar goes, a toast says so", async ({ browser }) => {
  const { context, page } = await openApp(browser, await draftPlan());
  await openApprovalSheet(page);
  await expect(page.locator("#approval-status")).toContainText("Safety check passed for everyone");
  await page.locator("#approve-confirm").click();
  await expect(status(page)).toContainText("✓ Approved");
  await expect(page.locator("#toast")).toContainText("Week approved. Your shopping list is ready.");
  await expect(page.locator("#open-approval")).toHaveCount(0);
  await page.reload();
  await ready(page);
  await expect(status(page)).toContainText("✓ Approved");
  await context.close();
});

test("swap, pending revision with diff, discard, then approve the changes", async ({ browser }) => {
  const { context, page } = await openApp(browser, await draftPlan());
  await approveFirstPlan(page);

  const swapFirst = async () => {
    await page.locator("#week button.swap").first().click();
    await expect(sheet(page)).toContainText("Pick one");
    const option = page.locator("#swap-options button.option").first();
    await expect(option).toBeVisible();
    await option.click();
    await expect(sheet(page)).toHaveCount(0);
  };
  await swapFirst();
  await expect(page.locator("#toast")).toContainText("Swapped. Changes need your approval.");
  await expect(status(page)).toContainText("Changes not approved yet");
  await expect(page.getByText("Changed", { exact: true }).first()).toBeVisible();
  await expect(page.getByText(/^Approved: /).first()).toBeVisible();
  await expect(page.getByText(/^Proposed: /).first()).toBeVisible();
  await expect(page.locator("#open-approval")).toHaveText("Review 1 change");

  await openApprovalSheet(page);
  await expect(sheet(page)).toContainText("Approve 1 change?");
  await expect(sheet(page)).toContainText("Everything else stays as approved.");
  await expect(sheet(page)).toContainText(/Was: /);
  await expect(sheet(page)).toContainText(/Now: /);
  await expectNoAxeViolations(page, "approval sheet (revision)");

  // Discard changes asks first; Keep editing leaves everything as it was.
  await page.locator("#approve-discard").click();
  await expect(page.getByRole("alertdialog")).toContainText("Discard your changes?");
  await page.locator("#discard-keep").click();
  await expect(status(page)).toContainText("Changes not approved yet");
  await page.locator("#approve-discard").click();
  await page.locator("#discard-yes").click();
  await expect(status(page)).toContainText("✓ Approved");
  await expect(page.getByText("Changed", { exact: true })).toHaveCount(0);

  // Swap again and approve the revision with the confirm button.
  await swapFirst();
  await openApprovalSheet(page);
  await page.locator("#approve-confirm").click();
  await expect(status(page)).toContainText("✓ Approved");
  await expect(page.locator("#toast")).toContainText("Changes approved. Your list is updated.");
  await context.close();
});

test("swap sheet: reason chips, Pick for me, and Cancel", async ({ browser }) => {
  const { context, page } = await openApp(browser, await draftPlan());
  await page.locator("#week button.swap").first().click();
  const chip = page.getByRole("button", { name: "Too long" });
  await chip.click();
  await expect(chip).toHaveAttribute("aria-pressed", "true");
  await expectNoAxeViolations(page, "swap sheet");
  await page.locator("#swap-cancel").click();
  await expect(sheet(page)).toHaveCount(0);
  await page.locator("#week button.swap").first().click();
  await page.locator("#swap-pick").click();
  await expect(sheet(page)).toHaveCount(0);
  await expect(status(page)).toContainText("Draft");
  await context.close();
});

test("meal detail shows who is eating, ingredients and steps", async ({ browser }) => {
  const { context, page } = await openApp(browser, await draftPlan());
  await page.locator("#week button.title").first().click();
  await expect(page.locator("#detail-title")).toBeVisible();
  await expect(page.locator("#eating li")).toHaveCount(3);
  await expect(page.locator("#ingredients li").first()).toBeVisible();
  await expect(page.getByText("Approve the week to mark meals cooked.")).toBeVisible();
  await expectNoAxeViolations(page, "meal detail");
  await page.locator("#detail-back").click();
  await expect(page.locator("#week")).toBeVisible();
  await context.close();
});

test("regenerate keeps locked meals", async ({ browser }) => {
  const { context, page } = await openApp(browser, await draftPlan());
  const withLock = page.locator("#week li.meal:has(button.lock)");
  for (const i of [0, 7, 14]) await withLock.nth(i).locator("button.lock").click();
  const locked = async () => {
    const out: string[] = [];
    const items = page.locator("#week li.meal:has(button.lock[aria-label^='Unlock'])");
    for (let i = 0; i < (await items.count()); i++) {
      out.push(`${await items.nth(i).locator("button.lock").getAttribute("aria-label")} => ${await items.nth(i).locator(".title").first().textContent()}`);
    }
    return out;
  };
  const before = await locked();
  expect(before).toHaveLength(3);
  await expect(page.getByText("🔒 Locked")).toHaveCount(3);

  await page.locator("#regenerate").click();
  await expect(page.getByRole("alertdialog")).toContainText("Replace all unlocked meals? Locked meals stay.");
  await page.locator("#regenerate-yes").click();
  await expect(sheet(page)).toHaveCount(0);
  await expect(page.locator("#regenerate")).toBeEnabled();
  expect(await locked()).toEqual(before);
  await expect(status(page)).toContainText("Draft");
  await context.close();
});

test("blocked by safety: card, disabled actions with the reason, Approve cannot open", async ({ browser }) => {
  const { context, page } = await openApp(browser, await blockedByNewMember());
  const card = page.locator("#blocked-card");
  await expect(card).toContainText(/Answer the safety question for .+ to keep planning\./);
  for (const target of [page.locator("#regenerate"), page.locator("#open-approval"), page.locator("#week button.swap").first()]) {
    await expect(target).toHaveAttribute("aria-disabled", "true");
    await target.click();
    await expect(page.locator("#hint")).toContainText(/I can't change meals until I know what .+ must avoid\./);
  }
  await expect(sheet(page)).toHaveCount(0);
  await expect(status(page)).toContainText("Draft");
  await expectNoAxeViolations(page, "blocked by safety");
  await page.locator("#blocked-answer").click();
  await expect(page.getByRole("tab", { name: "Household", selected: true })).toBeVisible();
  await context.close();
});

test("a rule that makes an approved meal unsafe: update card, then a pending revision", async ({ browser }) => {
  const first = await openApp(browser, await draftPlan());
  await approveFirstPlan(first.page);
  const approved = await readSnapshot(first.page);
  await first.context.close();
  const blocked = await withBlockingRule(approved);
  expect(blocked, "some catalog restriction must make a seeded meal unsafe").toBeDefined();

  const { context, page } = await openApp(browser, blocked);
  await expect(page.locator("#safety-changed")).toContainText("Your safety answers changed. Some meals need replacing.");
  await expect(page.getByText("▲ Needs replacing").first()).toBeVisible();
  await expect(status(page)).toContainText("Approved");
  await expectNoAxeViolations(page, "update card");
  await page.locator("#update-plan").click();
  await expect(status(page)).toContainText("Changes not approved yet");
  await expect(page.locator("#open-approval")).toContainText("Review");
  await context.close();
});

test("axe: week plan (draft) and approval sheet (first plan)", async ({ browser }) => {
  const { context, page } = await openApp(browser, await draftPlan());
  await expectNoAxeViolations(page, "week plan");
  await openApprovalSheet(page);
  await expectNoAxeViolations(page, "approval sheet");
  await page.keyboard.press("Escape");
  await page.locator("#regenerate").click();
  await expectNoAxeViolations(page, "regenerate confirm");
  await context.close();
});
