// tests/contracts/2890-2893-avisos-com-destino-certo.test.mjs
// Static over the newest capture of each function; the live arm reads the body in production and skips without env.
/**
 * Onboarding wave 0, PR-5. Two notices with the wrong destination:
 *
 *   A  #2890: respond_re_engagement linked /admin/members/re-engagement, a route that does not exist (it fell into
 *      [id].astro with the id "re-engagement"). The link it writes must resolve to a page in src/pages: now the member
 *      page of who answered. Its delivery mode comes from the catalog, for the same type it writes;
 *   B  #2893: notify_offboard_cascade found the leaders by the legacy members.tribe_id. Its body must not read tribe_id,
 *      and the leaders come from engagements: active leader or co-leader (kind volunteer) of an initiative where the
 *      person had an engagement up to this transaction;
 *   C  the catalog carries both re-engagement types with the mode they already had (digest_weekly);
 *   L  live: the offboard cascade in production does not read tribe_id.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const RRE = maskLineComments(latestFunctionCapture(ROOT, 'respond_re_engagement').body);
const NOC_CAPTURE = latestFunctionCapture(ROOT, 'notify_offboard_cascade');
const DMF = maskLineComments(latestFunctionCapture(ROOT, '_delivery_mode_for').body);

/** The page a link written by SQL lands on: a literal path, optionally followed by `|| <id expression>`. */
function routeFile(literal, hasDynamicTail) {
  const base = resolve(ROOT, 'src/pages', literal.replace(/^\//, ''));
  if (hasDynamicTail) {
    assert.ok(literal.endsWith('/'), `a link built as '${literal}' || id has no "/" before the id`);
    return [resolve(base, '[id].astro')];
  }
  return [`${base}.astro`, resolve(base, 'index.astro')];
}

/** Mirrors the notice evaluation for one body, so the live arm and the static arm say the same thing. */
export function offboardViolations(prosrc) {
  const body = maskLineComments(prosrc);
  const v = [];
  if (/tribe_id/.test(body)) v.push('B: the offboard cascade still reads tribe_id');
  const stake = body.slice(body.indexOf('INTO v_stakeholders'), body.indexOf('IF v_stakeholders IS NOT NULL'));
  if (!/m\.operational_role IN \('manager','deputy_manager'\)/.test(stake)) v.push('B: the managers are no longer notified');
  if (!/AND m\.id <> NEW\.id\s+AND m\.id IS DISTINCT FROM v_actor/.test(stake)) v.push('B: the person or the actor would be notified');
  if (!/OR EXISTS \(\s*SELECT 1\s+FROM public\.engagements le\s+JOIN public\.engagements pe ON pe\.initiative_id = le\.initiative_id\s+WHERE le\.person_id = m\.person_id\s+AND le\.kind = 'volunteer'\s+AND le\.role IN \('leader','co_leader'\)\s+AND le\.status = 'active'\s+AND pe\.person_id = NEW\.person_id\s+AND pe\.initiative_id IS NOT NULL\s+AND \(pe\.status = 'active' OR pe\.revoked_at >= now\(\)\)\s*\)/.test(stake)) {
    v.push('B: the leaders do not come from the engagements of the initiatives the person was in');
  }
  return v;
}

test('A1: the link the re-engagement notice writes lands on a page that exists', () => {
  const insert = RRE.slice(RRE.indexOf('INSERT INTO public.notifications'), RRE.indexOf('FROM public.members mgr'));
  const m = insert.match(/COALESCE\(p_note, NULL\),\s*'(\/[^']*)'(\s*\|\|\s*v_caller\.id::text)?,\s*'re_engagement_pipeline', p_pipeline_id/);
  assert.ok(m, 'could not read the link of the re-engagement notice');
  const files = routeFile(m[1], Boolean(m[2]));
  assert.ok(files.some((f) => existsSync(f)), `the link ${m[1]}${m[2] ? '<id>' : ''} has no page: ${files.map((f) => f.slice(ROOT.length + 1)).join(' or ')}`);
  assert.equal(m[1], '/admin/members/', 'the link is not the member page');
  assert.ok(m[2], 'the member page link has no member id');
});

test('A2: the re-engagement notice reads its mode from the catalog, for the type it writes', () => {
  assert.match(RRE, /INSERT INTO public\.notifications \(recipient_id, type, title, body, link, source_type, source_id, delivery_mode\)/);
  assert.match(RRE, /'re_engagement_pipeline', p_pipeline_id,\s*public\._delivery_mode_for\(CASE WHEN p_response = 'accepted' THEN 're_engagement_accepted' ELSE 're_engagement_declined' END\)\s*FROM public\.members mgr/,
    'the mode does not come from the catalog for the same type');
  assert.match(RRE, /SELECT mgr\.id,\s*CASE WHEN p_response = 'accepted' THEN 're_engagement_accepted' ELSE 're_engagement_declined' END,/);
});

test('B: the offboard cascade finds the leaders by engagement, never by tribe_id', () => {
  assert.deepEqual(offboardViolations(NOC_CAPTURE.body), [], `in ${NOC_CAPTURE.file}`);
});

test('B-M: the offboard evaluator says no to each defect', () => {
  const base = NOC_CAPTURE.body;
  const cases = [
    ['tribe_id back', "      OR EXISTS (", "      OR (NEW.tribe_id IS NOT NULL AND m.tribe_id = NEW.tribe_id)\n      OR EXISTS (", /still reads tribe_id/],
    ['only active engagements', "AND (pe.status = 'active' OR pe.revoked_at >= now())", "AND pe.status = 'active'", /do not come from the engagements/],
    ['any role', "AND le.role IN ('leader','co_leader')", "AND le.role IS NOT NULL", /do not come from the engagements/],
    ['managers dropped', "m.operational_role IN ('manager','deputy_manager')", "false", /managers are no longer notified/],
  ];
  for (const [label, from, to, expected] of cases) {
    const mutated = base.split(from).join(to);
    assert.notEqual(mutated, base, `${label}: the mutation did not change the body`);
    assert.match(offboardViolations(mutated).join(' | '), expected, `${label}: the evaluator did not say no`);
  }
});

test('C: the catalog carries both re-engagement types with the mode they already had', () => {
  for (const t of ['re_engagement_accepted', 're_engagement_declined']) {
    assert.match(DMF, new RegExp(`WHEN '${t}'\\s+THEN 'digest_weekly'`), `${t} is not catalogued as digest_weekly`);
  }
});

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);

test('L live: the offboard cascade in production finds leaders by engagement', { skip: dbGated ? false : 'Supabase env required' }, async () => {
  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_function_source', { p_proname: 'notify_offboard_cascade' });
  assert.ifError(error);
  assert.equal(data?.length, 1, `expected 1 signature of notify_offboard_cascade, got ${data?.length}`);
  assert.deepEqual(offboardViolations(data[0].prosrc), [], 'the live offboard cascade reads tribe_id again');
});
