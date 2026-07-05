/**
 * #1113 — tribe/initiative roadmap read + authoring (fast-follow #1103 item 3)
 *
 * get_initiative_roadmap: SECDEF read gated by rls_can_see_initiative() (confidential initiatives
 * only to engaged members + GP, ADR-0105); always returns the 3 horizons as arrays (graceful empty).
 * set_initiative_roadmap: SECDEF write gated by can_by_member('write_board','initiative') OR
 * manage_platform (the same authority the tribe page uses for leader UI), validates {h6,h12,h18}
 * arrays, writes into initiatives.metadata.roadmap.
 *
 * Source-contract (offline) locks the RPC shape + gates. Behavioural (DB, guarded) proves the read
 * returns the normalised shape and that the write gate accepts an initiative leader / denies others.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000340_1113_initiative_roadmap_read_write.sql', import.meta.url)),
  'utf8',
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

function headers() {
  return { 'Content-Type': 'application/json', apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` };
}
async function rpc(fn, args) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: 'POST', headers: headers(), body: JSON.stringify(args) });
  if (!res.ok) throw new Error(`rpc ${fn} HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}
async function getRows(table, query) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${query}`, { headers: headers() });
  if (!res.ok) throw new Error(`${table} HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}

// ── Source contract (offline) ───────────────────────────────────────────────
test('1113: get_initiative_roadmap is SECURITY DEFINER + confidentiality-gated', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_initiative_roadmap\(p_initiative_id uuid\)/, 'read RPC exists');
  const body = MIG.slice(MIG.indexOf('get_initiative_roadmap'), MIG.indexOf('set_initiative_roadmap'));
  assert.match(body, /SECURITY DEFINER/, 'read is SECDEF');
  assert.match(body, /IF NOT public\.rls_can_see_initiative\(p_initiative_id\) THEN/, 'applies the ADR-0105 confidentiality gate');
  // always returns the 3 horizons as arrays (graceful empty)
  assert.match(body, /'h6',\s*COALESCE\(v_roadmap->'h6',\s*'\[\]'::jsonb\)/, 'h6 normalised to array');
  assert.match(body, /'h12',\s*COALESCE\(v_roadmap->'h12',\s*'\[\]'::jsonb\)/, 'h12 normalised to array');
  assert.match(body, /'h18',\s*COALESCE\(v_roadmap->'h18',\s*'\[\]'::jsonb\)/, 'h18 normalised to array');
});

test('1113: set_initiative_roadmap is SECDEF + leader/admin gated + shape-validated', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.set_initiative_roadmap\(p_initiative_id uuid, p_roadmap jsonb\)/, 'write RPC exists');
  const body = MIG.slice(MIG.indexOf('set_initiative_roadmap'));
  assert.match(body, /SECURITY DEFINER/, 'write is SECDEF');
  // fail-closed: member must exist
  assert.match(body, /WHERE auth_id = auth\.uid\(\)/, 'resolves the caller member from auth.uid()');
  assert.match(body, /RAISE EXCEPTION 'Unauthorized: member not found'/, 'fail-closed when no member');
  // initiative-scoped leader authority OR platform admin
  assert.match(body, /public\.can_by_member\(v_member_id, 'write_board', 'initiative', p_initiative_id\)/, 'initiative-scoped write_board gate');
  assert.match(body, /public\.can_by_member\(v_member_id, 'manage_platform', NULL, NULL\)/, 'platform admin bypass');
  assert.match(body, /RAISE EXCEPTION 'Unauthorized: requires write_board on this initiative'/, 'denies non-leaders');
  // shape validation
  assert.match(body, /jsonb_typeof\(p_roadmap\) <> 'object'/, 'roadmap must be an object');
  assert.match(body, /jsonb_typeof\(v_clean->'h6'\)\s*<> 'array'/, 'h6 must be an array');
  assert.match(body, /jsonb_set\(COALESCE\(metadata, '\{\}'::jsonb\), '\{roadmap\}', v_clean\)/, 'writes into metadata.roadmap');
});

test('1113: grants — read to anon+authenticated, write to authenticated only', () => {
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.get_initiative_roadmap\(uuid\) TO anon, authenticated;/, 'read granted to anon+authenticated');
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.set_initiative_roadmap\(uuid, jsonb\) TO authenticated;/, 'write granted to authenticated');
  // write must NOT be granted to anon
  assert.doesNotMatch(MIG, /GRANT EXECUTE ON FUNCTION public\.set_initiative_roadmap\(uuid, jsonb\) TO [^;]*\banon\b/, 'write NOT granted to anon');
});

// ── Behavioural (DB, guarded) ────────────────────────────────────────────────
test(canRun ? '1113: read returns the normalised {h6,h12,h18} shape for a live initiative' : skipMsg, { skip: !canRun }, async () => {
  const inits = await getRows('initiatives', "select=id,visibility&or=(visibility.is.null,visibility.neq.confidential)&limit=1");
  if (!inits.length) { console.log('  (skip: no non-confidential initiative live)'); return; }
  const out = await rpc('get_initiative_roadmap', { p_initiative_id: inits[0].id });
  assert.ok(out && out.roadmap, 'returns a roadmap object');
  assert.ok(Array.isArray(out.roadmap.h6), 'h6 is an array');
  assert.ok(Array.isArray(out.roadmap.h12), 'h12 is an array');
  assert.ok(Array.isArray(out.roadmap.h18), 'h18 is an array');
});

test(canRun ? '1113: write gate — initiative leader passes, researcher denied' : skipMsg, { skip: !canRun }, async () => {
  // a tribe_leader with an authoritative engagement on an initiative
  const leaders = await getRows(
    'members',
    "select=id,auth_id,operational_role&operational_role=eq.tribe_leader&auth_id=not.is.null&limit=5",
  );
  if (!leaders.length) { console.log('  (skip: no tribe_leader with auth live)'); return; }

  let probed = false;
  for (const l of leaders) {
    const eng = await getRows('auth_engagements', `select=initiative_id&auth_id=eq.${l.auth_id}&is_authoritative=eq.true&initiative_id=not.is.null&limit=1`);
    if (!eng.length) continue;
    const initId = eng[0].initiative_id;
    const leaderAllowed = await rpc('can_by_member', { p_member_id: l.id, p_action: 'write_board', p_resource_type: 'initiative', p_resource_id: initId });
    assert.equal(leaderAllowed, true, 'initiative leader passes write_board gate');

    const others = await getRows('members', "select=id&operational_role=eq.researcher&auth_id=not.is.null&limit=1");
    if (others.length) {
      const otherAllowed = await rpc('can_by_member', { p_member_id: others[0].id, p_action: 'write_board', p_resource_type: 'initiative', p_resource_id: initId });
      assert.equal(otherAllowed, false, 'researcher denied write_board on the leader initiative');
    }
    probed = true;
    break;
  }
  if (!probed) console.log('  (skip: no tribe_leader with an authoritative initiative engagement live)');
});
