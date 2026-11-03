// tests/contracts/2888-pedido-de-tribo-expirado-avisa-e-aparece.test.mjs
// Static over the latest capture of each function and over the component; the live layers skip without env.
/**
 * Onboarding wave 0, PR-2. A volunteer's own tribe request that expires without the leader's review:
 *
 *   A  #2888: the expiry part of process_tribe_request_nudges notifies the person who asked, only for a
 *      self-request, once (its own mark), through the delivery catalog;
 *   B  #2885: the notice to the GP names who asked and when, and links to the member page, without the
 *      request message;
 *   C  #2892 item 2: the leader's queue does not list a request whose deadline passed;
 *   D  #2888: get_my_tribe_request_context returns the latest self-request as `expired` only when that latest
 *      one expired in the last 14 days, and only with no pending request and no tribe;
 *   E  #2891: every notification type written by a literal INSERT in the tribe-request and welcome functions is
 *      in the CASE of _delivery_mode_for, with the mode the INSERT uses;
 *   F  owner's decision of 01/11/2026 (P1 = a): get_onboarding_contacts returns display names only, to active
 *      members only, and the seed of its key carries no identifier;
 *   G  live: anon cannot call get_onboarding_contacts, and a caller with no member gets an empty list;
 *   H  the panel: the expired state, "Request again" with the previous message, the contact in the pending,
 *      expired and empty states, and the response-time promise only next to the onboarding group.
 *
 * Each assertion binds the condition to the result inside the deciding block (.claude/rules/guards.md); comments
 * are masked before matching, so a sentence explaining the mechanism cannot keep a test green.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const body = (fn) => maskLineComments(latestFunctionCapture(ROOT, fn).body);

function between(text, from, to, label) {
  const start = text.indexOf(from);
  assert.ok(start >= 0, `${label}: "${from}" is gone`);
  const stop = text.indexOf(to, start + from.length);
  assert.ok(stop > start, `${label}: "${to}" no longer follows "${from}"`);
  return text.slice(start, stop + to.length);
}

// ── A + B: process_tribe_request_nudges, the expiry part ──

const NUDGES = body('process_tribe_request_nudges');
const INVITEE_BLOCK = between(NUDGES, 'IF NOT p_dry_run AND v_invitee_due > 0 THEN', 'END IF;', 'invitee notice');
const GP_BLOCK = between(NUDGES, 'IF NOT p_dry_run AND v_gp_due > 0 THEN', 'END IF;', 'GP fallback');

test('A1: the invitee notice goes to the invitee of an expired self-request, through the catalog', () => {
  const due = between(INVITEE_BLOCK, 'WITH due AS (', '), ins AS (', 'invitee due set');
  assert.match(due, /WHERE ii\.status = 'expired'\s+AND ii\.inviter_member_id = ii\.invitee_member_id\s+AND \(ii\.metadata->>'invitee_notified_at'\) IS NULL\s+AND ii\.expires_at > v_run_at - interval '3 days'/,
    'the due set is not "expired self-requests of the last 3 days not yet notified"');
  assert.match(INVITEE_BLOCK, /INSERT INTO public\.notifications\s*\([^)]*\)\s*SELECT d\.invitee_member_id, 'tribe_request_expired',[\s\S]*?'\/workspace',\s*'initiative_invitation', d\.invitation_id, public\._delivery_mode_for\('tribe_request_expired'\)\s*FROM due d/,
    'the expired request does not notify the person who asked');
});

test('A2: the invitee notice says it is not a rejection and marks the request once', () => {
  assert.match(INVITEE_BLOCK, /'tribe_request_expired',\s*'[^']+',\s*'Seu pedido para a tribo ' \|\| d\.title \|\| ' passou do prazo sem resposta do líder\. Isso não é uma recusa\./,
    'the notice text lost "not a rejection"');
  assert.match(INVITEE_BLOCK, /UPDATE public\.initiative_invitations ii\s+SET metadata = ii\.metadata \|\| jsonb_build_object\('invitee_notified_at', v_run_at\)[\s\S]*?AND ii\.inviter_member_id = ii\.invitee_member_id\s+AND \(ii\.metadata->>'invitee_notified_at'\) IS NULL/,
    'the invitee notice is not marked, so it would repeat every hour');
  // The due count that gates the block uses the same population.
  assert.match(NUDGES, /SELECT count\(\*\) INTO v_invitee_due[\s\S]*?WHERE ii\.status = 'expired'\s+AND ii\.inviter_member_id = ii\.invitee_member_id\s+AND \(ii\.metadata->>'invitee_notified_at'\) IS NULL/,
    'the gate count of the invitee notice is not the same population');
});

test('B1: the GP notice names who asked and when, and links to the member page', () => {
  assert.match(GP_BLOCK, /SELECT ii\.id AS invitation_id, ii\.invitee_member_id, ii\.created_at AS requested_at, i\.title/,
    'the GP due set no longer carries the invitee and the request date');
  assert.match(GP_BLOCK, /'tribe_request_expired_gp',\s*'Pedido de tribo de ' \|\| coalesce\(mi\.name, 'um voluntário'\) \|\| ' expirou sem revisão',\s*coalesce\(mi\.name, 'Um voluntário'\) \|\| ' pediu para entrar na tribo ' \|\| d\.title \|\| ' em '\s*\|\| to_char\(d\.requested_at AT TIME ZONE 'America\/Sao_Paulo', 'DD\/MM\/YYYY'\)/,
    'the GP notice does not say who asked and when');
  assert.match(GP_BLOCK, /'\/admin\/members\/' \|\| d\.invitee_member_id::text,\s*'initiative_invitation', d\.invitation_id, public\._delivery_mode_for\('tribe_request_expired_gp'\)/,
    'the GP notice does not link to the person');
  assert.match(GP_BLOCK, /LEFT JOIN public\.members mi ON mi\.id = d\.invitee_member_id/, 'the name is not read from the invitee');
});

test('B2: the GP notice keeps the request message out and drops the tab that never showed the request', () => {
  assert.doesNotMatch(GP_BLOCK, /\bmessage\b/, 'the request message entered the GP notice (it also goes by e-mail)');
  assert.doesNotMatch(GP_BLOCK, /\?tab=members/, 'the GP notice still links to the tribe tab, where an expired request does not appear');
  assert.doesNotMatch(GP_BLOCK, /Um pedido de entrada na tribo/, 'the GP notice went back to the text that does not say who');
});

// ── C: list_tribe_pending_requests ──

test('C: the leader queue lists only pending requests whose deadline has not passed', () => {
  const list = body('list_tribe_pending_requests');
  const where = between(list, 'FROM public.initiative_invitations ii', 'IF v_count > 0 THEN', 'pending list');
  assert.match(where, /WHERE ii\.initiative_id = v_initiative_id\s+AND ii\.status = 'pending'\s+AND ii\.expires_at > now\(\)/,
    'the leader queue lists a request that review_tribe_request will refuse as expired');
});

// ── D: get_my_tribe_request_context ──

test('D: `expired` is the latest self-request, only if that one expired in the last 14 days, only with nothing pending and no tribe', () => {
  const ctx = body('get_my_tribe_request_context');
  const block = between(ctx, 'IF v_pending IS NULL AND v_tribe_id IS NULL AND NOT v_has_tribe_engagement THEN', 'END IF;', 'expired block');
  assert.match(block, /SELECT to_jsonb\(x\) - 'status' INTO v_expired FROM \(/, 'the expired block does not fill v_expired');
  assert.match(block, /WHERE ii\.invitee_member_id = v_member_id AND ii\.inviter_member_id = v_member_id\s+ORDER BY ii\.created_at DESC\s+LIMIT 1\s+\) x\s+WHERE x\.status = 'expired' AND x\.expires_at > now\(\) - interval '14 days';/,
    'expired is not "the latest self-request, when it expired in the last 14 days"');
  const ret = ctx.slice(ctx.lastIndexOf('RETURN jsonb_build_object('));
  assert.match(ret, /'pending', v_pending,\s*'expired', v_expired,/, 'the context does not return expired');
});

// ── E: the delivery catalog covers the flow ──

const FLOW_FUNCTIONS = ['request_tribe_assignment', 'review_tribe_request', 'process_tribe_request_nudges', '_enqueue_engagement_welcome'];

function catalog() {
  const dmf = body('_delivery_mode_for');
  const map = new Map();
  for (const m of dmf.matchAll(/WHEN '([a-z0-9_]+)'\s+THEN '([a-z_]+)'/g)) map.set(m[1], m[2]);
  return map;
}

// Each INSERT INTO public.notifications of a body: the type literal right after the recipient, and the
// delivery_mode expression at the end of the select list or of the VALUES tuple.
function notificationInserts(sql) {
  const out = [];
  for (const m of sql.matchAll(/INSERT INTO public\.notifications\s*\(([^)]*)\)\s*(SELECT|VALUES\s*\()([\s\S]*?)(?:\n\s*FROM\b|\n\s*RETURNING\b|;)/g)) {
    const cols = m[1].split(',').map((c) => c.trim());
    // Only the VALUES form closes its tuple; in the SELECT form a trailing ")" belongs to the last expression.
    const list = (m[2] === 'SELECT' ? m[3] : m[3].replace(/\)\s*$/, '')).trim();
    const type = list.match(/^[^,]+,\s*'([a-z0-9_]+)'/);
    const mode = list.match(/(?:'([a-z_]+)'|public\._delivery_mode_for\('([a-z0-9_]+)'\))\s*$/);
    out.push({ cols, type: type?.[1] ?? null, literalMode: mode?.[1] ?? null, catalogArg: mode?.[2] ?? null, text: m[0].slice(0, 120) });
  }
  return out;
}

test('E: every type the flow writes is catalogued, with the mode its INSERT uses', () => {
  const cat = catalog();
  assert.ok(cat.size > 50, `only ${cat.size} WHEN pairs read from _delivery_mode_for: the parser is not reading the catalog`);
  const seen = new Set();
  const missing = [];
  for (const fn of FLOW_FUNCTIONS) {
    const inserts = notificationInserts(body(fn));
    assert.ok(inserts.length > 0, `${fn}: no INSERT INTO public.notifications found, the parser is blind`);
    for (const ins of inserts) {
      assert.ok(ins.cols.includes('type') && ins.cols.includes('delivery_mode'), `${fn}: an INSERT without type or delivery_mode: ${ins.text}`);
      assert.ok(ins.type, `${fn}: could not read the type of ${ins.text}`);
      assert.ok(ins.literalMode || ins.catalogArg, `${fn}: could not read the delivery_mode of ${ins.type}`);
      seen.add(ins.type);
      if (!cat.has(ins.type)) { missing.push(`${fn}: ${ins.type}`); continue; }
      if (ins.literalMode) assert.equal(ins.literalMode, cat.get(ins.type), `${fn}: ${ins.type} writes '${ins.literalMode}' and the catalog says '${cat.get(ins.type)}'`);
      if (ins.catalogArg) assert.equal(ins.catalogArg, ins.type, `${fn}: ${ins.type} asks the catalog for '${ins.catalogArg}'`);
    }
  }
  assert.deepEqual(missing, [], `types written by the flow and missing from _delivery_mode_for:\n  ${missing.join('\n  ')}`);
  // Positive control: the walk saw the six types it exists to cover.
  for (const t of ['tribe_request', 'tribe_request_reviewed', 'tribe_request_nudge', 'tribe_request_expired_gp', 'tribe_request_expired', 'engagement_welcome']) {
    assert.ok(seen.has(t), `the enumeration did not see ${t}: an INSERT moved or the parser stopped reading it`);
  }
});

test('E2: the expiry part reads every mode from the catalog', () => {
  const inserts = notificationInserts(NUDGES);
  assert.equal(inserts.length, 3, `expected 3 INSERTs in process_tribe_request_nudges, found ${inserts.length}`);
  for (const ins of inserts) assert.equal(ins.catalogArg, ins.type, `${ins.type} still writes a literal delivery_mode`);
});

// ── F: get_onboarding_contacts ──

const CONTACTS = latestFunctionCapture(ROOT, 'get_onboarding_contacts');
const CONTACTS_BODY = maskLineComments(CONTACTS.body);
const CONTACTS_MIG = maskLineComments(readFileSync(resolve(ROOT, 'supabase/migrations', CONTACTS.file), 'utf8'));

test('F1: the reader returns display names only, to active members only', () => {
  assert.match(CONTACTS_BODY, /IF NOT EXISTS \(\s*SELECT 1 FROM public\.members m WHERE m\.auth_id = auth\.uid\(\) AND m\.is_active = true\s*\) THEN\s*RETURN '\[\]'::jsonb;/,
    'a caller who is not an active member gets the names');
  const builds = [...CONTACTS_BODY.matchAll(/jsonb_build_object\(([^)]*)\)/g)].map((m) => m[1].trim());
  assert.deepEqual(builds, ["'name', m.name"], `the reader builds something other than {name}: ${JSON.stringify(builds)}`);
  assert.doesNotMatch(CONTACTS_BODY, /email|phone|pmi_id|to_jsonb|row_to_json|\bm\.\*/i, 'the reader touches a contact field or a whole row');
  assert.match(CONTACTS_BODY, /FROM jsonb_array_elements_text\(v_ids\) WITH ORDINALITY AS c\(member_id, ord\)\s+JOIN public\.members m ON m\.id::text = c\.member_id AND m\.is_active = true/,
    'the names do not come from the key, or a contact who left still shows');
  assert.match(CONTACTS_BODY, /FROM public\.platform_settings ps WHERE ps\.key = 'onboarding_contacts'/, 'the reader does not read its key');
});

