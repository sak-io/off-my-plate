// Build: tsc (page + service worker), copy static files, copy the Wasm module, stamp the service worker
// with the precache list and a content version. Usage: OMP_WASM=/path/omp-web-wasm.wasm node scripts/build.mjs
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const tsc = join(root, 'node_modules', '.bin', 'tsc');
rmSync(dist, { recursive: true, force: true });
execFileSync(tsc, ['-p', 'tsconfig.json'], { cwd: root, stdio: 'inherit' });
execFileSync(tsc, ['-p', 'tsconfig.sw.json'], { cwd: root, stdio: 'inherit' });
for (const f of ['index.html', 'styles.css', 'manifest.webmanifest', 'icon.svg']) cpSync(join(root, 'src', f), join(dist, f));

const wasm = process.env.OMP_WASM;
if (!wasm || !existsSync(wasm)) throw new Error('set OMP_WASM to the built omp-web-wasm.wasm');
cpSync(wasm, join(dist, 'omp-web-wasm.wasm'));

const files = readdirSync(dist).filter((f) => statSync(join(dist, f)).isFile() && f !== 'sw.js');
const hash = createHash('sha256');
for (const f of files.sort()) { hash.update(f); hash.update(readFileSync(join(dist, f))); }
const version = hash.digest('hex').slice(0, 12);
const precache = ['index.html', ...files.filter((f) => f !== 'index.html')];
let sw = readFileSync(join(dist, 'sw.js'), 'utf8');
sw = sw.replace('__VERSION__', version).replace('__PRECACHE__', JSON.stringify(precache));
if (sw.includes('__PRECACHE__') || sw.includes('__VERSION__')) throw new Error('sw placeholders not replaced');
writeFileSync(join(dist, 'sw.js'), sw);
console.log(`built dist (${version}): ${precache.join(', ')}`);
