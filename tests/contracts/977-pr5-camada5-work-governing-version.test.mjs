// tests/contracts/977-pr5-camada5-work-governing-version.test.mjs
//
// #977 (PR-5 of #571) — Camada 5 Material-change backbone: AUDIT-TRAIL POR OBRA
// + VERSÃO REGENTE (WA4 — Termo 15.4.1 regra + 15.4.7 ledger + 15.4.6 tie-break).
//
// Guards: the polymorphic table + RLS (permissive + RESTRICTIVE AJ confidential gate
// + RESTRICTIVE org-scope), the partial-unique active stamp, work_type WITHOUT
// publication_submission, the D1 nullability split (Política NOT NULL = dormancy gate,
// Termo NULLABLE = tie-break fallback), the dormancy RAISE + deterministic count-guard,
// the tie-break by signed_at, the write-once trigger (protects id, blocks DELETE, allows
// superseded_by_id, NOT SECURITY DEFINER), the deferrable supersede FK, the cross-org
// guard in get_, the org-NULLABLE knowledge_asset path, and the SECDEF REVOKEs. The full
// behavior is additionally verified by the apply-time smoke (DO + RAISE rollback).
//
// Two layers:
//   (A) Static — parses the migration file; always runs (no DB).
//   (B) DB-aware — calls live RPCs; SKIPPED without SUPABASE_URL + SERVICE_ROLE_KEY.
//
// SPEC: docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md §5 PR-5 + §9.6 + §4. ADR-0117.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(
  __dirname,
  '../../supabase/migrations/20260805000305_977_pr5_camada5_work_governing_version.sql',
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

test('PR-5: table created with RLS + 3 policies (permissive read + RESTRICTIVE AJ confidential + RESTRICTIVE org-scope)', () => {
  assert.match(sql, /CREATE TABLE IF NOT EXISTS public\.work_governing_version/);
  assert.match(sql, /ALTER TABLE public\.work_governing_version ENABLE ROW LEVEL SECURITY/);
  assert.match(sql, /CREATE POLICY wgv_read ON public\.work_governing_version[\s\S]*?FOR SELECT TO authenticated/);
  // confidential gate (ADR-0105) — RESTRICTIVE, via the polymorphic helper
  assert.match(sql, /CREATE POLICY "AJ_wgv_confidential_visibility"[\s\S]*?AS RESTRICTIVE[\s\S]*?rls_can_see_initiative\(public\._work_initiative_id\(work_type, work_id\)\)/);
  // org-scope RESTRICTIVE — R1: the `OR organization_id IS NULL` clause is load-bearing under M0
  assert.match(sql, /CREATE POLICY wgv_org_scope[\s\S]*?AS RESTRICTIVE[\s\S]*?organization_id = public\.auth_org\(\) OR organization_id IS NULL/);
});

test('PR-5: work_type CHECK has the 5 live types and does NOT include publication_submission (§9.6 double-stamp)', () => {
  for (const t of ['content_product', 'tribe_deliverable', 'event_showcase', 'public_publication', 'knowledge_asset']) {
    assert.match(sql, new RegExp(`^\\s*'${t}'`, 'm'), `work_type '${t}' must be a live CHECK entry`);
  }
  // publication_submission may appear only in the "REMOVIDO" comment (prefixed by `-- `), never as a live entry
  assert.doesNotMatch(sql, /^\s*'publication_submission'/m, 'publication_submission must not be a live work_type');
});

test('PR-5: D1 nullability split — Política NOT NULL (dormancy gate); Termo NULLABLE (tie-break fallback)', () => {
  assert.match(sql, /governing_politica_version_id uuid NOT NULL REFERENCES public\.document_versions\(id\)/);
  assert.doesNotMatch(sql, /governing_termo_version_id uuid NOT NULL/, 'governing_termo_version_id must be NULLABLE (D1)');
  assert.match(sql, /governing_termo_version_id uuid REFERENCES public\.document_versions\(id\)/);
  // M0: organization_id is NULLABLE (knowledge_asset is org-agnostic)
  assert.match(sql, /^\s*organization_id uuid,/m, 'organization_id must be NULLABLE (M0)');
  assert.doesNotMatch(sql, /organization_id uuid NOT NULL/, 'organization_id must not be NOT NULL (M0)');
});

test('PR-5: partial-unique active stamp + deferrable supersede FK (M3)', () => {
  assert.match(sql, /CREATE UNIQUE INDEX IF NOT EXISTS wgv_active_unique[\s\S]*?WHERE superseded_by_id IS NULL/);
  assert.match(sql, /superseded_by_id uuid REFERENCES public\.work_governing_version\(id\) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED/);
});

test('PR-5: write-once trigger protects id (M2), blocks DELETE, allows superseded_by_id, NOT SECURITY DEFINER (M8)', () => {
  const trg = fn('trg_work_governing_version_immutable');
  assert.match(trg, /NEW\.id IS DISTINCT FROM OLD\.id/, 'trigger must guard the PK id (M2)');
  assert.match(trg, /TG_OP = 'DELETE'/, 'trigger must block DELETE (write-once)');
  assert.match(trg, /nunca DELETE/);
  // superseded_by_id is the ONLY mutable business column => it must NOT appear in the immutability IF
  assert.doesNotMatch(trg, /NEW\.superseded_by_id IS DISTINCT FROM OLD\.superseded_by_id/, 'superseded_by_id must remain mutable (retificação chain)');
  assert.doesNotMatch(trg, /SECURITY DEFINER/, 'pure trigger must not be SECURITY DEFINER (M8)');
  assert.match(sql, /BEFORE UPDATE OR DELETE ON public\.work_governing_version/);
});

