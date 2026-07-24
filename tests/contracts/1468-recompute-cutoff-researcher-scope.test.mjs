/**
 * Contract: #1468 (follow-up do audit A3 / Onda 2 PR #1467) — o corte objetivo por mediana em
 * recompute_application_status passa a ser researcher-only.
 *
 * A Onda 2 (mig 20260805000479) tornou o corte objetivo/research researcher-only em
 * _compute_pert_cutoff_core / get_cutoff_dispatch_health / _selection_cutoff_pending_cron.
 * recompute_application_status ficou de fora: seu cyc_median calculava
 * median(objective_score_avg)*0.75 agrupado SO por cycle_id (sem role_applied), poolando
 * researchers + leaders — o unico caminho remanescente onde um corte pooled cross-role podia
 * setar status='objective_cutoff' num lider.
 *
 * FIX (mig 20260805000489): cyc_median ganha AND role_applied = 'researcher'. Materialidade baixa
 * (nao wired a cron; self-heal manual; in_cutoff=0 hoje) — comportamento preservado HOJE.
 *
 * Static locks o escopo. O DB-gated prova que o dry-run nao muda nada hoje (nenhum lider flipa
 * para objective_cutoff) e que a mediana researcher-only difere da pooled (o escopo importa).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const MIGP = fileURLToPath(new URL('../../supabase/migrations/20260805000489_1468_recompute_cutoff_researcher_scope.sql', import.meta.url));
const migRaw = existsSync(MIGP) ? readFileSync(MIGP, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC ────────────────────────────────────────────────────────────────────────
test('#1468 static: migration file exists + redefines recompute_application_status', () => {
  assert.ok(existsSync(MIGP), 'migration 20260805000489 exists');
  assert.match(migRaw, /CREATE OR REPLACE FUNCTION public\.recompute_application_status\(/, 'redefines recompute_application_status');
});

test('#1468 static: cyc_median is scoped to role_applied = researcher', () => {
  const idx = migRaw.indexOf('cyc_median AS (');
  assert.notEqual(idx, -1, 'cyc_median CTE present');
  const cte = migRaw.slice(idx, migRaw.indexOf('),', idx));
  assert.match(cte, /objective_score_avg IS NOT NULL\s*\n\s*AND role_applied = 'researcher'/i,
    'cyc_median filters role_applied = researcher (aligns A3 researcher-only cutoff)');
});

test('#1468 static: migration notifies PostgREST', () => {
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/i, 'schema reload notified');
});

// ── BEHAVIOURAL (DB-gated) ──────────────────────────────────────────────────────────
test('#1468 behavioural: dry-run changes nothing today (researcher scope is behavior-preserving)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.rpc('recompute_application_status', { p_application_id: null, p_cycle_id: null, p_dry_run: true });
    assert.ifError(error);
    assert.equal(data?.success, true, 'dry-run ok');
    assert.equal(data?.changed, 0, 'no status flips today — no leader dragged into objective_cutoff by a pooled median');
  });

test('#1468 behavioural: no leader currently sits at objective_cutoff (the invariant the scope protects)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.from('selection_applications')
      .select('id').eq('role_applied', 'leader').eq('status', 'objective_cutoff');
    assert.ifError(error);
    assert.equal((data || []).length, 0, 'no leader in objective_cutoff (researcher-only cutoff holds)');
  });
