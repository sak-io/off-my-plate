// Prints the size of every section of a .wasm file (informational: where do the megabytes go?).
import { readFileSync } from 'node:fs';
const bytes = readFileSync(process.argv[2]);
let pos = 8;
function leb() { let r = 0, s = 0, b; do { b = bytes[pos++]; r += (b & 0x7f) * 2 ** s; s += 7; } while (b & 0x80); return r; }
const names = ['custom', 'type', 'import', 'function', 'table', 'memory', 'global', 'export', 'start', 'element', 'code', 'data', 'datacount'];
const out = [];
while (pos < bytes.length) {
  const id = bytes[pos++]; const size = leb(); let label = names[id] ?? `id${id}`;
  if (id === 0) { const save = pos; const n = leb(); label = 'custom:' + Buffer.from(bytes.subarray(pos, pos + n)).toString(); pos = save; }
  out.push(`${label}=${size}`); pos += size;
}
console.log(out.join(' '));
