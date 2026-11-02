// Local persistence: one IndexedDB record holding the facade's state.export snapshot. Nothing else is stored
// (no accounts, no network). deleteEverything() is the "Delete all data" implementation.
const DB = "omp", STORE = "kv", KEY = "snapshot";

function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => { req.result.createObjectStore(STORE); };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function tx<T>(mode: IDBTransactionMode, run: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await open();
  try {
    return await new Promise<T>((resolve, reject) => {
      const t = db.transaction(STORE, mode);
      const r = run(t.objectStore(STORE));
      t.oncomplete = () => resolve(r.result);
      t.onerror = () => reject(t.error);
      t.onabort = () => reject(t.error);
    });
  } finally { db.close(); }
}

export async function saveSnapshot(snapshot: unknown): Promise<void> {
  await tx("readwrite", (s) => s.put({ savedAt: new Date().toISOString(), snapshot }, KEY));
}

export async function loadSnapshot(): Promise<unknown | undefined> {
  const rec = await tx<{ snapshot: unknown } | undefined>("readonly", (s) => s.get(KEY));
  return rec?.snapshot;
}

export interface Wiped { databases: number; caches: number; registrations: number }

/** Removes the IndexedDB database(s), every Cache Storage cache, local/session storage and the service worker. */
export async function deleteEverything(): Promise<Wiped> {
  const wiped: Wiped = { databases: 0, caches: 0, registrations: 0 };
  const dbs = (await indexedDB.databases?.()) ?? [{ name: DB }];
  for (const d of dbs) {
    if (!d.name) continue;
    await new Promise<void>((resolve, reject) => {
      const r = indexedDB.deleteDatabase(d.name!);
      r.onsuccess = () => resolve();
      r.onerror = () => reject(r.error);
      r.onblocked = () => resolve();   // other tabs hold it open; deletion completes when they close
    });
    wiped.databases++;
  }
  if ("caches" in globalThis) for (const k of await caches.keys()) { await caches.delete(k); wiped.caches++; }
  localStorage.clear(); sessionStorage.clear();
  if ("serviceWorker" in navigator) for (const r of await navigator.serviceWorker.getRegistrations()) { if (await r.unregister()) wiped.registrations++; }
  return wiped;
}
