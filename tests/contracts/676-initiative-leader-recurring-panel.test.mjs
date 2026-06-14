import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// #676 Slice B — leader self-service panel on the initiative page. The global GP screen (A)
// stays; B gives the initiative leader a scoped surface via get_recurring_meeting_admin_list
// (p_initiative_id) which is leader-scoped (_can_manage_recurring_rule).
const MIG = 'supabase/migrations/20260805000170_676_admin_list_leader_scoped_initiative_filter.sql';
const PANEL = 'src/components/initiative/InitiativeRecurringMeetingsPanel.tsx';
const PAGE = 'src/pages/initiative/[id].astro';
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'];
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const sb = SUPABASE_URL && SERVICE_KEY ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } }) : null;

test('#676 sliceB static: read RPC is leader-scoped with an initiative filter (GC-097 DROP+CREATE)', () => {
  const body = read(MIG);
  assert.ok(body, 'migration present');
  assert.match(body, /DROP FUNCTION IF EXISTS public\.get_recurring_meeting_admin_list\(date\)/, 'old signature dropped');
  assert.match(body, /p_initiative_id uuid DEFAULT NULL/, 'new initiative filter param');
  // scoped: GP or leader of the initiative; global (null): GP only
  assert.match(body, /IF p_initiative_id IS NOT NULL THEN[\s\S]*?_can_manage_recurring_rule\(v_member, p_initiative_id\)/, 'scoped gate = leader of that initiative');
  assert.match(body, /ELSE[\s\S]*?can_by_member\(v_member, 'manage_platform'\)/, 'global gate stays GP-only');
  assert.match(body, /WHERE \(p_initiative_id IS NULL OR r\.initiative_id = p_initiative_id\)/, 'rows filtered by initiative');
});

test('#676 sliceB static: panel self-gates + reuses write RPCs + mounted on initiative page', () => {
  const panel = read(PANEL);
  assert.ok(panel, 'panel present');
  assert.match(panel, /rpc\('get_recurring_meeting_admin_list', \{[\s\S]*?p_initiative_id: initiativeId/, 'reads scoped to this initiative');
  assert.match(panel, /if \(!canManage\) return null/, 'self-gates (hidden for non-managers)');
  assert.match(panel, /rpc\('update_recurring_meeting_rule'/, 'reuses update RPC');
  assert.match(panel, /rpc\('create_recurring_meeting_rule'/, 'reuses create RPC');
  assert.match(panel, /rpc\('reconcile_recurring_meeting'/, 'reuses reconcile RPC');
  assert.match(panel, /initiative_id: initiativeId/, 'create is pre-scoped to this initiative (no picker)');
  assert.ok(!/\bclass=/.test(panel), 'uses className (React)');
  // mounted on the initiative page with i18n namespace bundled
  const page = read(PAGE);
  assert.match(page, /InitiativeRecurringMeetingsPanel client:load initiativeId=/, 'mounted on initiative page');
  assert.match(page, /'comp\.recurringAgenda'/, 'page bundles the panel i18n namespace');
});

test('#676 sliceB static: panel i18n keys parity across 3 dictionaries', () => {
  const KEYS = ['comp.recurringAgenda.panelHeading', 'comp.recurringAgenda.panelSubtitle', 'comp.recurringAgenda.panelEmpty'];
  for (const dict of DICTS) {
    const body = read(dict);
    for (const k of KEYS) assert.ok(body.includes(`'${k}'`), `${dict} missing ${k}`);
  }
});

test('#676 sliceB live: scoped read returns only the initiative rules; global still returns all', { skip: sb ? false : 'Supabase env required' }, async () => {
  // pick a real tribe initiative that has a rule
  const { data: rule } = await sb.from('recurring_meeting_rules').select('initiative_id, title').eq('scope_type', 'tribe').not('initiative_id', 'is', null).limit(1).single();
  assert.ok(rule?.initiative_id, 'a tribe rule exists');

  const { data: scoped, error: eS } = await sb.rpc('get_recurring_meeting_admin_list', { p_horizon_end: null, p_initiative_id: rule.initiative_id });
  assert.ifError(eS);
  assert.ok(Array.isArray(scoped) && scoped.length >= 1, 'scoped returns this initiative rules');
  assert.ok(scoped.every((r) => r.scope_name && r.title), 'rows shaped');

  const { data: globalAll, error: eG } = await sb.rpc('get_recurring_meeting_admin_list');
  assert.ifError(eG);
  assert.ok(globalAll.length >= scoped.length, 'global (no filter) returns at least as many as one initiative');
});

test('#676 sliceB live: anon is denied on the scoped read (gate enforced)', { skip: (SUPABASE_URL && ANON_KEY) ? false : 'anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { error } = await anon.rpc('get_recurring_meeting_admin_list', {
    p_horizon_end: null, p_initiative_id: '00000000-0000-4000-8000-0000000000aa',
  });
  assert.ok(error, 'anon cannot read the scoped recurring list');
});
