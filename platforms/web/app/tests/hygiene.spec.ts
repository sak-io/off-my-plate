// Non-browser tests: the privacy lint catches planted violations, the repo is clean, and the op classification
// matches the facade (so no state-changing op can silently skip persistence).
import { test, expect } from "@playwright/test";
import { readFileSync, readdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
// @ts-ignore plain ES module script
import { checkFile, checkDir } from "../scripts/privacy-check.mjs";
import { PERSISTED, NOT_PERSISTED, classify } from "../src/ops";

const violates = (name: string, text: string, needle: RegExp) => {
  const r: string[] = checkFile(name, text);
  expect(r.join("\n")).toMatch(needle);
};

test.describe("privacy lint fixtures: planted violations fail", () => {
  test("network APIs are rejected in app code", () => {
    violates("main.ts", 'await fetch("/x");', /fetch/);
    violates("main.ts", "const x = new XMLHttpRequest();", /XMLHttpRequest/);
    violates("main.ts", "new WebSocket(u)", /WebSocket/);
    violates("main.ts", "navigator.sendBeacon(u, d)", /sendBeacon/);
    violates("main.ts", "new EventSource(u)", /EventSource/);
    violates("sw.ts", "importScripts(a)", /importScripts/);
  });
  test("remote URLs, protocol-relative URLs and dynamic remote import are rejected", () => {
    violates("main.ts", 'const u = "https://example.com/a.js";', /remote URL/);
    violates("styles.css", "body{background:url(http://cdn.example/x.png)}", /remote URL/);
    violates("styles.css", 'a{background:url("//cdn.example.com/x.png")}', /protocol-relative/);
    violates("main.ts", 'import("https://esm.sh/x")', /remote/);
  });
  test("analytics, third-party scripts, fonts and inline script are rejected", () => {
    violates("main.ts", 'loadScript("googletagmanager")', /analytics/);
    violates("main.ts", "Sentry.init()", /analytics/);
    violates("index.html", '<script src="https://x.example/a.js"></script>', /remote/);
    violates("index.html", '<script src="//x.example/a.js"></script>', /remote script/);
    violates("index.html", "<script>alert(1)</script>", /inline script/);
    violates("index.html", '<link rel="stylesheet" href="https://fonts.googleapis.com/css?family=X">', /remote/);
    violates("index.html", '<iframe src="a.html"></iframe>', /embedded/);
    violates("styles.css", '@import "fonts.css";', /@import/);
  });
  test("allowed: the service worker may fetch its own precache; SVG namespace; comments mentioning fetch", () => {
    expect(checkFile("sw.ts", 'const r = await fetch(url, { cache: "reload" });')).toEqual([]);
    expect(checkFile("sw.js", "await fetch(WASM)")).toEqual([]);
    expect(checkFile("icon.svg", '<svg xmlns="http://www.w3.org/2000/svg"/>')).toEqual([]);
    expect(checkFile("engine.ts", "// the page may not fetch(...) or use https://example.com\nconst a = 1; /* fetch( */")).toEqual([]);
  });
  test("fetch is rejected in every file except the service worker", () => {
    violates("engine.ts", "fetch(url)", /fetch/);
    violates("sw.ts", 'fetch("https://evil.example/")', /remote URL/);
  });
  test("the real src tree is clean; a directory with a bad file or file type fails", () => {
    expect(checkDir(new URL("../src", import.meta.url).pathname, "src")).toEqual([]);
    const tmp = mkdtempSync(join(tmpdir(), "omp-lint-"));
    writeFileSync(join(tmp, "a.js"), 'navigator.sendBeacon("/x")');
    writeFileSync(join(tmp, "track.php"), "x");
    const r: string[] = checkDir(tmp, "dist");
    expect(r.join("\n")).toMatch(/a\.js: uses sendBeacon/);
    expect(r.join("\n")).toMatch(/track\.php: unexpected file type/);
  });
});

test("op classification: PERSISTED and NOT_PERSISTED are disjoint and cover every op the facade handles", () => {
  const dir = new URL("../../facade/Sources", import.meta.url).pathname;
  const ops = new Set<string>();
  const walk = (d: string) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      const p = `${d}/${e.name}`;
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith(".swift")) for (const m of readFileSync(p, "utf8").matchAll(/case "([a-z]+\.[A-Za-z]+)"/g)) ops.add(m[1]!);
    }
  };
  walk(dir);
  expect(ops.size).toBeGreaterThan(40);
  for (const o of PERSISTED) expect(NOT_PERSISTED.has(o), `${o} in both lists`).toBe(false);
  expect([...ops].filter((o) => classify(o) === "unknown")).toEqual([]);
  expect([...PERSISTED, ...NOT_PERSISTED].filter((o) => !ops.has(o))).toEqual([]);   // no stale names
  // Regression for the old suffix regex: a write op with a read-style name must still persist if classified so.
  for (const w of ["household.create", "plan.approve", "pantry.add", "shopping.check", "safety.confirm"]) expect(classify(w)).toBe("persisted");
  for (const r of ["household.get", "plan.current", "state.export", "pantry.list"]) expect(classify(r)).toBe("not-persisted");
  expect(classify("made.up")).toBe("unknown");
});
