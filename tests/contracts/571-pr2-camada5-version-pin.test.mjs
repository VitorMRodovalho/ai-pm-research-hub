// tests/contracts/571-pr2-camada5-version-pin.test.mjs
//
// #974 (PR-2 of #571) — Camada 5 Material-change backbone: VERSION PIN (WA3).
// Guards instrument_version_bindings (SSOT do pin instrumento->versão), the
// propagation trigger (editorial append-only auto-advance / material re-anchor
// flag), the 3 SECDEF RPCs, the 4-agreement backfill, and the AN invariant.
//
// Two layers:
//   (A) Static — parses the migration file; always runs (no DB).
//   (B) DB-aware — calls live RPCs/tables; SKIPPED without
//       SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (CI provides them).
//
// SPEC: docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md §5 PR-2 + §9.1 + §9.3. ADR-0114.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(
  __dirname,
  '../../supabase/migrations/20260805000302_974_pr2_camada5_instrument_version_bindings.sql',
);

// ─────────────────────────────────────────────────────────────────────────
// (A) Static migration-file guards — always run
// ─────────────────────────────────────────────────────────────────────────
test('PR-2 migration: pinned_version_id NOT NULL (vedação de remissão dinâmica por construção)', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  assert.match(
    sql,
    /pinned_version_id uuid NOT NULL REFERENCES public\.document_versions\(id\)/,
    'pinned_version_id must be a NOT NULL FK to document_versions (hard pin, no dynamic remission)',
  );
  assert.match(sql, /CONSTRAINT ivb_referenced_not_bound CHECK \(referenced_document_id <> bound_document_id\)/);
});

test('PR-2 migration: partial unique index on active bindings (§9.3 — separate statement)', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  assert.match(
    sql,
    /CREATE UNIQUE INDEX IF NOT EXISTS ivb_active_unique\s+ON public\.instrument_version_bindings\(bound_document_id, referenced_document_id\)\s+WHERE status = 'active'/,
    'partial unique index keeps <=1 active binding per (bound, referenced) pair',
  );
});

test('PR-2 migration: RLS enabled + SELECT policy gated on manage_platform; no write policy', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  assert.match(sql, /ALTER TABLE public\.instrument_version_bindings ENABLE ROW LEVEL SECURITY/);
  assert.match(sql, /CREATE POLICY ivb_select_admin[\s\S]*?USING \(public\.rls_can\('manage_platform'\)\)/);
  // only a SELECT policy exists on the table (writes only via SECDEF RPCs / service_role / migration).
  // Match each CREATE POLICY ON the table and inspect its FOR <cmd> clause directly (precise — does
  // not span into RPC bodies where `SELECT ... FOR UPDATE` row-locks would false-match).
  const policyCmds = [...sql.matchAll(/CREATE POLICY \w+ ON public\.instrument_version_bindings\s+FOR (\w+)/g)].map((m) => m[1]);
  assert.deepEqual(policyCmds, ['SELECT'], 'only a SELECT policy may exist (no INSERT/UPDATE/DELETE policy)');
});

