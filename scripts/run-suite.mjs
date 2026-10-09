#!/usr/bin/env node
// Runs one bucket of the test suite with the files DERIVED from disk at run time (09/10/2026, decision of the GP).
//
// Until then each package.json script carried its file list on ONE line, and every lane that added a test edited
// the same line: on 09/10 that conflicted in every parallel PR and caused at least 4 of 14 CI re-runs. The list now
// comes from scripts/classify-test-suite.mjs (`suiteFiles`): every test file on disk lands in a bucket unless it is a
// DECLARED exclusion, and a DB-aware test lands in the behavioural bucket because the classifier reads its content.
//
// Same commands and concurrency as the lists they replace:
//   structural  -> node --experimental-strip-types --test --test-concurrency=4 <files>          (hermetic, parallel)
//   behavioural -> node scripts/with-db-lease.mjs -- node --experimental-strip-types --test --test-concurrency=1 <files>
//                  (#1261 serial on the shared DB; #1961 lease)
//   contracts   -> node --test --test-concurrency=1 <tests/contracts files>
// Extra arguments after the bucket are passed to node --test (e.g. --test-name-pattern).
//
// Usage: node scripts/run-suite.mjs <structural|behavioural|contracts> [extra node --test args]
import { spawn } from 'node:child_process';
import { suiteFiles } from './classify-test-suite.mjs';

export const COMMANDS = {
  structural: ['node', '--experimental-strip-types', '--test', '--test-concurrency=4'],
  behavioural: ['node', 'scripts/with-db-lease.mjs', '--', 'node', '--experimental-strip-types', '--test', '--test-concurrency=1'],
  contracts: ['node', '--test', '--test-concurrency=1'],
};

if (import.meta.url === `file://${process.argv[1]}`) {
  const [bucket, ...extra] = process.argv.slice(2);
  if (!COMMANDS[bucket]) {
    console.error(`uso: node scripts/run-suite.mjs <${Object.keys(COMMANDS).join('|')}> [args]`);
    process.exit(2);
  }
  const files = suiteFiles(bucket);
  if (files.length === 0) {
    // A bucket with zero files would pass silently; that is never the intended state.
    console.error(`run-suite: o balde ${bucket} saiu VAZIO; recusando rodar verde sem testes`);
    process.exit(2);
  }
  console.error(`run-suite: ${bucket} = ${files.length} arquivo(s), derivados do disco`);
  const [cmd, ...args] = COMMANDS[bucket];
  const child = spawn(cmd, [...args, ...extra, ...files], { stdio: 'inherit' });
  child.on('exit', (code, signal) => process.exit(signal ? 1 : (code ?? 1)));
}
