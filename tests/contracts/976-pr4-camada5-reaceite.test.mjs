// tests/contracts/976-pr4-camada5-reaceite.test.mjs
//
// #976 (PR-4 of #571) — Camada 5 Material-change backbone: MÁQUINA DE ESTADOS DE
// RE-ACEITE (WA1 — Termo 15.3 / 15.4.3 / 15.4.4 / 15.4.5; Política 12.2.1/12.3).
//
// Guards: the two tables + RLS, the deadline anchoring (effective_from, NUNCA
// notified_at), the no-auth disengage helper, the OUTWARD-gated signature-based
// fan-out (GR-1 / never members.is_active), the §9.5 accommodation clock recompute,
// the license-preservation guards in BOTH anonymization crons (+ DPO visibility),
// and the lifecycle cron. The full behavioral lifecycle is additionally verified by
// the apply-time smoke (DO + RAISE rollback, session_replication_role=replica).
//
// Two layers:
//   (A) Static — parses the migration file; always runs (no DB).
//   (B) DB-aware — calls live RPCs; SKIPPED without SUPABASE_URL + SERVICE_ROLE_KEY.
//
// SPEC: docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md §5 PR-4 + §9.5 + §4. ADR-0116.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(
  __dirname,
  '../../supabase/migrations/20260805000304_976_pr4_camada5_reacceptance_state_machine.sql',
);
const sql = readFileSync(MIGRATION_PATH, 'utf8');

