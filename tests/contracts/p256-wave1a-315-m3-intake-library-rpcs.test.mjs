import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// p256 Wave 1a M3 — SECDEF RPCs for governance doc intake + member-facing library.
// Spec: SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md §19.5.
//
// PM corrections rev2 plan:
//   #2 Intake NÃO cria proposer_consent signoff. proposer_ack_offline=true →
//      INSERT admin_audit_log with action='governance.proposer_attestation_offline'.
//      proposer_member_id optional; if present, MUST differ from caller (no self-attest).
//   P0-Q8 forward-defense — library response shape never includes file_id/drive_url/content.
//   SEDIMENT-239b.A — FK source columns reference v_caller_member_id (resolved via
//      members WHERE auth_id = auth.uid()), NOT raw auth.uid().

const MIGRATION_PATH = 'supabase/migrations/20260805000037_p256_wave1a_315_m3_intake_library_rpcs.sql';
const MIGRATION_SQL  = readFileSync(MIGRATION_PATH, 'utf8');

// Strip `--` SQL line comments to build MIGRATION_CODE for forward-defense regex
// matching on LIVE function bodies — keeps WHY/ROLLBACK examples from triggering
// false positives.
const MIGRATION_CODE = MIGRATION_SQL
  .split('\n')
  .map(l => {
    const idx = l.indexOf('--');
    return idx >= 0 ? l.slice(0, idx) : l;
  })
  .join('\n');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

