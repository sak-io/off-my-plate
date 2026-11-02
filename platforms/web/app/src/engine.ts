// Loads the Wasm module through the service worker (the page itself may not fetch: CSP connect-src 'none').
import { Core } from "./core.js";

export interface LoadStats { rawBytes: number; fetchMs: number; compileMs: number; totalMs: number }

export async function registerWorker(): Promise<ServiceWorkerRegistration> {
  if (!("serviceWorker" in navigator)) throw new Error("This browser cannot run the app offline (no service worker).");
  await navigator.serviceWorker.register("sw.js", { scope: "./" });
  return navigator.serviceWorker.ready;
}

export function wasmFromWorker(reg: ServiceWorkerRegistration): Promise<ArrayBuffer> {
  return new Promise((resolve, reject) => {
    const target = reg.active;
    if (!target) return reject(new Error("service worker not active"));
    const { port1, port2 } = new MessageChannel();
    port1.onmessage = (e) => (e.data.ok ? resolve(e.data.bytes as ArrayBuffer) : reject(new Error(e.data.message)));
    target.postMessage({ type: "get-wasm" }, [port2]);
  });
}

export async function loadCore(reg: ServiceWorkerRegistration): Promise<{ core: Core; bytes: ArrayBuffer; stats: LoadStats }> {
  const t0 = performance.now();
  const bytes = await wasmFromWorker(reg);
  const t1 = performance.now();
  const core = await Core.instantiate(bytes);
  const t2 = performance.now();
  return { core, bytes, stats: { rawBytes: bytes.byteLength, fetchMs: Math.round(t1 - t0), compileMs: Math.round(t2 - t1), totalMs: Math.round(t2 - t0) } };
}
