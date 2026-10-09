// tests/contracts/curadoria-prazo-do-item-segue-curadores.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
// (DB-aware: the live layer reads the published body and the pending items.)
/**
 * Curation: the ITEM due date follows the ACTIVE curators.
 *
 * Measured 2026-10-08: the overdue sweep (curation_reviewer_sla_sweep) released the late curators and assigned new ones
 * through _curation_assign_one, which wrote the new due date on the CURATOR only. The reminder e-mail reads the
 * curator's date ("until 09/10"); the dashboard and the queue read board_items.curation_due_at and showed "7d late"
 * for the same item. One item was out of line on that date.
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

/** The rule, read from the body of _curation_assign_one. */
export function regra(body) {
  const b = maskLineComments(body || '').replace(/\s+/g, ' ');
  const insert = b.indexOf('INSERT INTO public.curation_reviewer_assignments');
  const upd = b.search(/UPDATE public\.board_items bi SET curation_due_at = \(SELECT max\(ca\.due_at\) FROM public\.curation_reviewer_assignments ca WHERE ca\.board_item_id = p_item_id AND ca\.released_at IS NULL\) WHERE bi\.id = p_item_id AND bi\.curation_status = 'curation_pending';/);
  return {
    // the item date is the max of the ACTIVE curators, on THIS item, only while pending
    segueAtivos: upd > 0,
    // and it runs after the assignment is written, so the new curator counts
    depoisDaAtribuicao: insert > 0 && upd > insert,
  };
}

const CAP = latestFunctionCapture(ROOT, '_curation_assign_one').body;

test('curation (capture): the item due date follows the active curators, after the assignment', () => {
  const r = regra(CAP);
  assert.deepEqual(r, Object.fromEntries(Object.keys(r).map((k) => [k, true])));
});

test('curation mutation: each detector fails on its defect', () => {
  const m = (a, b) => { const out = CAP.replace(a, b); assert.notEqual(out, CAP, `mutation did not apply: ${a}`); return out; };
  // counts released curators too (the late ones would win again)
  assert.equal(regra(m('AND ca.released_at IS NULL)', ')')).segueAtivos, false);
  // the update disappears (the defect of 08/10)
  assert.equal(regra(m('UPDATE public.board_items bi', 'SELECT 1 FROM public.board_items bi')).segueAtivos, false);
});

test(dbGated ? 'curation (live): no pending item is out of line with its active curators' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data: items, error: e1 } = await sb.from('board_items')
      .select('id, curation_due_at').eq('curation_status', 'curation_pending');
    assert.equal(e1, null, e1?.message);
    const ids = (items ?? []).map((i) => i.id);
    if (ids.length === 0) return;
    const { data: asg, error: e2 } = await sb.from('curation_reviewer_assignments')
      .select('board_item_id, due_at, released_at').in('board_item_id', ids).is('released_at', null);
    assert.equal(e2, null, e2?.message);
    const maxDue = new Map();
    for (const a of asg ?? []) {
      const cur = maxDue.get(a.board_item_id);
      if (!cur || new Date(a.due_at) > new Date(cur)) maxDue.set(a.board_item_id, a.due_at);
    }
    const fora = (items ?? []).filter((i) => maxDue.has(i.id)
      && new Date(i.curation_due_at ?? 0).getTime() !== new Date(maxDue.get(i.id)).getTime());
    assert.deepEqual(fora.map((i) => i.id), [], 'pending item whose due date differs from its active curators');
  });

test(dbGated ? 'curation (live): the published _curation_assign_one carries the rule' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.rpc('_audit_function_source', { p_proname: '_curation_assign_one' });
    assert.equal(error, null, `_audit_function_source failed: ${error?.message ?? ''}`);
    assert.ok(Array.isArray(data) && data.length === 1);
    const r = regra(data[0].prosrc);
    assert.deepEqual(r, Object.fromEntries(Object.keys(r).map((k) => [k, true])));
  });
