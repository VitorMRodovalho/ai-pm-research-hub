// tests/contracts/975-pr3-camada5-material-chain.test.mjs
//
// #975 (PR-3 of #571) — Camada 5 Material-change backbone: CADEIA DE RATIFICAÇÃO (WA2).
// Guards the Gate Matrix v3: committee_majority (maioria simples contra roster pinado),
// partner_consultation (consultivo janelado 15 úteis, SEM veto), the gate_state column,
// the activation triggers + helper, the gate_state system-only guard, the chain_approved
// notification trigger, the window-close cron, and the new policy template.
//
// Two layers:
//   (A) Static — parses the migration file; always runs (no DB).
//   (B) DB-aware — calls live RPCs; SKIPPED without SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY.
//
// Behavioral majority/window/sequence/conclusion correctness is additionally verified by the
// apply-time smoke (DO + RAISE rollback, session_replication_role=replica) — see the PR notes.
//
// SPEC: docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md §5 PR-3 + §9.4 + §4. ADR-0115.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(
  __dirname,
  '../../supabase/migrations/20260805000303_975_pr3_camada5_material_ratification_chain.sql',
);
const sql = readFileSync(MIGRATION_PATH, 'utf8');

// #1152 (2026-07-21): committee_majority was a stub `false` in #975 (this migration);
// ACTIVATED later by mig 20260805000474 (Comitê de Curadoria roster via `ip_committee`).
// Guard both: the #975-era stub in THIS file, and the activation in the newer file.
const MIGRATION_1152_PATH = join(
  __dirname,
  '../../supabase/migrations/20260805000474_1152_committee_majority_activate_ip_committee_roster.sql',
);
const sql1152 = readFileSync(MIGRATION_1152_PATH, 'utf8');

// ─────────────────────────────────────────────────────────────────────────
// (A) Static migration-file guards — always run
// ─────────────────────────────────────────────────────────────────────────

test('PR-3: _validate_gates_shape extends BOTH branches (kind allowlist + threshold allowlist)', () => {
  const fn = sql.match(/CREATE OR REPLACE FUNCTION public\._validate_gates_shape[\s\S]*?\$function\$;/);
  assert.ok(fn, '_validate_gates_shape must be (re)defined');
  // kind allowlist gains the 2 new kinds
  assert.match(fn[0], /'committee_majority','partner_consultation'/, 'kind allowlist must include the 2 new kinds');
  // threshold string allowlist gains 'majority' + 'window_optional' (the §4.4 second branch)
  assert.match(fn[0], /g->>'threshold' IN \('all','majority','window_optional'\)/, "threshold allowlist must include 'majority' and 'window_optional'");
  // optional keys validated when present (rejects malformed)
  assert.match(fn[0], /NOT \(g \? 'blocking'\) OR jsonb_typeof\(g->'blocking'\) = 'boolean'/, 'blocking must be validated as boolean when present');
  assert.match(fn[0], /NOT \(g \? 'window_business_days'\)/, 'window_business_days must be validated when present');
});

test('PR-3: _can_sign_gate — partner_consultation = president_others predicate; committee_majority stub in #975 (activated in #1152)', () => {
  const fn = sql.match(/CREATE OR REPLACE FUNCTION public\._can_sign_gate[\s\S]*?\$function\$;/);
  assert.ok(fn, '_can_sign_gate must be (re)defined');
  assert.match(
    fn[0],
    /WHEN 'partner_consultation' THEN\s+v_member\.chapter IN \('PMI-CE','PMI-DF','PMI-MG','PMI-RS'\)\s+AND 'chapter_board' = ANY\(v_member\.designations\)\s+AND 'legal_signer' = ANY\(v_member\.designations\)/,
    'partner_consultation must reuse the president_others predicate (CE/DF/MG/RS + chapter_board + legal_signer)',
  );
  // Historical guard: THIS migration (#975/303) authored committee_majority as a stub false.
  // The LIVE invariant changed — activation is asserted by the #1152 test below (mig 474).
  assert.match(fn[0], /WHEN 'committee_majority' THEN false/, 'committee_majority was a stub false in #975 (dormant until the Comitê de Curadoria roster existed; activated in #1152)');
  // president_others must NOT be repurposed — still present as its own WHEN
  assert.match(fn[0], /WHEN 'president_others' THEN/, 'president_others must remain (not repurposed)');
});

