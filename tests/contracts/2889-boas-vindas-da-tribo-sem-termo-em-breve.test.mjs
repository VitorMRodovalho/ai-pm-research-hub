// tests/contracts/2889-boas-vindas-da-tribo-sem-termo-em-breve.test.mjs
// Static over the newest capture of _enqueue_engagement_welcome; the live arm reads the body in production and skips
// without env.
/**
 * Onboarding wave 0, PR-3 (#2889 part 2). The volunteer branch of the welcome also fires when a leader approves a
 * tribe request, and asking for a tribe requires the signed Term; the text promised "soon" a Term the person had
 * already signed, linked to /initiative/<id> instead of the tribe page, and had no accents.
 *
 *   A  "has the Term" is any ACTIVE engagement of the same person with agreement_certificate_id (the tribe engagement
 *      itself is born without it);
 *   B  with the Term, in a research tribe: "Você agora faz parte da tribo X", linking to /tribe/<legacy_tribe_id> of
 *      the same initiative, and no word about a Term to sign;
 *   C  with the Term, outside a tribe: no word about a Term to sign either;
 *   D  the promise of the Term lives only in the branch of who has not signed it, and the branch is accented;
 *   E  the INSERT reads its delivery mode from the catalog;
 *   L  live: the same evaluation over the body in production.
 *
 * The evaluation is ONE function (`violations`), used for the newest capture, the live body and the mutations below,
 * so a mutation that does not go through the evaluator cannot pass for a test. Comments are masked first.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const CAPTURE = latestFunctionCapture(ROOT, '_enqueue_engagement_welcome');

/** The volunteer branch: from its WHEN to the next kind's WHEN. */
export function volunteerBranch(prosrc) {
  const body = maskLineComments(prosrc);
  const start = body.search(/WHEN\s+'volunteer'\s+THEN/);
  if (start < 0) return null;
  const rest = body.slice(start);
  const next = rest.search(/\n\s*WHEN\s+'study_group_owner'\s+THEN/);
  return next < 0 ? null : rest.slice(0, next);
}

/** Splits the branch into its three arms, or null when the shape is gone. */
function arms(branch) {
  const m = branch.match(/IF v_has_term AND v_initiative_kind = 'research_tribe' THEN([\s\S]*?)\n\s*ELSIF v_has_term THEN([\s\S]*?)\n\s*ELSE\b([\s\S]*?)\n\s*END IF;/);
  return m ? { tribe: m[1], termed: m[2], unsigned: m[3] } : null;
}

export function violations(prosrc) {
  const v = [];
  const branch = volunteerBranch(prosrc);
  if (branch === null) return ["the WHEN 'volunteer' branch is gone"];

  if (!/v_has_term := EXISTS \(\s*SELECT 1 FROM public\.engagements eo\s+WHERE eo\.person_id = v_eng\.person_id\s+AND eo\.status = 'active'\s+AND eo\.agreement_certificate_id IS NOT NULL\s*\);/.test(branch)) {
    v.push('A: "has the Term" is not "an active engagement of the same person with the certificate"');
  }
  const a = arms(branch);
  if (!a) {
    v.push('the branch does not split by the Term and by research_tribe: everyone gets the same text again');
    return v;
  }
  if (!/v_body := 'Você agora faz parte da tribo ' \|\| COALESCE\(v_initiative_title, 'de pesquisa'\)/.test(a.tribe)) {
    v.push('B: the tribe arm does not say "Você agora faz parte da tribo X"');
  }
  if (!/v_link := COALESCE\('\/tribe\/' \|\| v_legacy_tribe_id::text, v_link\);/.test(a.tribe)) {
    v.push('B: the tribe arm does not link to the tribe page');
  }
  if (/Termo/i.test(a.tribe)) v.push('B: the tribe arm still talks about a Term');
  if (/Termo/i.test(a.termed)) v.push('C: the arm of who has the Term outside a tribe still talks about a Term');
  if (!/Em breve você receberá o Termo de Voluntariado para assinatura\./.test(a.unsigned)) {
    v.push('D: the arm of who has not signed lost the Term notice');
  }
  if ((branch.match(/Termo de Voluntariado/g) || []).length !== 1) v.push('D: the Term is promised outside the unsigned arm');
  for (const w of ['participacao', 'voluntario(a)', 'voce ', 'recebera', 'proximos', "'Nucleo"]) {
    if (branch.includes(w)) v.push(`D: unaccented "${w}" in the volunteer branch`);
  }
  return v;
}