test('F2: the reader is SECURITY DEFINER with a search_path, callable by authenticated and service_role only', () => {
  assert.match(CONTACTS.block, /CREATE FUNCTION public\.get_onboarding_contacts\(\)\s+RETURNS jsonb\s+LANGUAGE plpgsql\s+STABLE\s+SECURITY DEFINER\s+SET search_path TO 'public', 'pg_temp'/);
  assert.match(CONTACTS_MIG, /REVOKE ALL ON FUNCTION public\.get_onboarding_contacts\(\) FROM PUBLIC, anon;/, 'anon can call the reader');
  assert.match(CONTACTS_MIG, /GRANT EXECUTE ON FUNCTION public\.get_onboarding_contacts\(\) TO authenticated, service_role;/);
});

test('F3: the seed of the key carries no identifier and does not overwrite a contact changed later', () => {
  const seed = between(CONTACTS_MIG, "INSERT INTO public.platform_settings (key, value, description, change_reason)\nSELECT 'onboarding_contacts',", 'ON CONFLICT (key) DO NOTHING;', 'seed');
  assert.match(seed, /CASE WHEN count\(\*\) = 1 THEN jsonb_build_array\(min\(m\.id::text\)\) ELSE '\[\]'::jsonb END/, 'the seed is not "the single manager, or empty"');
  assert.match(seed, /WHERE m\.operational_role = 'manager' AND m\.member_status = 'active'/);
  assert.doesNotMatch(seed, /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i, 'a member id is written in the repository');
});

