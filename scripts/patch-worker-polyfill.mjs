#!/usr/bin/env node
/**
 * Post-build patch: injects a MessageChannel polyfill into the Worker
 * entry point. Cloudflare Workers' publish validation runs top-level
 * module code in an environment where MessageChannel may not be
 * available (even with nodejs_compat). React 19's browser build of
 * react-dom/server requires it for scheduling.
 *
 * The polyfill uses setTimeout as the scheduling mechanism, which is
 * always available in Workers.
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const workerEntry = resolve(__dirname, '..', 'dist', '_worker.js', 'index.js');

if (!existsSync(workerEntry)) {
  console.warn('[patch-worker] _worker.js/index.js not found — skipping polyfill.');
  process.exit(0);
}

const POLYFILL = [
  'if(typeof globalThis.MessageChannel==="undefined"){',
  'globalThis.MessageChannel=class{constructor(){',
  'let a=null,b=null;',
  'this.port1={set onmessage(f){a=f},get onmessage(){return a},postMessage(d){if(b)setTimeout(()=>b({data:d}),0)},close(){}};',
  'this.port2={set onmessage(f){b=f},get onmessage(){return b},postMessage(d){if(a)setTimeout(()=>a({data:d}),0)},close(){}};',
  '}}}\n',
].join('');

const original = readFileSync(workerEntry, 'utf8');

if (original.startsWith('if(typeof globalThis.MessageChannel')) {
  console.log('[patch-worker] Polyfill already present — skipping.');
  process.exit(0);
}

writeFileSync(workerEntry, POLYFILL + original);
console.log('[patch-worker] MessageChannel polyfill injected into _worker.js/index.js');