test('#1152: committee_majority ACTIVATED — ip_committee predicate + Comitê de Curadoria roster (mig 474)', () => {
  const fn = sql1152.match(/CREATE OR REPLACE FUNCTION public\._can_sign_gate[\s\S]*?\$function\$;/);
  assert.ok(fn, '_can_sign_gate must be redefined in the #1152 migration');
  // stub false -> real designation predicate (the roster is pinned at activation via _gate_threshold_met)
  assert.match(fn[0], /WHEN 'committee_majority' THEN 'ip_committee' = ANY\(v_member\.designations\)/, 'committee_majority must be activated to the ip_committee designation predicate');
  assert.doesNotMatch(fn[0], /WHEN 'committee_majority' THEN false/, 'the stub false must be gone in the activation migration');
  // roster seed: exactly the 3 committee members get the ip_committee designation, idempotently
  assert.match(sql1152, /array_append\(designations, 'ip_committee'\)/, 'the migration must seed the ip_committee designation');
  assert.match(sql1152, /NOT \('ip_committee' = ANY\(designations\)\)/, 'the roster seed must be idempotent');
  const ids = sql1152.match(/'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'/g) || [];
  assert.equal(new Set(ids).size, 3, 'exactly 3 committee members must be seeded (Sarah, Fabricio, Roberto)');
});

test('PR-3: _gate_threshold_met — majority branch (pinned roster, n>=1 guard, strict floor)', () => {
  const fn = sql.match(/CREATE OR REPLACE FUNCTION public\._gate_threshold_met[\s\S]*?\$function\$;/);
  assert.ok(fn, '_gate_threshold_met must be (re)defined');
  assert.match(fn[0], /WHEN \(p_gate->>'threshold'\) = 'majority' THEN/, 'majority branch must exist');
  // roster read from gate_state snapshot (NOT live _can_sign_gate)
  assert.match(fn[0], /gate_state -> \(p_gate->>'kind'\) -> 'committee_roster_ids'/, 'roster must come from gate_state snapshot');
  assert.match(fn[0], /r\.n >= 1/, 'empty-roster guard (n>=1) must be present');
  assert.match(fn[0], /> floor\(r\.n::numeric \/ 2\)/, 'strict majority (> floor(n/2)) must be present');
  assert.match(fn[0], /signoff_type = 'approval'\s+AND s\.signer_id = ANY\(r\.roster\)/, 'majority counts only approvals by roster members');
});

test('PR-3: _gate_threshold_met — window_optional branch with eligible_snapshot>0 guard (review BLOCKER fix)', () => {
  const fn = sql.match(/CREATE OR REPLACE FUNCTION public\._gate_threshold_met[\s\S]*?\$function\$;/);
  assert.match(fn[0], /WHEN \(p_gate->>'threshold'\) = 'window_optional' THEN/, 'window_optional branch must exist');
  // auto_closed_at path (window expiry)
  assert.match(fn[0], /gate_state -> \(p_gate->>'kind'\) ->> 'auto_closed_at'\) IS NOT NULL/, 'auto_closed_at path must exist');
  // BLOCKER fix: eligible_snapshot > 0 guard before the count comparison (regression lock)
  assert.match(
    fn[0],
    /gate_state -> \(p_gate->>'kind'\) ->> 'eligible_snapshot'\)::int > 0/,
    'eligible_snapshot>0 guard MUST be present (prevents instant auto-satisfy with 0 eligible partners — the consensus blocker)',
  );
  // count DISTINCT responders (any signoff_type — a rejection is a response, never a veto)
  assert.match(fn[0], /count\(DISTINCT s\.signer_id\)/, 'window_optional must count DISTINCT responders');
});

test('PR-3: gate_state jsonb column added (NOT NULL default {})', () => {
  assert.match(sql, /ALTER TABLE public\.approval_chains\s+ADD COLUMN IF NOT EXISTS gate_state jsonb NOT NULL DEFAULT '\{\}'::jsonb/);
});

test('PR-3: activation helper + 2 triggers + REVOKE on the wrappers (review #6)', () => {
  assert.match(sql, /CREATE OR REPLACE FUNCTION public\._activate_eligible_gates\(p_chain_id uuid\)/);
  // review #5: FOR UPDATE serializes concurrent activations
  assert.match(sql, /FROM public\.approval_chains ac WHERE ac\.id = p_chain_id\s+FOR UPDATE;/, '_activate_eligible_gates must SELECT ... FOR UPDATE');
  assert.match(sql, /CREATE TRIGGER trg_activate_eligible_gates_on_signoff\s+AFTER INSERT ON public\.approval_signoffs/);
  assert.match(sql, /CREATE TRIGGER trg_activate_eligible_gates_on_chain\s+AFTER INSERT OR UPDATE OF status ON public\.approval_chains\s+FOR EACH ROW\s+WHEN \(NEW\.status = 'review'\)/);
  for (const f of ['_activate_eligible_gates', 'trg_activate_eligible_gates_on_signoff', 'trg_activate_eligible_gates_on_chain']) {
    assert.match(sql, new RegExp(`REVOKE EXECUTE ON FUNCTION public\\.${f}\\([^)]*\\) FROM PUBLIC, anon, authenticated`), `${f} must REVOKE`);
  }
});

