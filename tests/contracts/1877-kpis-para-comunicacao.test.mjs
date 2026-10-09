// tests/contracts/1877-kpis-para-comunicacao.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
// (DB-aware: the live layer reads the published body through _audit_function_source.)
/**
 * #1877 — the communication team reads the annual KPIs, through the comms gate and nothing wider.
 *
 * Measured 2026-10-08/09: get_annual_kpis answered 'Unauthorized' to a comms member, so the KPI panel of
 * /admin/portfolio vanished in silence for the team the GP had just opened the page to (#2623). The V4 audit found
 * the designation-based comms gate (can_view_comms_analytics) already in place; granting view_aggregate_analytics
 * instead would have opened 12 RPCs (selection, diversity, role transitions).
 *
 * The KPI payload is aggregate except infra_cost_current (monthly infrastructure cost, BRL): it stays with whoever
 * already read it (internal or aggregate analytics); a caller who passes only through the comms gate gets null.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

/** The three facts, read from a function body. */
export function regras(body) {
  const b = maskLineComments(body || '').replace(/\s+/g, ' ');
  return {
    // who already read analytics is the same set as before #1877
    analytics: /v_analytics := v_caller_id IS NOT NULL AND \(public\.can_by_member\(v_caller_id, 'view_internal_analytics'\) OR public\.can_by_member\(v_caller_id, 'view_aggregate_analytics'\)\);/.test(b),
    // the gate admits the comms path, and refusing still raises
    portao: /IF v_caller_id IS NULL OR NOT \(v_analytics OR public\.can_view_comms_analytics\(\)\) THEN RAISE EXCEPTION 'Unauthorized';/.test(b),
    // the financial field is bound to the analytics flag, not to the comms path
    custo: /'infra_cost_current', CASE WHEN NOT v_analytics THEN NULL ELSE \(SELECT COALESCE\(SUM\(ce\.amount_brl\), 0\)/.test(b),
    // and nothing wider was granted
    semAmpliar: !/view_aggregate_analytics[^)]*\)\s*OR\s*true/.test(b),
  };
}

const CAP = latestFunctionCapture(ROOT, 'get_annual_kpis').body;

test('#1877 (capture): KPIs open to the comms gate, infra cost bound to analytics', () => {
  const r = regras(CAP);
  assert.deepEqual(r, Object.fromEntries(Object.keys(r).map((k) => [k, true])));
});

test('#1877 mutation: each detector fails on its defect, by the same function', () => {
  const m = (a, b) => { const out = CAP.replace(a, b); assert.notEqual(out, CAP, `mutation did not apply: ${a}`); return out; };
  assert.equal(regras(m('OR public.can_view_comms_analytics()', '')).portao, false);
  assert.equal(regras(m("CASE WHEN NOT v_analytics THEN NULL ELSE", 'CASE WHEN false THEN NULL ELSE')).custo, false);
  assert.equal(regras(m("OR public.can_by_member(v_caller_id, 'view_aggregate_analytics'));", '));')).analytics, false);
});

test(dbGated ? '#1877 (live): the published get_annual_kpis carries the same rules' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.rpc('_audit_function_source', { p_proname: 'get_annual_kpis' });
    assert.equal(error, null, `_audit_function_source failed: ${error?.message ?? ''}`);
    assert.ok(Array.isArray(data) && data.length === 1, 'expected exactly one get_annual_kpis');
    const r = regras(data[0].prosrc);
    assert.deepEqual(r, Object.fromEntries(Object.keys(r).map((k) => [k, true])));
  });
