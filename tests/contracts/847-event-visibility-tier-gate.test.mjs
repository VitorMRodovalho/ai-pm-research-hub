/**
 * #847 — gp_only/leadership event VISIBILITY TIER must be enforced server-side in the
 * two read RPCs that #846 only gated for initiative CONFIDENTIALITY.
 *
 * Before this migration, get_events_with_attendance and list_meetings_with_notes returned
 * every gp_only/leadership standalone event (initiative_id IS NULL) — including
 * minutes_text/agenda_text — to any authenticated member over the wire. /attendance hid
 * them client-side (cosmetic); /meetings rendered them directly (no client filter).
 *
 * Fix (mig 20260805000238): a new helper public.rls_can_see_event_tier(visibility,
 * initiative_id) mirroring the per-event tier gate already shipped in get_event_detail
 * (#846): gp_only -> manage_platform, leadership -> manage_event, confidential-initiative
 * engaged members bypass the tier, and service_role/cron (auth.uid() IS NULL) bypasses for
 * analytics (invariant m3a D12). Both RPCs AND the helper next to rls_can_see_initiative.
 *
 * The 4-identity behavioural proof (regular member sees 0 restricted; tribe leader sees
 * leadership but not gp_only; GP sees all; service_role sees all) was validated live in
 * ROLLBACK transactions during development. The harness has no per-user JWT path
 * (service_role sets auth.uid() = NULL), so only the service_role analytics-bypass leg is
 * replayed here as a DB-gated regression lock.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG_PATH = resolve(process.cwd(), 'supabase/migrations/20260805000238_847_event_visibility_tier_gate.sql');
const MIG = existsSync(MIG_PATH) ? readFileSync(MIG_PATH, 'utf8') : '';

/** Slice the CREATE OR REPLACE block for a given function out of the migration text. */
function fnBlock(sql, name) {
  const start = sql.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  if (start === -1) return null;
  const next = sql.indexOf('CREATE OR REPLACE FUNCTION public.', start + 1);
  return sql.slice(start, next === -1 ? undefined : next);
}

// ── Static (offline) assertions ─────────────────────────────────────────────
test('#847: migration 20260805000238 exists', () => {
  assert.ok(MIG.length > 0, 'migration file must exist');
});

test('#847: rls_can_see_event_tier helper maps tiers to capabilities', () => {
  const block = fnBlock(MIG, 'rls_can_see_event_tier');
  assert.ok(block, 'rls_can_see_event_tier must be CREATE OR REPLACE\'d');
  assert.match(block, /auth\.uid\(\)\s+IS\s+NULL/i, 'service_role/cron bypass present');
  assert.match(block, /'leadership'[\s\S]*can_by_member\([\s\S]*'manage_event'\)/i, 'leadership -> manage_event');
  assert.match(block, /'gp_only'[\s\S]*can_by_member\([\s\S]*'manage_platform'\)/i, 'gp_only -> manage_platform');
  assert.match(block, /visibility\s*=\s*'confidential'/i, 'confidential-initiative engaged bypass present');
  assert.match(block, /SECURITY DEFINER/i);
});

for (const name of ['get_events_with_attendance', 'list_meetings_with_notes']) {
  test(`#847: ${name} applies rls_can_see_event_tier`, () => {
    const block = fnBlock(MIG, name);
    assert.ok(block, `${name} must be CREATE OR REPLACE'd in migration 238`);
    assert.match(block, /rls_can_see_event_tier\(\s*e\.visibility\s*,\s*e\.initiative_id\s*\)/i,
      `${name} must AND the tier gate`);
    // the confidential gate from #846 must NOT be dropped
    assert.ok(block.includes('rls_can_see_initiative'), `${name} must keep the #846 confidential gate`);
  });
}

test('#847: get_events_with_attendance keeps the service_role confidential bypass', () => {
  const block = fnBlock(MIG, 'get_events_with_attendance');
  assert.match(block, /rls_can_see_initiative\(e\.initiative_id\)\s+OR\s+auth\.uid\(\)\s+IS\s+NULL/i,
    'analytics path (m3a D12) must survive the confidential gate');
});

// ── DB-gated: service_role analytics bypass must survive the tier gate ───────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#847 DB: service_role still sees gp_only + leadership events (analytics not broken)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.rpc('get_events_with_attendance', { p_limit: 2000, p_offset: 0 });
    assert.ifError(error);
    assert.ok(Array.isArray(data) && data.length > 0, 'service_role must receive rows');
    const gp = data.filter((e) => e.visibility === 'gp_only').length;
    const lead = data.filter((e) => e.visibility === 'leadership').length;
    assert.ok(gp > 0, 'service_role must still see gp_only events (tier bypass via auth.uid() IS NULL)');
    assert.ok(lead > 0, 'service_role must still see leadership events');
  });
