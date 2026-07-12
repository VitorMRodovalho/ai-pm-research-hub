/**
 * Contract: #1302 [EPIC #1020] Tribe leader succession must transfer V4 AUTHORITY,
 * not just the operational_role cache + the tribes.leader_member_id pointer.
 *
 * Migration: supabase/migrations/20260805000430_1302_tribe_successor_transfers_authority.sql
 * Fixes admin_change_tribe_leader (the shared swap reused by place_tribe_successor, #1296).
 *
 * Root cause: leader authority is an engagement grant (volunteer x leader scoped to the
 * tribe's initiative — ADR-0007), NOT operational_role. The old swap wrote the cache + the
 * pointer but never touched engagements, so the successor got the label with no can()
 * authority (and it reverted on the next recompute) while the outgoing leader kept theirs.
 *
 * Invariants under test:
 *  Static (always):
 *   - swap grants the successor a volunteer x leader engagement (promote existing, else insert);
 *   - swap demotes the outgoing leader's engagement leader->researcher (B1);
 *   - outgoing-leader guard is the PK test (.id IS NOT NULL), not a composite-record test;
 *   - both member_cycle_history writes ON CONFLICT (member_id, cycle_code) DO UPDATE
 *     (mid-cycle succession must not raise on the existing current-cycle row);
 *   - unsigned successor -> authority_pending_agreement, and the tribe_leader label is NOT
 *     faked when authority is pending (A1 — the term gate is not bypassed).
 *  DB-gated invariant (guards the exact bug class going forward):
 *   - no active tribe leader carries operational_role='tribe_leader' WITHOUT an active
 *     volunteer x leader engagement on that tribe's initiative (label-without-authority).
 *
 *  The functional transfer (successor gains manage_event, outgoing leader loses it) was proven
 *  live via a rolled-back DO block (see PR): tribe 1, promote path (researcher w/ term) and
 *  a real outgoing leader — before/after can_by_member flipped f->t (successor) and t->f
 *  (outgoing), operational_role + engagement role in lockstep, history deduped, all reverted.
 *  admin_change_tribe_leader depends on auth.uid(), so it cannot be exercised from a
 *  service-role client without mutating live data; the invariant test below is the CI guard.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000430_1302_tribe_successor_transfers_authority.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1302: migration present + re-captures admin_change_tribe_leader', () => {
  assert.ok(existsSync(MIG), 'migration file present');
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.admin_change_tribe_leader\(/);
});

test('#1302: successor is granted a volunteer x leader engagement (promote or insert)', () => {
  // resolve the tribe's initiative to scope the grant
  assert.match(mig, /FROM public\.initiatives i\s*\n\s*WHERE i\.legacy_tribe_id = p_tribe_id AND i\.kind = 'research_tribe'/,
    'resolves the tribe initiative (authority scope)');
  // promote an existing active engagement...
  assert.match(mig, /UPDATE public\.engagements SET role = 'leader'/, 'promotes existing engagement to leader');
  // ...else insert a fresh volunteer x leader engagement
  assert.match(mig, /INSERT INTO public\.engagements \([\s\S]*?'volunteer', 'leader', 'active'/,
    'inserts a volunteer x leader engagement when none exists');
});

test('#1302 (B1): outgoing leader engagement demoted leader->researcher', () => {
  assert.match(mig, /UPDATE public\.engagements\s*\n\s*SET role = 'researcher'[\s\S]*?role IN \('leader', 'comms_leader'\)/,
    'outgoing leader engagement demoted to researcher (loses authority, stays in tribe)');
});

test('#1302: outgoing-leader guard is the PK test, not a composite-record test', () => {
  assert.match(mig, /IF v_old_leader\.id IS NOT NULL THEN/, 'guards on .id (PK), robust to NULL member columns');
  assert.ok(!/IF v_old_leader IS NOT NULL THEN/.test(mig), 'must not use the composite-record NULL test (silent no-op bug)');
});

test('#1302: both history writes ON CONFLICT DO UPDATE (mid-cycle succession safe)', () => {
  const conflicts = mig.match(/ON CONFLICT \(member_id, cycle_code\) DO UPDATE SET/g) || [];
  assert.equal(conflicts.length, 2, 'outgoing + incoming history writes both upsert on the current-cycle row');
});

test('#1302 (A1): unsigned successor -> pending, tribe_leader label not faked', () => {
  // authority is derived from is_authoritative (signed term), not assumed
  assert.match(mig, /bool_or\(ae\.is_authoritative\)/, 'reads is_authoritative to decide pending');
  assert.match(mig, /IF NOT v_authority_pending THEN\s*\n\s*UPDATE public\.members SET operational_role = 'tribe_leader'/,
    'only writes the tribe_leader label when authority is real (term signed)');
  assert.match(mig, /'authority_pending_agreement', v_authority_pending/, 'return surfaces the pending flag');
});

// ── DB-gated invariant: label-without-authority must not exist ──
test('#1302 DB: every tribe_leader has an active volunteer x leader engagement on the tribe initiative',
  { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data: tribes, error: e1 } = await sb
    .from('tribes').select('id, name, leader_member_id')
    .eq('is_active', true).not('leader_member_id', 'is', null);
  assert.ok(!e1, `tribes read: ${e1?.message}`);
  assert.ok(tribes.length > 0, 'there is at least one led tribe to check');

  const leaderIds = tribes.map(t => t.leader_member_id);
  const { data: leaders, error: e2 } = await sb
    .from('members').select('id, person_id, operational_role').in('id', leaderIds);
  assert.ok(!e2, `members read: ${e2?.message}`);
  const leaderById = new Map(leaders.map(m => [m.id, m]));

  const { data: inits, error: e3 } = await sb
    .from('initiatives').select('id, legacy_tribe_id')
    .in('legacy_tribe_id', tribes.map(t => t.id)).eq('kind', 'research_tribe');
  assert.ok(!e3, `initiatives read: ${e3?.message}`);
  const initByTribe = new Map(inits.map(i => [i.legacy_tribe_id, i.id]));

  const personIds = leaders.map(m => m.person_id).filter(Boolean);
  const { data: engs, error: e4 } = await sb
    .from('engagements').select('person_id, initiative_id, role, kind, status')
    .in('person_id', personIds).eq('status', 'active').eq('kind', 'volunteer').eq('role', 'leader');
  assert.ok(!e4, `engagements read: ${e4?.message}`);
  const leaderEng = new Set(engs.map(e => `${e.person_id}|${e.initiative_id}`));

  const offenders = [];
  for (const t of tribes) {
    const m = leaderById.get(t.leader_member_id);
    if (!m || m.operational_role !== 'tribe_leader') continue; // only the fully-promoted label
    const initId = initByTribe.get(t.id);
    if (!initId) continue; // tribe without a mapped initiative (legacy fallback path)
    if (!leaderEng.has(`${m.person_id}|${initId}`)) {
      offenders.push(`tribe ${t.id} (${t.name}) leader ${m.id} lacks volunteer x leader engagement on ${initId}`);
    }
  }
  assert.equal(offenders.length, 0, `label-without-authority leaders:\n${offenders.join('\n')}`);
});
