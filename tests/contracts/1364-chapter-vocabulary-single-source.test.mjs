/**
 * #1364 — Single chapter-code vocabulary + /admin/members ↔ /admin/filiacao reconciliation.
 *
 * Grounded finding (live 2026-07-13): the reported "PMI-RS shows 16 on /members but 3 on /filiacao"
 * is NOT a vocabulary drift. Every surface uses the SAME bare 2-letter code
 * (chapter_registry.chapter_code / members.entry_chapter_code / member_chapter_affiliations.chapter_code
 * are all 'RS', never 'BR-RS'). The divergence is two DIFFERENT populations, both correct:
 *   * /admin/members  = full active roster, keyed by members.chapter ('PMI-RS').
 *   * /admin/filiacao = a verification QUEUE (a strict subset — pre-onboarding OR unverified).
 *
 * This guard locks BOTH facts so the confusion cannot silently recur:
 *   (1) the single bare-code vocabulary — no 'BR-XX' code ever appears, and every entry/affiliation
 *       code resolves to a chapter_registry entry (so a future stray 'BR-RS' fails CI);
 *   (2) members.chapter is the strict 'PMI-'||entry_chapter_code derivation (the roster axis);
 *   (3) the reconciliation RPC get_affiliation_chapter_rollup() exists, is gated, and its migration
 *       captures the CREATE FUNCTION block; the FE surfaces it on the chapter filter.
 *
 * Data-driven, no absolute-count coupling (memory reference-roster-tests-data-driven-single-source).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const read = (p) => readFileSync(join(REPO_ROOT, p), 'utf8');

const MIGRATION = 'supabase/migrations/20260805000436_1364_affiliation_chapter_rollup.sql';
const MIGRATION_SCOPE = 'supabase/migrations/20260805000437_1364b_affiliation_queue_scope_all.sql';
const ISLAND = 'src/components/admin/AffiliationQueueIsland.tsx';

// ---------- static (offline) ----------

test('rollup RPC migration creates a gated, aggregate SECURITY DEFINER function', () => {
  const src = read(MIGRATION);
  assert.match(src, /CREATE OR REPLACE FUNCTION public\.get_affiliation_chapter_rollup\(\)/,
    'migration must create get_affiliation_chapter_rollup');
  assert.match(src, /SECURITY DEFINER/, 'must be SECURITY DEFINER');
  assert.match(src, /SET search_path TO 'public', 'pg_temp'/, 'must pin search_path');
  // same audience gate as the queue: filiacao_director OR manage_member
  assert.match(src, /filiacao_director/, 'must gate on filiacao_director designation');
  assert.match(src, /can_by_member\(v_caller_id, 'manage_member'\)/, 'must gate on manage_member authority');
  // grants: revoked from anon, granted to authenticated (mirrors the queue RPC)
  assert.match(src, /REVOKE ALL ON FUNCTION public\.get_affiliation_chapter_rollup\(\) FROM public, anon;/,
    'must revoke from public, anon');
  assert.match(src, /GRANT EXECUTE ON FUNCTION public\.get_affiliation_chapter_rollup\(\) TO authenticated, service_role;/,
    'must grant to authenticated, service_role');
  assert.match(src, /NOTIFY pgrst, 'reload schema';/, 'must reload PostgREST schema');
  // aggregate-only: no per-member PII logging call (unlike the queue RPC). Match a CALL, not a mention.
  assert.doesNotMatch(src, /PERFORM\s+public\.log_pii_access/, 'rollup is aggregate-only — must not log PII access');
  // in_queue predicate must mirror the queue cohort, not invent a new one
  assert.match(src, /member_is_pre_onboarding/, 'in_queue must reuse the canonical pre-onboarding helper');
});

test('FE surfaces the reconciliation on the chapter filter', () => {
  const src = read(ISLAND);
  assert.match(src, /get_affiliation_chapter_rollup/, 'island must call the rollup RPC');
  assert.match(src, /comp\.affiliationQueue\.chapterReconcile/, 'island must render the reconciliation key');
  assert.match(src, /chapterFilter !== 'all'/, 'banner must be scoped to an active chapter filter');
});

test('i18n: chapterReconcile exists in all three dictionaries', () => {
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const src = read(`src/i18n/${dict}.ts`);
    assert.match(src, /'comp\.affiliationQueue\.chapterReconcile':/,
      `${dict} must define comp.affiliationQueue.chapterReconcile`);
  }
});

// ---------- #1364b — "Todos" tab (full active roster) ----------

test('scope migration adds p_scope via DROP+CREATE without losing the queue shape', () => {
  const src = read(MIGRATION_SCOPE);
  // arg count changed -> must DROP then re-CREATE (GC-097), not a bare CREATE OR REPLACE of the 0-arg
  assert.match(src, /DROP FUNCTION IF EXISTS public\.get_affiliation_verification_queue\(\);/,
    'must DROP the 0-arg function before recreating with the new signature');
  assert.match(src, /CREATE OR REPLACE FUNCTION public\.get_affiliation_verification_queue\(p_scope text DEFAULT 'queue'\)/,
    'must recreate with p_scope defaulting to queue (back-compatible)');
  // p_scope='all' relaxes the cohort; the rich per-row shape is preserved (single source, not duplicated)
  assert.match(src, /p_scope = 'all'/, "p_scope='all' must relax the cohort WHERE");
  assert.match(src, /chapter_affiliations/, 'the SSOT chapter read-through shape must be preserved');
  assert.match(src, /PERFORM public\.log_pii_access_batch/, 'nominal PII read logging must be preserved');
  // grants re-applied on the NEW (text) signature
  assert.match(src, /REVOKE ALL ON FUNCTION public\.get_affiliation_verification_queue\(text\) FROM public, anon;/,
    'must revoke the new (text) signature from public, anon');
  assert.match(src, /GRANT EXECUTE ON FUNCTION public\.get_affiliation_verification_queue\(text\) TO authenticated, service_role;/,
    'must grant the new (text) signature to authenticated, service_role');
});

test('FE has a third "Todos" tab that loads the full roster via p_scope=all', () => {
  const src = read(ISLAND);
  assert.match(src, /'pre' \| 'queue' \| 'all'/, 'tab state must be the three scopes');
  assert.match(src, /p_scope: 'all'/, 'the Todos tab must request the full-roster scope');
  assert.match(src, /comp\.affiliationQueue\.tabEveryone/, 'must render the "Todos" tab label');
});

test('i18n: tabEveryone + loadingAll exist in all three dictionaries', () => {
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const src = read(`src/i18n/${dict}.ts`);
    assert.match(src, /'comp\.affiliationQueue\.tabEveryone':/, `${dict} must define tabEveryone`);
    assert.match(src, /'comp\.affiliationQueue\.loadingAll':/, `${dict} must define loadingAll`);
  }
});

// ---------- DB-aware (skipped without creds) ----------

async function rest(path) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const res = await fetch(`${url}/rest/v1/${path}`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` },
  });
  if (!res.ok) assert.fail(`REST ${path} failed: ${res.status} ${await res.text()}`);
  return res.json();
}

const needCreds = (t) =>
  (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY)
    ? (t.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set'), true)
    : false;

test('DB: no BR- prefixed chapter code exists on any surface (single bare-code vocabulary)', async (t) => {
  if (needCreds(t)) return;
  const entry = await rest('members?select=id&entry_chapter_code=like.BR-*');
  assert.equal(entry.length, 0, 'members.entry_chapter_code must never carry a BR- prefixed code');
  const mca = await rest('member_chapter_affiliations?select=id&chapter_code=like.BR-*');
  assert.equal(mca.length, 0, 'member_chapter_affiliations.chapter_code must never carry a BR- prefix');
  const reg = await rest('chapter_registry?select=chapter_code&chapter_code=like.BR-*');
  assert.equal(reg.length, 0, 'chapter_registry.chapter_code must never carry a BR- prefix');
});

test('DB: every entry / affiliation code resolves to a chapter_registry entry (vocabulary parity)', async (t) => {
  if (needCreds(t)) return;
  const reg = new Set((await rest('chapter_registry?select=chapter_code')).map((r) => r.chapter_code));
  assert.ok(reg.size >= 10, 'registry should be populated');

  const entries = await rest('members?select=entry_chapter_code&entry_chapter_code=not.is.null');
  for (const code of new Set(entries.map((r) => r.entry_chapter_code))) {
    assert.ok(reg.has(code), `entry_chapter_code '${code}' must exist in chapter_registry`);
  }
  const affs = await rest('member_chapter_affiliations?select=chapter_code');
  for (const code of new Set(affs.map((r) => r.chapter_code))) {
    assert.ok(reg.has(code), `member_chapter_affiliations.chapter_code '${code}' must exist in chapter_registry`);
  }
});

test('DB: members.chapter is the strict PMI-||entry_chapter_code derivation (roster axis)', async (t) => {
  if (needCreds(t)) return;
  const rows = await rest('members?select=chapter,entry_chapter_code&entry_chapter_code=not.is.null');
  assert.ok(rows.length >= 1, 'expected members with a resolved entry chapter');
  for (const r of rows) {
    assert.equal(r.chapter, `PMI-${r.entry_chapter_code}`,
      `member with entry '${r.entry_chapter_code}' must have chapter 'PMI-${r.entry_chapter_code}', got '${r.chapter}'`);
  }
});
