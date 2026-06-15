/**
 * #472 correction #2 — VEP worker must NOT regress an advanced application's
 * status on a same-cycle re-import (B2 root cause) — p472.
 *
 * Root cause: the Cloudflare worker `pmi-vep-sync/src/db.ts`
 * `upsertSelectionApplication()` matches an existing row by COMPOUND KEY
 * (vep_application_id, vep_opportunity_id) and, on the same-cycle update branch,
 * applied `status: payload.status` unconditionally. VEP only knows its own
 * buckets (→ submitted | approved | rejected | cancelled, default 'submitted')
 * and is blind to the platform-internal pipeline (screening … final_eval), so a
 * re-sync knocked every advanced candidate back to 'submitted' — they vanished
 * from the final ranking. Live evidence at fix time: all 37 in-flight apps
 * carried vep_status_raw='Submitted'.
 *
 * Fix (db.ts): `resolveReimportStatus(existing.status, payload.status)` —
 * forward-only + terminal-safe, byte-aligned with the DB heal-cron
 * `recompute_application_status` (migration 20260805000090) so the two never
 * fight (worker clobber → cron heal → worker clobber …).
 *
 * STATIC SOURCE-PARSE test (mirrors worker-mapper-db-update-coverage +
 * p277-444-vep-reconciled-email-preserve): the worker runs on Cloudflare and is
 * not exercised by main CI's runtime, so we lock the regression class at the
 * source level — CI catches a revert (or a worker↔migration ladder drift) before
 * the next deploy. No DB or network calls.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const DB_PATH = join(REPO_ROOT, 'cloudflare-workers/pmi-vep-sync/src/db.ts');
const MIGRATION_PATH = join(
  REPO_ROOT,
  'supabase/migrations/20260805000090_472_selection_status_recompute.sql'
);

const readDb = () => readFileSync(DB_PATH, 'utf8');
const readMigration = () => readFileSync(MIGRATION_PATH, 'utf8');

/** Strip block + line comments (so a comment that *mentions* the old anti-pattern
 *  for documentation doesn't trip the forward-defense regex). */
