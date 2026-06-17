/**
 * Contract: #766 PR2 — server-side `term_signed` milestone.
 *
 * PR2 of the server-side milestones framework (table member_milestones + record_milestone
 * shipped in PR1, mig 20260805000201). PR2 records a `term_signed` milestone when a member's
 * volunteer_agreement certificate is issued:
 *   - trigger _trg_record_term_signed_milestone (AFTER INSERT ON certificates, WHEN
 *     type=volunteer_agreement AND status=issued) — mirrors the sibling
 *     _trg_complete_volunteer_term_on_cert (mig 20260805000018);
 *   - SILENT backfill (acknowledged_at=now()) of the existing issued signers, run BEFORE
 *     CREATE TRIGGER (race-safe, SPEC §6.3) so they are not re-celebrated;
 *   - invariant AB_term_signed_milestone_has_cert_ancestry — a term_signed milestone must
 *     have a volunteer_agreement cert of ANY status (Wave-3c reject/reissue is valid
 *     ancestry); only a milestone with no cert at all is a violation.
 *
 * Migration: 20260805000202_term_signed_milestone.sql.
 * Cross-ref: docs/specs/SPEC_766_SERVER_SIDE_MILESTONES.md §7 (PR2).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');
const MIG = read('supabase/migrations/20260805000202_term_signed_milestone.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Offline: migration shape ───────────────────────────────────────────────────
test('migration: trigger is AFTER INSERT, gated by type AND status=issued', () => {
  assert.ok(MIG, 'PR2 migration exists');
  assert.match(MIG, /CREATE TRIGGER trg_record_term_signed_milestone\s+AFTER INSERT ON public\.certificates/);
  assert.match(MIG, /WHEN \(NEW\.type = 'volunteer_agreement' AND NEW\.status = 'issued'\)/);
});

test('migration: trigger fn reuses record_milestone (idempotent helper from PR1)', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\._trg_record_term_signed_milestone\(\)/);
  assert.match(MIG, /PERFORM public\.record_milestone\(\s*NEW\.member_id, 'term_signed'/);
  assert.match(MIG, /SET search_path = ''/);
});

test('migration: backfill is silent (acknowledged_at) and runs BEFORE CREATE TRIGGER', () => {
  const backfillIdx = MIG.indexOf("INSERT INTO public.member_milestones");
  const triggerIdx = MIG.indexOf('CREATE TRIGGER trg_record_term_signed_milestone');
  assert.ok(backfillIdx > -1 && triggerIdx > -1, 'both present');
  assert.ok(backfillIdx < triggerIdx, 'backfill must precede CREATE TRIGGER (race-safe, SPEC §6.3)');
  assert.match(MIG, /'term_signed', c\.issued_at, 'certificate', c\.id, now\(\)/); // acknowledged_at=now() -> silent
  assert.match(MIG, /ON CONFLICT \(member_id, milestone_key\) DO NOTHING/);
  // occurred_at is the real signing moment (issued_at), not migration time
  assert.match(MIG, /SELECT DISTINCT ON \(c\.member_id\)/);
});

test('migration: sanity guard asserts every issued-cert member got a milestone', () => {
  assert.match(MIG, /backfill sanity FAIL/);
});

test('migration: invariant AB present with cert-ancestry-of-any-status predicate', () => {
  assert.match(MIG, /AB_term_signed_milestone_has_cert_ancestry/);
  // ancestry = ANY status: the predicate must NOT filter on status='issued'
  const abBlock = MIG.slice(MIG.indexOf('-- AB (#766 PR2)'));
  assert.match(abBlock, /milestone_key = 'term_signed'/);
  assert.match(abBlock, /AND NOT EXISTS/);
  assert.ok(!/c\.status\s*=\s*'issued'/.test(abBlock.slice(0, abBlock.indexOf('FROM drift'))),
    'AB must accept rejected/superseded ancestry (no status=issued filter)');
});

// ── DB-gated: live behaviour ────────────────────────────────────────────────────
test('DB: AB invariant present and reports 0 violations', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('check_schema_invariants');
  assert.ok(!error, error?.message);
  const ab = data.find((r) => r.invariant_name === 'AB_term_signed_milestone_has_cert_ancestry');
  assert.ok(ab, 'AB invariant present');
  assert.equal(ab.severity, 'medium');
  assert.equal(ab.violation_count, 0, 'AB must have 0 violations');
});

test('DB: every issued volunteer_agreement signer has a term_signed milestone', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // members with an issued volunteer_agreement cert
  const { data: certs, error: e1 } = await sb
    .from('certificates').select('member_id').eq('type', 'volunteer_agreement').eq('status', 'issued');
  assert.ok(!e1, e1?.message);
  const signerIds = [...new Set((certs || []).map((c) => c.member_id).filter(Boolean))];
  const { data: ms, error: e2 } = await sb
    .from('member_milestones').select('member_id, acknowledged_at').eq('milestone_key', 'term_signed');
  assert.ok(!e2, e2?.message);
  const milestoneIds = new Set((ms || []).map((m) => m.member_id));
  const missing = signerIds.filter((id) => !milestoneIds.has(id));
  assert.equal(missing.length, 0, `issued signers without a term_signed milestone: ${missing.join(', ')}`);
});

test('DB: backfilled term_signed milestones are acknowledged (silent, not pending)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('member_milestones')
    .select('acknowledged_at, metadata')
    .eq('milestone_key', 'term_signed')
    .contains('metadata', { backfill: true });
  assert.ok(!error, error?.message);
  const pending = (data || []).filter((m) => m.acknowledged_at === null);
  assert.equal(pending.length, 0, 'backfilled milestones must be acknowledged (no retroactive celebration)');
});
