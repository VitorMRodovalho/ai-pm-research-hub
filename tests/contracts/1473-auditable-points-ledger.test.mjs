/**
 * #1473 Onda 5a — "Minha Pontuação, auditável" (painel de ledger fato-a-fato).
 *
 * Migration 20260805000482:
 *   - _points_statement_json(member,org,scope,...) — helper INTERNO (SECDEF,
 *     revogado de TODOS os roles) que constrói o extrato. Self e admin passam a
 *     compartilhá-lo → fatos byte-idênticos (crítico p/ auditabilidade).
 *   - get_my_points_statement(text,text,integer,integer) — MESMA assinatura
 *     self-only (SEM p_member_id: o guard anti-IDOR do #1087 wave1 continua).
 *   - get_member_points_ledger(p_member_id,...) — NOVO, gate view_pii + chapter
 *     scope (espelha get_member_cycle_xp). Superfície admin ?member=.
 *   - Cada linha de fato expõe occurred_at (data DO FATO) + o ciclo a que pertence
 *     (resolvido pela janela que contém effective_at) — responde "de onde vêm e
 *     em qual ciclo" (o caso Jefferson).
 *
 * Frontend: página dedicada /minha-pontuacao (+ /en /es), nav item, i18n 3 dicts.
 * Todas as asserções rodam OFFLINE (sem DB env).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');

const MIG = read('../../supabase/migrations/20260805000482_1473_wave5a_auditable_points_ledger.sql');
const NAV = read('../../src/lib/navigation.config.ts');
const DICTS = {
  'pt-BR': read('../../src/i18n/pt-BR.ts'),
  'en-US': read('../../src/i18n/en-US.ts'),
  'es-LATAM': read('../../src/i18n/es-LATAM.ts'),
};

// ── Backend: internal helper is not directly callable (no IDOR via helper) ──
test('1473: _points_statement_json is internal-only (revoked from every role)', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\._points_statement_json\(/, 'helper defined');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._points_statement_json\(uuid, uuid, text, text, integer, integer\) FROM public, anon, authenticated;/, 'helper revoked from public, anon AND authenticated — no direct IDOR surface');
  assert.doesNotMatch(MIG, /GRANT EXECUTE ON FUNCTION public\._points_statement_json/, 'helper granted to NO role (called only by SECDEF wrappers)');
});

// ── Backend: self statement keeps the anti-IDOR guard (no p_member_id) ──
test('1473: get_my_points_statement stays self-only, same signature, no p_member_id', () => {
  const idx = MIG.indexOf('CREATE FUNCTION public.get_my_points_statement(');
  assert.notEqual(idx, -1, 'self statement (re)defined via DROP+CREATE');
  assert.match(MIG, /DROP FUNCTION IF EXISTS public\.get_my_points_statement\(text, text, integer, integer\);/, 'DROP before CREATE (signature preserved)');
  const stmt = MIG.slice(idx, MIG.indexOf('CREATE OR REPLACE FUNCTION public.get_member_points_ledger('));
  assert.doesNotMatch(stmt, /p_member_id/, 'NO p_member_id in the self statement — anti-IDOR guard preserved');
  assert.match(stmt, /WHERE m\.auth_id = auth\.uid\(\)/, 'caller derived from auth.uid()');
  assert.match(stmt, /RETURN public\._points_statement_json\(v_member_id, v_org_id,/, 'delegates to the shared helper (identical facts vs admin path)');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.get_my_points_statement\(text, text, integer, integer\) FROM public, anon;/, 'revoke public/anon');
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.get_my_points_statement\(text, text, integer, integer\) TO authenticated;/, 'grant authenticated');
});

// ── Backend: admin cross-member ledger is properly gated ──
test('1473: get_member_points_ledger gates cross-member reads (view_pii + chapter scope)', () => {
  const idx = MIG.indexOf('CREATE OR REPLACE FUNCTION public.get_member_points_ledger(');
  assert.notEqual(idx, -1, 'admin ledger defined');
  const fn = MIG.slice(idx);
  assert.match(fn, /p_member_id uuid/, 'takes an explicit member id');
  assert.match(fn, /IF p_member_id = v_caller_id THEN\s+RETURN public\._points_statement_json\(v_caller_id/, 'self short-circuit → same helper as get_my_points_statement');
  assert.match(fn, /IF NOT public\.can_by_member\(v_caller_id, 'view_pii'\) THEN\s+RAISE EXCEPTION 'Unauthorized'/, 'cross-member requires view_pii (fail-closed)');
  assert.match(fn, /public\.caller_chapter_scope\(\)/, 'chapter scope enforced (no out-of-chapter reads)');
  assert.match(fn, /IF v_target_org <> v_caller_org THEN\s+RAISE EXCEPTION 'Unauthorized'/, 'org boundary enforced');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.get_member_points_ledger\(uuid, text, text, integer, integer\) FROM public, anon;/, 'revoke public/anon');
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.get_member_points_ledger\(uuid, text, text, integer, integer\) TO authenticated;/, 'grant authenticated');
});

// ── Backend: the core 5a value — occurred_at + per-fact cycle attribution ──
test('1473: each fact exposes occurred_at (data do fato) + the cycle it belongs to', () => {
  assert.match(MIG, /'occurred_at', e\.occurred_at/, 'occurred_at exposed per entry (not just created_at)');
  assert.match(MIG, /'effective_at', e\.effective_at/, 'effective_at = COALESCE(occurred_at, created_at)');
  assert.match(MIG, /'cycle_code', e\.fact_cycle_code/, 'cycle_code resolved per fact');
  assert.match(MIG, /'cycle_label', e\.fact_cycle_label/, 'cycle_label resolved per fact');
  // per-fact cycle = the cycle window that CONTAINS effective_at (independent of query scope)
  assert.match(MIG, /FROM public\.cycles c\s+WHERE COALESCE\(gp\.occurred_at, gp\.created_at\) >= c\.cycle_start::timestamptz/, 'cycle resolved by the window containing the fact date');
  // ordering is by the FACT date, not the attribution date
  assert.match(MIG, /ORDER BY e\.effective_at DESC/, 'entries ordered by effective_at (fact date), not created_at');
});

// ── Frontend: dedicated route + localized redirects exist ──
test('1473: /minha-pontuacao page + /en /es localized redirects exist', () => {
  assert.ok(existsSync(fileURLToPath(new URL('../../src/pages/minha-pontuacao.astro', import.meta.url))), 'PT page exists');
  for (const loc of ['en', 'es']) {
    const p = fileURLToPath(new URL(`../../src/pages/${loc}/minha-pontuacao.astro`, import.meta.url));
    assert.ok(existsSync(p), `${loc}/ redirect page exists`);
    assert.match(readFileSync(p, 'utf8'), /http-equiv="refresh"[^>]*minha-pontuacao/, `${loc}/ redirects to /minha-pontuacao`);
  }
});

// ── Frontend: nav registers the item (SSOT navigation.config.ts) ──
test('1473: navigation.config registers my-points → /minha-pontuacao (member, auth)', () => {
  const line = NAV.split('\n').find((l) => l.includes("key: 'my-points'"));
  assert.ok(line, 'my-points nav item present');
  assert.match(line, /href: '\/minha-pontuacao'/, 'href points to the dedicated route');
  assert.match(line, /labelKey: 'nav\.myPoints'/, 'uses nav.myPoints label');
  assert.match(line, /minTier: 'member'/, 'member tier');
  assert.match(line, /requiresAuth: true/, 'requires auth');
});

// ── i18n: every new key exists in ALL 3 dictionaries (parity) ──
const NEW_KEYS = [
  'nav.myPoints',
  'myPoints.title', 'myPoints.heading', 'myPoints.subtitle', 'myPoints.loading',
  'myPoints.loginRequired', 'myPoints.noPoints', 'myPoints.errorLoad',
  'myPoints.mode.cycle', 'myPoints.mode.lifetime',
  'myPoints.summary.lifetime', 'myPoints.summary.cycle', 'myPoints.summary.rank',
  'myPoints.ptsLabel', 'myPoints.certsLifetimeNote', 'myPoints.export.btn',
  'myPoints.fact.attributedBy', 'myPoints.fact.loggedOn', 'myPoints.fact.reversal',
  'myPoints.fact.championBy', 'myPoints.emptyPillar', 'myPoints.cycleGroup',
  'myPoints.noCycle', 'myPoints.admin.bannerPrefix', 'myPoints.admin.back',
  'myPoints.admin.forbidden', 'profile.auditableCta',
];

test('1473: all new i18n keys exist in pt-BR / en-US / es-LATAM (3-dict parity)', () => {
  for (const [locale, src] of Object.entries(DICTS)) {
    for (const key of NEW_KEYS) {
      assert.ok(src.includes(`'${key}':`), `${locale} missing key ${key}`);
    }
  }
});

// ── House rule: no em/en-dash in the new user-facing strings ──
test('1473: new i18n values contain no em/en-dash (deliverable prose rule)', () => {
  for (const [locale, src] of Object.entries(DICTS)) {
    for (const key of NEW_KEYS) {
      const m = src.match(new RegExp(`'${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}':\\s*'([^']*)'`));
      if (m) assert.ok(!/[—–]/.test(m[1]), `${locale} ${key} has an em/en-dash: ${m[1]}`);
    }
  }
});
