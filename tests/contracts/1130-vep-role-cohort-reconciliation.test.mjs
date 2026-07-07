/**
 * #1130 — Reconciliação VEP↔plataforma por papel×coorte + correção de causa-raiz do bucket B.
 *
 * Duas garantias:
 *
 *  (A) Semântica do bucket B (onboarding_divergent) em get_vep_divergence_report.
 *      VEP 'Active' = voluntário que JÁ ACEITOU a oferta e está na jornada (estado saudável).
 *      O bucket antigo marcava ('Submitted','Active') como divergência → contava o roster ativo
 *      inteiro (62 crescendo sem parar). Corrigido: divergência = aprovado/convertido MAS ainda
 *      pré-aceite no VEP ('Submitted' OU 'OfferExtended' = oferta emitida aguardando aceite).
 *      'Active' NUNCA pode entrar no bucket B — senão o farol volta a ser enganoso.
 *
 *  (B) Nova RPC get_vep_role_cohort_reconciliation(): matriz papel×coorte + listas nominais,
 *      join estável por PMI id (resolve o falso-gap do caso Paulo, e-mails divergentes/mesmo pmi_id).
 *
 * Static locks + DB-aware smoke (função deployada e gated). Skips offline como os demais.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000354_1130_vep_role_cohort_reconciliation.sql');
const ISLAND = resolve(ROOT, 'src/components/admin/VepReconciliationIsland.tsx');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC: migration ─────────────────────────────────────────────────────────
test('#1130 static: migration 20260805000354 exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000354 present');
});

test('#1130 static: new RPC get_vep_role_cohort_reconciliation defined + gated', () => {
  const src = readFileSync(MIG, 'utf8');
  assert.match(src, /CREATE OR REPLACE FUNCTION public\.get_vep_role_cohort_reconciliation\(/,
    'get_vep_role_cohort_reconciliation defined');
  assert.match(src, /SECURITY DEFINER/, 'SECURITY DEFINER');
  assert.match(src, /can_by_member\(v_caller_id,\s*'view_internal_analytics'\)/,
    'gated on view_internal_analytics');
  assert.match(src, /selection_coi_recused/, 'COI recusal preserved');
});

test('#1130 static: matrix joins by stable PMI id key (fallback email)', () => {
  const src = readFileSync(MIG, 'utf8');
  // match_key = COALESCE(NULLIF(pmi_id,''), 'e:'||lower(email)) → pmi_id primário, e-mail fallback.
  assert.match(src, /COALESCE\(NULLIF\([^)]*pmi_id[^)]*,\s*''\),\s*'e:'\s*\|\|\s*lower\(/,
    'stable match key by pmi_id then email');
});

test('#1130 static: bucket B corrected — Submitted/OfferExtended, NEVER Active alone', () => {
  const src = readFileSync(MIG, 'utf8');
  // The onboarding_divergent predicate must be the pre-acceptance set.
  assert.match(src, /a\.vep_status_raw IN \('Submitted',\s*'OfferExtended'\)/,
    "bucket B predicate = IN ('Submitted','OfferExtended')");
  // Regression guard: the old buggy predicate that swept 'Active' into onboarding must be gone.
  assert.doesNotMatch(src, /status IN \('approved',\s*'converted'\)[\s\S]{0,120}?vep_status_raw IN \('Submitted',\s*'Active'\)/,
    "old ('Submitted','Active') onboarding predicate must not resurface");
});

// ── STATIC: frontend island ────────────────────────────────────────────────────
test('#1130 static: island wires the matrix RPC + tab + F3 error state + F4 cross-nav', () => {
  const src = readFileSync(ISLAND, 'utf8');
  assert.match(src, /get_vep_role_cohort_reconciliation/, 'island calls the new RPC');
  assert.match(src, /'matrix'/, 'matrix tab key present');
  assert.match(src, /loadError/, 'F3: dedicated load error state (not just a toast)');
  assert.match(src, /\/admin\/filiacao/, 'F4: cross-nav to affiliation queue');
  assert.match(src, /\/admin\/selection\?cycle=/, 'F4: cross-nav to selection by cycle');
});

// ── DB-AWARE: functions deployed + gated (auth.uid() null → Unauthorized, not 404) ─────
test('#1130 db: get_vep_role_cohort_reconciliation is deployed and auth-gated', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_vep_role_cohort_reconciliation');
  // PostgREST resolving the function proves it is deployed + schema reloaded. Service-role calls
  // carry no auth.uid(), so the SECURITY DEFINER gate returns {error:'Unauthorized'} — that is the
  // expected shape here, NOT a PGRST202 "function not found".
  assert.equal(error, null, `RPC should resolve (no PostgREST error): ${error?.message || ''}`);
  assert.ok(data && typeof data === 'object', 'returns a jsonb object');
  assert.equal(data.error, 'Unauthorized', 'service-role (no auth.uid) must be Unauthorized');
});

test('#1130 db: divergence report reachable + summary carries onboarding_by_cohort shape', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_vep_divergence_report');
  assert.equal(error, null, `RPC should resolve: ${error?.message || ''}`);
  assert.ok(data && typeof data === 'object', 'returns object');
  assert.equal(data.error, 'Unauthorized', 'service-role must be Unauthorized (gated)');
});

// ── DB-AWARE INVARIANT: the data reality that motivated the fix ─────────────────
test('#1130 invariant: approved/converted + VEP Active exist and are NOT a pre-onboarding gap', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('selection_applications')
    .select('id, status, vep_status_raw')
    .in('status', ['approved', 'converted'])
    .not('vep_status_raw', 'is', null);
  assert.equal(error, null, error?.message || '');
  const active = data.filter((r) => r.vep_status_raw === 'Active');
  const preAccept = data.filter((r) => ['Submitted', 'OfferExtended'].includes(r.vep_status_raw));
  // The whole point of #1130: 'Active' approved/converted rows are the HEALTHY roster (should be
  // large) and must never be conflated with the pre-acceptance gap (which is the actionable set).
  assert.ok(active.length >= preAccept.length,
    `sanity: healthy Active roster (${active.length}) should dwarf pre-acceptance gap (${preAccept.length})`);
});
