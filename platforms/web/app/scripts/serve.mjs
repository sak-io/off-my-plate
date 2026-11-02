// Static test/dev server for dist/. Sends the CSP as a header too, and gzips the Wasm when the client accepts it
// (like a real static host), so the browser test measures realistic transfer size. Usage: node serve.mjs [port]
import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { dirname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createGzip } from 'node:zlib';

const dist = join(dirname(fileURLToPath(import.meta.url)), '..', 'dist');
const port = Number(process.argv[2] ?? 4173);
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json', '.wasm': 'application/wasm' };
const CSP = "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self'; img-src 'self'; manifest-src 'self'; worker-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'";

createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  let rel = normalize(decodeURIComponent(url.pathname)).replace(/^([/\\])+/, '');
  if (rel === '' ) rel = 'index.html';
  const file = join(dist, rel);
  if (rel.startsWith('..') || !existsSync(file) || !statSync(file).isFile()) { res.writeHead(404); res.end('not found'); return; }
  const ext = rel.slice(rel.lastIndexOf('.'));
  const headers = { 'content-type': types[ext] ?? 'application/octet-stream', 'cache-control': 'no-cache', 'x-content-type-options': 'nosniff' };
  if (ext === '.html') headers['content-security-policy'] = CSP;
  if (ext === '.wasm' && /\bgzip\b/.test(req.headers['accept-encoding'] ?? '')) {
    res.writeHead(200, { ...headers, 'content-encoding': 'gzip', vary: 'accept-encoding' });
    createReadStream(file).pipe(createGzip({ level: 6 })).pipe(res);
  } else {
    res.writeHead(200, { ...headers, 'content-length': statSync(file).size });
    createReadStream(file).pipe(res);
  }
}).listen(port, '127.0.0.1', () => console.log(`serving ${dist} on ${port}`));
