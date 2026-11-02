// Service worker: precaches the app shell and the Wasm module at install, then serves cache-first.
// The page's CSP has connect-src 'none', so the page never touches the network itself; it asks this worker
// for the module bytes with a message. The worker only ever fetches its own precache list (same origin).
/// <reference lib="webworker" />
const sw = self as unknown as ServiceWorkerGlobalScope;

const VERSION = "__VERSION__";
const PRECACHE: string[] = JSON.parse('__PRECACHE__');
const CACHE = `omp-shell-${VERSION}`;
const WASM = "omp-web-wasm.wasm";

sw.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    for (const url of PRECACHE) {
      const res = await fetch(url, { cache: "reload" });
      if (!res.ok) throw new Error(`precache ${url}: ${res.status}`);
      await cache.put(url, res);
    }
    await sw.skipWaiting();
  })());
});

sw.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    for (const k of await caches.keys()) if (k.startsWith("omp-shell-") && k !== CACHE) await caches.delete(k);
    await sw.clients.claim();
  })());
});

async function lookup(request: Request): Promise<Response | undefined> {
  return caches.match(request, { ignoreSearch: true });
}

sw.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET" || new URL(req.url).origin !== sw.location.origin) return;
  event.respondWith((async () => {
    const hit = await lookup(req);
    if (hit) return hit;
    if (req.mode === "navigate") { const shell = await caches.match("index.html"); if (shell) return shell; }
    return new Response("Not available offline.", { status: 504, statusText: "Offline" });
  })());
});

sw.addEventListener("message", (event) => {
  if (event.data?.type !== "get-wasm" || !event.ports[0]) return;
  const port = event.ports[0];
  event.waitUntil((async () => {
    try {
      const res = (await caches.match(WASM)) ?? (await fetch(WASM));
      const bytes = await res.arrayBuffer();
      port.postMessage({ ok: true, bytes }, [bytes]);
    } catch (e) {
      port.postMessage({ ok: false, message: String(e) });
    }
  })());
});