function stripComments(src) {
  return src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

/** All single-quoted string literals inside a fragment, in source order. */
function quotedStrings(fragment) {
  return [...fragment.matchAll(/'([^']+)'/g)].map((m) => m[1]);
}

/** db.ts `const SELECTION_STATUS_LADDER = [ ... ];` → array of strings. */
function workerLadder(src) {
  const m = src.match(/const\s+SELECTION_STATUS_LADDER\s*=\s*\[([\s\S]*?)\]/);
  assert.ok(m, 'db.ts must declare const SELECTION_STATUS_LADDER = [ ... ]');
  return quotedStrings(m[1]);
}

/** db.ts `const SELECTION_TERMINAL_STATUSES = new Set([ ... ]);` → array. */
function workerTerminals(src) {
  const m = src.match(/const\s+SELECTION_TERMINAL_STATUSES\s*=\s*new Set\(\[([\s\S]*?)\]\)/);
  assert.ok(m, 'db.ts must declare const SELECTION_TERMINAL_STATUSES = new Set([ ... ])');
  return quotedStrings(m[1]);
}

/** Migration `v_ladder text[] := ARRAY[ ... ];` → array of strings. */
function migrationLadder(src) {
  const m = src.match(/v_ladder\s+text\[\]\s*:=\s*ARRAY\[([\s\S]*?)\]/);
  assert.ok(m, 'migration must declare v_ladder text[] := ARRAY[ ... ]');
  return quotedStrings(m[1]);
}

/** Migration terminal-safe `WHERE cur NOT IN ( ... )` → array of strings.
 *  The recompute migration has exactly ONE `cur NOT IN` guard; assert that so a
 *  future second guard (with possibly different membership) fails loudly here
 *  rather than silently comparing against only the first match. */
function migrationTerminals(src) {
  const all = [...src.matchAll(/cur\s+NOT\s+IN\s*\(([\s\S]*?)\)/gi)];
  assert.equal(
    all.length,
    1,
    `expected exactly one \`cur NOT IN\` terminal-safe guard in the migration, found ${all.length}`
  );
  return quotedStrings(all[0][1]);
}

/** The same-cycle full-update `.update({...}).eq('id', existing.id)` SET body. */
function sameCycleUpdateBlock(src) {
  // The same-cycle branch is the .update({...}) that also sets motivation_letter
  // (the cross-cycle branch updates only commonRefresh fields).
  const blocks = [...src.matchAll(/\.update\(\s*\{([\s\S]*?)\}\s*\)\s*\.eq\('id'/g)].map((m) => m[1]);
  const block = blocks.find((b) => /motivation_letter\s*:/.test(b));
  assert.ok(block, 'same-cycle full-update block (with motivation_letter) not found in db.ts');
  return block;
}

/** The existing-row compound-key SELECT column string. */
function existingSelect(src) {
  const m = src.match(
    /\.select\(\s*'([^']*)'\s*\)\s*\.eq\('vep_application_id',\s*payload\.vep_application_id\)/
  );
  assert.ok(m, 'existing-row .select(...).eq(vep_application_id) probe not found in db.ts');
  return m[1];
}

test('#472 — existing-row SELECT loads status (needed for the freeze)', () => {
  const select = existingSelect(readDb());
  assert.ok(/\bstatus\b/.test(select), `existing-row SELECT must include status — got: "${select}"`);
});

test('#472 — same-cycle update uses resolveReimportStatus, NOT bare payload.status', () => {
  const block = sameCycleUpdateBlock(readDb());
  const statusLine = block.split('\n').find((l) => /^\s*status\s*:/.test(l));
  assert.ok(statusLine, 'same-cycle update must still declare a `status:` key (update-coverage test)');
  // #693 — the call now threads a third arg (payload.vep_status_raw) so a HARD
  // terminal VEP decision can override the mid-pipeline freeze. The first two
  // args MUST stay (existing.status, payload.status); the third is required so
  // the terminal-honoring path is wired.
  assert.ok(
    /resolveReimportStatus\(\s*existing\.status\s*,\s*payload\.status\s*,\s*payload\.vep_status_raw\s*\)/.test(statusLine),
    `status must be set via resolveReimportStatus(existing.status, payload.status, payload.vep_status_raw) — got: "${statusLine.trim()}"`
  );
  // Forward defense: the exact pre-fix clobber must not reappear in db.ts CODE
  // (comments documenting the anti-pattern are stripped first).
  assert.ok(
    !/status\s*:\s*payload\.status/.test(stripComments(readDb())),
    'REGRESSION: db.ts reverted to the unconditional `status: payload.status` overwrite (#472 B2)'
  );
});

test('#472 — resolveReimportStatus is exported with forward-only + terminal-safe logic', () => {
  const src = readDb();
  assert.ok(
    /export function resolveReimportStatus\(/.test(src),
    'db.ts must export resolveReimportStatus()'
  );
  // defensive null-guard: a missing/empty existing status falls back to incoming
  // (status is NOT NULL on update, but the guard protects against a future SELECT
  // that omits status — its removal would otherwise go undetected by static parse)
  assert.ok(
    /if \(!existing\) return incoming/.test(src),
    'resolveReimportStatus must keep the defensive `if (!existing) return incoming` guard'
  );
  // terminal-safe: a terminal existing status freezes
  assert.ok(
    /SELECTION_TERMINAL_STATUSES\.has\(existing\)\)\s*return existing/.test(src),
    'resolveReimportStatus must freeze when existing status is terminal (terminal-safe)'
  );
  // forward-only: only advance when incoming ranks strictly ahead
  assert.ok(
    /return inRank > exRank \? incoming : existing/.test(src),
    'resolveReimportStatus must be forward-only (inRank > exRank ? incoming : existing)'
  );
});

test('#472 — worker ladder is byte-aligned with the heal-cron migration v_ladder', () => {
  const w = workerLadder(readDb());
  const m = migrationLadder(readMigration());
  assert.deepEqual(
    w,
    m,
    `worker SELECTION_STATUS_LADDER must equal migration v_ladder (else worker and ` +
      `recompute_application_status disagree on stage order and fight).\n` +
      `worker:    ${JSON.stringify(w)}\nmigration: ${JSON.stringify(m)}`
  );
  // sanity floor
  assert.ok(w.length >= 8, `ladder too short (${w.length}) — regex likely broken`);
});

test('#472 — worker terminal set matches the heal-cron migration terminal-safe list', () => {
  const w = [...workerTerminals(readDb())].sort();
  const m = [...migrationTerminals(readMigration())].sort();
  assert.deepEqual(
    w,
    m,
    `worker SELECTION_TERMINAL_STATUSES must equal migration terminal NOT IN list (else the ` +
      `worker could overwrite a status the cron treats as terminal, or vice-versa).\n` +
      `worker:    ${JSON.stringify(w)}\nmigration: ${JSON.stringify(m)}`
  );
  assert.ok(w.length >= 7, `terminal set too short (${w.length}) — regex likely broken`);
});

// ─────────────────────────────────────────────────────────────────────────────
// #693 defect 1 — HARD terminal VEP status must override the #472 mid-pipeline
// freeze. resolveReimportStatus gained a third arg (vepStatusRaw); a hard
// terminal raw status (OfferNotExtended/Withdrawn/Expired/OfferExpired/Declined/
// Removed) propagates a terminal `incoming` even mid-pipeline, WITHOUT weakening
// the blind-'Submitted' freeze (the #472 core invariant).
// ─────────────────────────────────────────────────────────────────────────────

/** db.ts `const VEP_HARD_TERMINAL_STATUSES = new Set([ ... ]);` → array. */
function workerVepHardTerminals(src) {
  const m = src.match(/const\s+VEP_HARD_TERMINAL_STATUSES\s*=\s*new Set\(\[([\s\S]*?)\]\)/);
  assert.ok(m, 'db.ts must declare const VEP_HARD_TERMINAL_STATUSES = new Set([ ... ])');
  return quotedStrings(m[1]);
}

test('#693 — db.ts declares VEP_HARD_TERMINAL_STATUSES with the VEP terminal decisions', () => {
  const got = [...workerVepHardTerminals(readDb())].sort();
  // lowercase, since the match is case-insensitive (vepStatusRaw.toLowerCase())
  const expected = ['declined', 'expired', 'offerexpired', 'offernotextended', 'removed', 'withdrawn'].sort();
  assert.deepEqual(got, expected, `VEP_HARD_TERMINAL_STATUSES drift — got ${JSON.stringify(got)}`);
});

test('#693 — resolveReimportStatus takes vepStatusRaw and honors hard-terminal mid-pipeline', () => {
  const src = readDb();
  // signature gained the third param
  assert.ok(
    /export function resolveReimportStatus\(\s*existing[^)]*incoming\s*:\s*string\s*,\s*vepStatusRaw\?\s*:\s*string\s*\|\s*null/.test(src),
    'resolveReimportStatus must accept a third `vepStatusRaw?: string | null` parameter'
  );
  // the hard-terminal override branch: guarded by BOTH the raw set AND a terminal incoming
  assert.ok(
    /VEP_HARD_TERMINAL_STATUSES\.has\(vepStatusRaw\.toLowerCase\(\)\)\s*&&\s*\n?\s*SELECTION_TERMINAL_STATUSES\.has\(incoming\)/.test(src),
    'hard-terminal override must require vepStatusRaw ∈ VEP_HARD_TERMINAL_STATUSES AND a terminal incoming'
  );
  // REGRESSION GUARD: the #472 blind-Submitted freeze must still be present —
  // the VEP-soft-exit rule (accept only from 'submitted' intake) is untouched.
  assert.ok(
    /inRank === -1\) return existing === 'submitted' \? incoming : existing/.test(src),
    "resolveReimportStatus must keep the #472 soft-exit freeze (VEP exit only from 'submitted')"
  );
});

