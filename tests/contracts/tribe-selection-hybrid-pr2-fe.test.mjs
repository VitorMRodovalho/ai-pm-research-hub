/**
 * Contract: Tribe Selection Híbrida — PR2 (researcher-facing). SPEC §5, migration 20260805000217.
 *
 * Continuous post-promotion tribe entry: TribeRequestBlock island on /workspace lets a promoted,
 * termed researcher WITHOUT a tribe pick a tribe + write a motivation (>= 50 chars) and submit a
 * request (request_tribe_assignment, shipped in PR1). The leader approves it via review_tribe_request
 * (PR3) -> the bridge trigger sets members.tribe_id.
 *
 * ONE read powers the island: get_my_tribe_request_context() -> { eligible, pending, tribes }.
 * GROUNDING CORRECTION: the SPEC said PR2 reuses `list_my_initiative_invitations` — that public RPC
 * does NOT exist (MCP-only tool name); the only invitations-list RPC is the LEADER-facing
 * list_invitations_for_my_initiatives. PR2 adds the missing researcher-facing read (mig 217).
 *
 * Static source assertions + DB-gated shape check on the new read RPC.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const MIG_FILE = '20260805000217_tribe_selection_hybrid_pr2_read_context.sql';
const MIG = read(`supabase/migrations/${MIG_FILE}`);
const BLOCK = read('src/components/tribe/TribeRequestBlock.tsx');
const WK = read('src/pages/workspace.astro');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── (A) migration: the read RPC + grants ──
test('migration declares get_my_tribe_request_context, authenticated-only', () => {
  assert.ok(MIG, 'migration file exists');
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_my_tribe_request_context\(\)/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.get_my_tribe_request_context\(\) FROM PUBLIC, anon;/);
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.get_my_tribe_request_context\(\) TO authenticated;/);
});

test('read RPC eligibility mirrors the request_tribe_assignment gates (termed, no tribe, active)', () => {
  assert.match(MIG, /member_is_pre_onboarding\(v_person_id, v_member_status\)/);
  assert.match(MIG, /v_tribe_id IS NULL/);
  // "already in a tribe" guard: active volunteer engagement in a research_tribe initiative
  assert.match(MIG, /e\.kind = 'volunteer' AND e\.status = 'active'/);
  // selectable tribes are the active research_tribe initiatives (SSOT), not static data
  assert.match(MIG, /i\.kind = 'research_tribe' AND i\.status = 'active'/);
});

test('migration is registered in the active synthetic series', () => {
  const files = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => f.endsWith('.sql'));
  assert.ok(files.includes(MIG_FILE), 'migration present');
  const ts = Number(MIG_FILE.slice(0, 14));
  assert.ok(ts >= 20260805000217 && ts < 20260806000000, 'timestamp in the active synthetic series');
});

// ── (B) island: reads context, calls the PR1 write, self-gates, trilingual ──
test('TribeRequestBlock: component exists', () => {
  assert.ok(BLOCK, 'TribeRequestBlock.tsx exists');
});

test('TribeRequestBlock: one read powers the island (get_my_tribe_request_context)', () => {
  assert.match(BLOCK, /rpc\(['"]get_my_tribe_request_context['"]\)/);
});

test('TribeRequestBlock: submits via request_tribe_assignment (the PR1 write RPC)', () => {
  assert.match(BLOCK, /rpc\(['"]request_tribe_assignment['"],\s*\{[\s\S]*?p_tribe_id[\s\S]*?p_message/);
});

test('TribeRequestBlock: enforces the >= 50 char motivation before enabling submit', () => {
  assert.match(BLOCK, /MIN_MESSAGE\s*=\s*50/);
  assert.match(BLOCK, /remaining === 0/);
});

test('TribeRequestBlock: self-gates on server-truthed eligible/pending (no client-side authority)', () => {
  // pending -> awaiting-leader state; else eligible+tribes -> picker; else render nothing
  assert.match(BLOCK, /ctx\.pending/);
  assert.match(BLOCK, /ctx\.eligible/);
  assert.match(BLOCK, /return null/);
});

test('TribeRequestBlock: does NOT call review/approve RPCs (that is the leader-facing PR3)', () => {
  assert.ok(!/rpc\(['"]review_tribe_request['"]/.test(BLOCK), 'no review_tribe_request');
  assert.ok(!/rpc\(['"]select_tribe['"]/.test(BLOCK), 'no legacy select_tribe');
});

test('TribeRequestBlock: trilingual copy (pt-BR / en-US / es-LATAM)', () => {
  assert.match(BLOCK, /'pt-BR':/);
  assert.match(BLOCK, /'en-US':/);
  assert.match(BLOCK, /'es-LATAM':/);
});

test('workspace.astro mounts TribeRequestBlock', () => {
  assert.match(WK, /import TribeRequestBlock from '\.\.\/components\/tribe\/TribeRequestBlock'/);
  assert.match(WK, /<TribeRequestBlock client:load lang=\{lang\} \/>/);
});

// ── (C) DB-gated: the read RPC returns the right shape ──
test('DB: get_my_tribe_request_context returns { eligible, pending, tribes }', { skip: !dbGated && skipMsg }, async () => {
  const supa = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await supa.rpc('get_my_tribe_request_context');
  assert.equal(error, null, error ? `rpc failed: ${error.message}` : '');
  assert.ok(data && typeof data === 'object', 'returns an object');
  assert.ok('eligible' in data && 'pending' in data && 'tribes' in data, 'has eligible/pending/tribes');
  assert.ok(Array.isArray(data.tribes), 'tribes is an array');
  // service_role has no member row -> not eligible; tribes still lists active research_tribe initiatives
  assert.equal(data.eligible, false, 'service_role (no member) is not eligible');
  for (const t of data.tribes) {
    assert.ok(typeof t.tribe_id === 'number' && typeof t.title === 'string', 'tribe option shape');
  }
});

// ── (D) #1139: ineligibility empty-states (reason + next step, never a blank block) ──
const MIG_1139 = read('supabase/migrations/20260805000347_1139_tribe_journey_hardening.sql');
const TRIBE_PAGE = read('src/pages/tribe/[id].astro');

test('#1139 migration: get_my_tribe_request_context surfaces ineligible_reason + current_tribe_title', () => {
  assert.ok(MIG_1139, 'mig 347 exists');
  assert.match(MIG_1139, /'ineligible_reason'/);
  assert.match(MIG_1139, /'current_tribe_title'/);
  assert.match(MIG_1139, /'pending_term'/); // the dominant kickoff case (unsigned volunteer term)
  assert.match(MIG_1139, /member_is_pre_onboarding/);
});

test('#1139 migration: request_tribe_assignment deep-links the leader notification to the Membros tab', () => {
  assert.match(MIG_1139, /'\/tribe\/' \|\| p_tribe_id::text \|\| '\?tab=members'/);
});

test('#1139 FE: TribeRequestBlock renders pending_term + has_tribe empty-states with a sign-term CTA', () => {
  assert.match(BLOCK, /ineligible_reason === 'pending_term'/);
  assert.match(BLOCK, /\/volunteer-agreement/); // actionable next step for the unsigned-term cohort
  assert.match(BLOCK, /ineligible_reason === 'has_tribe'/);
});

test('#1139 FE: Membros-tab pending-request badge + sync helper live on the tribe page', () => {
  assert.match(TRIBE_PAGE, /members-req-badge/);
  assert.match(TRIBE_PAGE, /function syncMembersReqBadge/);
  assert.match(TRIBE_PAGE, /tribe\.requests\.pendingBadge/);
});

test('#1139 i18n: tribe.requests.pendingBadge exists in all 3 dictionaries', () => {
  for (const f of ['pt-BR', 'en-US', 'es-LATAM']) {
    assert.match(read(`src/i18n/${f}.ts`), /'tribe\.requests\.pendingBadge'/, `${f} has pendingBadge`);
  }
});

test('DB: get_my_tribe_request_context now includes ineligible_reason (no_member for service_role)', { skip: !dbGated && skipMsg }, async () => {
  const supa = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await supa.rpc('get_my_tribe_request_context');
  assert.equal(error, null, error ? `rpc failed: ${error.message}` : '');
  assert.ok('ineligible_reason' in data && 'current_tribe_title' in data, 'has the new reason keys');
  assert.equal(data.ineligible_reason, 'no_member', 'service_role (no member) -> no_member reason');
});
