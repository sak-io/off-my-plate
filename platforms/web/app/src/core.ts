// Thin JSON wrapper over the OMPWeb Wasm facade (memory protocol: docs/windows/w03-report.md section 5).
// Every call carries an explicit ctx (clock, zone, locale); nothing here reads host defaults.
import { makeWasiImports, WasiExit } from "./wasi.js";

export interface Ctx { now: string; timeZone: string; locale: string }
export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type Reply =
  | { ok: true; result: any }
  | { ok: false; error: { code: string; message: string; details?: Json } };

interface Exports {
  memory: WebAssembly.Memory;
  _initialize(): void;
  omp_version(): number;
  omp_alloc(n: number): number;
  omp_free(ptr: number): void;
  omp_call(ptr: number, n: number): number;
  omp_result_ptr(): number;
}

export const PROTOCOL_VERSION = 1;

export function makeCtx(date: Date = new Date()): Ctx {
  return {
    now: date.toISOString().replace(/\.\d+Z$/, "Z"),
    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
    locale: navigator.language || "en-IN",
  };
}

export class Core {
  private encoder = new TextEncoder();
  private decoder = new TextDecoder();
  readonly consoleLog: string[] = [];
  private constructor(private ex: Exports) {}

  /** Compiles and starts a fresh instance (fresh in-memory state). */
  static async instantiate(wasm: ArrayBuffer | WebAssembly.Module): Promise<Core> {
    const module = wasm instanceof WebAssembly.Module ? wasm : await WebAssembly.compile(wasm);
    const wasiNames = WebAssembly.Module.imports(module).filter((i) => i.module === "wasi_snapshot_preview1" && i.kind === "function").map((i) => i.name);
    const foreign = WebAssembly.Module.imports(module).filter((i) => i.module !== "wasi_snapshot_preview1");
    if (foreign.length > 0) throw new Error(`unexpected imports: ${foreign.map((i) => i.module + "." + i.name).join(", ")}`);
    let memory: WebAssembly.Memory | undefined;
    const logs: string[] = [];
    const imports = makeWasiImports(() => memory!, wasiNames, (fd, text) => { if (logs.length < 200) logs.push(`fd${fd}: ${text}`); });
    const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: imports });
    const ex = instance.exports as unknown as Exports;
    memory = ex.memory;
    try { ex._initialize(); } catch (e) { if (!(e instanceof WasiExit && e.code === 0)) throw e; }
    if (ex.omp_version() !== PROTOCOL_VERSION) throw new Error(`unsupported core protocol ${ex.omp_version()}`);
    const core = new Core(ex);
    core.consoleLog.push(...logs);
    return core;
  }

  /** One synchronous call. ctx is required; there is deliberately no default. */
  call(op: string, args: Record<string, Json> | undefined, ctx: Ctx): Reply {
    const request = this.encoder.encode(JSON.stringify({ op, args: args ?? {}, ctx }));
    const ptr = this.ex.omp_alloc(request.length);
    if (ptr === 0) return { ok: false, error: { code: "request_too_large", message: "The request is too large." } };
    try {
      new Uint8Array(this.ex.memory.buffer).set(request, ptr);   // re-read buffer: memory can grow
      const length = this.ex.omp_call(ptr, request.length);
      if (length < 0) return { ok: false, error: { code: "internal_error", message: `omp_call refused the buffer (${length})` } };
      const out = new Uint8Array(this.ex.memory.buffer, this.ex.omp_result_ptr(), length).slice();
      return JSON.parse(this.decoder.decode(out)) as Reply;
    } finally {
      this.ex.omp_free(ptr);
    }
  }
}
