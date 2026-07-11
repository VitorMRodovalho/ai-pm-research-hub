/**
 * Contract: #1221 fatia 1 — merit of completed work is immutable (advisory audit) + the deferred
 * ADR-0121 interim-grant reversion invariant.
 *
 * Part A: supabase/migrations/20260805000402_1221_merit_transfer_audit_rpc.sql
 *   _audit_merit_transfer_on_completed_cards() — an ADVISORY review queue (NOT a CI gate): grounded
 *   live 2026-07-10, board_lifecycle_events covers only ~26% of completed cards, so a hard baseline-0
 *   gate would be blind; and "completed card assigned to a leader" is ~310 legitimate rows. So it
 *   surfaces the divergent subset for a human: post-completion reassignment by another actor, or a
 *   leader/GP holding a completed card that a non-leader created.
 *
 * Part B: supabase/migrations/20260805000403_1221_interim_grant_invariant.sql
 *   check_schema_invariants() gains AP_interim_grant_reverted_when_cert_issued (deferred from #1117):
 *   an engagement must not carry BOTH metadata->>'interim_grant'=true AND agreement_certificate_id
 *   (the interim flag must be reverted once the real term is signed, ADR-0121). Baseline 0.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG_A = resolve(ROOT, 'supabase/migrations/20260805000402_1221_merit_transfer_audit_rpc.sql');
const MIG_B = resolve(ROOT, 'supabase/migrations/20260805000403_1221_interim_grant_invariant.sql');
const a = existsSync(MIG_A) ? readFileSync(MIG_A, 'utf8') : '';
const b = existsSync(MIG_B) ? readFileSync(MIG_B, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Part A static ────────────────────────────────────────────────────────────
test('#1221 A: advisory audit RPC defined, SECDEF, gated, anon-revoked', () => {
  assert.ok(existsSync(MIG_A), 'Part A migration present');
  assert.match(a, /CREATE OR REPLACE FUNCTION public\._audit_merit_transfer_on_completed_cards\(\)/);
  assert.match(a, /SECURITY DEFINER/);
  assert.match(a, /public\.can\([\s\S]*?'manage_platform'\)/, 'gated on manage_platform');
  assert.match(a, /REVOKE EXECUTE ON FUNCTION public\._audit_merit_transfer_on_completed_cards\(\) FROM PUBLIC, anon;/);
});

test('#1221 A: two divergence flags + self-reassignment noise filter', () => {
  assert.match(a, /'reassigned_after_completion'/);
  assert.match(a, /'completed_credit_from_non_leader_creator'/);
  // self-touch filter: reassignment actor must differ from the current assignee
  assert.match(a, /e\.actor_member_id IS DISTINCT FROM bi\.assignee_id/);
  // advisory, not a hard gate: it is NOT wired into check_schema_invariants
  assert.ok(!/check_schema_invariants/.test(a), 'Part A must not touch the invariant gate');
});

// ── Part B static ────────────────────────────────────────────────────────────
test('#1221 B: check_schema_invariants gains AP interim-grant reversion invariant', () => {
  assert.ok(existsSync(MIG_B), 'Part B migration present');
  assert.match(b, /CREATE OR REPLACE FUNCTION public\.check_schema_invariants\(\)/);
  assert.match(b, /AP_interim_grant_reverted_when_cert_issued/);
  assert.match(b, /metadata ->> 'interim_grant'/);
  assert.match(b, /agreement_certificate_id IS NOT NULL/);
  // the AO guard from the prior migration must still be present (re-emitted from live, not truncated)
  assert.match(b, /AO_active_member_stale_tribe_id_after_leave/);
});

// ── DB-gated ─────────────────────────────────────────────────────────────────
test('#1221 A DB: advisory audit runs for service_role and returns an array', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_merit_transfer_on_completed_cards');
  assert.ok(!error, `advisory audit should run for service_role: ${error?.message}`);
  assert.ok(Array.isArray(data), 'returns a rowset');
});

test('#1221 B DB: AP invariant is present and at baseline 0', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('check_schema_invariants');
  assert.ok(!error, error?.message);
  const ap = (data || []).find((r) => r.invariant_name === 'AP_interim_grant_reverted_when_cert_issued');
  assert.ok(ap, 'AP invariant must be emitted by check_schema_invariants');
  assert.equal(ap.violation_count, 0, `AP baseline must be 0, got ${ap?.violation_count}`);
});