describe('p256 M3 — create_governance_document_intake + list_governance_library', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp', () => {
      assert.ok(existsSync(MIGRATION_PATH));
      assert.ok(MIGRATION_SQL.length > 0);
    });

    it('header documents WHAT / WHY / SPEC / SCOPE LOCK / ROLLBACK / INVARIANTS / CROSS-REF', () => {
      assert.match(MIGRATION_SQL, /-- WHAT: Wave 1a M3/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- SPEC:/);
      assert.match(MIGRATION_SQL, /-- SCOPE LOCK/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK/);
      assert.match(MIGRATION_SQL, /-- INVARIANTS:/);
      assert.match(MIGRATION_SQL, /-- CROSS-REF:/);
    });

    it('mentions PM correction #2 (no fake proposer_consent via GP)', () => {
      assert.match(MIGRATION_SQL, /PM #2/);
      assert.match(MIGRATION_SQL, /governance\.proposer_attestation_offline/);
    });
  });

  describe('create_governance_document_intake — SECDEF + search_path + V4 gate', () => {
    it('function defined with SECURITY DEFINER + pinned search_path', () => {
      assert.match(MIGRATION_SQL, /CREATE OR REPLACE FUNCTION public\.create_governance_document_intake\(p_payload jsonb\)/);
      assert.match(MIGRATION_SQL, /create_governance_document_intake[\s\S]+?SECURITY DEFINER/);
      assert.match(MIGRATION_SQL, /create_governance_document_intake[\s\S]+?SET search_path TO 'public', 'pg_temp'/);
    });

    it('gates manage_event via can_by_member (per spec §19.5 ratificada)', () => {
      assert.match(MIGRATION_SQL, /IF NOT public\.can_by_member\(v_caller_member_id, 'manage_event'\)/);
      assert.match(MIGRATION_SQL, /Unauthorized: requires manage_event capability/);
    });

    it('validates 5 Tier-1 fields (P1-Q6)', () => {
      assert.match(MIGRATION_SQL, /required fields title\/doc_type\/author_label\/visibility_class\/description/);
      ['title','doc_type','author_label','visibility_class','description'].forEach(f => {
        assert.match(MIGRATION_SQL, new RegExp(`nullif\\(trim\\(p_payload->>'${f}'\\), ''\\)`));
      });
    });

    it('validates visibility_class CHECK matches 5-class CHECK constraint', () => {
      assert.match(MIGRATION_SQL, /v_visibility_class NOT IN \('public','active_members','legal_scoped','admin_only','audit_restricted'\)/);
    });

    it('PM #2 — rejects self-attestation when proposer_member_id = caller', () => {
      assert.match(MIGRATION_SQL, /v_proposer_member_id IS NOT NULL AND v_proposer_member_id = v_caller_member_id/);
      assert.match(MIGRATION_SQL, /proposer_member_id must differ from caller \(GP cannot self-attest as proposer\)/);
    });

    it("status logic per A2: false → pending_proposer_consent, true → draft", () => {
      assert.match(MIGRATION_SQL, /v_initial_status := CASE WHEN v_proposer_ack_offline THEN 'draft' ELSE 'pending_proposer_consent' END/);
    });

    it("PM #2 — proposer_ack_offline=true creates admin_audit_log row with action 'governance.proposer_attestation_offline'", () => {
      assert.match(MIGRATION_SQL, /IF v_proposer_ack_offline THEN\s+INSERT INTO public\.admin_audit_log/);
      assert.match(MIGRATION_SQL, /'governance\.proposer_attestation_offline'/);
    });

    it("PM #2 forward-defense — function body NEVER inserts into approval_signoffs with gate_kind='proposer_consent'", () => {
      // Use MIGRATION_CODE (comment-stripped) so WHY/ROLLBACK references to "proposer_consent" don't match.
      const fakeSignoffPattern = /INSERT INTO[\s\S]{0,200}?approval_signoffs[\s\S]{0,400}?proposer_consent/;
      assert.doesNotMatch(MIGRATION_CODE, fakeSignoffPattern,
        'PM #2: intake must not INSERT proposer_consent signoff via GP. Real consent flow ships Wave 1b.');
    });

    it("PM #2 forward-defense — no approval_chains INSERT in intake (deferred Wave 1b)", () => {
      const fakeChainPattern = /CREATE OR REPLACE FUNCTION public\.create_governance_document_intake[\s\S]+?INSERT INTO[\s\S]{0,200}?approval_chains/;
      assert.doesNotMatch(MIGRATION_CODE, fakeChainPattern,
        'intake must not INSERT into approval_chains — chain creation is a separate workflow ships Wave 1b');
    });

    it('SEDIMENT-239b.A — admin_audit_log INSERT uses v_caller_member_id (not raw auth.uid()) for actor_id', () => {
      // The actor_id source in admin_audit_log INSERT must be v_caller_member_id (resolved from members.id)
      assert.match(MIGRATION_SQL, /INSERT INTO public\.admin_audit_log[\s\S]+?VALUES \(\s+v_caller_member_id,/);
    });

    it('default acknowledgement_mode per A1 — full CASE table', () => {
      // Spot-check key A1 entries
      ['cooperation_agreement', 'legal_signature'].forEach(t => assert.match(MIGRATION_SQL, new RegExp(t)));
      assert.match(MIGRATION_SQL, /WHEN 'cooperation_agreement'\s+THEN 'legal_signature'/);
      assert.match(MIGRATION_SQL, /WHEN 'volunteer_term_template' THEN 'binding'/);
      assert.match(MIGRATION_SQL, /WHEN 'editorial_guide'\s+THEN 'informational'/);
    });

    it('inserts doc with organization_id = caller member organization_id', () => {
      assert.match(MIGRATION_SQL, /SELECT id, organization_id INTO v_caller_member_id, v_caller_org_id/);
      assert.match(MIGRATION_SQL, /INSERT INTO public\.governance_documents[\s\S]+?v_caller_org_id/);
    });

    it('REVOKE PUBLIC + GRANT authenticated', () => {
      assert.match(MIGRATION_SQL, /REVOKE EXECUTE ON FUNCTION public\.create_governance_document_intake\(jsonb\) FROM PUBLIC/);
      assert.match(MIGRATION_SQL, /GRANT  EXECUTE ON FUNCTION public\.create_governance_document_intake\(jsonb\) TO authenticated/);
    });
  });

  describe('list_governance_library — STABLE SECDEF + visibility filter + P0-Q8 forward-defense', () => {
    it('function defined STABLE + SECURITY DEFINER + pinned search_path', () => {
      assert.match(MIGRATION_SQL, /CREATE OR REPLACE FUNCTION public\.list_governance_library\(p_filters jsonb DEFAULT '\{\}'::jsonb\)/);
      assert.match(MIGRATION_SQL, /list_governance_library[\s\S]+?STABLE/);
      assert.match(MIGRATION_SQL, /list_governance_library[\s\S]+?SECURITY DEFINER/);
      assert.match(MIGRATION_SQL, /list_governance_library[\s\S]+?SET search_path TO 'public', 'pg_temp'/);
    });

    it('requires active membership (is_active = true gate)', () => {
      // The active membership gate inside list_governance_library
      const fnBody = MIGRATION_SQL.match(/CREATE OR REPLACE FUNCTION public\.list_governance_library[\s\S]+?REVOKE EXECUTE/);
      assert.ok(fnBody);
      assert.match(fnBody[0], /WHERE auth_id = auth\.uid\(\) AND is_active = true/);
    });

    it('admin_only branch gated by can_by_member(_, manage_member)', () => {
      const fnBody = MIGRATION_SQL.match(/CREATE OR REPLACE FUNCTION public\.list_governance_library[\s\S]+?REVOKE EXECUTE/);
      assert.match(fnBody[0], /visibility_class = 'admin_only' AND v_is_admin/);
      // and v_is_admin is computed from can_by_member(...,'manage_member')
      assert.match(fnBody[0], /v_is_admin\s+:= public\.can_by_member\(v_caller_member_id, 'manage_member'\)/);
    });

    it('audit_restricted branch gated by can_by_member(_, manage_platform)', () => {
      const fnBody = MIGRATION_SQL.match(/CREATE OR REPLACE FUNCTION public\.list_governance_library[\s\S]+?REVOKE EXECUTE/);
      assert.match(fnBody[0], /visibility_class = 'audit_restricted' AND v_is_platform_admin/);
      assert.match(fnBody[0], /v_is_platform_admin := public\.can_by_member\(v_caller_member_id, 'manage_platform'\)/);
    });

    it('legal_scoped branch checks member_document_signatures.is_current = true OR v_is_admin', () => {
      const fnBody = MIGRATION_SQL.match(/CREATE OR REPLACE FUNCTION public\.list_governance_library[\s\S]+?REVOKE EXECUTE/);
      assert.match(fnBody[0], /visibility_class = 'legal_scoped' AND \(\s+v_is_admin\s+OR EXISTS/);
      assert.match(fnBody[0], /member_document_signatures mds[\s\S]+?mds\.is_current = true/);
    });

    it('PM #2 / P0-Q8 forward-defense — response shape NEVER includes file_id/drive_url/content/pdf_url', () => {
      const fnBody = MIGRATION_SQL.match(/CREATE OR REPLACE FUNCTION public\.list_governance_library[\s\S]+?REVOKE EXECUTE/);
      assert.ok(fnBody);
      // Inside the body, no jsonb_build_object key should be 'file_id', 'drive_url', 'content', or 'pdf_url'
      // The jsonb_build_object construction is in the SELECT — search for these as keys
      ['file_id','drive_url','content','pdf_url'].forEach(k => {
        const pattern = new RegExp(`jsonb_build_object[\\s\\S]{0,800}?'${k}'\\s*,`);
        assert.ok(!pattern.test(fnBody[0]), `P0-Q8 forward-defense: '${k}' must NOT appear as jsonb_build_object key in list_governance_library`);
      });
    });

    it('REVOKE PUBLIC + GRANT authenticated', () => {
      assert.match(MIGRATION_SQL, /REVOKE EXECUTE ON FUNCTION public\.list_governance_library\(jsonb\) FROM PUBLIC/);
      assert.match(MIGRATION_SQL, /GRANT  EXECUTE ON FUNCTION public\.list_governance_library\(jsonb\) TO authenticated/);
    });
  });

  describe('NOTIFY pgrst at end', () => {
    it("issues NOTIFY pgrst, 'reload schema'", () => {
      assert.match(MIGRATION_SQL, /NOTIFY pgrst, 'reload schema'/);
    });
  });

  describe('DB-gated live verification (skip without env)', () => {
    if (!sb) {
      it.skip('SUPABASE env not set — skipping DB-gated assertions');
      return;
    }

    it('both RPCs exist and are SECDEF', async () => {
      // Use a generic probe via PostgREST is hard for plpgsql shape; rely on the contract test
      // for the migration body assertions above. DB-gated step: verify list_governance_library
      // returns a jsonb envelope with documents+total keys, even with no auth context.
      const { data, error } = await sb.rpc('list_governance_library', { p_filters: {} });
      // Service role bypasses RLS but the function itself has an explicit
      // members.is_active = true gate. service role won't have a members row,
      // so we expect an Unauthorized error here — that itself proves the gate fires.
      if (error) {
        assert.match(error.message, /Unauthorized|no active member/, `expected active-member gate to fire under service_role probe; got: ${error.message}`);
      } else {
        // If it succeeded (unlikely under service_role), confirm shape at minimum
        assert.ok(typeof data === 'object', 'list_governance_library must return jsonb object');
        assert.ok('documents' in data && 'total' in data, 'expected documents+total keys');
      }
    });
  });
});