test('A-D: the newest capture welcomes the tribe member without promising the Term, and keeps it for who has not signed', () => {
  assert.deepEqual(violations(CAPTURE.body), [], `in ${CAPTURE.file}`);
});

test('B: the tribe number comes from the same initiative the welcome reads', () => {
  const body = maskLineComments(CAPTURE.body);
  assert.match(body, /SELECT i\.title, i\.kind, i\.legacy_tribe_id INTO v_initiative_title, v_initiative_kind, v_legacy_tribe_id\s+FROM public\.initiatives i WHERE i\.id = v_eng\.initiative_id;/,
    'the tribe link is not read from the initiative of this engagement');
});

test('E: the welcome INSERT reads its delivery mode from the catalog', () => {
  const body = maskLineComments(CAPTURE.body);
  assert.match(body, /'engagement',\s*p_engagement_id,\s*public\._delivery_mode_for\('engagement_welcome'\)\s*\);/,
    'the welcome still writes a literal delivery_mode');
});

test('M: the evaluator says no to each defect, through the same function', () => {
  const base = CAPTURE.body;
  const cases = [
    ['the tribe arm promises the Term again', "'Na página da tribo estão o horário das reuniões, os próximos eventos e quem participa.'",
      "'Em breve você receberá o Termo de Voluntariado para assinatura.'", /B: the tribe arm still talks|D: the Term is promised/],
    ['the tribe arm links to /initiative/', "v_link := COALESCE('/tribe/' || v_legacy_tribe_id::text, v_link);", "v_link := v_link;", /B: the tribe arm does not link/],
    ['"has the Term" reads the new engagement only', 'WHERE eo.person_id = v_eng.person_id', 'WHERE eo.id = v_eng.id', /A: "has the Term"/],
    ['the Term check ignores the status', "          AND eo.status = 'active'\n", '', /A: "has the Term"/],
    ['the branch no longer splits', "IF v_has_term AND v_initiative_kind = 'research_tribe' THEN", 'IF true THEN', /does not split/],
    ['the unsigned arm loses the Term notice', "'Em breve você receberá o Termo de Voluntariado para assinatura. ' ||\n", '', /D: the arm of who has not signed/],
    ['the accents are gone', 'Sua participação como voluntário(a) foi registrada. ', 'Sua participacao como voluntario(a) foi registrada. ', /D: unaccented/],
  ];
  for (const [label, from, to, expected] of cases) {
    const mutated = base.split(from).join(to);
    assert.notEqual(mutated, base, `${label}: the mutation did not change the body`);
    assert.match(violations(mutated).join(' | '), expected, `${label}: the evaluator did not say no`);
  }
  // A comment that quotes the right text cannot approve a body that lost it.
  const onlyInComment = base.replace("v_body := 'Você agora faz parte da tribo '", "v_body := '' -- Você agora faz parte da tribo\n || '");
  assert.notEqual(onlyInComment, base);
  assert.match(violations(onlyInComment).join(' | '), /B: the tribe arm does not say/, 'the evaluator matched a comment');
});

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);

test('L live: the welcome in production passes the same evaluation', { skip: dbGated ? false : 'Supabase env required' }, async () => {
  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_function_source', { p_proname: '_enqueue_engagement_welcome' });
  assert.ifError(error);
  assert.equal(data?.length, 1, `expected 1 signature of _enqueue_engagement_welcome, got ${data?.length}`);
  assert.deepEqual(violations(data[0].prosrc), [], 'the live welcome promises the Term to a tribe member again');
});
