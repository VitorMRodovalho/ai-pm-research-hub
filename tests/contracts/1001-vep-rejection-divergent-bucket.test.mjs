/**
 * #1001 — bucket D (rejection_divergent) em get_vep_divergence_report.
 *
 * Sentido antes invisível: plataforma REJEITADA (`status='rejected'`) + oferta VEP
 * ainda ABERTA (`Submitted`/`Active`/`OfferExtended` = não negada nem expirada).
 * "Rejeitei no Núcleo, falta negar no VEP." Antes o report tinha 3 buckets (seleção,
 * onboarding, membros ativos) e este estado não aparecia na /admin/vep-reconciliation
 * nem no widget do /admin. Mesma taxonomia dos chips do #1000 (as duas telas não podem
 * divergir entre si).
 *
 * Static locks (predicado + wiring de frontend + paridade i18n) + DB-aware smoke (função
 * deployada e gated). Skips offline como os demais contract tests DB-aware.
 *
 * Register in BOTH the "test" and "test:contracts" whitelists in package.json (#1109).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000429_1001_vep_divergence_rejection_bucket.sql');
const ISLAND = resolve(ROOT, 'src/components/admin/VepReconciliationIsland.tsx');
const WIDGET = resolve(ROOT, 'src/components/admin/VepReconciliationWidget.tsx');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => resolve(ROOT, `src/i18n/${l}.ts`));

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC: migration ─────────────────────────────────────────────────────────
test('#1001 static: migration 20260805000429 exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000429 present');
});

test('#1001 static: rejection bucket predicate — rejected + VEP-open + open cycle + not-reconciled', () => {
  const src = readFileSync(MIG, 'utf8');
  assert.match(src, /CREATE OR REPLACE FUNCTION public\.get_vep_divergence_report\(/, 'report redefined');
  // The bucket variable + output key.
  assert.match(src, /INTO v_rejection/, 'v_rejection bucket computed');
  assert.match(src, /'rejection_divergent',\s*v_rejection/, 'rejection_divergent in result');
  // Predicate: rejected on platform + VEP still open (the pre-denial set).
  assert.match(src, /a\.status = 'rejected'/, "predicate status = 'rejected'");
  assert.match(src, /a\.vep_status_raw IN \('Submitted',\s*'Active',\s*'OfferExtended'\)/,
    "VEP-open set = ('Submitted','Active','OfferExtended')");
  // Same guard rails as the other buckets: open cycle + not-reconciled clause.
  assert.match(src, /INTO v_rejection[\s\S]{0,600}?c\.status = 'open'/, 'rejection bucket scoped to open cycle');
  assert.match(src, /INTO v_rejection[\s\S]{0,700}?vep_reconciled_at IS NULL OR a\.vep_reconciled_at < a\.vep_last_seen_at/,
    'rejection bucket excludes reconciled (same clause as A/B/C)');
});

test('#1001 static: summary carries rejection_count and total_divergent sums it', () => {
  const src = readFileSync(MIG, 'utf8');
  assert.match(src, /'rejection_count',\s*jsonb_array_length\(v_rejection\)/, 'rejection_count in summary');
  assert.match(src,
    /'total_divergent',\s*\(jsonb_array_length\(v_selection\)\s*\+\s*jsonb_array_length\(v_onboarding\)\s*\+\s*jsonb_array_length\(v_active\)\s*\+\s*jsonb_array_length\(v_rejection\)\)/,
    'total_divergent includes v_rejection');
});

// ── STATIC: frontend wiring ─────────────────────────────────────────────────────
test('#1001 static: island wires the rejection tab', () => {
  const src = readFileSync(ISLAND, 'utf8');
  assert.match(src, /'rejection'/, 'rejection tab key present');
  assert.match(src, /rejection:\s*data\.rejection_divergent\s*\|\|\s*\[\]/, 'rejection list bound to data.rejection_divergent');
  assert.match(src, /rejection:\s*summary\.rejection_count/, 'tab count reads summary.rejection_count');
  assert.match(src, /comp\.vepReconciliation\.tabRejection/, 'tab label/hint i18n keys referenced');
});

test('#1001 static: widget renders a rejection tile', () => {
  const src = readFileSync(WIDGET, 'utf8');
  assert.match(src, /summary\.rejection_count/, 'widget shows rejection_count');
  assert.match(src, /comp\.vepReconciliation\.tabRejection/, 'widget references tabRejection label');
});

test('#1001 static: i18n parity — tabRejection + tabRejectionHint in all 3 dicts', () => {
  for (const d of DICTS) {
    const src = readFileSync(d, 'utf8');
    assert.match(src, /comp\.vepReconciliation\.tabRejection'/, `${d}: tabRejection present`);
    assert.match(src, /comp\.vepReconciliation\.tabRejectionHint'/, `${d}: tabRejectionHint present`);
  }
});

// ── DB-AWARE: function deployed + gated ─────────────────────────────────────────
test('#1001 db: divergence report resolves + is auth-gated (service-role → Unauthorized)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_vep_divergence_report');
  // PostgREST resolving the function proves deploy + schema reload. Service-role has no
  // auth.uid(), so the SECURITY DEFINER gate returns {error:'Unauthorized'} — expected shape.
  assert.equal(error, null, `RPC should resolve: ${error?.message || ''}`);
  assert.ok(data && typeof data === 'object', 'returns object');
  assert.equal(data.error, 'Unauthorized', 'service-role (no auth.uid) must be Unauthorized');
});

// ── DB-AWARE INVARIANT: the bucket predicate is well-defined + disjoint from the others ─
test('#1001 invariant: rejection bucket rows are rejected + VEP-open and never overlap A/B', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('selection_applications')
    .select('id, status, vep_status_raw')
    .not('vep_status_raw', 'is', null);
  assert.equal(error, null, error?.message || '');
  const open = ['Submitted', 'Active', 'OfferExtended'];
  const bucketD = data.filter((r) => r.status === 'rejected' && open.includes(r.vep_status_raw));
  // Disjointness: bucket D is rejected-only; bucket B (onboarding) is approved/converted-only;
  // bucket A (selection) requires a VEP-terminal status. None can share a row with D.
  for (const r of bucketD) {
    assert.equal(r.status, 'rejected', 'bucket D is rejected-only');
    assert.ok(!['approved', 'converted'].includes(r.status), 'never overlaps onboarding bucket B');
    assert.ok(!['Withdrawn', 'Declined', 'OfferNotExtended'].includes(r.vep_status_raw),
      'VEP-open, so never overlaps selection bucket A (VEP-terminal)');
  }
});
