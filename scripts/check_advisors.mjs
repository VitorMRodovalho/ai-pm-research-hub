#!/usr/bin/env node
/**
 * Supabase Advisor drift check (preventive)
 *
 * Calls the Supabase management API for `/projects/{ref}/advisors?type=security`
 * and diffs results against `scripts/advisor_baseline.json`. Exits non-zero if
 * any ERROR-level finding is NOT in the baseline allowlist — meaning a new
 * security issue was introduced since baseline snapshot.
 *
 * Requires env vars:
 *   SUPABASE_PROJECT_REF        — e.g. ldrfrvwhxsmgaabwmaik
 *   SUPABASE_ACCESS_TOKEN       — personal access token from Supabase dashboard
 *                                 (NOT service_role — that's a different key)
 *
 * Skips gracefully if token absent (CI friendly; local runs can omit).
 *
 * To regenerate baseline after an intentional accepted change:
 *   1. Run with --emit-current > /tmp/current.json
 *   2. Review new entries, add rationale in scripts/advisor_baseline.json
 *   3. Re-run to confirm 0 unexpected findings
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const BASELINE_PATH = resolve(__dirname, 'advisor_baseline.json');

const PROJECT_REF = process.env.SUPABASE_PROJECT_REF || 'ldrfrvwhxsmgaabwmaik';
const TOKEN = process.env.SUPABASE_ACCESS_TOKEN;

const args = new Set(process.argv.slice(2));
const EMIT_CURRENT = args.has('--emit-current');

if (!TOKEN) {
  console.warn('::warning::SUPABASE_ACCESS_TOKEN not set — advisor check skipped.');
  console.warn('To enable: create a personal access token at https://supabase.com/dashboard/account/tokens');
  console.warn('and store as SUPABASE_ACCESS_TOKEN secret in GitHub Actions.');
  process.exit(0);
}

async function fetchAdvisors(type) {
  const url = `https://api.supabase.com/v1/projects/${PROJECT_REF}/advisors?type=${type}`;
  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      Accept: 'application/json',
    },
  });
  if (!res.ok) {
    throw new Error(`Supabase API ${res.status}: ${await res.text()}`);
  }
  const body = await res.json();
  return body.lints || [];
}

function loadBaseline() {
  const raw = readFileSync(BASELINE_PATH, 'utf8');
  const json = JSON.parse(raw);
  const accepted = new Set();
  for (const e of json.security?.accepted_errors || []) accepted.add(e.cache_key);
  for (const w of json.security?.accepted_warnings || []) accepted.add(w.cache_key);
  return accepted;
}

async function main() {
  const lints = await fetchAdvisors('security');

  if (EMIT_CURRENT) {
    console.log(JSON.stringify(lints, null, 2));
    return;
  }

  const accepted = loadBaseline();
  const unexpectedErrors = [];
  const unexpectedWarnings = [];

  for (const lint of lints) {
    if (accepted.has(lint.cache_key)) continue;
    if (lint.level === 'ERROR') unexpectedErrors.push(lint);
    else if (lint.level === 'WARN') unexpectedWarnings.push(lint);
  }

  const emoji = (n) => (n === 0 ? '✅' : '❌');
  console.log(`${emoji(unexpectedErrors.length)} Unexpected ERROR advisors: ${unexpectedErrors.length}`);
  console.log(`${emoji(unexpectedWarnings.length)} Unexpected WARN advisors:  ${unexpectedWarnings.length}`);
  console.log(`   Total lints: ${lints.length} | Baseline allowlist: ${accepted.size}`);

  if (unexpectedErrors.length > 0) {
    console.error('\nNew ERROR-level advisors not in baseline:');
    for (const lint of unexpectedErrors) {
      console.error(`  - ${lint.cache_key}`);
      console.error(`    ${lint.title}: ${lint.detail}`);
      console.error(`    Remediation: ${lint.remediation}`);
    }
    console.error('\nFix options:');
    console.error('  (a) Fix the underlying issue (preferred).');
    console.error('  (b) If intentional, add the cache_key to scripts/advisor_baseline.json');
    console.error('      under security.accepted_errors with a rationale.');
    process.exit(1);
  }

  if (unexpectedWarnings.length > 0) {
    console.warn('\nNew WARN-level advisors (non-blocking) not in baseline:');
    for (const lint of unexpectedWarnings) {
      console.warn(`  - ${lint.cache_key}: ${lint.detail}`);
    }
  }
}

main().catch((err) => {
  console.error('advisor-check failed:', err.message);
  process.exit(2);
});
