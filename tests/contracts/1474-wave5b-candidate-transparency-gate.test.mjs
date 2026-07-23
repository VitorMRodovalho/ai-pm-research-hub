// tests/contracts/1474-wave5b-candidate-transparency-gate.test.mjs
//
// Onda 5b (arco de auditoria pontuacao/merito, umbrella #1465): transparencia do candidato pos-decisao.
// Policy ratificada pelo owner (2026-07-23): candidato APROVADO/CONVERTIDO ve seu breakdown por criterio
// SOMENTE apos o anuncio (fase 'announcement'); candidato REJEITADO (ou qualquer status nao-selecionado)
// ve SO "nao selecionado", sem breakdown numerico. A politica e imposta na FONTE (RPC) e alcanca web + MCP.
// Notas/scores por-avaliador NUNCA sao expostos por auto-servico (reservados ao canal formal Art. 18).
//
// Comportamento (aprovado ve breakdown / rejeitado ve null) foi verificado por impersonacao (set_config
// request.jwt.claims) em QA manual desta sessao contra cycle3-2026 (announcement) -- supabase-js nao seta
// jwt.claims + chama a RPC numa transacao (ver nota em 1326-my-meetings-audience-scope). Este guard e
// ESTRUTURAL (migration + UI) + graceful DB-gated, prevenindo REGRESSAO do gate.
//
// To fix a structural failure: the gate predicate was removed/loosened -- restore it.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = readFileSync(
  resolve(ROOT, 'supabase/migrations/20260805000483_wave5b_candidate_transparency_gate.sql'),
  'utf8'
);
const PAGE = readFileSync(resolve(ROOT, 'src/pages/minha-candidatura.astro'), 'utf8');
const stripComments = (s) => s.replace(/--[^\n]*/g, '');
const CODE = stripComments(MIG);

const RE_SEL = /CREATE OR REPLACE FUNCTION public\.get_my_selection_result\b/;
const RE_FB = /CREATE OR REPLACE FUNCTION public\.get_my_evaluation_feedback\b/;

// ── (A) migration redeclares both self-service RPCs ──────────────────────────────
test('#1474: migration redeclares get_my_selection_result + get_my_evaluation_feedback', () => {
  assert.match(CODE, RE_SEL, 'get_my_selection_result must be redeclared');
  assert.match(CODE, RE_FB, 'get_my_evaluation_feedback must be redeclared');
});

// ── (B) breakdown/rank gated by approved|converted AND announcement (source-side) ─
test('#1474: get_my_selection_result gates breakdown by approved/converted AND announcement', () => {
  // The reveal predicate must couple status AND phase; a status-only gate would leak scores pre-announcement.
  assert.match(
    CODE,
    /a\.status = ANY\(ARRAY\['approved','converted'\]\) AND sc\.phase = 'announcement'/,
    'breakdown reveal must require approved/converted AND phase=announcement'
  );
  // reveal_breakdown flag surfaced so the client renders without re-deriving the policy.
  assert.match(CODE, /as reveal_breakdown\b/, 'reveal_breakdown flag must be exposed');
  // own_evaluations_sample (per-evaluator sample) removed -- de-anonymizing + not the aggregate.
  assert.ok(
    !/own_evaluations_sample/.test(CODE),
    'own_evaluations_sample must be removed (per-evaluator leak)'
  );
});

// ── (C) evaluation_feedback: numeric gated to approved/converted; evaluator notes gone ─
test('#1474: get_my_evaluation_feedback gates scores + drops per-evaluator notes/array', () => {
  assert.match(
    CODE,
    /v_reveal_scores\s*:?=\s*v_app\.status = ANY\(ARRAY\['approved','converted'\]\)/,
    'numeric scores must be gated to approved/converted'
  );
  assert.match(CODE, /WHEN v_reveal_scores THEN v_app\.objective_score_avg/, 'objective score must honor the gate');
  // The per-evaluator array (with e.notes) must NOT be returned by self-service anymore.
  assert.ok(!/'evaluations',\s*v_evals/.test(CODE), "per-evaluator 'evaluations' array must be removed");
  assert.ok(!/\be\.notes\b/.test(CODE), 'evaluator free-text notes (e.notes) must not be selected');
  // Qualitative narrative feedback stays (must NOT be regressed).
  assert.match(CODE, /'narrative_feedback',\s*v_app\.feedback/, 'narrative feedback must remain available');
});

// ── (D) regression guard vs #511: alt-email UNION + auth.uid() gate retained ──────
test('#1474: both RPCs keep the #511 alt-email UNION and the auth.uid() caller gate', () => {
  const altUnion = CODE.match(/FROM public\.member_emails me\s+WHERE me\.member_id = v_caller\.id/g) || [];
  assert.ok(altUnion.length >= 2, `expected >=2 alt-email UNION clauses, found ${altUnion.length}`);
  const gates = CODE.match(/WHERE auth_id = auth\.uid\(\)/g) || [];
  assert.ok(gates.length >= 2, `expected >=2 auth.uid() caller gates, found ${gates.length}`);
});

// ── (E) UI respects the server gate (renders breakdown only on reveal_breakdown) ──
test('#1474: minha-candidatura.astro consumes get_my_selection_result and honors reveal_breakdown', () => {
  assert.match(PAGE, /get_my_selection_result/, 'page must fetch get_my_selection_result');
  assert.match(PAGE, /reveal_breakdown === true/, 'page must render breakdown only when reveal_breakdown===true');
});

// ── (F) DB-gated: both RPCs live and gate gracefully for service-role (no throw) ──
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1474 DB: both RPCs live; service-role (auth.uid null) returns not_authenticated', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  for (const fn of ['get_my_selection_result', 'get_my_evaluation_feedback']) {
    const { data, error } = await sb.rpc(fn);
    assert.ok(!error, `${fn} must not throw for service-role: ${error?.message}`);
    assert.strictEqual(data?.error, 'not_authenticated', `${fn} should return not_authenticated jsonb`);
  }
});
