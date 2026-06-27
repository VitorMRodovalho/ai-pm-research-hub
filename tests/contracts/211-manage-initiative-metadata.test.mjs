// #211 (ADR-0094 §G3.1) backend: self-service initiative metadata editing via the NEW V4 action
// `manage_initiative` + the `manage_initiative_metadata` RPC.
//
// Static contract over migration 20260805000260: asserts the authority-design invariants that
// matter for a new authority surface — who is seeded, that the RPC gates on can('manage_initiative',
// 'initiative', id), that the editable whitelist excludes structural fields, and that the RPC is
// granted to `authenticated` (not anon/public). Live both-sides validation (manager→true /
// guest→false, seeds=8) was performed at apply time; this test locks the design against regression.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const MIG = resolve(
  process.cwd(),
  'supabase/migrations/20260805000260_211_manage_initiative_metadata.sql'
);
const sql = readFileSync(MIG, 'utf8');

test('#211 seeds manage_initiative for the org manager tier (co_gp/deputy_manager/manager, organization scope)', () => {
  for (const role of ['co_gp', 'deputy_manager', 'manager']) {
    assert.match(
      sql,
      new RegExp(`'volunteer',\\s*'${role}',\\s*'organization'`),
      `manage_initiative must be seeded for volunteer/${role} at organization scope`
    );
  }
});

test('#211 seeds manage_initiative for owner/leader kinds at initiative scope', () => {
  for (const pair of [
    /'committee_member',\s*'leader',\s*'initiative'/,
    /'study_group_owner',\s*'owner',\s*'initiative'/,
    /'study_group_owner',\s*'leader',\s*'initiative'/,
    /'volunteer',\s*'leader',\s*'initiative'/,
    /'workgroup_member',\s*'leader',\s*'initiative'/,
  ]) {
    assert.match(sql, pair, `expected initiative-scope seed matching ${pair}`);
  }
  // and the action name itself is the new one
  assert.match(sql, /'manage_initiative'/, "action 'manage_initiative' must be seeded");
});

test('#211 RPC gates the metadata write on can(manage_initiative, initiative, id)', () => {
  assert.match(
    sql,
    /can\(\s*v_caller_person_id,\s*'manage_initiative',\s*'initiative',\s*p_initiative_id\s*\)/,
    'manage_initiative_metadata must gate on the initiative-scoped manage_initiative action'
  );
  // caller person_id must be resolved (never auth.uid() passed to can() — see #730)
  assert.doesNotMatch(sql, /can\(\s*auth\.uid\(\)/, 'must not pass auth.uid() to can() (see #730)');
});

test('#211 editable whitelist excludes structural fields', () => {
  // the whitelist array must be present
  assert.match(sql, /v_allowed\s+text\[\]\s*:=\s*ARRAY\[/, 'whitelist array must exist');
  // and these structural keys must NOT be editable through this RPC
  for (const forbidden of ['status', 'leader_member_id', 'start_date', 'end_date', "'name'", "'kind'"]) {
    assert.ok(
      !new RegExp(`ARRAY\\[[^\\]]*${forbidden.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`, 's').test(sql),
      `structural field ${forbidden} must NOT be in the editable whitelist`
    );
  }
  // a representative editable key IS present
  assert.match(sql, /'whatsapp_url'/, 'whatsapp_url must be editable');
});

test('#211 RPC is granted to authenticated, not anon/public', () => {
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.manage_initiative_metadata\(uuid, jsonb\) FROM PUBLIC/);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.manage_initiative_metadata\(uuid, jsonb\) TO authenticated/);
  assert.doesNotMatch(sql, /TO anon/, 'manage_initiative_metadata must not be granted to anon');
});
