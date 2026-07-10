/**
 * Contract: Tribe request deadline enforcement (migration 20260805000397).
 *
 * The tribe-choice deadline (16/07 23:59 BRT = 17/07 02:59 UTC) was communicated to volunteers but
 * nothing in code stopped new self-service requests after it. This migration makes it real, server-side:
 *   1. SSOT setting platform_settings.tribe_request_deadline (ISO-8601 UTC; absent/null = open window).
 *   2. request_tribe_assignment: hard gate — rejects NEW requests once now() > deadline. This is the
 *      REAL enforcement (the FE picker hiding is cosmetic; the RPC is callable directly).
 *   3. get_my_tribe_request_context: mirrors the gate as ineligible_reason='window_closed' and returns
 *      the deadline so the FE shows it in the open picker and renders a closed empty-state.
 *
 * The end-to-end gate behaviour (impersonated active member + past deadline -> RPC raises) was validated
 * via a rolled-back transactional smoke test at apply time (gate_fired=true, setting left untouched);
 * CI keeps the DB checks read-only per house convention (see tribe-selection-hybrid-pr1.test.mjs).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const MIG_FILE = '20260805000397_tribe_request_deadline_enforcement.sql';
const MIG = read(`supabase/migrations/${MIG_FILE}`);
const BLOCK = read('src/components/tribe/TribeRequestBlock.tsx');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── (A) static: the migration seeds the setting + gates both RPCs ──
test('migration seeds the tribe_request_deadline SSOT setting (idempotent)', () => {
  assert.ok(MIG, 'migration file exists');
  assert.match(MIG, /INSERT INTO public\.platform_settings[\s\S]*'tribe_request_deadline'/);
  assert.match(MIG, /ON CONFLICT \(key\) DO UPDATE/);
});

test('request_tribe_assignment gains the deadline gate (reads the SSOT, raises after the deadline)', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.request_tribe_assignment\(p_tribe_id integer, p_message text\)/);
  // reads the deadline from the SSOT setting and blocks once now() has passed it
  assert.match(MIG, /FROM public\.platform_settings WHERE key = 'tribe_request_deadline'/);
  assert.match(MIG, /v_deadline IS NOT NULL AND now\(\) > v_deadline/);
  assert.match(MIG, /O prazo para pedir uma tribo encerrou/);
  // the gate must be BEFORE the write (invitation INSERT) so nothing is created after the deadline
  const gateIdx = MIG.search(/v_deadline IS NOT NULL AND now\(\) > v_deadline/);
  const insertIdx = MIG.search(/INSERT INTO public\.initiative_invitations/);
  assert.ok(gateIdx > 0 && insertIdx > 0 && gateIdx < insertIdx, 'deadline gate precedes the invitation INSERT');
});

test('request_tribe_assignment keeps the pre-existing gates (term + already-in-a-tribe)', () => {
  // the deadline gate is ADDED, not a replacement: the volunteer-term + single-tribe guards remain
  assert.match(MIG, /member_is_pre_onboarding\(v_person_id, v_member_status\)/);
  assert.match(MIG, /Você já participa de uma tribo/);
});

test('get_my_tribe_request_context computes window_closed and returns the deadline', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_my_tribe_request_context\(\)/);
  assert.match(MIG, /v_window_closed := v_deadline IS NOT NULL AND now\(\) > v_deadline/);
  assert.match(MIG, /v_reason := 'window_closed'/);
  assert.match(MIG, /'deadline', v_deadline/);
  // window_closed only blocks callers WITHOUT a tribe (deadline is about joining, not existing membership)
  assert.match(MIG, /IF v_window_closed AND v_tribe_id IS NULL AND NOT v_has_tribe_engagement THEN/);
});

test('migration is registered in the active synthetic series', () => {
  const files = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => f.endsWith('.sql'));
  assert.ok(files.includes(MIG_FILE), 'migration present in migrations dir');
  const ts = Number(MIG_FILE.slice(0, 14));
  assert.ok(ts >= 20260805000397 && ts < 20260806000000, 'timestamp in the active synthetic series');
});

// ── (B) FE: the island surfaces the deadline + the closed empty-state ──
test('TribeRequestBlock: ineligible_reason type includes window_closed', () => {
  assert.match(BLOCK, /'pending_term'\s*\|\s*'window_closed'/);
});

test('TribeRequestBlock: renders the window_closed empty-state (routes to coordination)', () => {
  assert.match(BLOCK, /ineligible_reason === 'window_closed'/);
  assert.match(BLOCK, /windowClosedTitle/);
  assert.match(BLOCK, /windowClosedBody/);
});

test('TribeRequestBlock: shows the deadline in the open picker', () => {
  assert.match(BLOCK, /ctx\.deadline &&/);
  assert.match(BLOCK, /deadlineNotice\(formatDeadline\(ctx\.deadline, lang\)\)/);
});

test('TribeRequestBlock: window_closed copy is localized in all 3 dictionaries', () => {
  assert.match(BLOCK, /O prazo para escolher tribo encerrou/);   // pt-BR
  assert.match(BLOCK, /Tribe selection is closed/);              // en-US
  assert.match(BLOCK, /El plazo para elegir tribu terminó/);     // es-LATAM
  // deadlineNotice: interface declaration + one impl per locale = 4 `deadlineNotice:` sites
  assert.equal((BLOCK.match(/deadlineNotice:/g) || []).length, 4, 'deadlineNotice declared + 3 locale impls');
});

// ── (C) DB-gated (read-only): the setting is live + the context exposes the deadline key ──
test('DB: tribe_request_deadline setting is present and parseable', { skip: !dbGated && skipMsg }, async () => {
  const supa = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await supa.from('platform_settings').select('key,value').eq('key', 'tribe_request_deadline').single();
  assert.equal(error, null, error ? `select failed: ${error.message}` : '');
  assert.ok(data, 'setting row exists');
  // value is a JSON string; must parse to a valid date
  const iso = typeof data.value === 'string' ? data.value : String(data.value);
  assert.ok(!Number.isNaN(Date.parse(iso)), `deadline value parses to a date (got ${iso})`);
});

test('DB: get_my_tribe_request_context includes the deadline key (null for the no-member caller)', { skip: !dbGated && skipMsg }, async () => {
  const supa = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await supa.rpc('get_my_tribe_request_context');
  assert.equal(error, null, error ? `rpc failed: ${error.message}` : '');
  assert.ok(data && typeof data === 'object', 'returns an object');
  assert.ok('deadline' in data, 'payload carries the deadline key');
  // service_role has no member row -> early no_member return, deadline is null there
  assert.equal(data.deadline, null, 'no-member caller gets deadline=null');
});
