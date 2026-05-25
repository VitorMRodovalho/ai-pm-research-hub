import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// p261 #312-W4b (#377) — sign_proposer_consent canonical A2 path.
// Spec: SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md §11 row 2 (Autor/proponente).
// PM ratification: p260 audit close §15.5 D1-D5 + dispatch sequence 1/7.
//
// What this migration does:
//   1) ALTER TABLE governance_documents ADD COLUMN proposer_member_id uuid REFERENCES members(id)
//      ON DELETE RESTRICT (nullable for backwards compat with pre-#377 docs).
//   2) Backfills the 1 Frontiers fixture (18ec4690-…) with Fabrício Costa member_id (92d26057-…)
//      from p259 evidence doc (p256 M3 validated but never persisted the value).
//   3) CREATE OR REPLACE create_governance_document_intake — minimum-diff extension to INSERT
//      proposer_member_id from payload (preserves all prior behavior).
//   4) CREATE sign_proposer_consent(p_document_id uuid, p_evidence jsonb DEFAULT NULL):
//      - Gate: caller MUST equal governance_documents.proposer_member_id (no GP-on-behalf).
//      - Status transition pending_proposer_consent → draft.
//      - Idempotent: returns already_signed=true when status='draft' (no double-write).
//      - Captures evidence in admin_audit_log (pre-chain — chains start later).
//
// Sediment respected:
//   - SEDIMENT-239b.A: FK source columns reference members.id NOT auth.users.id.
//   - SEDIMENT-235.A: no auto-close keyword + #N substring in migration body for stay-open issues.

const MIGRATION_PATH = 'supabase/migrations/20260805000040_p261_312_w4b_sign_proposer_consent.sql';
const MIGRATION_SQL  = readFileSync(MIGRATION_PATH, 'utf8');

// Strip `--` SQL line comments to build MIGRATION_CODE for forward-defense regex against LIVE function bodies.
const MIGRATION_CODE = MIGRATION_SQL
  .split('\n')
  .map(l => {
    const idx = l.indexOf('--');
    return idx >= 0 ? l.slice(0, idx) : l;
  })
  .join('\n');

const FRONTIERS_DOC_ID    = '18ec4690-4f5a-4cab-904d-451e2c7245bf';
const FABRICIO_MEMBER_ID  = '92d26057-5550-4f15-a3bf-b00eed5f32f9';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

