import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// #1024: GP/DPO write-pair for #729. Records an externally-communicated image_voice_publicity
// revocation into consent_records so the #729 read-branch (get_member_comms_card →
// image_consent_revoked) is reachable and demonstrable (LGPD Art. 18 VI). SECDEF, gated on
// manage_member, REVOKE anon (#965 drift avoidance).
const MIGRATION_PATH = 'supabase/migrations/20260805000326_1024_gp_record_image_consent_revocation.sql';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');

const URL = process.env.SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;

describe('#1024 — gp_record_image_consent_revocation (write-pair for #729)', () => {
  describe('migration static assertions', () => {
    it('is SECDEF with pinned search_path, gated on manage_member', () => {
      assert.match(MIGRATION_SQL, /FUNCTION public\.gp_record_image_consent_revocation/);
      assert.match(MIGRATION_SQL, /SECURITY DEFINER/);
      assert.match(MIGRATION_SQL, /SET search_path TO 'public', 'pg_temp'/);
      assert.match(MIGRATION_SQL, /can_by_member\(v_caller, 'manage_member'\)/);
    });

    it('REVOKEs anon/PUBLIC and grants only authenticated + service_role (#965)', () => {
      assert.match(MIGRATION_SQL, /REVOKE ALL ON FUNCTION public\.gp_record_image_consent_revocation\([^)]*\) FROM PUBLIC, anon/);
      assert.match(MIGRATION_SQL, /GRANT EXECUTE ON FUNCTION public\.gp_record_image_consent_revocation\([^)]*\) TO authenticated, service_role/);
    });

    it('writes a revoked image_voice_publicity row on the legal-vetted shape', () => {
      // channel must be a value allowed by consent_records_channel_check (admin_attestation).
      assert.match(MIGRATION_SQL, /'image_voice_publicity', v_version, v_doc_id, 'admin_attestation'/);
      // F2 (security review): accepted_at is a nominal sentinel (now()); revoked_at carries the
      // communicated date (v_effective ← p_effective_at). The row is born revoked.
      assert.match(MIGRATION_SQL, /now\(\), v_effective, v_reason, v_org/);
      // policy_version is NOT NULL → resolved from the volunteer_addendum (mirror grant path).
      assert.match(MIGRATION_SQL, /doc_type = 'volunteer_addendum'/);
      assert.match(MIGRATION_SQL, /v_version := COALESCE\(v_doc_version, 'unversioned'\)/);
    });

    it('idempotent: revokes an active opt-in (at the effective date) before inserting; audits', () => {
      assert.match(MIGRATION_SQL, /UPDATE public\.consent_records\s+SET revoked_at = v_effective[\s\S]*revoked_at IS NULL/);
      assert.match(MIGRATION_SQL, /IF v_consent_id IS NULL THEN[\s\S]*INSERT INTO public\.consent_records/);
      assert.match(MIGRATION_SQL, /'image_voice_consent_revoked_by_admin'/);
    });

    it('security-review guards: cross-org IDOR (F1), future-date (F4), member_not_found raise (F6)', () => {
      assert.match(MIGRATION_SQL, /v_org IS DISTINCT FROM v_caller_org THEN\s*\n\s*RAISE EXCEPTION 'access_denied: target member outside caller org'/);
      assert.match(MIGRATION_SQL, /v_effective > now\(\) \+ interval '1 hour' THEN\s*\n\s*RAISE EXCEPTION 'p_effective_at cannot be in the future'/);
      assert.match(MIGRATION_SQL, /v_org IS NULL THEN\s*\n\s*RAISE EXCEPTION 'member_not_found'/);
    });
  });

  describe('DB-gated: authority boundary', () => {
    const svc = URL && SERVICE ? it : it.skip;
    const anonIt = URL && ANON ? it : it.skip;

    svc('a caller with no auth.uid() (service role) is rejected by the manage_member gate', async () => {
      const sb = createClient(URL, SERVICE, { auth: { persistSession: false } });
      const { error } = await sb.rpc('gp_record_image_consent_revocation', {
        p_member_id: '00000000-0000-0000-0000-000000000000',
        p_reason: 'contract-test',
      });
      // v_caller is NULL for a tokenless service-role call → 'Not authenticated' RAISE.
      assert.ok(error, 'tokenless call must be rejected');
      assert.match(String(error.message || ''), /authenticated|insufficient|denied/i);
    });

    anonIt('anon cannot execute the function (REVOKE anon)', async () => {
      const sb = createClient(URL, ANON, { auth: { persistSession: false } });
      const { error } = await sb.rpc('gp_record_image_consent_revocation', {
        p_member_id: '00000000-0000-0000-0000-000000000000',
        p_reason: 'contract-test',
      });
      assert.ok(error, 'anon must not be able to execute this SECDEF write RPC');
    });
  });
});
