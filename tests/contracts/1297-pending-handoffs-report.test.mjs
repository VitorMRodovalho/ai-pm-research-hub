/**
 * Contract: #1297 [EPIC #1020 Onda E] reconciliacao — get_pending_handoffs_report.
 * Fecha o loop TBD (#1004): lista os responsibility_handoffs pending com overdue flag + sumario,
 * para nenhum handoff estacionado vencer silenciosamente.
 *
 * Migration: supabase/migrations/20260805000407_1297_pending_handoffs_report.sql
 *
 * Invariants under test:
 *  Static: STABLE SECDEF, gate manage_platform + service_role, REVOKE FROM PUBLIC/anon.
 *  DB-gated (data-driven, cleanup): park 1 overdue + 1 future -> report inclui ambos, overdue
 *   flag + days_overdue corretos, overdue ordenado primeiro, by_item_type/summary consistentes.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000407_1297_pending_handoffs_report.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1297: get_pending_handoffs_report — STABLE SECDEF, gate manage_platform + service_role', () => {
  assert.ok(existsSync(MIG), 'migration file present');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.get_pending_handoffs_report\(\)/);
  assert.match(mig, /STABLE SECURITY DEFINER/);
  assert.match(mig, /can_by_member\(v_caller, 'manage_platform'\)/);
  assert.match(mig, /'service_role'/);
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.get_pending_handoffs_report\(\) FROM PUBLIC, anon;/);
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.get_pending_handoffs_report\(\) TO authenticated, service_role;/);
  // reconciliation essentials
  assert.match(mig, /is_overdue/);
  assert.match(mig, /days_overdue/);
  assert.match(mig, /by_item_type/);
});

test('#1297 DB: report lists parked handoffs with overdue flag + summary (data-driven)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const someone = '92d26057-5550-4f15-a3bf-b00eed5f32f9';
  const gp = '880f736c-3e76-4df4-9375-33575c190305';
  const created = [];
  try {
    const { data: overdue } = await sb.rpc('park_responsibility_handoff', {
      p_from_member_id: someone, p_item_type: 'action_items', p_item_ref: 'test-e-overdue',
      p_owner_member_id: gp, p_due_date: '2026-07-01', p_reason: 'test overdue',
    });
    const { data: future } = await sb.rpc('park_responsibility_handoff', {
      p_from_member_id: someone, p_item_type: 'checklist_items', p_item_ref: 'test-e-future',
      p_owner_member_id: gp, p_due_date: '2026-12-31', p_reason: 'test future',
    });
    created.push(overdue.handoff_id, future.handoff_id);

    const { data: rep, error } = await sb.rpc('get_pending_handoffs_report');
    assert.ok(!error, `report must not throw: ${error?.message}`);
    assert.ok(!rep.error, `report returned error: ${JSON.stringify(rep.error)}`);

    const byRef = Object.fromEntries(rep.pending_handoffs.map((h) => [h.item_ref, h]));
    const od = byRef['test-e-overdue'];
    const fu = byRef['test-e-future'];
    assert.ok(od && fu, 'both parked handoffs must appear in the report');
    assert.equal(od.is_overdue, true, 'past due_date is flagged overdue');
    assert.ok(od.days_overdue > 0, 'overdue days computed');
    assert.equal(fu.is_overdue, false, 'future due_date not overdue');
    assert.ok(od.from_member_name != null, 'enrichment: from_member_name present');

    assert.ok(rep.total_pending >= 2, 'total_pending counts parked');
    assert.ok(rep.overdue_count >= 1, 'overdue_count includes the overdue one');
    assert.equal(rep.by_item_type['action_items'] >= 1, true, 'by_item_type breakdown includes action_items');

    // overdue ordered first
    const firstOverdueIdx = rep.pending_handoffs.findIndex((h) => h.item_ref === 'test-e-overdue');
    const firstFutureIdx = rep.pending_handoffs.findIndex((h) => h.item_ref === 'test-e-future');
    assert.ok(firstOverdueIdx < firstFutureIdx, 'overdue handoffs ordered before non-overdue');
  } finally {
    for (const id of created) if (id) await sb.from('responsibility_handoffs').delete().eq('id', id);
  }
});