function fn(name) {
  const m = sql.match(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\b[\\s\\S]*?\\$function\\$;`));
  assert.ok(m, `${name} must be (re)defined in the migration`);
  return m[0];
}

// ─────────────────────────────────────────────────────────────────────────
// (A) Static migration-file guards — always run
// ─────────────────────────────────────────────────────────────────────────

test('PR-4: both tables created with RLS enabled + member-scoped read policy', () => {
  assert.match(sql, /CREATE TABLE IF NOT EXISTS public\.member_reacceptance_obligations/);
  assert.match(sql, /CREATE TABLE IF NOT EXISTS public\.reacceptance_objections/);
  assert.match(sql, /ALTER TABLE public\.member_reacceptance_obligations ENABLE ROW LEVEL SECURITY/);
  assert.match(sql, /ALTER TABLE public\.reacceptance_objections ENABLE ROW LEVEL SECURITY/);
  // read policy is member-self OR manage_member admin (no DML policy => writes only via SECDEF)
  assert.match(sql, /CREATE POLICY mro_read_self_or_admin[\s\S]*?can_by_member\(m\.id, 'manage_member'\)/);
  assert.match(sql, /CREATE POLICY ro_read_self_or_admin[\s\S]*?can_by_member\(m\.id, 'manage_member'\)/);
  // FK circular resolved via ALTER ADD objection_id after both tables exist
  assert.match(sql, /ALTER TABLE public\.member_reacceptance_obligations\s+ADD COLUMN IF NOT EXISTS objection_id uuid REFERENCES public\.reacceptance_objections/);
});

test('PR-4: state machine has the 9 reachable states + dead pending_notification removed', () => {
  // initial state set by open() is the column default
  assert.match(sql, /state text NOT NULL DEFAULT 'notified'/);
  for (const s of ['notified', 'in_window', 'objection_pending', 'accommodation_window', 'suspended', 're_accepted', 'refused', 'lapsed_disengaged', 'superseded']) {
    assert.match(sql, new RegExp(`'${s}'`), `state '${s}' must be defined`);
  }
  // pending_notification must not be a LIVE state entry (it may appear only in the "removido" comment)
  assert.doesNotMatch(sql, /^\s*'pending_notification',/m, 'pending_notification must not be a live state entry');
});

test('PR-4: deadline anchoring on effective_from, NEVER notified_at (§9.5 / Termo 15.3)', () => {
  const open = fn('open_reacceptance_obligations');
  // effective = notified + 30 calendar days; window = add_business_days(effective,15); suspended = window + 30
  assert.match(open, /v_effective\s*:=\s*v_notified \+ INTERVAL '30 days'/);
  assert.match(open, /v_window_close\s*:=\s*public\.add_business_days\(v_effective, 15\)/);
  assert.match(open, /v_suspended\s*:=\s*v_window_close \+ INTERVAL '30 days'/);
});

test('PR-4: fan-out is signature-based (is_current), NEVER members.is_active (GR-1 / #648/#653)', () => {
  const open = fn('open_reacceptance_obligations');
  assert.match(open, /JOIN public\.member_document_signatures mds[\s\S]*?mds\.is_current = true/);
  assert.doesNotMatch(open, /m\.is_active\b/, 'open must not filter the fan-out by members.is_active (would catch guests)');
  // only material opens an obligation; editorial/unclassified => none (15.4.4 tácito proibido p/ material)
  assert.match(open, /v_version\.change_class IS DISTINCT FROM 'material'/);
  // OUTWARD safety: dry_run default true + manage_platform gate
  assert.match(open, /p_dry_run boolean DEFAULT true/);
  assert.match(open, /can_by_member\(v_caller\.id, 'manage_platform'\)/);
});

test('PR-4: _reacceptance_disengage — no auth.uid(), preserves licenses, RAISE on not-found, REVOKEd', () => {
  const dis = fn('_reacceptance_disengage');
  assert.doesNotMatch(dis, /auth\.uid\(\)/, 'disengage must NOT call auth.uid() (callable by cron)');
  assert.match(dis, /RAISE EXCEPTION 'member_not_found for reacceptance_disengage/, 'must RAISE (not soft-return) on missing member');
  assert.match(dis, /p_preserve_licenses=false nao e suportado/, 'must reject preserve=false (15.4.5 unconditional)');
  assert.doesNotMatch(dis, /DELETE FROM public\.member_document_signatures/, 'must never delete the license ledger');
  assert.match(dis, /member_status\s*=\s*'inactive'/, 'terminal status is inactive (reversible)');
  assert.match(sql, /REVOKE EXECUTE ON FUNCTION public\._reacceptance_disengage\(uuid, text, boolean\) FROM PUBLIC, anon, authenticated/);
});

test('PR-4: cron — §9.5 accommodation clock recompute + obligation-level lapse audit + committee-overdue', () => {
  const cron = fn('reacceptance_lifecycle_sweep_cron');
  // accommodation resume = accommodation_window_closes_at + (suspended_until_orig − committee_responded_at)
  assert.match(cron, /v_new_suspended\s*:=\s*v_ob\.obj_accom_closes \+ \(v_ob\.suspended_until - v_ob\.obj_responded_at\)/);
  // SSOT 'suspended' lives in obligation.state — cron must NOT write engagements.status
  assert.doesNotMatch(cron, /UPDATE public\.engagements/, 'cron must not mirror suspended into engagements.status');
  // obligation-grain audit on lapse (ADR-0013)
  assert.match(cron, /'reacceptance\.lapsed_disengaged', 'member_reacceptance_obligation'/);
  // committee SLA overdue idempotent log (1-day guard)
  assert.match(cron, /'reacceptance\.committee_overdue'/);
  assert.match(cron, /al\.created_at > v_now - INTERVAL '1 day'/);
  assert.match(sql, /REVOKE EXECUTE ON FUNCTION public\.reacceptance_lifecycle_sweep_cron\(\) FROM PUBLIC, anon, authenticated/);
  assert.match(sql, /cron\.schedule\('reacceptance-lifecycle-sweep-daily'/);
});

test('PR-4: license-preservation guard in BOTH member-touching anonymizers, with DPO visibility', () => {
  const byKind = fn('anonymize_by_engagement_kind');
  const inactive = fn('anonymize_inactive_members');
  for (const [label, body] of [['by_engagement_kind', byKind], ['inactive_members', inactive]]) {
    assert.match(body, /member_document_signatures mds[\s\S]*?mds\.is_current = true/, `${label} must guard on a current signature`);
    assert.match(body, /lgpd\.anonymization_deferred_ip_license/, `${label} must log the deferral for DPO visibility`);
  }
  // premember anonymizer is NOT redefined by this migration (pre-members have no ledger; guard = dead-code)
  assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION public\.anonymize_premember_applications/, 'premember anonymizer must not be redefined here');
});

test('PR-4: respond_reacceptance_objection — rejected notification reflects real state (no past-date / no message to disengaged)', () => {
  const resp = fn('respond_reacceptance_objection');
  // lapsed branch must NOT send the "retomado" message (disengage notifies); guarded by IF v_new_state = 'lapsed'
  assert.match(resp, /IF v_new_state = 'lapsed' THEN[\s\S]*?_reacceptance_disengage[\s\S]*?ELSE[\s\S]*?create_notification\(v_ob\.member_id, 'governance_reacceptance_objection_rejected'/);
  // notification body branches on v_new_state (in_window vs late)
  assert.match(resp, /CASE WHEN v_new_state = 'in_window'/);
  // accepted => audit forces visibility that recirculation is a manual GP step
  assert.match(resp, /'action_required_by_gp'/);
});

test('PR-4: offboard_reason_categories insert uses the REAL columns (label_pt/en/es), both codes', () => {
  assert.match(sql, /INSERT INTO public\.offboard_reason_categories\s*\(code, label_pt, label_en, label_es, description_pt, is_volunteer_fault, preserves_return_eligibility, sort_order, is_active\)/);
  assert.match(sql, /'reacceptance_refusal'/);
  assert.match(sql, /'reacceptance_lapse'/);
});

test('PR-4: every member/admin-facing SECDEF REVOKEs PUBLIC+anon; internals also revoke authenticated', () => {
  for (const f of [
    'open_reacceptance_obligations\\(uuid, uuid, boolean\\)',
    'notify_editorial_change_awareness\\(uuid, uuid, boolean\\)',
    'express_reacceptance\\(uuid\\)',
    'register_reacceptance_objection\\(uuid, text, text, text\\)',
    'respond_reacceptance_objection\\(uuid, text, text\\)',
    'refuse_reacceptance\\(uuid\\)',
    'get_my_reacceptance_obligations\\(\\)',
    'link_reacceptance_recirculation\\(uuid, uuid\\)',
  ]) {
    assert.match(sql, new RegExp(`REVOKE EXECUTE ON FUNCTION public\\.${f} FROM PUBLIC, anon`), `${f} must REVOKE PUBLIC, anon`);
  }
});

// ─────────────────────────────────────────────────────────────────────────
// (B) DB-aware guards — require live DB
// ─────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function rpc(name, body) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` },
    body: JSON.stringify(body),
  });
  return { ok: res.ok, status: res.status, json: res.ok ? await res.json() : null, text: res.ok ? null : await res.text() };
}

