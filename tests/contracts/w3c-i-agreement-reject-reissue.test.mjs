/**
 * Contract: Wave 3c-i (B8, #740 / ADR-0104) — volunteer-agreement reject/reissue lifecycle (DB).
 *
 * Adds the two new terminal states to the Termo de Voluntariado and the board/admin actions that
 * produce them, plus a domain CHECK. 'countersigned' stays a DERIVED sub-state (counter_signed_by
 * IS NOT NULL), not a status value, so a valid term remains status='issued' and readiness/verify/
 * sign/auto-link need no change. counter_sign_certificate's pg_catalog qualifier bug (every
 * counter-sign raised "function public.convert_to does not exist") is fixed in-slice.
 *
 * Live behavior (reject pre/post counter-sign, counter-sign of rejected blocked, counter-sign of
 * issued succeeds with a 64-hex hash, reissue→superseded, CHECK blocks bogus status) was validated
 * at apply time via a rolled-back probe; this static test guards the DDL.
 *
 * Static-only (reads migration source + ADR) → runs without DB env.
 *
 * Cross-ref: #740 Wave 3 (B8), ADR-0104, ADR-0022 (_delivery_mode_for).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIG_PATH = 'supabase/migrations/20260805000196_w3c_i_agreement_reject_reissue_lifecycle.sql';
const ADR_PATH = 'docs/adr/ADR-0104-chapter-affiliations-ssot.md';

const MIG = readFileSync(MIG_PATH, 'utf8');

describe('w3c-i — status domain CHECK + revoked_by self-doc', () => {
  it('constrains certificates.status to the lifecycle domain', () => {
    assert.ok(existsSync(MIG_PATH));
    assert.match(MIG, /ALTER TABLE public\.certificates DROP CONSTRAINT IF EXISTS certificates_status_check/);
    assert.match(MIG, /ADD CONSTRAINT certificates_status_check\s*\n\s*CHECK \(status IS NULL OR status IN \('draft','issued','rejected','superseded','revoked'\)\)/);
  });

  it('self-documents the existing revoked_by column reject_certificate writes', () => {
    assert.match(MIG, /ALTER TABLE public\.certificates ADD COLUMN IF NOT EXISTS revoked_by uuid/);
  });
});

describe('w3c-i — reject_certificate', () => {
  it('is a SECDEF RPC, board/admin authority, granted to authenticated only', () => {
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.reject_certificate\(p_certificate_id uuid, p_reason text\)/);
    assert.match(MIG, /SECURITY DEFINER/);
    assert.match(MIG, /v_is_manage_member := public\.can_by_member\(v_caller_id, 'manage_member'\)/);
    assert.match(MIG, /ae\.kind = 'chapter_board' AND ae\.status = 'active'/);
    assert.match(MIG, /REVOKE EXECUTE ON FUNCTION public\.reject_certificate\(uuid, text\) FROM anon/);
    assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.reject_certificate\(uuid, text\) TO authenticated/);
  });

  it('requires a reason, applies only to a valid issued agreement, and records the invalidation', () => {
    assert.match(MIG, /IF p_reason IS NULL OR length\(trim\(p_reason\)\) = 0 THEN\s*\n\s*RETURN jsonb_build_object\('error', 'reason_required'\)/);
    assert.match(MIG, /IF v_cert\.type != 'volunteer_agreement' THEN RETURN jsonb_build_object\('error', 'not_an_agreement'\)/);
    assert.match(MIG, /IF v_cert\.status IS DISTINCT FROM 'issued' THEN\s*\n\s*RETURN jsonb_build_object\('error', 'not_rejectable'/);
    assert.match(MIG, /SET status = 'rejected', revoked_at = now\(\), revoked_by = v_caller_id,\s*\n\s*revoked_reason = p_reason/);
  });

  it('unlinks the engagement and notifies the member to re-sign', () => {
    assert.match(MIG, /UPDATE engagements SET agreement_certificate_id = NULL\s*\n\s*WHERE agreement_certificate_id = p_certificate_id/);
    assert.match(MIG, /'volunteer_agreement_rejected'/);
  });
});

describe('w3c-i — reissue_agreement', () => {
  it('is a SECDEF RPC, manage_member only, supersedes the current valid term', () => {
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.reissue_agreement\(p_member_id uuid, p_reason text\)/);
    assert.match(MIG, /IF NOT public\.can_by_member\(v_caller_id, 'manage_member'\) THEN/);
    assert.match(MIG, /WHERE member_id = p_member_id AND type = 'volunteer_agreement'\s*\n\s*AND status = 'issued' AND cycle = v_cycle/);
    assert.match(MIG, /UPDATE certificates SET status = 'superseded', updated_at = now\(\) WHERE id = v_cert\.id/);
    assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.reissue_agreement\(uuid, text\) TO authenticated/);
  });
});

describe('w3c-i — counter_sign_certificate precondition + pg_catalog bugfix', () => {
  it('only a valid issued term is counter-signable', () => {
    assert.match(MIG, /IF v_cert\.status IS DISTINCT FROM 'issued' THEN\s*\n\s*RETURN jsonb_build_object\('error', 'not_signable'/);
  });

  it('hashes with unqualified sha256/convert_to (resolve via pg_catalog, not public)', () => {
    assert.match(MIG, /v_hash := encode\(sha256\(convert_to\(/);
    assert.doesNotMatch(MIG, /encode\(public\.sha256\(public\.convert_to\(/);
  });
});

describe('w3c-i — read-side + notification catalogue', () => {
  it('get_my_certificates hides superseded along with revoked', () => {
    assert.match(MIG, /COALESCE\(c\.status, 'issued'\) NOT IN \('revoked', 'superseded'\)/);
  });

  it('_delivery_mode_for registers the two new actionable types as transactional_immediate', () => {
    assert.match(MIG, /WHEN 'volunteer_agreement_rejected'\s+THEN 'transactional_immediate'/);
    assert.match(MIG, /WHEN 'volunteer_agreement_reissued'\s+THEN 'transactional_immediate'/);
  });
});

describe('w3c-i — ADR-0104 amended', () => {
  it('ADR documents the 3c-i delivery + the migration', () => {
    assert.ok(existsSync(ADR_PATH));
    const adr = readFileSync(ADR_PATH, 'utf8');
    assert.match(adr, /Amendment — Wave 3c-i/);
    assert.match(adr, /20260805000196/);
    assert.match(adr, /reject_certificate/);
  });
});
