/**
 * Forward-defense: p233 #321 / Gap A of #230 reframe —
 *   complete onboarding_progress.volunteer_term when matching cert is issued.
 *
 * Origin: p230 audit (2026-05-23) of #230 reframe surfaced Gap A:
 *   sign_volunteer_agreement() inserts a certificates row of
 *   type='volunteer_agreement' but does NOT atomically mark the corresponding
 *   onboarding_progress.volunteer_term row as completed. Result: 30 of 38
 *   pending vol_term rows had a matching cert (88% phantom rate).
 *
 * Migration: supabase/migrations/20260805000018_p233_321_complete_volunteer_term_on_cert.sql
 *
 * Asserts:
 *   - Static (11): migration file present + trigger fn SECDEF/search_path +
 *     AFTER INSERT trigger WHEN clause + body NULL member_id guard +
 *     idempotent UPDATE + metadata enrichment + audit gated on rows_affected +
 *     backfill DISTINCT ON CTE + backfill audit + sanity RAISE EXCEPTION +
 *     NOTIFY pgrst.
 *   - DB-gated (1): post-backfill state has 0 phantom vol_term rows where
 *     matching cert exists. Skip when SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
 *     are absent.
 *
 * Cross-ref:
 *   - GH #321
 *   - p230 audit doc: docs/audit/HERLON_TRUST_AUDIT_P230.md (live evidence)
 *   - sign_volunteer_agreement() RPC (mig 20260415020000 + p209 cap fix)
 *   - sibling triggers on certificates: trg_auto_remove_designation_on_cert,
 *     trg_certificate_pdf_autogen (unaffected — independent scope)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(
  ROOT,
  'supabase/migrations/20260805000018_p233_321_complete_volunteer_term_on_cert.sql'
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ===================================================================
// STATIC migration body assertions (always run — forward-defense)
// ===================================================================

test('p233 #321: migration file present at canonical path', () => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.startsWith('20260805000018_'));
  assert.equal(files.length, 1,
    'Exactly one migration file must exist for version 20260805000018 (p233 #321 Gap A)');
  assert.match(files[0], /^20260805000018_p233_321_complete_volunteer_term_on_cert\.sql$/,
    'Migration filename must follow `<timestamp>_<descriptive_name>.sql` per CLAUDE.md GC-097');
});

test('p233 #321: trigger function declared with SECURITY DEFINER + pinned search_path', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\._trg_complete_volunteer_term_on_cert\(\)/i,
    'Trigger function name must be canonical _trg_complete_volunteer_term_on_cert');
  assert.match(body, /SECURITY DEFINER/i,
    'Trigger function must be SECURITY DEFINER (writes admin_audit_log under elevated context)');
  assert.match(body, /SET search_path = 'public', 'pg_temp'/i,
    'Trigger function must pin search_path to public + pg_temp (CLAUDE.md GC-097 search_path injection defense)');
});

test('p233 #321: trigger is AFTER INSERT on certificates with WHEN (NEW.type = volunteer_agreement)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /DROP TRIGGER IF EXISTS trg_complete_volunteer_term_on_cert ON public\.certificates/i,
    'Migration must DROP trigger IF EXISTS before CREATE (idempotent re-apply per p219 pattern)');
  assert.match(body, /CREATE TRIGGER trg_complete_volunteer_term_on_cert[\s\S]{0,200}AFTER INSERT ON public\.certificates/i,
    'Trigger must be AFTER INSERT on public.certificates');
  assert.match(body, /FOR EACH ROW\s+WHEN \(NEW\.type = 'volunteer_agreement'\)/i,
    'Trigger must gate with WHEN (NEW.type = \'volunteer_agreement\') per #321 AC');
});

test('p233 #321: trigger body has NULL member_id defense-in-depth guard', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /IF NEW\.member_id IS NULL THEN RETURN NEW;\s*END IF;/i,
    'Trigger body must early-return on NULL member_id (defense-in-depth despite NOT NULL constraint)');
});

test('p233 #321: UPDATE is idempotent — WHERE filters status != completed + uniqueness on (member_id, step_key)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /UPDATE public\.onboarding_progress/i,
    'Trigger must UPDATE public.onboarding_progress');
  assert.match(body, /SET[\s\S]{0,500}status\s*=\s*'completed'/i,
    'UPDATE must set status=completed');
  assert.match(body, /completed_at\s*=\s*COALESCE\(NEW\.issued_at,\s*now\(\)\)/i,
    'completed_at must use COALESCE(NEW.issued_at, now()) for historical accuracy');
  assert.match(body, /WHERE member_id\s*=\s*NEW\.member_id[\s\S]{0,100}AND step_key\s*=\s*'volunteer_term'[\s\S]{0,100}AND status\s*!=\s*'completed'/i,
    'WHERE clause must filter by member_id + step_key=volunteer_term + status!=completed (idempotency)');
});

test('p233 #321: trigger enriches metadata with cert_id + verification_code + migration tag', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /metadata\s*=\s*COALESCE\(metadata,\s*'\{\}'::jsonb\)\s*\|\|\s*jsonb_build_object/i,
    'metadata must be merged via || jsonb_build_object (preserves existing keys)');
  assert.match(body, /'completed_via',\s*'cert_trigger'/i,
    'metadata.completed_via must mark trigger origin');
  assert.match(body, /'cert_id',\s*NEW\.id/i,
    'metadata.cert_id must reference the inserted cert (forensic traceability)');
  assert.match(body, /'verification_code',\s*NEW\.verification_code/i,
    'metadata.verification_code must reference the cert verification code');
  assert.match(body, /'migration',\s*'20260805000018'/i,
    'metadata.migration must reference this migration version (allows targeted rollback)');
});

test('p233 #321: audit log only when rows_affected > 0 (avoids noisy audit on no-op)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /GET DIAGNOSTICS v_rows_affected = ROW_COUNT/i,
    'Must capture ROW_COUNT into v_rows_affected for conditional audit');
  assert.match(body, /IF v_rows_affected > 0 THEN[\s\S]{0,500}INSERT INTO public\.admin_audit_log/i,
    'Audit INSERT must be inside IF v_rows_affected > 0 block (no-op no audit)');
  assert.match(body, /'onboarding\.volunteer_term_completed_on_cert'/i,
    'Audit action must be canonical onboarding.volunteer_term_completed_on_cert (matches admin_audit_log CHECK regex)');
});

test('p233 #321: backfill uses DISTINCT ON latest cert per member', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /WITH latest_cert_per_member AS \(\s*SELECT DISTINCT ON \(c\.member_id\)/i,
    'Backfill must use DISTINCT ON (c.member_id) CTE to get latest cert per member');
  assert.match(body, /ORDER BY c\.member_id, c\.issued_at DESC/i,
    'DISTINCT ON ORDER must be (c.member_id, c.issued_at DESC) — latest cert wins');
  assert.match(body, /UPDATE public\.onboarding_progress op[\s\S]{0,500}FROM latest_cert_per_member lcm[\s\S]{0,500}WHERE op\.member_id\s*=\s*lcm\.member_id[\s\S]{0,200}AND op\.step_key\s*=\s*'volunteer_term'[\s\S]{0,100}AND op\.status\s*=\s*'pending'/i,
    'Backfill UPDATE must join phantom rows to latest cert with strict status=pending guard (idempotent re-apply)');
});

test('p233 #321: backfill writes admin_audit_log per affected row with canonical action', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /INSERT INTO public\.admin_audit_log[\s\S]{0,500}'p233_321_backfill_volunteer_term_phantom'/i,
    'Backfill audit action must be p233_321_backfill_volunteer_term_phantom');
  assert.match(body, /'target_type'[\s\S]{0,200}|'onboarding_progress'/i,
    'Backfill audit target_type must be onboarding_progress');
  assert.match(body, /'cert_id_linked',\s*u\.cert_id/i,
    'Backfill audit changes.cert_id_linked must reference the linked cert');
});

test('p233 #321: sanity DO block RAISES EXCEPTION if any phantom remains post-backfill', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /RAISE EXCEPTION '#321 sanity FAIL/i,
    'Sanity DO block must RAISE EXCEPTION (fails loud at apply time, not runtime)');
  assert.match(body, /v_phantom_count int/i,
    'Sanity block must declare v_phantom_count variable for the assertion');
  assert.match(body, /FROM public\.onboarding_progress op[\s\S]{0,500}WHERE op\.step_key\s*=\s*'volunteer_term'[\s\S]{0,100}AND op\.status\s*=\s*'pending'[\s\S]{0,500}EXISTS \(\s*SELECT 1 FROM public\.certificates c[\s\S]{0,200}c\.type\s*=\s*'volunteer_agreement'/i,
    'Sanity query must check pending vol_term rows with matching issued vol_agreement cert');
});

test('p233 #321: migration reloads PostgREST schema cache', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /NOTIFY pgrst,\s*'reload schema'/i,
    'Migration must NOTIFY pgrst reload schema (CLAUDE.md GC-097)');
});

// ===================================================================
// DB-GATED assertions (require SUPABASE_URL + SERVICE_ROLE_KEY)
// ===================================================================

function makeClient() {
  return createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

test('p233 #321 (live): post-backfill 0 phantom vol_term rows where matching cert exists',
  { skip: !dbGated && skipMsg },
  async () => {
    const sb = makeClient();
    // Replicates the sanity DO block in the migration: count pending vol_term
    // rows whose member has an issued vol_agreement cert. Must be 0 post-apply.
    const { data: pending, error: e1 } = await sb
      .from('onboarding_progress')
      .select('member_id')
      .eq('step_key', 'volunteer_term')
      .eq('status', 'pending');
    assert.ok(!e1, `onboarding_progress query failed: ${e1?.message}`);

    if (!pending || pending.length === 0) {
      return; // trivially 0 phantoms
    }

    const memberIds = [...new Set(pending.map(r => r.member_id).filter(Boolean))];
    if (memberIds.length === 0) {
      return; // all pending rows have NULL member_id; can't be phantom by definition
    }

    const { data: certs, error: e2 } = await sb
      .from('certificates')
      .select('member_id')
      .eq('type', 'volunteer_agreement')
      .eq('status', 'issued')
      .in('member_id', memberIds);
    assert.ok(!e2, `certificates query failed: ${e2?.message}`);

    const memberIdsWithCert = new Set((certs || []).map(c => c.member_id));
    const phantomCount = pending.filter(p => p.member_id && memberIdsWithCert.has(p.member_id)).length;

    assert.strictEqual(
      phantomCount,
      0,
      `Expected 0 pending vol_term rows with matching cert (post-backfill); got ${phantomCount}. ` +
      `Backfill DO block in 20260805000018 should have flipped all such rows to completed, ` +
      `and trigger should keep that invariant going forward.`
    );
  }
);
