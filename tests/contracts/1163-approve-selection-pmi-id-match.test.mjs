/**
 * Contract: #1163 — approve_selection_application must match member/person by pmi_id first.
 *
 * Migration: supabase/migrations/20260805000427_1163_approve_selection_pmi_id_match.sql
 *
 * ROOT CAUSE: the member lookup matched ONLY by lower(email). When an applicant's PMI-registered
 * application email diverges from their platform member email (same pmi_id), the lookup returned
 * NULL and the function fell into the INSERT path, which collided on members_pmi_id_key
 * (UNIQUE pmi_id) -> 23505 -> PostgREST 409. Reproduced with Paulo Alves de Oliveira Junior
 * (member paulo-junior@outlook.com, app pejota81@gmail.com, shared pmi_id 1158211).
 *
 * SECONDARY: the promotion CASE omitted 'researcher', so an already-active researcher approved on
 * the leader track was never elevated to tribe_leader. Fix adds researcher -> tribe_leader only
 * (never a demotion).
 *
 * Invariants:
 *  Static (always run — reads migration SQL):
 *   - Member lookup prefers pmi_id (NULLIF/trim guard + ORDER BY CASE), email preserved as fallback.
 *   - Person lookup ALSO pmi_id-first (avoids forking identity into a duplicate person).
 *   - Promotion CASE elevates researcher -> tribe_leader, scoped so it is never a demotion.
 *  DB-gated (non-destructive, read-only — the approval RPC mutates so it is not exercised here):
 *   - No two members share a pmi_id (the constraint the 409 was hitting).
 *   - The divergent-email repro cohort (app.pmi_id matches a member whose email differs) each
 *     resolves to exactly ONE member by pmi_id — i.e. re-approval would UPDATE, not duplicate.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000427_1163_approve_selection_pmi_id_match.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// The function body between BEGIN and END (excludes the file's leading doc comment).
function fnBody() {
  const start = mig.indexOf('CREATE OR REPLACE FUNCTION public.approve_selection_application');
  assert.ok(start >= 0, 'migration must (re)define approve_selection_application');
  return mig.slice(start);
}

// ── Static ──
test('#1163: migration file present + redefines the canonical approval RPC', () => {
  assert.ok(existsSync(MIG), 'migration file present');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.approve_selection_application\(p_application_id uuid, p_decision jsonb/);
  assert.match(mig, /SECURITY DEFINER/);
  assert.match(mig, /SET search_path TO 'public', 'pg_temp'/);
});

test('#1163: member lookup matches pmi_id first with email fallback (no 409 on email drift)', () => {
  const body = fnBody();
  // the pmi_id-first predicate: a non-empty app pmi_id matched against members.pmi_id
  assert.match(body,
    /WHERE \(NULLIF\(trim\(v_app\.pmi_id\), ''\) IS NOT NULL AND pmi_id = NULLIF\(trim\(v_app\.pmi_id\), ''\)\)\s*\n\s*OR lower\(email\) = lower\(v_app\.email\)/,
    'member SELECT must match pmi_id first, email as fallback');
  // pmi_id match must be PREFERRED when both branches could hit
  assert.match(body,
    /ORDER BY CASE\s*\n\s*WHEN NULLIF\(trim\(v_app\.pmi_id\), ''\) IS NOT NULL AND pmi_id = NULLIF\(trim\(v_app\.pmi_id\), ''\) THEN 0/,
    'must ORDER BY a CASE that ranks the pmi_id match ahead of the email match');
  // regression guard: the case-insensitive email lookup must still exist (fallback preserved)
  assert.match(body, /lower\(email\)\s*=\s*lower\(v_app\.email\)/,
    'email fallback (case-insensitive) must be preserved');
});

test('#1163: person lookup is ALSO pmi_id-first (does not fork identity into a duplicate person)', () => {
  const body = fnBody();
  // the same pmi_id-first predicate must appear for BOTH the members and persons SELECTs
  const matches = body.match(/WHERE \(NULLIF\(trim\(v_app\.pmi_id\), ''\) IS NOT NULL AND pmi_id = NULLIF\(trim\(v_app\.pmi_id\), ''\)\)/g) || [];
  assert.ok(matches.length >= 2,
    `pmi_id-first predicate must appear for both member and person lookups (found ${matches.length})`);
  // and it must sit inside a persons SELECT
  assert.match(body,
    /FROM public\.persons\s*\n\s*WHERE \(NULLIF\(trim\(v_app\.pmi_id\), ''\) IS NOT NULL AND pmi_id = NULLIF\(trim\(v_app\.pmi_id\), ''\)\)/,
    'the persons lookup must use the pmi_id-first predicate');
});

test('#1163: promotion elevates researcher -> tribe_leader, scoped so it is never a demotion', () => {
  const body = fnBody();
  // the added elevation clause, AND-scoped to the leader target (not a blanket promotion)
  assert.match(body,
    /\(v_member_role = 'researcher' AND v_target_role = 'tribe_leader'\)/,
    'must add researcher -> tribe_leader elevation, scoped to the tribe_leader target');
  // the entry-level promotable set must remain (observer/guest/none/alumni/inactive)
  assert.match(body,
    /v_member_role IN \('observer', 'guest', 'none', 'alumni', 'inactive'\)/,
    'entry-level promotable set must be preserved');
  // promotion still requires an active member (no promoting a terminal-status row)
  assert.match(body, /v_member_status = 'active'/, 'promotion must still require active member');
});

// ── DB-gated (read-only; the RPC mutates so it is not called here) ──
test('#1163 DB: no two members share a pmi_id (the UNIQUE the 409 was hitting)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('members')
    .select('pmi_id')
    .not('pmi_id', 'is', null);
  assert.ok(!error, `must not error: ${error?.message}`);
  const seen = new Map();
  for (const row of data) {
    const k = String(row.pmi_id).trim();
    if (!k) continue;
    seen.set(k, (seen.get(k) || 0) + 1);
  }
  const dups = [...seen.entries()].filter(([, n]) => n > 1);
  assert.equal(dups.length, 0, `no pmi_id may map to >1 member; dups: ${JSON.stringify(dups)}`);
});

test('#1163 DB: divergent-email applications resolve to exactly one member by pmi_id', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // approved/converted apps with a pmi_id
  const { data: apps, error: e1 } = await sb
    .from('selection_applications')
    .select('id, email, pmi_id')
    .in('status', ['approved', 'converted'])
    .not('pmi_id', 'is', null);
  assert.ok(!e1, `apps query must not error: ${e1?.message}`);

  for (const app of apps) {
    const pmi = String(app.pmi_id || '').trim();
    if (!pmi) continue;
    const { data: members, error: e2 } = await sb
      .from('members')
      .select('id, email')
      .eq('pmi_id', pmi);
    assert.ok(!e2, `member lookup must not error: ${e2?.message}`);
    if (!members || members.length === 0) continue; // no member yet -> approval would INSERT (fine)
    // the pmi_id must resolve to a single member -> approval UPDATEs it (no duplicate INSERT / no 409),
    // even when the application email diverges from that member's email (the #1163 repro shape).
    assert.equal(members.length, 1,
      `pmi_id ${pmi} (app ${app.id}) must resolve to exactly one member, found ${members.length}`);
  }
});