describe('p261 #312-W4b — sign_proposer_consent canonical A2 path', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp 20260805000040', () => {
      assert.ok(existsSync(MIGRATION_PATH));
      assert.ok(MIGRATION_SQL.length > 0);
    });

    it('header documents WHAT / WHY / SPEC / SCOPE LOCK / ROLLBACK / INVARIANTS / CROSS-REF', () => {
      assert.match(MIGRATION_SQL, /-- WHAT:.*Wave 1b leaf #312-W4b/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- SPEC:/);
      assert.match(MIGRATION_SQL, /-- SCOPE LOCK/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK/);
      assert.match(MIGRATION_SQL, /-- INVARIANTS:/);
      assert.match(MIGRATION_SQL, /-- CROSS-REF:/);
    });

    it('header cross-refs umbrella + audit + p256 deferral origin + p259 surfaced + p260 ratification', () => {
      assert.match(MIGRATION_SQL, /#312/);
      assert.match(MIGRATION_SQL, /#315/);
      assert.match(MIGRATION_SQL, /#377/);
      assert.match(MIGRATION_SQL, /p256/);
      assert.match(MIGRATION_SQL, /p259/);
      assert.match(MIGRATION_SQL, /p260/);
      assert.match(MIGRATION_SQL, /SEDIMENT-239b\.A/);
    });
  });

  describe('p261.1 — ALTER TABLE proposer_member_id column add', () => {
    it('ALTER TABLE adds proposer_member_id with REFERENCES members(id) ON DELETE RESTRICT', () => {
      assert.match(MIGRATION_SQL,
        /ALTER TABLE public\.governance_documents\s+ADD COLUMN proposer_member_id uuid\s+REFERENCES public\.members\(id\) ON DELETE RESTRICT/);
    });

    it('column is nullable (no NOT NULL constraint applied)', () => {
      // Scope negative match to ALTER TABLE block: must not see NOT NULL before next blank/section break
      const alterBlock = MIGRATION_CODE.match(/ALTER TABLE public\.governance_documents\s+ADD COLUMN proposer_member_id uuid[^;]*?;/);
      assert.ok(alterBlock, 'ALTER TABLE block must exist');
      assert.doesNotMatch(alterBlock[0], /NOT NULL/);
    });

    it('COMMENT ON COLUMN documents the proposer convention', () => {
      assert.match(MIGRATION_SQL, /COMMENT ON COLUMN public\.governance_documents\.proposer_member_id IS/);
      assert.match(MIGRATION_SQL, /named proposer member\.id \(distinct from GP submitter\)/);
    });
  });

  describe('p261.2 — Frontiers fixture backfill', () => {
    it('UPDATE targets the exact Frontiers doc_id + Fabrício member_id', () => {
      assert.match(MIGRATION_SQL, /UPDATE public\.governance_documents\s+SET proposer_member_id = '92d26057-5550-4f15-a3bf-b00eed5f32f9'/);
      assert.match(MIGRATION_SQL, /WHERE id = '18ec4690-4f5a-4cab-904d-451e2c7245bf'/);
    });

    it('backfill is idempotent — WHERE proposer_member_id IS NULL + WHERE status = pending_proposer_consent', () => {
      assert.match(MIGRATION_SQL, /AND status = 'pending_proposer_consent'/);
      assert.match(MIGRATION_SQL, /AND proposer_member_id IS NULL/);
    });

    it('sanity DO RAISES if backfill missed the Frontiers fixture', () => {
      assert.match(MIGRATION_SQL, /DO \$\$\s*DECLARE v_count int;[\s\S]*?RAISE EXCEPTION 'p261 #312-W4b: Frontiers fixture backfill failed/);
    });
  });

  describe('p261.3 — create_governance_document_intake extended to persist proposer_member_id', () => {
    it('INSERT INTO governance_documents now includes proposer_member_id column', () => {
      // The INSERT block inside create_governance_document_intake must list proposer_member_id;
      // both pieces must exist in the migration body (no extraction needed — full body has them).
      assert.match(MIGRATION_CODE, /INSERT INTO public\.governance_documents \([\s\S]*?proposer_member_id,[\s\S]*?\)\s*VALUES/);
      assert.match(MIGRATION_CODE, /VALUES \([\s\S]*?v_proposer_member_id,/);
    });

    it('SECURITY DEFINER + pinned search_path preserved (minimum-diff CREATE OR REPLACE)', () => {
      assert.match(MIGRATION_SQL, /create_governance_document_intake[\s\S]*?SECURITY DEFINER[\s\S]*?SET search_path TO 'public', 'pg_temp'/);
    });

    it('GRANT EXECUTE TO authenticated + REVOKE FROM PUBLIC preserved', () => {
      assert.match(MIGRATION_SQL, /REVOKE EXECUTE ON FUNCTION public\.create_governance_document_intake\(jsonb\) FROM PUBLIC/);
      assert.match(MIGRATION_SQL, /GRANT  EXECUTE ON FUNCTION public\.create_governance_document_intake\(jsonb\) TO authenticated/);
    });
  });

  describe('p261.4 — sign_proposer_consent RPC body', () => {
    it('function signature: (uuid, jsonb DEFAULT NULL) RETURNS jsonb', () => {
      assert.match(MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\.sign_proposer_consent\(\s*p_document_id uuid,\s*p_evidence jsonb DEFAULT NULL\s*\)\s*RETURNS jsonb/);
    });

    it('SECURITY DEFINER + pinned search_path TO public, pg_temp', () => {
      assert.match(MIGRATION_SQL,
        /sign_proposer_consent[\s\S]*?SECURITY DEFINER\s+SET search_path TO 'public', 'pg_temp'/);
    });

    it('SEDIMENT-239b.A — caller resolved via members WHERE auth_id = auth.uid() (FK source = members.id)', () => {
      assert.match(MIGRATION_CODE, /SELECT id INTO v_caller_member_id\s+FROM public\.members\s+WHERE auth_id = auth\.uid\(\) AND is_active = true/);
    });

    it('caller MUST equal proposer_member_id (GP/admin cannot sign on behalf)', () => {
      assert.match(MIGRATION_CODE, /IF v_caller_member_id != v_doc_proposer_member_id THEN/);
      assert.match(MIGRATION_SQL, /only the named proposer can sign proposer_consent/);
    });

    it('rejects docs without proposer_member_id set (created pre-#377 or missing payload)', () => {
      assert.match(MIGRATION_CODE, /IF v_doc_proposer_member_id IS NULL THEN/);
      assert.match(MIGRATION_SQL, /sign_proposer_consent requires a named proposer/);
    });

    it('idempotent branch — already-draft returns already_signed=true without double-write', () => {
      assert.match(MIGRATION_CODE, /IF v_doc_status = 'draft' THEN[\s\S]*?'already_signed', true/);
    });

    it('status guard — only pending_proposer_consent transitions to draft', () => {
      assert.match(MIGRATION_CODE, /IF v_doc_status != 'pending_proposer_consent' THEN/);
      assert.match(MIGRATION_SQL, /requires pending_proposer_consent/);
    });

    it('atomic status flip: UPDATE governance_documents SET status = draft', () => {
      assert.match(MIGRATION_CODE, /UPDATE public\.governance_documents\s+SET status = 'draft'/);
    });

    it('audit log INSERT with canonical action governance.proposer_consent_signed', () => {
      assert.match(MIGRATION_SQL, /INSERT INTO public\.admin_audit_log[\s\S]*?'governance\.proposer_consent_signed'/);
    });

    it('audit metadata includes document_id, document_title, proposer_member_id, signed_at, evidence, rpc_version', () => {
      // Capture broader audit block — from canonical action literal through the jsonb_build_object close + NOTIFY trail.
      const auditBlock = MIGRATION_CODE.match(/'governance\.proposer_consent_signed'[\s\S]*?\)\s*\);/);
      assert.ok(auditBlock, 'audit log INSERT block must exist');
      const block = auditBlock[0];
      ['document_id', 'document_title', 'proposer_member_id', 'signed_at', 'evidence', 'rpc_version'].forEach(field => {
        assert.match(block, new RegExp(`'${field}'`), `audit metadata missing field ${field}`);
      });
      assert.match(block, /'p261_312_w4b'/);
    });

    it('FORWARD-DEFENSE: NEVER INSERTs into approval_signoffs (pre-chain capture only)', () => {
      // sign_proposer_consent body must NOT touch approval_signoffs (the doc has no chain yet)
      const fnBody = MIGRATION_CODE.match(/CREATE OR REPLACE FUNCTION public\.sign_proposer_consent[\s\S]*?\$\$ ?(?:LANGUAGE|;)/);
      assert.ok(fnBody, 'sign_proposer_consent body must be present');
      assert.doesNotMatch(fnBody[0], /INSERT INTO[\s\S]{0,200}?approval_signoffs/);
    });

    it('GRANT EXECUTE TO authenticated + REVOKE FROM PUBLIC', () => {
      assert.match(MIGRATION_SQL, /REVOKE EXECUTE ON FUNCTION public\.sign_proposer_consent\(uuid, jsonb\) FROM PUBLIC/);
      assert.match(MIGRATION_SQL, /GRANT  EXECUTE ON FUNCTION public\.sign_proposer_consent\(uuid, jsonb\) TO authenticated/);
    });

    it('migration ends with NOTIFY pgrst reload schema', () => {
      assert.match(MIGRATION_SQL, /NOTIFY pgrst, 'reload schema';/);
    });
  });

  describe('forward-defense: SEDIMENT-235.A close-keyword discipline (in migration body)', () => {
    it('migration body MUST NOT have close|fix|resolve + #N matching auto-close regex for stay-open issues (#312, #315, #96)', () => {
      // Search in migration SQL (including comments — GitHub regex matches PR body, not SQL, but
      // this defends against later copy/paste of phrasing into PR descriptions).
      const closePattern = /(close[sd]?|fix(?:es|ed)?|resolve[sd]?)\s+#(312|315|96)\b/i;
      assert.doesNotMatch(MIGRATION_SQL, closePattern,
        'Migration body contains close-keyword + stay-open #N — risk of accidental auto-close if copy/pasted into PR');
    });
  });

  // ─── DB-gated smoke ──────────────────────────────────────────────────────────
  describe('DB-gated live smoke (skips without SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY)', () => {
    it('Frontiers fixture has proposer_member_id = Fabrício Costa', { skip: !sb }, async () => {
      const { data, error } = await sb
        .from('governance_documents')
        .select('id, proposer_member_id, status')
        .eq('id', FRONTIERS_DOC_ID)
        .single();
      assert.ifError(error);
      assert.equal(data.proposer_member_id, FABRICIO_MEMBER_ID,
        'Frontiers fixture must have proposer_member_id backfilled to Fabrício Costa');
    });

    it('sign_proposer_consent RPC is callable via PostgREST (existence probe)', { skip: !sb }, async () => {
      // Calling with a clearly-invalid UUID returns an error from the RPC body, NOT a "function not found"
      // PostgREST error. This proves the RPC is exposed + registered.
      const { error } = await sb.rpc('sign_proposer_consent', {
        p_document_id: '00000000-0000-0000-0000-000000000000',
        p_evidence: null,
      });
      // Service-role call: should fail with "no active member record" (caller has no JWT membership context)
      // OR with "Unauthorized" / "not found" — NOT with "function does not exist".
      if (error) {
        assert.doesNotMatch(error.message || '', /does not exist|function .* not found/i,
          `sign_proposer_consent must be registered in PostgREST: ${error.message}`);
      }
    });
  });
});
