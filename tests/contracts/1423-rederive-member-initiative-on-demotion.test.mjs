/**
 * Contract: #1423 — removing a member from a NON-tribe initiative must re-derive
 * members.initiative_id (dual-write bridge), not leave it pointing at an initiative
 * the person no longer engages in.
 *
 * Bug (2026-07-18): manage_initiative_engagement action=remove expired the engagement
 * but _sync_member_initiative_from_engagement() only SET the bridge on an active
 * engagement — it never re-derived it on demotion. Removing Nicolas from the CPMAI
 * study group left members.initiative_id = CPMAI (orphaned pointer); members.tribe_id
 * was correctly Radar. Same class as the dual-write demotion fix #1270/#1273
 * ([[reference-dual-write-demotion-clear-both-columns]]), which the tribe-side twin
 * _sync_tribe_id_from_engagement only covers for kind='volunteer' in a research_tribe.
 *
 * Fix (migration 20260805000471): the trigger gained a demotion branch. On an
 * active->non-active transition of a NON-tribe initiative engagement, if the bridge
 * still points at that initiative with no remaining active engagement there, it is
 * re-derived: tribe membership wins (clear -> members-level sync_initiative_from_tribe
 * rebuilds from tribe_id), else another active non-tribe initiative, else NULL.
 * research_tribe removal stays owned by _sync_tribe_id_from_engagement.
 *
 * Static test (always run): the trigger fn body carries the demotion branch.
 * DB invariant test (gated): no ACTIVE member retains an initiative_id that has no
 * backing active engagement (the orphan class). Non-active members are already
 * covered by #1288.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1423 static: _sync_member_initiative_from_engagement carries the demotion re-derivation branch', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql'));
  const mig = files.find(f => f.includes('1423_rederive_member_initiative'));
  assert.ok(mig, 'migration 20260805000471_1423_rederive_member_initiative_on_engagement_demotion.sql must exist.');
  const body = readFileSync(join(MIGRATIONS_DIR, mig), 'utf8');

  assert.ok(/CREATE OR REPLACE FUNCTION public\._sync_member_initiative_from_engagement/i.test(body),
    'migration must CREATE OR REPLACE _sync_member_initiative_from_engagement.');
  // Demotion branch: active -> non-active transition.
  assert.ok(/OLD\.status\s*=\s*'active'\s*[\s\S]{0,80}NEW\.status\s+IS\s+DISTINCT\s+FROM\s+'active'/i.test(body),
    'trigger must handle the active -> non-active demotion transition.');
  // Must skip research_tribe (owned by _sync_tribe_id_from_engagement).
  assert.ok(/kind\s*=\s*'research_tribe'/i.test(body),
    'trigger must scope the demotion branch away from research_tribe (owned by the tribe-side twin).');
  // Re-derivation must clear/re-point the bridge that pointed at the demoted initiative.
  assert.ok(/UPDATE\s+public\.members[\s\S]{0,200}initiative_id\s*=\s*NEW\.initiative_id/i.test(body),
    'trigger must re-point members.initiative_id only where it still equals the demoted initiative.');
});

test('#1423 DB: no active member retains an initiative_id with no backing active engagement', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  // Members carrying a live initiative_id cache.
  const { data: members, error: mErr } = await sb
    .from('members')
    .select('id, name, person_id, initiative_id, member_status')
    .not('initiative_id', 'is', null);
  assert.equal(mErr, null, mErr?.message);

  const offenders = [];
  for (const m of members ?? []) {
    // Non-active members are #1288's territory; here we assert the live-active bridge.
    if (m.member_status && m.member_status !== 'active') continue;
    const { data: eng, error: eErr } = await sb
      .from('engagements')
      .select('id')
      .eq('person_id', m.person_id)
      .eq('initiative_id', m.initiative_id)
      .eq('status', 'active')
      .limit(1);
    assert.equal(eErr, null, eErr?.message);
    if (!eng || eng.length === 0) offenders.push({ id: m.id, name: m.name, initiative_id: m.initiative_id });
  }

  assert.equal(offenders.length, 0,
    `Orphaned initiative_id bridge (#1423 class) on active members: ${JSON.stringify(offenders.slice(0, 10))}`);
});