test('live: check_schema_invariants — 0 violations after PR-4', { skip: !canRun && skipMsg }, async () => {
  const { ok, json, text } = await rpc('check_schema_invariants', {});
  assert.ok(ok, `check_schema_invariants must run: ${text}`);
  assert.equal(json.filter((r) => r.violation_count > 0).length, 0, 'no invariant may be violated');
});

test('live: get_my_reacceptance_obligations is callable and member-scoped (empty without a member)', { skip: !canRun && skipMsg }, async () => {
  // service_role has no auth.uid() member => the function returns [] (does not error / does not leak)
  const { ok, json, text } = await rpc('get_my_reacceptance_obligations', {});
  assert.ok(ok, `get_my_reacceptance_obligations must run: ${text}`);
  assert.deepEqual(json, [], 'must be empty for a caller with no member record');
});

test('live: the lifecycle machine is dormant — 0 obligations, 0 objections', { skip: !canRun && skipMsg }, async () => {
  // exercised via PostgREST head-count on the tables (RLS: service_role bypasses)
  for (const table of ['member_reacceptance_obligations', 'reacceptance_objections']) {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?select=id`, {
      headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}`, Prefer: 'count=exact', Range: '0-0' },
    });
    const cr = res.headers.get('content-range') || '';
    assert.match(cr, /\/0$/, `${table} must be empty (dormant); content-range=${cr}`);
  }
});