test('PR-2 migration: 3 SECDEF RPCs, each REVOKE FROM PUBLIC, anon, authenticated (§9.1)', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  for (const fn of ['pin_instrument_version', 'reanchor_instrument_binding', 'list_stale_instrument_bindings']) {
    assert.match(sql, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(`), `${fn} must be defined`);
    assert.match(
      sql,
      new RegExp(`REVOKE EXECUTE ON FUNCTION public\\.${fn}\\([^)]*\\) FROM PUBLIC, anon, authenticated`),
      `${fn} must REVOKE EXECUTE FROM PUBLIC, anon, authenticated`,
    );
  }
  // all 3 RPCs gate on manage_platform (uniform read/write gate — no SECDEF privilege asymmetry)
  const writes = sql.match(/can_by_member\(v_member\.id, '(\w+)'\)/g) || [];
  assert.ok(writes.every((w) => w.includes("'manage_platform'")), 'all binding RPCs must gate on manage_platform');
});

test('PR-2 migration: trigger has OF-columns + WHEN clause (fires only on the lock transition)', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  assert.match(
    sql,
    /CREATE TRIGGER trg_propagate_version_change_class\s+AFTER UPDATE OF locked_at, change_class ON public\.document_versions\s+FOR EACH ROW\s+WHEN \(OLD\.locked_at IS NULL AND NEW\.locked_at IS NOT NULL AND NEW\.change_class IS NOT NULL\)/,
    'trigger must fire only on the lock transition with a resolved change_class',
  );
});

test('PR-2 migration: editorial branch is append-only + FOR UPDATE; material flags re_anchor (no pin move)', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  const fn = sql.match(/CREATE OR REPLACE FUNCTION public\.trg_propagate_version_change_class[\s\S]*?\$function\$;/);
  assert.ok(fn, 'trigger function must exist');
  // editorial: cursor uses FOR UPDATE (serializes concurrent editorial locks) + supersede-then-insert
  assert.match(fn[0], /WHERE referenced_document_id = NEW\.document_id AND status = 'active'\s+FOR UPDATE/);
  assert.match(fn[0], /SET status = 'superseded'/);
  // material: sets re_anchor_required, NOT a new pin
  assert.match(fn[0], /SET re_anchor_required = true, last_material_version_id = NEW\.id/);
  // both branches write the audit channel (ciência 12.3, SPEC §9.3)
  assert.match(fn[0], /instrument_binding\.auto_advanced/);
  assert.match(fn[0], /instrument_binding\.material_reanchor_flagged/);
});

test('PR-2 migration: reanchor requires pin advancement (rejects same-version re-anchor)', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  const fn = sql.match(/CREATE OR REPLACE FUNCTION public\.reanchor_instrument_binding[\s\S]*?\$function\$;/);
  assert.ok(fn, 'reanchor function must exist');
  assert.match(fn[0], /FOR UPDATE/, 'reanchor must lock the old binding row (§9.3 concurrency)');
  assert.match(fn[0], /IF p_new_version_id = v_old\.pinned_version_id THEN/, 're-anchor must reject same-version (Termo 15.4.1)');
});

test('PR-2 migration: backfill + self-verifying guard (4 coop->policy bindings) + NOTIFY pgrst', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  assert.match(sql, /INSERT INTO public\.instrument_version_bindings[\s\S]*?FROM public\.governance_documents agr\s+CROSS JOIN public\.governance_documents pol/);
  assert.match(sql, /expected 4 active cooperation_agreement->policy bindings, found %/);
  assert.match(sql, /NOTIFY pgrst, 'reload schema'/);
});

test('PR-2 migration: AN invariant added + gated on a ratified cooperation_addendum (legal review)', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  assert.match(sql, /'AN_no_dynamic_remission_cooperation'::text/);
  // dormant until a cooperation_addendum ratifies (status='active') — anticipatory pin pre-ratification
  assert.match(
    sql,
    /addn\.doc_type = 'cooperation_addendum' AND addn\.status = 'active'/,
    'AN must be gated on an active (ratified) cooperation_addendum',
  );
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
async function select(path) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` },
  });
  if (!res.ok) throw new Error(`select ${path} failed: HTTP ${res.status} — ${await res.text()}`);
  return res.json();
}

test('backfill: exactly 4 active bindings, each agreement->policy pinned to the policy head', { skip: !canRun && skipMsg }, async () => {
  const [pol] = await select('governance_documents?doc_type=eq.policy&select=id,current_version_id');
  assert.ok(pol, 'one policy doc must exist');
  const agreements = await select('governance_documents?doc_type=eq.cooperation_agreement&status=eq.active&select=id');
  const agreementIds = new Set(agreements.map((a) => a.id));
  const bindings = await select('instrument_version_bindings?status=eq.active&select=bound_document_id,referenced_document_id,pinned_version_id,re_anchor_required');
  assert.equal(bindings.length, 4, 'exactly 4 active bindings');
  for (const b of bindings) {
    assert.equal(b.referenced_document_id, pol.id, 'each binding references the policy doc');
    assert.equal(b.pinned_version_id, pol.current_version_id, 'each binding pins the policy head (v2.7-p128)');
    assert.equal(b.re_anchor_required, false, 'fresh backfill pins are not flagged for re-anchor');
    assert.ok(agreementIds.has(b.bound_document_id), 'each binding is bound to an active cooperation_agreement');
  }
  assert.equal(new Set(bindings.map((b) => b.bound_document_id)).size, 4, 'one binding per distinct agreement');
});

test('check_schema_invariants: AN present, dormant (count 0), and 0 total violations', { skip: !canRun && skipMsg }, async () => {
  const { ok, json, text } = await rpc('check_schema_invariants', {});
  assert.ok(ok, `check_schema_invariants must run: ${text}`);
  const an = json.find((r) => r.invariant_name === 'AN_no_dynamic_remission_cooperation');
  assert.ok(an, 'AN_no_dynamic_remission_cooperation must be registered');
  assert.equal(an.severity, 'high');
  assert.equal(an.violation_count, 0, 'AN must be 0 (dormant: cooperation_addendum under_review; or all agreements pinned)');
  assert.equal(json.filter((r) => r.violation_count > 0).length, 0, 'no invariant may be violated');
});

test('binding RPCs enforce auth (no member context => denied)', { skip: !canRun && skipMsg }, async () => {
  // service_role has no auth.uid()/member row => the manage_platform-gated RPCs must refuse.
  const r = await rpc('list_stale_instrument_bindings', {});
  assert.equal(r.ok, false, 'list_stale_instrument_bindings must reject a call with no authenticated member');
});
