/**
 * Contract: #308-PR0 (#987) — curation_review_log RLS deny-all + REVOKE anon
 * get_all_certificates + denormalized initiative_id. Behavior-neutral hardening.
 * Parent #308 · Spec docs/specs/SPEC_308_CURATOR_EVIDENCE_BUNDLES.md §8/§11 · ADR-0119.
 *
 * Three items, all re-grounded live (prod ldrfrvwhxsmgaabwmaik, 2026-06-30):
 *  (a) curation_review_log SELECT was PERMISSIVE USING(true) to `authenticated`
 *      → replaced with an explicit deny-all FOR SELECT USING(false). All reads go
 *      via the 7 SECURITY DEFINER readers (exec_cycle_report, get_curation_dashboard,
 *      get_curation_queue_state, get_item_curation_history, get_card_full_history,
 *      list_curation_pending_board_items, submit_curation_review) which bypass RLS.
 *  (b) get_all_certificates(text,text,boolean): EXECUTE was held via the default
 *      PUBLIC grant AND an explicit anon grant → REVOKE FROM PUBLIC, anon; keep
 *      authenticated + service_role. #965-class but READ-ONLY ⇒ NOT in the #965 sweep
 *      and deliberately NOT added to that allowlist (SPEC §11 F-H7).
 *  (c) initiative_id denormalized onto curation_review_log via
 *      board_item_id → board_items.board_id → project_boards.initiative_id,
 *      kept fresh by a BEFORE INSERT trigger (no RPC body touched ⇒ neutral, F-B2).
 *
 * Layers: (A) static migration-file guard (always). (B) DB-aware service-role probes
 * (SKIP without SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY). (C) anon-negative probe
 * (SKIP unless a REAL anon key is present — CI provides a mock key, so it skips there).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(
  __dirname,
  '../../supabase/migrations/20260805000307_987_pr0_curation_review_log_rls_hardening.sql',
);
// Defensive read (684 pattern): a missing file becomes a clean assertion, not an ENOENT crash.
const sql = existsSync(MIGRATION_PATH) ? readFileSync(MIGRATION_PATH, 'utf8') : '';

const GAC_SIG = 'get_all_certificates(text, text, boolean)';

// ─────────────────────────────────────────────────────────────────────────
// (A) Static migration-file guard — always runs (offline safe)
// ─────────────────────────────────────────────────────────────────────────
test('#987 (a) curation_review_log SELECT is deny-all (drops USING(true) read policy)', () => {
  assert.ok(sql, `migration file missing at expected path: ${MIGRATION_PATH}`);
  assert.ok(
    sql.includes('DROP POLICY IF EXISTS curation_review_log_read ON public.curation_review_log'),
    'must drop the USING(true) read policy',
  );
  assert.ok(
    sql.includes('CREATE POLICY curation_review_log_no_direct_select'),
    'must create the deny-all read policy',
  );
  assert.match(sql, /curation_review_log_no_direct_select[\s\S]*?FOR SELECT[\s\S]*?USING \(false\)/, 'deny-all is FOR SELECT USING (false)');
});

test('#987 (b) REVOKE anon on get_all_certificates via PUBLIC + anon (keeps authenticated + service_role)', () => {
  // ACL grounding: EXECUTE was held via the default PUBLIC grant AND an explicit anon
  // grant — REVOKE FROM anon alone is a no-op, so PUBLIC must be revoked too.
  assert.ok(
    sql.includes(`REVOKE EXECUTE ON FUNCTION public.${GAC_SIG} FROM PUBLIC, anon`),
    'must REVOKE FROM PUBLIC, anon (not FROM anon alone — anon inherits via PUBLIC)',
  );
  assert.ok(
    sql.includes(`GRANT  EXECUTE ON FUNCTION public.${GAC_SIG} TO authenticated, service_role`),
    'must keep authenticated + service_role',
  );
  // Must NOT over-revoke authenticated (the admin certificates UI calls this).
  assert.ok(
    !sql.includes(`REVOKE EXECUTE ON FUNCTION public.${GAC_SIG} FROM PUBLIC, anon, authenticated`),
    'authenticated must NOT be revoked',
  );
});

test('#987 (c) initiative_id denormalized from project_boards + kept fresh by a BEFORE INSERT trigger', () => {
  assert.ok(sql.includes('ADD COLUMN IF NOT EXISTS initiative_id uuid'), 'adds nullable initiative_id');
  assert.ok(
    sql.includes('REFERENCES public.initiatives(id) ON DELETE SET NULL'),
    'FK → initiatives ON DELETE SET NULL (mirrors project_boards.initiative_id convention)',
  );
  assert.ok(
    sql.includes('CREATE TRIGGER trg_curation_review_log_fill_initiative'),
    'installs the denorm-fill trigger',
  );
  assert.match(sql, /BEFORE INSERT ON public\.curation_review_log/, 'trigger is BEFORE INSERT');
  // Grounding correction: derivation is board_item → project_boards (board_items has no initiative_id).
  assert.match(
    sql,
    /JOIN public\.project_boards pb ON pb\.id = bi\.board_id/,
    'derives initiative_id via board_items.board_id → project_boards.initiative_id',
  );
  // security-medium: gate-bearing denorm must derive UNCONDITIONALLY, never trust caller input.
  assert.ok(
    !/IF\s+NEW\.initiative_id\s+IS\s+NULL/i.test(sql),
    'trigger must NOT honor caller-supplied initiative_id (no IF NEW.initiative_id IS NULL guard)',
  );
});

test('#987 forward-defense: anon-execute audit oracle defined + locked to service_role', () => {
  assert.ok(
    sql.includes('CREATE OR REPLACE FUNCTION public._audit_get_all_certificates_anon_execute()'),
    'audit oracle must be defined',
  );
  assert.ok(
    sql.includes('REVOKE EXECUTE ON FUNCTION public._audit_get_all_certificates_anon_execute() FROM PUBLIC, anon, authenticated'),
    'audit oracle must be locked down',
  );
  assert.ok(
    sql.includes('GRANT  EXECUTE ON FUNCTION public._audit_get_all_certificates_anon_execute() TO service_role'),
    'audit oracle callable by service_role',
  );
});

test('#987 behavior-neutral: migration does NOT redefine submit_curation_review (F-B2)', () => {
  // A header-comment mention is fine; what must NOT appear is DDL redefining the RPC.
  assert.ok(
    !/(CREATE|ALTER|DROP)\s+(OR\s+REPLACE\s+)?FUNCTION\s+public\.submit_curation_review/i.test(sql),
    'no production RPC body change (F-B2)',
  );
});

test('#987 F-H7: get_all_certificates is NOT added to the #965 allowlist', () => {
  // It is READ-ONLY ⇒ never in the _audit_secdef_public_grant_drift() sweep;
  // adding it to the allowlist would be wrong (SPEC §11 F-H7).
  const p965 = join(__dirname, '965-secdef-public-grant-drift.test.mjs');
  const s965 = existsSync(p965) ? readFileSync(p965, 'utf8') : '';
  assert.ok(s965, '#965 test file present');
  assert.ok(!s965.includes('get_all_certificates'), 'get_all_certificates must NOT appear in the #965 allowlist');
});

// ─────────────────────────────────────────────────────────────────────────
// (B) DB-aware — service role (real DB required)
// ─────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const svc = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test('#987 db: curation_review_log.initiative_id column exists (PostgREST-selectable)', { skip: dbGated ? false : skipMsg }, async () => {
  const { error } = await svc().from('curation_review_log').select('initiative_id').limit(1);
  assert.ok(!error, `initiative_id must be selectable, got: ${JSON.stringify(error)}`);
});

test('#987 db: get_all_certificates retains EXECUTE for service_role (GRANT intact)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await svc().rpc('get_all_certificates', {
    p_status_filter: null, p_search: null, p_include_volunteer_agreements: false,
  });
  // A grant/permission failure would surface as a PostgREST error — assert there is none.
  assert.ok(!error, `service_role must retain EXECUTE (no permission error): ${JSON.stringify(error)}`);
  // Returns a jsonb envelope: either the Unauthorized gate (null-auth) or a summary.
  assert.ok(data && typeof data === 'object', `must return a jsonb object, got: ${String(data).slice(0, 120)}`);
});

test('#987 db: anon has NO EXECUTE on get_all_certificates (live grant ratchet)', { skip: dbGated ? false : skipMsg }, async () => {
  // Runs in CI via service_role (no anon key needed) — the durable guard for item (b).
  const { data, error } = await svc().rpc('_audit_get_all_certificates_anon_execute');
  assert.ok(!error, `audit oracle must be callable by service_role: ${JSON.stringify(error)}`);
  assert.equal(data, false, 'anon must NOT have EXECUTE on get_all_certificates (REVOKE intact)');
});

// ─────────────────────────────────────────────────────────────────────────
// (C) DB-aware — anon-negative (real anon key required; CI uses a mock → skips)
// ─────────────────────────────────────────────────────────────────────────
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const realAnon = !!(SUPABASE_URL && ANON_KEY && !/mock/i.test(ANON_KEY));
const anonSkip = 'Skipped: real anon key required (CI provides a mock key)';

test('#987 db(anon): get_all_certificates is not anon-executable after REVOKE', { skip: realAnon ? false : anonSkip }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { error } = await anon.rpc('get_all_certificates', {
    p_status_filter: null, p_search: null, p_include_volunteer_agreements: false,
  });
  assert.ok(error, 'anon must be blocked at the grant layer (no EXECUTE)');
});
