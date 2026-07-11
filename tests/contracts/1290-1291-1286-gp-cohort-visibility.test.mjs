/**
 * Contract: #1290 / #1291 / #1286 — GP/co-GP visibility (camada de dado read-only).
 *
 * Migration: supabase/migrations/20260805000409_1290_1291_1286_gp_cohort_visibility.sql
 *
 * Duas RPCs GP-gated (manage_member OR view_internal_analytics), expostas como MCP tools:
 *   get_gp_cohort_health()               -> #1290 pendentes de aprovacao do lider + #1291 coorte em risco
 *   get_cycle_attendance_overview(text)  -> #1286 presencas/faltas cross-membro por ciclo
 *
 * Invariantes:
 *  Static:
 *   - ambas STABLE SECURITY DEFINER, gate manage_member OR view_internal_analytics endurecido
 *     com coalesce(v_is_service,false) (barra postgres-direto), REVOKE FROM PUBLIC,anon,authenticated.
 *   - kickoff derivado (NAO hardcoded): type='kickoff' OR title ILIKE '%kick%' na janela do ciclo.
 *  DB-gated (nao-destrutivo, via service_role — bypassa o gate por v_is_service):
 *   - get_gp_cohort_health retorna cohort_summary + pending_leader_approvals[] + at_risk_members[].
 *   - get_cycle_attendance_overview(null) retorna cycle + members[]; cycle inexistente -> error.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000409_1290_1291_1286_gp_cohort_visibility.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1290/#1291/#1286: migration defines both RPCs (STABLE SECURITY DEFINER)', () => {
  assert.ok(existsSync(MIG), 'migration file present');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.get_gp_cohort_health\(\)[\s\S]*?STABLE SECURITY DEFINER/);
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.get_cycle_attendance_overview\(p_cycle_code text DEFAULT NULL\)[\s\S]*?STABLE SECURITY DEFINER/);
});

test('#1290/#1291/#1286: gate is manage_member OR view_internal_analytics, hardened for postgres-direct', () => {
  const cohortGate = mig.match(/get_gp_cohort_health[\s\S]*?RETURN v_result;/)[0];
  const attGate = mig.match(/get_cycle_attendance_overview[\s\S]*?RETURN v_result;/)[0];
  for (const [name, body] of [['cohort', cohortGate], ['attendance', attGate]]) {
    assert.match(body, /can_by_member\(v_caller, 'manage_member'\)/, `${name}: gate manage_member`);
    assert.match(body, /can_by_member\(v_caller, 'view_internal_analytics'\)/, `${name}: gate view_internal_analytics`);
    assert.match(body, /NOT coalesce\(v_is_service, false\)/, `${name}: hardened coalesce (blocks postgres-direct)`);
  }
});

test('#1290/#1291/#1286: REVOKE FROM PUBLIC,anon,authenticated + GRANT to authenticated,service_role', () => {
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.get_gp_cohort_health\(\) FROM PUBLIC, anon, authenticated;/);
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.get_gp_cohort_health\(\) TO authenticated, service_role;/);
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.get_cycle_attendance_overview\(text\) FROM PUBLIC, anon, authenticated;/);
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.get_cycle_attendance_overview\(text\) TO authenticated, service_role;/);
});

test('#1291: kickoff is DERIVED (not hardcoded event id) — type or title match in cycle window', () => {
  assert.match(mig, /type = 'kickoff' OR title ILIKE '%kick%'/, 'kickoff derived from type/title, not a hardcoded uuid');
});

// ── DB-gated (non-destructive; service_role bypasses the gate via v_is_service) ──
test('#1290/#1291 DB: get_gp_cohort_health returns summary + approvals + at_risk', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_gp_cohort_health');
  assert.ok(!error, `must not throw: ${error?.message}`);
  assert.ok(!data.error, `returned error: ${JSON.stringify(data.error)}`);
  assert.ok(data.cohort_summary && typeof data.cohort_summary.total === 'number', 'cohort_summary.total present');
  assert.ok(Array.isArray(data.pending_leader_approvals), 'pending_leader_approvals is an array');
  assert.ok(Array.isArray(data.at_risk_members), 'at_risk_members is an array');
  // consistency: without_tribe count matches the flagged subset
  const flaggedNoTribe = data.at_risk_members.filter((m) => m.no_tribe).length;
  assert.equal(flaggedNoTribe, data.cohort_summary.without_tribe, 'no_tribe flags match cohort_summary.without_tribe');
});

test('#1286 DB: get_cycle_attendance_overview(null) returns current cycle + members[]', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_cycle_attendance_overview', { p_cycle_code: null });
  assert.ok(!error, `must not throw: ${error?.message}`);
  assert.ok(!data.error, `returned error: ${JSON.stringify(data.error)}`);
  assert.ok(data.cycle && data.cycle.is_current === true, 'defaults to current cycle');
  assert.ok(Array.isArray(data.members), 'members is an array');
});

test('#1286 DB: get_cycle_attendance_overview(unknown) returns a not-found error', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data } = await sb.rpc('get_cycle_attendance_overview', { p_cycle_code: 'cycle_does_not_exist' });
  assert.match(data?.error || '', /Cycle not found/, `unknown cycle must error: ${JSON.stringify(data)}`);
});
