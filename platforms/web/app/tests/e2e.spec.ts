// Browser proof (real Chromium): the Wasm core loads, state persists, the app works offline after the first
// visit, the CSP blocks network from the page, and Delete all data empties every store.
import { test, expect, type BrowserContext, type Page } from "@playwright/test";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { gzipSync } from "node:zlib";

test.describe.configure({ mode: "serial" });

let context: BrowserContext;
let page: Page;
const consoleErrors: string[] = [];

test.beforeAll(async ({ browser }) => {
  context = await browser.newContext();
  page = await context.newPage();
  page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text()); });
  page.on("pageerror", (e) => consoleErrors.push(String(e)));
});
test.afterAll(async () => { await context.close(); });

const ready = async () => { await expect(page.locator("html")).toHaveAttribute("data-ready", "true", { timeout: 120_000 }); };

test("first visit: Wasm loads in Chromium and answers meta.version; size and time recorded", async () => {
  const t0 = Date.now();
  await page.goto("/index.html");
  await ready();
  const wallMs = Date.now() - t0;
  const d = await page.evaluate(() => ({ ...document.documentElement.dataset }));
  const wasm = readFileSync("dist/omp-web-wasm.wasm");
  const metrics = {
    rawBytes: wasm.length, gzip6Bytes: gzipSync(wasm, { level: 6 }).length, gzip9Bytes: gzipSync(wasm, { level: 9 }).length,
    pageReportedRawBytes: Number(d.rawBytes), swFetchMs: Number(d.fetchMs), compileInstantiateMs: Number(d.compileMs),
    pageLoadToReadyMsIncludingFirstInstall: wallMs, userAgent: await page.evaluate(() => navigator.userAgent),
  };
  mkdirSync("metrics", { recursive: true });
  writeFileSync("metrics/metrics.json", JSON.stringify(metrics, null, 1));
  console.log("METRICS " + JSON.stringify(metrics));
  expect(Number(d.rawBytes)).toBe(wasm.length);
  expect(d.restore).toBe("fresh");
  // W05: a new profile starts in onboarding (the tabs only appear once the safety question is answered).
  await page.locator("#children-plus").click();             // 2 adults + 1 child
  await page.locator("#size-continue").click();
  await page.locator("#nobody").click();
  await page.locator("#cuisines-skip").click();
  await expect(page.getByRole("tab", { name: "Plan", selected: true })).toBeVisible({ timeout: 60_000 });
  await page.getByRole("tab", { name: "Household" }).click();
  await expect(page.locator("#engine-stats")).toContainText("ready in");
});

test("four tabs, keyboard navigation", async () => {
  await expect(page.getByRole("tab")).toHaveText(["Plan", "List", "Pantry", "Household"]);
  await page.getByRole("tab", { name: "Plan" }).click();
  await page.getByRole("tab", { name: "Plan" }).press("ArrowRight");
  await expect(page.getByRole("tab", { name: "List", selected: true })).toBeFocused();
});

test("page cannot reach the network (CSP connect-src 'none')", async () => {
  const csp = await page.locator('meta[http-equiv="Content-Security-Policy"]').getAttribute("content");
  expect(csp).toContain("connect-src 'none'");
  const outcome = await page.evaluate(async () => {
    try { await fetch("/index.html"); return "allowed"; } catch { return "blocked"; }
  });
  expect(outcome).toBe("blocked");
});

test("household persists across reload (IndexedDB snapshot via state.export/import)", async () => {
  await page.getByRole("tab", { name: "Household" }).click();
  await expect(page.locator("#members")).toHaveText("3 people in this household.");   // created by onboarding above
  await page.reload();
  await ready();
  await expect(page.locator("html")).toHaveAttribute("data-restore", "restored");
  await page.getByRole("tab", { name: "Household" }).click();
  await expect(page.locator("#members")).toHaveText("3 people in this household.");
});

test("works offline after the first visit", async () => {
  await context.setOffline(true);
  await page.reload();
  await ready();
  await expect(page.locator("html")).toHaveAttribute("data-restore", "restored");
  await page.getByRole("tab", { name: "Household" }).click();
  await expect(page.locator("#members")).toHaveText("3 people in this household.");
  await context.setOffline(false);
});

test("Delete all data empties IndexedDB, caches and the service worker", async () => {
  const before = await page.evaluate(async () => ({
    dbs: (await indexedDB.databases()).length, caches: (await caches.keys()).length,
    regs: (await navigator.serviceWorker.getRegistrations()).length,
  }));
  expect(before.dbs).toBeGreaterThan(0); expect(before.caches).toBeGreaterThan(0); expect(before.regs).toBeGreaterThan(0);
  await page.getByRole("tab", { name: "Household" }).click();
  await page.locator("#delete-all").click();
  await expect(page.getByRole("alertdialog")).toContainText("It can't be undone");
  await page.locator("#confirm-delete-yes").click();
  await expect(page.locator("html")).toHaveAttribute("data-deleted", "true");
  const after = await page.evaluate(async () => ({
    dbs: (await indexedDB.databases()).length, caches: (await caches.keys()).length,
    regs: (await navigator.serviceWorker.getRegistrations()).length, local: localStorage.length,
  }));
  expect(after).toEqual({ dbs: 0, caches: 0, regs: 0, local: 0 });
});

test("no console errors during the run", async () => {
  // The blocked fetch in the CSP test logs one expected violation; anything else is a failure.
  const unexpected = consoleErrors.filter((e) => !/Content Security Policy|connect-src/i.test(e));
  expect(unexpected).toEqual([]);
});