test('PR-5: stamp — dormancy RAISE + deterministic count-guard (M6); tie-break by signed_at (M7); cross-org guard (M12); v_first RAISE (M11)', () => {
  const stamp = fn('stamp_work_governing_version');
  assert.match(stamp, /dormant: a Politica de PI ainda nao foi ratificada/);
  assert.match(stamp, /status <> 'superseded'/, 'dormancy gate must filter superseded (deterministic, M6)');
  assert.match(stamp, /ambiguo ou ausente/, 'count-guard must reject !=1 active policy doc (M6)');
  // tie-break 15.4.6 by signed_at (the act of signing), NEVER is_current
  assert.match(stamp, /COALESCE\(mds\.signed_at, mds\.created_at\) <= v_first/);
  assert.doesNotMatch(stamp, /mds\.is_current/, 'tie-break must NOT use is_current at stamp-time');
  // termo resolved by doc_type JOIN (2 volunteer_term_template docs exist)
  assert.match(stamp, /JOIN public\.governance_documents gd ON gd\.id = mds\.document_id AND gd\.doc_type = 'volunteer_term_template'/);
  // M11: anchor RAISE instead of silent now()
  assert.match(stamp, /first_material_contribution_at obrigatorio para obras sem created_at/);
  // M12: cross-org stamp guard
  assert.match(stamp, /nao pertence a org do caller/);
  // M1: event_showcase org via events (es has no organization_id)
  assert.match(stamp, /JOIN public\.events e ON e\.id = es\.event_id/);
});

test('PR-5: attribution_text bifurcates on requires_review — never asserts a Termo that does not exist (M5)', () => {
  const stamp = fn('stamp_work_governing_version');
  assert.match(stamp, /Termo de Voluntariado NAO verificado/, 'requires_review branch must NOT assert a Termo');
  assert.match(stamp, /e o Termo de Voluntariado \(versao/, 'verified branch must embed the real Termo label');
  // real labels are looked up (self-contained snapshot)
  assert.match(stamp, /SELECT version_label INTO v_pol_label/);
});

test('PR-5: get_work_governing_version — ADR-0105 confidential gate + cross-org PII guard (M4)', () => {
  const get = fn('get_work_governing_version');
  assert.match(get, /rls_can_see_initiative\(public\._work_initiative_id\(p_work_type, p_work_id\)\)/, 'reader must apply the confidential gate');
  assert.match(get, /v_row\.organization_id IS DISTINCT FROM public\.auth_org\(\)/, 'reader must reapply tenancy (SECDEF bypasses RLS, M4)');
});

test('PR-5: _work_initiative_id polymorphic helper covers all 5 types (event via events; knowledge_asset NULL, M10)', () => {
  const h = fn('_work_initiative_id');
  assert.match(h, /WHEN 'event_showcase'[\s\S]*?JOIN public\.events e ON e\.id = es\.event_id/);
  assert.match(h, /WHEN 'knowledge_asset'\s+THEN v_init := NULL/);
  // M10: no v_init leftover in the stamp RPC (initiative resolved at read-time, not stored).
  // Target the DECLARE/usage, NOT the documenting comment ("sem v_init") — regex-fragility lesson (PR-4).
  const stamp = fn('stamp_work_governing_version');
  assert.doesNotMatch(stamp, /\bv_init uuid;/, 'stamp must not declare v_init (dead code, M10)');
  assert.doesNotMatch(stamp, /INTO[^\n;]*\bv_init\b/, 'stamp must not SELECT INTO v_init (dead code, M10)');
});

test('PR-5: every SECDEF REVOKEs PUBLIC + anon', () => {
  for (const f of [
    '_work_initiative_id\\(text, uuid\\)',
    'stamp_work_governing_version\\(text, uuid, uuid, timestamptz, jsonb\\)',
    'get_work_governing_version\\(text, uuid\\)',
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

test('live: check_schema_invariants — 0 violations after PR-5', { skip: !canRun && skipMsg }, async () => {
  const { ok, json, text } = await rpc('check_schema_invariants', {});
  assert.ok(ok, `check_schema_invariants must run: ${text}`);
  assert.equal(json.filter((r) => r.violation_count > 0).length, 0, 'no invariant may be violated');
});

test('live: the stamp ledger is dormant — 0 rows', { skip: !canRun && skipMsg }, async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/work_governing_version?select=id`, {
    headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}`, Prefer: 'count=exact', Range: '0-0' },
  });
  const cr = res.headers.get('content-range') || '';
  assert.match(cr, /\/0$/, `work_governing_version must be empty (dormant); content-range=${cr}`);
});

test('live: stamp/get auth-gate fires for a caller with no member (no leak)', { skip: !canRun && skipMsg }, async () => {
  // service_role has no auth.uid() member => both RPCs must error (not silently insert / not leak a row)
  const stamp = await rpc('stamp_work_governing_version', { p_work_type: 'content_product', p_work_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(!stamp.ok, 'stamp must reject a caller with no member record');
  const get = await rpc('get_work_governing_version', { p_work_type: 'content_product', p_work_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(!get.ok, 'get must reject a caller with no member record');
});
