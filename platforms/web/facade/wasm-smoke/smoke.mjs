// Smoke test of the browser module's memory protocol under Node's WASI (CI, .github/workflows/web-facade.yml).
// Usage: node smoke.mjs path/to/omp-web-wasm.wasm
// Exercises: _initialize, omp_version, omp_alloc/omp_call/omp_result_ptr/omp_free, the synchronous driver
// (actors and the service lock), the gate, and the approval door, all through linear memory.
import { readFileSync } from 'node:fs';
import { WASI } from 'node:wasi';

const file = process.argv[2];
const wasi = new WASI({ version: 'preview1', args: ['omp-web-wasm'], env: {} });
const compiled = await WebAssembly.compile(readFileSync(file));
const instance = await WebAssembly.instantiate(compiled, wasi.getImportObject());
wasi.initialize(instance);
const ex = instance.exports;
for (const name of ['memory', 'omp_alloc', 'omp_free', 'omp_call', 'omp_result_ptr', 'omp_version']) {
  if (!(name in ex)) throw new Error(`missing export ${name}`);
}
if (ex.omp_version() !== 1) throw new Error('unexpected protocol version');

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const ctx = { now: '2026-11-02T04:30:00Z', timeZone: 'Asia/Kolkata', locale: 'en-IN' };

function call(op, args = {}) {
  const bytes = encoder.encode(JSON.stringify({ op, args, ctx }));
  const ptr = ex.omp_alloc(bytes.length);
  new Uint8Array(ex.memory.buffer, ptr, bytes.length).set(bytes);
  const length = ex.omp_call(ptr, bytes.length);
  ex.omp_free(ptr);
  if (length < 0) throw new Error('omp_call rejected the buffer');
  const text = decoder.decode(new Uint8Array(ex.memory.buffer, ex.omp_result_ptr(), length));
  return JSON.parse(text);
}

function expect(condition, message, detail) {
  if (!condition) {
    console.error(`SMOKE-FAIL ${message} ${detail === undefined ? '' : JSON.stringify(detail).slice(0, 400)}`);
    process.exit(1);
  }
}

let r = call('meta.version');
expect(r.ok && r.result.protocolVersion === 1, 'meta.version', r);
r = call('household.create', { adults: 2, children: 1 });
expect(r.ok && r.result.gate.status === 'refused', 'household.create', r);
r = call('plan.generate');
expect(!r.ok && r.error.code === 'gate_refused', 'gate must refuse planning', r);
r = call('safety.confirmNobody', { pendingItemCount: 0 });
expect(r.ok && r.result.gate.status === 'open', 'confirmNobody', r);
r = call('plan.generate');
expect(r.ok && r.result.plan.status === 'draft', 'plan.generate', r);
const planId = r.result.plan.id;
r = call('plan.approve', { planId, shownContentHash: '0000', gesture: 'confirm-button' });
expect(!r.ok && r.error.code === 'stale_preview', 'stale hash must be refused', r);
r = call('plan.approvalPreview', { planId });
expect(r.ok && r.result.canApprove === true, 'preview', r);
const hash = r.result.plan.contentHash;
r = call('plan.approve', { planId, shownContentHash: hash, gesture: 'voice' });
expect(!r.ok && r.error.code === 'approval_gesture_required', 'wrong gesture must be refused', r);
r = call('plan.approve', { planId, shownContentHash: hash, gesture: 'confirm-button' });
expect(r.ok && r.result.approved.plan.status === 'approved', 'approve', r);
r = call('state.export');
expect(r.ok && r.result.snapshot.version === 1, 'state.export', r);
const snapshot = r.result.snapshot;
r = call('state.import', { snapshot });
expect(r.ok && r.result.imported === true, 'state.import', r);
r = call('nope');
expect(!r.ok && r.error.code === 'unknown_op', 'unknown op', r);
console.log('SMOKE-OK');
