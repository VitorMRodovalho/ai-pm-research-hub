/**
 * Contract: Tribe Selection Híbrida — PR3 (leader-facing). SPEC §5, migration 20260805000218.
 *
 * Closes the hybrid loop: a tribe LEADER (or GP) sees the pending join requests for their tribe on
 * the /tribe/[id] Membros tab and [Accept]/[Decline]s each via review_tribe_request (PR1). Approving
 * fires the bridge trigger -> members.tribe_id.
 *
 * GROUNDING CORRECTION: the SPEC said PR3 reuses `list_invitations_for_my_initiatives`. That RPC
 * scopes to owner/coordinator/lead (role IN ('owner','coordinator','lead')) OR admin — a tribe leader
 * is volunteer/role='leader' ('leader' != 'lead'), so it returns EMPTY for them. Same authority gap
 * PR1 hit on the WRITE path. PR3 adds list_tribe_pending_requests with the SAME Caminho-3 inline
 * authority as review_tribe_request.
 *
 * Static source assertions + a DB-gated auth-gate check.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const MIG_FILE = '20260805000218_tribe_selection_hybrid_pr3_leader_queue.sql';
const MIG = read(`supabase/migrations/${MIG_FILE}`);
const PAGE = read('src/pages/tribe/[id].astro');
const PT = read('src/i18n/pt-BR.ts');
const EN = read('src/i18n/en-US.ts');
const ES = read('src/i18n/es-LATAM.ts');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── (A) migration: reader RPC + Caminho-3 authority + grants + PII logging ──
test('migration declares list_tribe_pending_requests, authenticated-only', () => {
  assert.ok(MIG, 'migration file exists');
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.list_tribe_pending_requests\(p_tribe_id integer\)/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.list_tribe_pending_requests\(integer\) FROM PUBLIC, anon;/);
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.list_tribe_pending_requests\(integer\) TO authenticated;/);
});

test('reader uses Caminho-3 inline authority (GP OR volunteer/leader of THIS tribe), not the shared gate', () => {
  assert.match(MIG, /can_by_member\(v_caller_member_id, 'manage_member'\)/);
  assert.match(MIG, /e\.initiative_id = v_initiative_id\s+AND e\.kind = 'volunteer'\s+AND e\.role = 'leader'/);
  // resolves the tribe's research_tribe initiative from the integer id (scoped, not the shared reader)
  assert.match(MIG, /i\.legacy_tribe_id = p_tribe_id AND i\.kind = 'research_tribe'/);
});

test('reader is scoped to self-requests + logs PII access for invitee names', () => {
  assert.match(MIG, /ii\.invitee_member_id = ii\.inviter_member_id/);
  assert.match(MIG, /log_pii_access\(/);
  assert.match(MIG, /ii\.status = 'pending'/);
});

test('migration is registered in the active synthetic series', () => {
  const files = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => f.endsWith('.sql'));
  assert.ok(files.includes(MIG_FILE), 'migration present');
  const ts = Number(MIG_FILE.slice(0, 14));
  assert.ok(ts >= 20260805000218 && ts < 20260806000000, 'timestamp in the active synthetic series');
});

// ── (B) page: leader-gated section reads the reader + acts via the PR1 write ──
test('tribe page renders the leader queue from list_tribe_pending_requests', () => {
  assert.match(PAGE, /rpc\(['"]list_tribe_pending_requests['"],\s*\{\s*p_tribe_id:\s*TRIBE_ID/);
  assert.match(PAGE, /tribeRequestsSectionHtml/);
});

test('tribe page gates the queue on isLeaderOfThisTribeV4 (leader/GP display gate)', () => {
  assert.match(PAGE, /if \(!isLeaderOfThisTribeV4\(\)\) return ''/);
});

test('accept/decline call review_tribe_request (the PR1 write) with approve/decline', () => {
  assert.match(PAGE, /rpc\(['"]review_tribe_request['"],\s*\{[\s\S]*?p_invitation_id[\s\S]*?p_decision/);
  assert.match(PAGE, /action === 'review-tribe-accept'/);
  assert.match(PAGE, /action === 'review-tribe-decline'/);
  // shared submit receives the explicit decision; accept passes 'approve', decline-confirm passes 'decline'
  assert.match(PAGE, /submitTribeReview\([\s\S]*?'approve'/);
  assert.match(PAGE, /submitTribeReview\([\s\S]*?'decline'/);
});

test('decline is two-step with an optional reason passed as p_note (not always null)', () => {
  assert.match(PAGE, /data-action="review-tribe-decline-confirm"/);
  assert.match(PAGE, /data-action="review-tribe-decline-cancel"/);
  assert.match(PAGE, /data-req-note/);
  // the note value is read and forwarded (review can carry a reason)
  assert.match(PAGE, /p_note: note/);
});

test('queue empties cleanly + a11y: status region, focus move, section removal', () => {
  assert.match(PAGE, /data-req-status/);
  assert.match(PAGE, /aria-busy/);
  assert.match(PAGE, /section\?\.remove\(\)/);
});

// ── (C) i18n: 3-dict parity for the new keys ──
test('tribe.requests.* keys exist in all 3 dictionaries', () => {
  for (const [name, dict] of [['pt-BR', PT], ['en-US', EN], ['es-LATAM', ES]]) {
    for (const k of ['title', 'subtitle', 'accept', 'decline', 'toastAccepted', 'toastDeclined', 'toastError']) {
      assert.ok(dict.includes(`'tribe.requests.${k}'`), `${name} missing tribe.requests.${k}`);
    }
  }
});

// ── (D) DB-gated: the reader's auth gate fires for a caller with no member row ──
test('DB: list_tribe_pending_requests rejects a caller with no active member (auth gate)', { skip: !dbGated && skipMsg }, async () => {
  const supa = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // service_role has no members row -> auth.uid() is null -> 'Not authenticated'
  const { error } = await supa.rpc('list_tribe_pending_requests', { p_tribe_id: 1 });
  assert.ok(error, 'expected an error for a non-member caller');
});
