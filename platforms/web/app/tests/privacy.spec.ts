// Privacy guarantees (W11, AC-13.2): nothing leaves the device. Real Chromium. Every request the browser makes
// (page and service worker) is recorded; after the first load there must be none beyond own assets, and none at all
// while the user works. Also: CSP and headers, hostile-code probes, offline, and Delete all data completeness.
import { test, expect, type BrowserContext, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";

const ORIGIN = "http://127.0.0.1:4173";
const precache: string[] = JSON.parse(/const PRECACHE = JSON\.parse\('(.*?)'\)/.exec(readFileSync("dist/sw.js", "utf8"))![1]!);
const OWN_ASSETS = new Set(["/", "/sw.js", ...precache.map((f) => "/" + f)]);

const ready = (page: Page) => expect(page.locator("html")).toHaveAttribute("data-ready", "true", { timeout: 120_000 });
const isData = (u: string) => /^(data|blob|about):/.test(u);

function record(context: BrowserContext) {
  const urls: string[] = [];
  const sockets: string[] = [];
  context.on("request", (r) => { if (!isData(r.url())) urls.push(r.url()); });
  context.on("page", (p) => p.on("websocket", (w) => sockets.push(w.url())));
  return {
    urls, sockets,
    foreign: () => urls.filter((u) => !u.startsWith(ORIGIN + "/")),
    notOwnAssets: () => urls.filter((u) => !OWN_ASSETS.has(new URL(u).pathname)),
    clear: () => { urls.length = 0; },
  };
}

test.describe("no network beyond own assets", () => {
  test.describe.configure({ mode: "serial" });
  let context: BrowserContext, page: Page, rec: ReturnType<typeof record>;
  test.beforeAll(async ({ browser }) => {
    context = await browser.newContext();
    rec = record(context);
    page = await context.newPage();
    page.on("websocket", (w) => rec.sockets.push(w.url()));
  });
  test.afterAll(async () => { await context.close(); });

  test("first load: every request is to the own origin and an own asset", async () => {
    await page.goto("/index.html");
    await ready(page);
    expect(rec.urls.length).toBeGreaterThan(0);          // the recorder is alive
    expect(rec.foreign()).toEqual([]);
    expect(rec.notOwnAssets()).toEqual([]);
    expect(rec.sockets).toEqual([]);
  });

  test("after load: zero requests of any kind while using every tab and creating a household", async () => {
    await page.waitForTimeout(1500);                      // let the service worker finish installing
    rec.clear();
    for (const t of ["Plan", "List", "Pantry", "Household"]) {
      await page.getByRole("tab", { name: t }).click();
      await expect(page.getByRole("tab", { name: t, selected: true })).toBeVisible();
    }
    await page.locator("#adults").fill("2");
    await page.locator("#children").fill("1");
    await page.locator("#create-household").click();
    await expect(page.locator("#members")).toHaveText("3 people in this household.");
    await page.waitForTimeout(1000);
    expect(rec.urls).toEqual([]);
    expect(rec.sockets).toEqual([]);
    // Liveness: the recorder does see an own-origin request made now.
    await page.evaluate(() => { new Image().src = "/icon.svg?probe"; });
    await expect.poll(() => rec.urls.length).toBeGreaterThan(0);
    rec.clear();
  });

  test("hostile code in the page cannot reach any network API (CSP)", async () => {
    const result = await page.evaluate(async () => {
      const foreign = "http://127.0.0.2:9/x";
      const out: Record<string, string> = {};
      try { await fetch(foreign); out.fetch = "allowed"; } catch { out.fetch = "blocked"; }
      out.xhr = await new Promise((res) => {
        const x = new XMLHttpRequest();
        x.onload = () => res("allowed"); x.onerror = () => res("blocked");
        try { x.open("GET", foreign); x.send(); } catch { res("blocked"); }
      });
      out.ws = await new Promise((res) => {
        try { const w = new WebSocket("ws://127.0.0.2:9/x"); w.onopen = () => res("allowed"); w.onerror = () => res("blocked"); w.onclose = () => res("blocked"); }
        catch { res("blocked"); }
      });
      out.img = await new Promise((res) => {
        const i = new Image(); i.onload = () => res("allowed"); i.onerror = () => res("blocked"); i.src = "http://127.0.0.2:9/x.png";
      });
      out.script = await new Promise((res) => {
        const s = document.createElement("script"); s.src = "http://127.0.0.2:9/x.js";
        s.onload = () => res("allowed"); s.onerror = () => res("blocked"); document.head.append(s);
      });
      out.inline = await new Promise((res) => {
        (window as any).__ran = false;
        const s = document.createElement("script"); s.textContent = "window.__ran = true"; document.head.append(s);
        setTimeout(() => res((window as any).__ran ? "allowed" : "blocked"), 200);
      });
      return out;
    });
    expect(result).toEqual({ fetch: "blocked", xhr: "blocked", ws: "blocked", img: "blocked", script: "blocked", inline: "blocked" });
    expect(rec.foreign()).toEqual([]);
    expect(rec.sockets).toEqual([]);
  });

  test("reload online and offline: only own assets, nothing foreign, still works", async () => {
    await page.reload(); await ready(page);
    await context.setOffline(true);
    await page.reload(); await ready(page);
    await page.getByRole("tab", { name: "Household" }).click();
    await expect(page.locator("#members")).toHaveText("3 people in this household.");
    await context.setOffline(false);
    expect(rec.foreign()).toEqual([]);
    expect(rec.notOwnAssets()).toEqual([]);
    expect(rec.sockets).toEqual([]);
  });
});

test("CSP and response headers: meta equals header, no unsafe sources, sw.js carries no CSP", async ({ request }) => {
  const html = await request.get("/index.html");
  const header = html.headers()["content-security-policy"]!;
  expect(header).toBeTruthy();
  expect(html.headers()["x-content-type-options"]).toBe("nosniff");
  const body = await html.text();
  const meta = /<meta http-equiv="Content-Security-Policy" content="([^"]*)"/.exec(body)![1];
  expect(meta).toBe(header);
  const d = Object.fromEntries(header.split(";").map((x) => x.trim().split(/\s+/)).map(([k, ...v]) => [k, v]));
  expect(d["default-src"]).toEqual(["'none'"]);
  expect(d["connect-src"]).toEqual(["'none'"]);
  expect(d["script-src"]).toEqual(["'self'", "'wasm-unsafe-eval'"]);
  expect(d["style-src"]).toEqual(["'self'"]);
  expect(d["base-uri"]).toEqual(["'none'"]);
  expect(d["form-action"]).toEqual(["'none'"]);
  for (const [k, v] of Object.entries(d)) for (const src of v as string[]) {
    expect(src, `${k}`).not.toMatch(/^(\*|https?:|wss?:|data:|blob:|'unsafe-inline'|'unsafe-eval'|'strict-dynamic')/);
  }
  expect(header).not.toMatch(/\*/);
  // Hosting note (W04): a CSP header on sw.js with connect-src 'none' would break the first install.
  const sw = await request.get("/sw.js");
  expect(sw.headers()["content-security-policy"]).toBeUndefined();
  // Every served asset is own and plain: no file outside the precache list is reachable.
  const missing = await request.get("/analytics.js");
  expect(missing.status()).toBe(404);
});