test('PR-3: gate_state system-only guard trigger (review #4 HIGH) — INVOKER, blocks non-system writes', () => {
  const fn = sql.match(/CREATE OR REPLACE FUNCTION public\.trg_guard_gate_state_system_only[\s\S]*?\$function\$;/);
  assert.ok(fn, 'guard function must exist');
  // must NOT be SECURITY DEFINER (needs the real current_user of the statement)
  assert.doesNotMatch(fn[0], /SECURITY DEFINER/, 'guard must be SECURITY INVOKER (not DEFINER)');
  assert.match(fn[0], /NEW\.gate_state IS DISTINCT FROM OLD\.gate_state\s+AND current_user NOT IN \('postgres', 'supabase_admin', 'service_role'\)/);
  assert.match(fn[0], /RAISE EXCEPTION 'approval_chains\.gate_state is system-managed/);
  assert.match(sql, /CREATE TRIGGER trg_guard_gate_state_system_only\s+BEFORE UPDATE OF gate_state ON public\.approval_chains/);
});

test('PR-3: chain_approved notification trigger (review #3) — symmetric, skips project_charter', () => {
  const fn = sql.match(/CREATE OR REPLACE FUNCTION public\.trg_notify_chain_approved[\s\S]*?\$function\$;/);
  assert.ok(fn, 'trg_notify_chain_approved must exist');
  assert.match(fn[0], /doc_type = 'project_charter'[\s\S]*?RETURN NEW;/, 'must skip project_charter (dedicated notifier)');
  assert.match(fn[0], /_enqueue_gate_notifications\(NEW\.id, 'chain_approved', NULL\)/);
  assert.match(sql, /CREATE TRIGGER trg_notify_chain_approved\s+AFTER UPDATE OF status ON public\.approval_chains\s+FOR EACH ROW\s+WHEN \(NEW\.status = 'approved' AND OLD\.status = 'review'\)/);
  // cron must NOT also explicitly enqueue chain_approved (would double-notify)
  const cron = sql.match(/CREATE OR REPLACE FUNCTION public\.ratification_window_close_cron[\s\S]*?\$function\$;/);
  assert.doesNotMatch(cron[0], /_enqueue_gate_notifications\([^,]+, 'chain_approved'/, 'cron must not double-enqueue chain_approved (trigger handles it)');
});

test('PR-3: window-close cron defined, REVOKEd, scheduled', () => {
  assert.match(sql, /CREATE OR REPLACE FUNCTION public\.ratification_window_close_cron\(\)/);
  assert.match(sql, /REVOKE EXECUTE ON FUNCTION public\.ratification_window_close_cron\(\) FROM PUBLIC, anon, authenticated/);
  assert.match(sql, /cron\.schedule\('ratification-window-close-daily'/);
  // cron re-evaluates conclusion exactly like sign_ip_ratification
  assert.match(sql, /FROM jsonb_array_elements\(v_chain\.gates\) g\s+WHERE NOT public\._gate_threshold_met\(v_chain\.id, g\)/);
});

test('PR-3: resolve_default_gates(policy) = Gate Matrix v3 (committee_majority -> president_go -> partner_consultation)', () => {
  const fn = sql.match(/WHEN 'policy' THEN '(\[[\s\S]*?\])'::jsonb/);
  assert.ok(fn, "policy branch must exist");
  const tpl = JSON.parse(fn[1]);
  assert.deepEqual(tpl.map((g) => g.kind), ['committee_majority', 'president_go', 'partner_consultation']);
  assert.equal(tpl[0].threshold, 'majority');
  assert.equal(tpl[1].threshold, 1);
  assert.equal(tpl[2].threshold, 'window_optional');
  assert.equal(tpl[2].blocking, false);
  assert.equal(tpl[2].window_business_days, 15);
  // president_others must remain BLOQUEANTE in cooperation_agreement (NOT repurposed)
  const coop = sql.match(/WHEN 'cooperation_agreement' THEN '(\[[\s\S]*?\])'::jsonb/);
  assert.match(coop[1], /"kind":"president_others","order":6,"threshold":4/, 'cooperation_agreement keeps president_others threshold 4 (blocking)');
});

test('PR-3: _enqueue_gate_notifications has PT-BR CASE entries for both new kinds, with GO-calendar disclosure (review #8)', () => {
  const fn = sql.match(/CREATE OR REPLACE FUNCTION public\._enqueue_gate_notifications[\s\S]*?\$function\$;/);
  assert.ok(fn, '_enqueue_gate_notifications must be (re)defined');
  assert.match(fn[0], /WHEN 'committee_majority' THEN 'Deliberacao do Comite de Curadoria'/);
  assert.match(fn[0], /WHEN 'partner_consultation' THEN 'Manifestacao consultiva do capitulo parceiro'/);
  // GO-calendar transparency disclosure (both blocks reference Goias)
  const goMentions = (fn[0].match(/calendario de (?:dias uteis|feriados) de Goias/g) || []).length;
  assert.ok(goMentions >= 2, `partner_consultation notification must disclose the GO calendar in both blocks (found ${goMentions})`);
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

test('live: resolve_default_gates(policy) returns the Gate Matrix v3 template', { skip: !canRun && skipMsg }, async () => {
  const { ok, json, text } = await rpc('resolve_default_gates', { p_doc_type: 'policy' });
  assert.ok(ok, `resolve_default_gates must run: ${text}`);
  assert.deepEqual(json.map((g) => g.kind), ['committee_majority', 'president_go', 'partner_consultation']);
  assert.equal(json[2].threshold, 'window_optional');
  assert.equal(json[2].window_business_days, 15);
});

test('live: _validate_gates_shape accepts the new template and rejects malformed gates', { skip: !canRun && skipMsg }, async () => {
  const accept = await rpc('_validate_gates_shape', {
    p_gates: [
      { kind: 'committee_majority', order: 1, threshold: 'majority' },
      { kind: 'president_go', order: 2, threshold: 1 },
      { kind: 'partner_consultation', order: 3, threshold: 'window_optional', blocking: false, window_business_days: 15 },
    ],
  });
  assert.ok(accept.ok, `validate must run: ${accept.text}`);
  assert.equal(accept.json, true, 'new policy template must validate');

  for (const [label, gates] of [
    ['bad blocking type', [{ kind: 'partner_consultation', order: 1, threshold: 'window_optional', blocking: 'yes' }]],
    ['bad threshold string', [{ kind: 'committee_majority', order: 1, threshold: 'supermajority' }]],
    ['unknown kind', [{ kind: 'frobnicate', order: 1, threshold: 'all' }]],
    ['bad window_business_days', [{ kind: 'partner_consultation', order: 1, threshold: 'window_optional', window_business_days: 'soon' }]],
  ]) {
    const r = await rpc('_validate_gates_shape', { p_gates: gates });
    assert.ok(r.ok, `validate(${label}) must run: ${r.text}`);
    assert.equal(r.json, false, `malformed gate (${label}) must be rejected`);
  }
});

test('live: _gate_threshold_met never spuriously MET for an unknown chain (stateful gates default to not-met)', { skip: !canRun && skipMsg }, async () => {
  // Safety invariant: a committee_majority / partner_consultation gate must NEVER be "met"
  // (=== true) without a real pinned roster / window in gate_state. For a non-existent chain the
  // scalar subquery yields null (no row); for a REAL chain with no gate_state entry it yields false
  // (empty roster => n=0; absent window) — both mean "not satisfied". The dangerous outcome is true.
  const fakeChain = '00000000-0000-0000-0000-000000000000';
  const maj = await rpc('_gate_threshold_met', { p_chain_id: fakeChain, p_gate: { kind: 'committee_majority', order: 1, threshold: 'majority' } });
  assert.ok(maj.ok, `_gate_threshold_met must run: ${maj.text}`);
  assert.notEqual(maj.json, true, 'majority must NEVER be met without a pinned non-empty roster');
  const win = await rpc('_gate_threshold_met', { p_chain_id: fakeChain, p_gate: { kind: 'partner_consultation', order: 3, threshold: 'window_optional', window_business_days: 15 } });
  assert.ok(win.ok, `_gate_threshold_met must run: ${win.text}`);
  assert.notEqual(win.json, true, 'window_optional must NEVER be met without auto_close or a satisfied snapshot');
});

test('live: check_schema_invariants — 0 total violations after PR-3', { skip: !canRun && skipMsg }, async () => {
  const { ok, json, text } = await rpc('check_schema_invariants', {});
  assert.ok(ok, `check_schema_invariants must run: ${text}`);
  assert.equal(json.filter((r) => r.violation_count > 0).length, 0, 'no invariant may be violated');
});