// ── G: live ──

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const svc = SUPABASE_URL && SERVICE_KEY ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } }) : null;
const anon = SUPABASE_URL && ANON_KEY ? createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } }) : null;

test('G1 live: anon cannot call get_onboarding_contacts', { skip: anon ? false : 'anon env required' }, async () => {
  const { data, error } = await anon.rpc('get_onboarding_contacts');
  assert.ok(error, `anon called the reader and got ${JSON.stringify(data)}`);
  assert.match(error.message, /permission|denied/i, `anon refused for the wrong reason: ${error.message}`);
});

test('G2 live: with no member behind the call the reader returns an empty list', { skip: svc ? false : 'Supabase env required' }, async () => {
  // service_role has no auth.uid(): proves the reader exists, runs, and fails closed. The member branch (names only)
  // is exercised with impersonation in the verification that goes with the apply.
  const { data, error } = await svc.rpc('get_onboarding_contacts');
  assert.ok(!error, `service_role runs the reader: ${error?.message}`);
  assert.deepEqual(data, [], 'a call with no member got names');
});

// ── H: the panel ──

const BLOCK = maskJsComments(readFileSync(resolve(ROOT, 'src/components/tribe/TribeRequestBlock.tsx'), 'utf8'));

test('H1: the expired state comes before the picker, with "Request again" and "See other tribes"', () => {
  const state = between(BLOCK, 'if (ctx.expired && !pickerOpen) {', '</section>', 'expired state');
  assert.match(state, /\{copy\.expiredBody\(exp\.title\)\}/, 'the expired state does not say what happened');
  assert.match(state, /\{sameOpen && \(\s*<button\s+type="button"\s+onClick=\{retryExpired\}[^>]*>\s*\{copy\.expiredRetry\}/, '"Request again" is not wired to retryExpired');
  assert.match(state, /onClick=\{seeOtherTribes\}[^>]*>\s*\{copy\.expiredSeeOthers\}/, '"See other tribes" is not wired');
  assert.match(state, /\{contact && <ContactBlock lead=\{copy\.contactLeadExpired\}/, 'the expired state has no contact');
  const picker = BLOCK.indexOf('const pickerLangPrefix');
  assert.ok(picker > 0 && BLOCK.indexOf('if (ctx.expired && !pickerOpen) {') < picker, 'the expired state is not before the picker');
});

test('H2: "Request again" reopens the picker with the same tribe and the previous message', () => {
  const fn = between(BLOCK, 'const retryExpired = useCallback(() => {', '}, [ctx]);', 'retryExpired');
  assert.match(fn, /const exp = ctx\?\.expired;/);
  assert.match(fn, /setSelected\(open \? exp\.tribe_id : null\);\s*setMessage\(exp\.message \|\| ''\);\s*setPickerOpen\(true\);/,
    '"Request again" does not bring back the tribe and the message of the expired request');
});

test('H3: the contact is in the pending, expired and empty states, and loads where it is shown', () => {
  const pending = between(BLOCK, 'if (ctx.pending) {', '</section>', 'pending state');
  assert.match(pending, /\{contact && <ContactBlock lead=\{copy\.contactLeadPending\}/, 'the pending state has no contact');
  const empty = between(BLOCK, 'if (!ctx.tribes || ctx.tribes.length === 0) {', '</section>', 'empty state');
  assert.match(empty, /\{contact && <ContactBlock lead=\{copy\.contactLeadEmpty\}/, 'the empty state has no contact');
  // PR-4 (#1885) widened the load to every state of who has the Term and no tribe (the picker shows the contact too).
  assert.match(BLOCK, /if \(next\.pending \|\| next\.eligible\) loadContact\(sb\);/, 'the contact is not loaded for the states that show it');
  const lc = between(BLOCK, 'const loadContact = useCallback(async (sb: any) => {', '}, []);', 'loadContact');
  assert.match(lc, /sb\.rpc\('get_community_group_link', \{ p_group: 'onboarding' \}\)/, 'the group is not the onboarding group');
  assert.match(lc, /sb\.rpc\('get_onboarding_contacts'\)/, 'the names do not come from the reader');
});

test('H4: the response-time promise sits only next to the onboarding group; without it, the Núcleo address', () => {
  const block = between(BLOCK, 'function ContactBlock(', '\n}\n', 'ContactBlock');
  const withGroup = between(block, '{groupUrl && (', '</>', 'group branch');
  assert.match(withGroup, /\{phoneVisibleNotice\(lang\)\}[\s\S]*href=\{groupUrl\}[\s\S]*\{copy\.contactResponse\}/, 'the group branch lost the phone notice or the promise');
  const without = between(block, '{!groupUrl && (', '</a>', 'fallback branch');
  assert.match(without, /href=\{`mailto:\$\{COORDINATION_EMAIL\}`\}/, 'without the group the block has no channel');
  assert.doesNotMatch(without, /contactResponse/, 'the 3-day promise went to the e-mail, which the owner did not promise');
  assert.equal([...block.matchAll(/copy\.contactResponse/g)].length, 1, 'the promise appears more than once');
});

test('H5: the expired text says it is not a rejection, in the 3 languages; the group keeps its generic name', () => {
  for (const re of [
    /expiredBody: \(title\) => `Seu pedido para a tribo \$\{title\} passou do prazo sem resposta do líder\. Isso não é uma recusa\.`/,
    /expiredBody: \(title\) => `Your request to join the \$\{title\} tribe passed its deadline without a reply from the leader\. This is not a rejection\.`/,
    /expiredBody: \(title\) => `Tu solicitud para entrar en la tribu \$\{title\} pasó del plazo sin respuesta del líder\. Esto no es un rechazo\.`/,
  ]) assert.match(BLOCK, re);
  const groups = [...BLOCK.matchAll(/contactGroup: '([^']*)'/g)].map((m) => m[1]);
  assert.deepEqual(groups, [
    'Entrar no grupo de WhatsApp do onboarding do Núcleo',
    'Join the Hub onboarding WhatsApp group',
    'Entrar al grupo de WhatsApp de onboarding del Núcleo',
  ]);
  const responses = [...BLOCK.matchAll(/contactResponse: '([^']*)'/g)].map((m) => m[1]);
  assert.equal(responses.length, 3);
  for (const r of responses) assert.match(r, /3/, `the response time is missing: ${r}`);
});

// Sanity: this guard reads the migration the reader lives in, not a stale copy.
test('Z: the reader is defined once in the migrations', () => {
  const files = readdirSync(join(ROOT, 'supabase/migrations')).filter((f) => f.endsWith('.sql'));
  const defs = files.filter((f) => /CREATE (OR REPLACE )?FUNCTION public\.get_onboarding_contacts\(/.test(readFileSync(join(ROOT, 'supabase/migrations', f), 'utf8')));
  assert.equal(defs.length, 1, `get_onboarding_contacts defined in ${defs.length} migrations: ${defs.join(', ')}`);
});