test.describe("Delete all data", () => {
  test.describe.configure({ mode: "serial" });
  let context: BrowserContext, page: Page;
  test.beforeAll(async ({ browser }) => { context = await browser.newContext(); page = await context.newPage(); });
  test.afterAll(async () => { await context.close(); });

  const stores = () => page.evaluate(async () => ({
    dbs: (await indexedDB.databases()).length, caches: (await caches.keys()).length,
    regs: (await navigator.serviceWorker.getRegistrations()).length, local: localStorage.length, session: sessionStorage.length,
  }));

  test("saves are serialized, and none can recreate the database once deletion started", async () => {
    await page.goto("/index.html"); await ready(page);
    await page.getByRole("tab", { name: "Household" }).click();
    await page.locator("#create-household").click();
    await expect(page.locator("#members")).toBeVisible();
    const r = await page.evaluate(async () => {
      const store: any = await import("/store.js");
      const early = [1, 2, 3, 4].map((n) => store.saveSnapshot({ n }));          // in flight when the delete starts
      const wipe = store.deleteEverything();
      const late = store.saveSnapshot({ n: 99 });                                // issued after: must be refused
      const settled = await Promise.all([...early, late]);
      await wipe;
      const lateAfter = await store.saveSnapshot({ n: 100 });
      return { settled, lateAfter, dbs: (await indexedDB.databases()).length };
    });
    expect(r.settled[r.settled.length - 1]).toBe(false);
    expect(r.lateAfter).toBe(false);
    expect(r.dbs).toBe(0);
  });

  test("after a full reload the app is fresh and the UI delete clears storage and memory", async () => {
    await page.goto("/index.html"); await ready(page);
    await expect(page.locator("html")).toHaveAttribute("data-restore", "fresh");   // the race left nothing behind
    await page.getByRole("tab", { name: "Household" }).click();
    await page.locator("#adults").fill("3");
    await page.locator("#create-household").click();
    await expect(page.locator("#members")).toHaveText("3 people in this household.");
    const before = await stores();
    expect(before.dbs).toBeGreaterThan(0); expect(before.caches).toBeGreaterThan(0); expect(before.regs).toBeGreaterThan(0);
    await page.evaluate(() => { localStorage.setItem("probe", "1"); sessionStorage.setItem("probe", "1"); });
    await page.locator("#delete-all").click();
    await page.locator("#confirm-delete-yes").click();
    await expect(page.locator("html")).toHaveAttribute("data-deleted", "true");
    await expect(page.locator("html")).toHaveAttribute("data-memory", "empty");   // in-memory engine state is gone too
    expect(await stores()).toEqual({ dbs: 0, caches: 0, regs: 0, local: 0, session: 0 });
    await page.waitForTimeout(1000);                                              // nothing re-appears afterwards
    expect(await stores()).toEqual({ dbs: 0, caches: 0, regs: 0, local: 0, session: 0 });
    await page.goto("/index.html"); await ready(page);
    await expect(page.locator("html")).toHaveAttribute("data-restore", "fresh");
    await page.getByRole("tab", { name: "Household" }).click();
    await expect(page.locator("#members")).toHaveCount(0);                         // no household came back
  });
});
