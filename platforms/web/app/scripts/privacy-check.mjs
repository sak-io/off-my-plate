// Release-hygiene / privacy lint for the web app (W11, AC-13.2). Nothing may leave the device, so the app code must
// not contain: network APIs (fetch, XMLHttpRequest, WebSocket, sendBeacon, EventSource, importScripts), remote URLs,
// analytics or tracking libraries, third-party scripts, fonts or stylesheets.
//   node scripts/privacy-check.mjs src     lints the sources (run before the build)
//   node scripts/privacy-check.mjs dist    checks the built output (run after the build)
// The only allowed exception: the service worker (sw.ts / sw.js) may call fetch() for its own same-origin precache list.
// Exported functions return a list of violation strings (empty = clean) so the fixtures test can plant violations.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, basename, extname } from "node:path";
import { fileURLToPath } from "node:url";

const NETWORK_APIS = [
  ["fetch", /\bfetch\s*\(/], ["XMLHttpRequest", /\bXMLHttpRequest\b/], ["WebSocket", /\bWebSocket\b/],
  ["sendBeacon", /\bsendBeacon\b/], ["EventSource", /\bEventSource\b/], ["importScripts", /\bimportScripts\s*\(/],
  ["RTCPeerConnection", /\bRTCPeerConnection\b/], ["WebTransport", /\bWebTransport\b/],
];
const FETCH_ALLOWED_IN = new Set(["sw.ts", "sw.js"]);
const REMOTE_URL = /(?:https?|wss?|ftp):\/\/(?!(?:127\.0\.0\.1|localhost)\b)[^\s"'`)<>]+/gi;
const PROTOCOL_RELATIVE = /(?:["'`(=]|\burl\()\s*\/\/[a-z0-9][a-z0-9.-]*\.[a-z]{2,}/gi;
const NAMESPACE_URLS = new Set(["http://www.w3.org/2000/svg", "http://www.w3.org/1999/xlink"]);   // identifiers, never requested
const TRACKERS = /google-analytics|googletagmanager|\bgtag\s*\(|\bga\s*\(\s*['"]|mixpanel|segment\.(?:com|io)|sentry|plausible|hotjar|posthog|amplitude|fullstory|matomo|facebook\.net|doubleclick|clarity\.ms|datadog|bugsnag|newrelic/i;

export function stripComments(text, name) {
  if (![".ts", ".js", ".mjs", ".css"].includes(extname(name))) return text;
  return text.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/(^|\s)\/\/[^\n]*/g, "$1");
}

/** Checks the text of one file. `name` decides which rules apply (by extension). */
export function checkFile(name, raw) {
  const out = [];
  const file = basename(name), ext = extname(name);
  const text = stripComments(raw, name);
  const say = (m) => out.push(`${file}: ${m}`);
  if (ext === ".ts" || ext === ".js" || ext === ".mjs") {
    for (const [label, re] of NETWORK_APIS) {
      if (label === "fetch" && FETCH_ALLOWED_IN.has(file)) continue;
      if (re.test(text)) say(`uses ${label} (the app must make no network requests)`);
    }
    if (/\bimport\s*\(\s*["'`]?(?:https?:|\/\/)/.test(text)) say("dynamic import of a remote module");
  }
  for (const m of text.matchAll(REMOTE_URL)) if (!NAMESPACE_URLS.has(m[0])) say(`remote URL ${m[0].slice(0, 80)}`);
  if (PROTOCOL_RELATIVE.test(text)) say("protocol-relative remote URL");
  if (TRACKERS.test(text)) say("analytics or tracking reference");
  if (ext === ".html") {
    for (const m of text.matchAll(/<script\b([^>]*)>/gi)) {
      if (!/\bsrc\s*=/.test(m[1])) say("inline script (CSP forbids it)");
      else if (/\bsrc\s*=\s*["']?(?:[a-z]+:)?\/\//i.test(m[1])) say("remote script");
    }
    if (/<(?:iframe|embed|object)\b/i.test(text)) say("embedded third-party content element");
    if (/<link\b[^>]*\bhref\s*=\s*["']?(?:[a-z]+:)?\/\//i.test(text)) say("remote <link>");
    if (/\bstyle\s*=/i.test(text)) say("inline style attribute (CSP forbids it)");
  }
  if (ext === ".css" && /@import\b/i.test(text)) say("@import (fonts or styles must be own files)");
  return out;
}

const SOURCE_EXT = new Set([".ts", ".html", ".css", ".svg", ".webmanifest", ".mjs"]);
const DIST_EXT = new Set([".js", ".html", ".css", ".svg", ".webmanifest", ".wasm"]);

/** Checks every file in a directory (not recursive: the app is flat). */
export function checkDir(dir, kind) {
  const out = [];
  const allowed = kind === "dist" ? DIST_EXT : SOURCE_EXT;
  for (const f of readdirSync(dir).sort()) {
    const p = join(dir, f);
    if (!statSync(p).isFile()) { out.push(`${f}: unexpected sub-directory`); continue; }
    if (!allowed.has(extname(f))) { out.push(`${f}: unexpected file type in ${kind}`); continue; }
    if (extname(f) === ".wasm") continue;   // the engine; its imports are restricted to WASI by the loader (src/wasi.ts) and tested in the browser
    out.push(...checkFile(f, readFileSync(p, "utf8")));
  }
  return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const kind = process.argv[2];
  if (kind !== "src" && kind !== "dist") { console.error("usage: privacy-check.mjs src|dist"); process.exit(2); }
  const root = join(fileURLToPath(new URL("..", import.meta.url)), kind);
  const problems = checkDir(root, kind);
  for (const p of problems) console.error(`::error::privacy-check ${p}`);
  console.log(`privacy-check ${kind}: ${problems.length === 0 ? "clean" : problems.length + " violation(s)"}`);
  process.exit(problems.length ? 1 : 0);
}
