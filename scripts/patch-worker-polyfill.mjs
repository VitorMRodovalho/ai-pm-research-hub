#!/usr/bin/env node
/**
 * Post-build patch: injects a MessageChannel polyfill into Worker chunks
 * that reference it. Cloudflare Pages' publish validation evaluates ES
 * module top-level code in an environment where MessageChannel is
 * unavailable. React 19's browser build of react-dom/server calls
 * new MessageChannel() during module init.
 *
 * Because ES modules evaluate imports before the importing module's
 * own top-level code, the polyfill must live inside each chunk that
 * references MessageChannel — not just in the entry index.js.
 */
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const workerDir = resolve(__dirname, '..', 'dist', '_worker.js');
const chunksDir = join(workerDir, 'chunks');
const entryFile = join(workerDir, 'index.js');

const POLYFILL = 'if(typeof globalThis.MessageChannel==="undefined"){globalThis.MessageChannel=class{constructor(){let a=null,b=null;this.port1={set onmessage(f){a=f},get onmessage(){return a},postMessage(d){if(b)setTimeout(()=>b({data:d}),0)},close(){}};this.port2={set onmessage(f){b=f},get onmessage(){return b},postMessage(d){if(a)setTimeout(()=>a({data:d}),0)},close(){}}}}}\n';

const MARKER = 'if(typeof globalThis.MessageChannel';

let patched = 0;

function patchFile(filePath) {
  const code = readFileSync(filePath, 'utf8');
  if (code.startsWith(MARKER)) return;
  if (!code.includes('MessageChannel')) return;
  writeFileSync(filePath, POLYFILL + code);
  patched++;
  console.log(`[patch-worker] polyfill → ${filePath.replace(workerDir + '/', '')}`);
}

if (existsSync(entryFile)) {
  patchFile(entryFile);
}

if (existsSync(chunksDir)) {
  for (const name of readdirSync(chunksDir)) {
    if (name.endsWith('.mjs') || name.endsWith('.js')) {
      patchFile(join(chunksDir, name));
    }
  }
}

if (patched === 0) {
  console.log('[patch-worker] No files needed patching.');
} else {
  console.log(`[patch-worker] Done — ${patched} file(s) patched.`);
}
