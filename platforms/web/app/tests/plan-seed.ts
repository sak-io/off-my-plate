// Test helper (Node side): builds browser-state snapshots by driving a second copy of the Wasm core through
// the same facade ops the app uses. It never approves anything: approval in these tests always happens in
// the browser, from the confirm button (see plan.spec.ts).
import { readFileSync } from "node:fs";
import { Core, makeCtx, type Reply } from "../dist/core.js";

let wasm: ArrayBuffer | undefined;
async function fresh(): Promise<Core> {
  if (!wasm) { const b = readFileSync("dist/omp-web-wasm.wasm"); wasm = b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength) as ArrayBuffer; }
  return Core.instantiate(wasm);
}

export class Seed {
  readonly core: Core;
  private constructor(core: Core) { this.core = core; }
  static async empty(): Promise<Seed> { return new Seed(await fresh()); }
  static async fromSnapshot(snapshot: unknown): Promise<Seed> {
    const s = await Seed.empty();
    s.must("state.import", { snapshot });
    return s;
  }
  call(op: string, args: Record<string, any> = {}): Reply { return this.core.call(op, args, makeCtx()); }
  must(op: string, args: Record<string, any> = {}): any {
    const r = this.call(op, args);
    if (!r.ok) throw new Error(`${op} failed: ${r.error.code} ${r.error.message}`);
    return r.result;
  }
  snapshot(): unknown { return this.must("state.export").snapshot; }
}

/** A household of 2 adults and 1 child, everyone's safety question answered "nothing to avoid". */
export async function household(): Promise<Seed> {
  const s = await Seed.empty();
  s.must("household.create", { adults: 2, children: 1 });
  s.must("safety.confirmNobody", { pendingItemCount: 0 });
  return s;
}

/** The household plus a generated draft plan (not approved). */
export async function draftPlan(): Promise<unknown> {
  const s = await household();
  s.must("plan.generate", {});
  return s.snapshot();
}

export async function householdOnly(): Promise<unknown> { return (await household()).snapshot(); }

/** Draft plan, then a new unasked person joins: the safety gate refuses planning (blocked-by-safety). */
export async function blockedByNewMember(): Promise<unknown> {
  const s = await household();
  s.must("plan.generate", {});
  s.must("household.addMember", { role: "child" });
  return s.snapshot();
}

/**
 * Takes a snapshot that holds an approved plan (made in the browser) and adds one household-wide rule that
 * makes at least one planned meal unsafe (R1 re-check). Returns the new snapshot, or undefined if no catalog
 * restriction hits this plan.
 */
export async function withBlockingRule(approvedSnapshot: unknown): Promise<unknown | undefined> {
  const probe = await Seed.fromSnapshot(approvedSnapshot);
  const ids: string[] = probe.must("safety.catalog").restrictions.map((r: { id: string }) => r.id);
  for (const id of ids) {
    const s = await Seed.fromSnapshot(approvedSnapshot);
    const r = s.call("safety.addRule", { item: { restriction: id, scope: { kind: "household" } } });
    if (r.ok && r.result.recheck.blockedMealIds.length > 0) return s.snapshot();
  }
  return undefined;
}
