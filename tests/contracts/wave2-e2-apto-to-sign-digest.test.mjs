/**
 * Contract: Wave 2 / E2 — daily leadership digest "aptos a assinar o termo".
 *
 * Gap (discovery #740): leadership (manage_member) is notified when someone JÁ
 * assinou (volunteer_agreement_signed) but NOT when a candidate becomes APTO to
 * sign. Candidate side already exists (selection_termo_due, p157/p159 — re-grounded
 * 2026-06-16). PM decision (2026-06-16): deliver as a DAILY DIGEST (lowest noise),
 * not a per-candidate push, linking to the E1 prioritized queue.
 *
 * Static-only (reads the migration). Orphan + body-hash drift are enforced
 * separately by rpc-migration-coverage.
 *
 * Cross-ref: #740, get_pending_agreement_engagements (E1), selection_termo_due.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIG = 'supabase/migrations/20260805000188_wave2_e2_apto_to_sign_leadership_digest.sql';
const SQL = readFileSync(MIG, 'utf8');

describe('Wave2 E2 — apto-to-sign leadership digest cron', () => {
  it('migration exists and defines the SECDEF cron function with locked search_path', () => {
    assert.ok(existsSync(MIG));
    assert.match(SQL, /CREATE OR REPLACE FUNCTION public\._selection_apto_to_sign_digest_cron\(\)/);
    assert.match(SQL, /SECURITY DEFINER/);
    assert.match(SQL, /SET search_path = ''/);
  });

  it('cohort = active volunteer engagement requiring agreement with no certificate (canonical source)', () => {
    assert.match(SQL, /FROM public\.auth_engagements ae/);
    assert.match(SQL, /ae\.status = 'active'/);
    assert.match(SQL, /ae\.requires_agreement IS TRUE/);
    assert.match(SQL, /ae\.agreement_certificate_id IS NULL/);
    assert.match(SQL, /ae\.kind = 'volunteer'/);
  });

  it('recipients gated on V4 manage_member (ADR-0007), active members only', () => {
    assert.match(SQL, /public\.can_by_member\(m\.id, 'manage_member'\)/);
    assert.match(SQL, /m\.is_active IS TRUE/);
  });

  it('in-app only (delivery_mode suppress = no email spam) and links to the E1 queue', () => {
    assert.match(SQL, /'suppress'/);
    assert.match(SQL, /'\/admin\/certificates'/);
    assert.match(SQL, /'selection_apto_to_sign_digest'/);
  });

  it('idempotent once-per-day (20h window guard)', () => {
    assert.match(SQL, /interval '20 hours'/);
    assert.match(SQL, /NOT EXISTS \(\s*SELECT 1 FROM public\.notifications n/);
  });

  it('does nothing when the cohort is empty (no notification when apto_total = 0)', () => {
    assert.match(SQL, /IF v_apto_total = 0 THEN/);
  });

  it('return envelope exposes apto_total + not_notified + inserted (locked shape)', () => {
    assert.match(SQL, /v_not_notified int/);
    assert.match(SQL, /'apto_total', v_apto_total/);
    assert.match(SQL, /'not_notified', v_not_notified/);
    assert.match(SQL, /'inserted', v_inserted/);
  });

  it('scheduled as a daily pg_cron job, idempotently re-registered', () => {
    assert.match(SQL, /cron\.unschedule\('selection-apto-to-sign-digest-daily'\)/);
    assert.match(SQL, /cron\.schedule\(\s*'selection-apto-to-sign-digest-daily',\s*'45 13 \* \* \*'/);
  });

  it('locked down to service_role (revoked from public/anon/authenticated)', () => {
    assert.match(SQL, /REVOKE ALL ON FUNCTION public\._selection_apto_to_sign_digest_cron\(\) FROM public, anon, authenticated/);
    assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\._selection_apto_to_sign_digest_cron\(\) TO service_role/);
  });
});
