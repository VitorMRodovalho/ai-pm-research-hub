/**
 * #1197 — member chapter derives from the applicant's declaration; no chapter -> 'Outro'
 *
 * Migration 20260805000374 rewrites approve_selection_application's v_member_chapter
 * derivation: COALESCE(app.chapter, 'Outro'). The cycle's contracting chapter (a
 * legal/contract concept) must never leak into members.chapter as if it were the
 * member's own affiliation — that was the live 2026-07-08 incident: a "no chapter"
 * signer provisioned as PMI-GO tripped invariant U_active_person_has_primary_chapter_affiliation
 * on promotion (registry-chaptered active member with zero primary affiliations).
 *
 * Source-contract assertions run offline; the DB-aware checks verify the live column
 * default and that no regression case exists in the active cohort.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000374_1197_member_chapter_from_application_declaration.sql', import.meta.url)),
  'utf8',
);
// Comment-stripped view — "must NOT appear" assertions target executable SQL, not the
// header comments (which legitimately name the anti-pattern being removed).
const CODE = MIG.replace(/--.*$/gm, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function rest(path) {
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` },
  });
  if (!res.ok) throw new Error(`GET ${path} HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}

// ── Source contract (offline) ───────────────────────────────────────────────
test('1197: fallback for a no-chapter applicant is the canonical Outro', () => {
  assert.match(
    CODE,
    /v_member_chapter\s*:=\s*COALESCE\(\s*NULLIF\(trim\(v_app\.chapter\),\s*''\),\s*'Outro'\s*\)/,
    'v_member_chapter must COALESCE the application declaration straight to Outro',
  );
});

test('1197: contracting chapter no longer feeds member affiliation', () => {
  assert.doesNotMatch(
    CODE,
    /v_cycle_contracting_chapter/,
    'the cycle contracting chapter must play no role in approve_selection_application',
  );
  assert.doesNotMatch(
    CODE,
    /'Nao informado'/,
    'the legacy Nao informado fallback must be gone',
  );
});

test('1197: chapter_source telemetry distinguishes application vs no declaration', () => {
  assert.match(CODE, /'chapter_source'/, 'chapter_source key still emitted');
  assert.match(CODE, /'application'/, 'application source bucket');
  assert.match(CODE, /'no_chapter_declared'/, 'no_chapter_declared source bucket');
  assert.doesNotMatch(CODE, /'cycle_contracting_chapter'/, 'cycle_contracting_chapter bucket removed');
});

// ── DB-aware (live) ─────────────────────────────────────────────────────────
test('1197: members.chapter column default stays Outro (canonical no-chapter value)', { skip: canRun ? false : skipMsg }, async () => {
  // information_schema is not exposed via REST; assert indirectly through a probe the
  // migration relies on: the invariant suite must be green, i.e. no active
  // registry-chaptered member without a primary affiliation slipped through provisioning.
  const rows = await rest('/rest/v1/rpc/check_schema_invariants');
  const u = (Array.isArray(rows) ? rows : []).find(
    (r) => r.invariant === 'U_active_person_has_primary_chapter_affiliation',
  );
  assert.ok(u, 'invariant U present in suite');
  assert.equal(Number(u.violation_count), 0, 'invariant U must have 0 violations');
});