test('#693 — heal migration reconcile_vep_terminal_status exists + is symmetric-safe', () => {
  const path = join(REPO_ROOT, 'supabase/migrations/20260805000171_693_reconcile_vep_terminal_status.sql');
  const src = readFileSync(path, 'utf8');
  assert.ok(
    /CREATE OR REPLACE FUNCTION public\.reconcile_vep_terminal_status\(/.test(src),
    'migration must define reconcile_vep_terminal_status'
  );
  // heals only ACTIVE rows — never re-decides a platform-terminal one (mirrors the
  // recompute-cron `cur NOT IN` guard so the two never fight).
  assert.ok(
    /status\s+NOT\s+IN\s*\([\s\S]*?'rejected'[\s\S]*?'withdrawn'[\s\S]*?\)/i.test(src),
    'reconcile must restrict to non-terminal (active) rows via status NOT IN (...terminal...)'
  );
  // matches the same hard-terminal VEP set as the worker
  for (const s of ['offernotextended', 'withdrawn', 'expired', 'offerexpired', 'declined', 'removed']) {
    assert.ok(src.toLowerCase().includes(`'${s}'`), `migration hard-terminal set missing '${s}'`);
  }
  // manage_platform gate + dry-run support
  assert.ok(/can_by_member\(v_caller_id, 'manage_platform'\)/.test(src), 'reconcile must gate on manage_platform');
  assert.ok(/p_dry_run\s+boolean\s+DEFAULT\s+false/.test(src), 'reconcile must support dry-run');
});
