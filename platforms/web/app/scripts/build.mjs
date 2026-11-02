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

// W06: recipe titles, minutes, ingredients and steps for the plan screens, generated from the same seed files the
// Wasm core embeds (the page may not fetch, so this is a plain ES module under script-src 'self').
const seedDir = join(root, '..', '..', '..', 'core', 'Sources', 'OMPRecipes', 'Resources', 'seed');
const seedRecipes = JSON.parse(readFileSync(join(seedDir, 'recipes.json'), 'utf8')).recipes;
const seedIngredients = JSON.parse(readFileSync(join(seedDir, 'ingredients.json'), 'utf8')).ingredients;
const recipes = Object.fromEntries(seedRecipes.map((r) => [r.id, {
  title: r.title, servings: r.servings, minutes: r.prepMinutes + r.cookMinutes,
  ingredients: r.ingredients.map((i) => [i.ingredientId, i.quantity, i.unit]), steps: r.steps ?? [],
}]));
const ingredients = Object.fromEntries(seedIngredients.map((i) => [i.id, i.name]));
writeFileSync(join(dist, 'recipes-data.js'), `export const RECIPES = ${JSON.stringify(recipes)};\nexport const INGREDIENT_NAMES = ${JSON.stringify(ingredients)};\n`);

// Every file under dist/ (screens/ is a subfolder), as posix paths, except the service worker itself.
const walk = (dir, prefix = '') => readdirSync(dir).flatMap((name) => {
  const full = join(dir, name);
  return statSync(full).isDirectory() ? walk(full, `${prefix}${name}/`) : [`${prefix}${name}`];
});
const files = walk(dist).filter((f) => f !== 'sw.js');
const hash = createHash('sha256');
for (const f of files.sort()) { hash.update(f); hash.update(readFileSync(join(dist, f))); }
const version = hash.digest('hex').slice(0, 12);
const precache = ['index.html', ...files.filter((f) => f !== 'index.html')];
let sw = readFileSync(join(dist, 'sw.js'), 'utf8');
sw = sw.replace('__VERSION__', version).replace('__PRECACHE__', JSON.stringify(precache));
if (sw.includes('__PRECACHE__') || sw.includes('__VERSION__')) throw new Error('sw placeholders not replaced');
writeFileSync(join(dist, 'sw.js'), sw);
console.log(`built dist (${version}): ${precache.join(', ')}`);
