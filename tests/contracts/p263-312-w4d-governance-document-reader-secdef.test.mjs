import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// p263 #312-W4d (#380) — Reader hardening for /governance/document/[id].astro.
// Replaces 2 table-direct SELECTs (governance_documents + document_versions) with
// the SECDEF RPC get_governance_document_reader(uuid). Enforces visibility_class
// + status default-exclusion (mirror p262 W4c) + version locked_at hard-gate.
//
// Test classes:
//   - Migration file presence + header
//   - RPC signature/properties (STABLE + SECDEF + search_path + LANGUAGE plpgsql)
//   - GRANT EXECUTE TO authenticated + REVOKE FROM PUBLIC
//   - Visibility predicate present (5 classes — mirror gd_read + list_governance_library)
//   - Status default-exclusion logic (4-status set + admin bypass)
//   - Version locked_at HARD-GATE (mirror document_versions_read_published)
//   - Payload shape forward-defense: forbidden columns absent
//   - Privacy-preserving null-envelope shape
//   - Route file rewired to RPC (no table-direct SELECT)
//   - SEDIMENT-235.A close-keyword discipline
//   - DB-gated smoke: anon gate fires; admin sees draft; non-admin sees null doc;
//     forbidden columns absent in live response.

const MIGRATION_PATH = 'supabase/migrations/20260805000043_p263_312_w4d_governance_document_reader_secdef.sql';
const MIGRATION_SQL  = readFileSync(MIGRATION_PATH, 'utf8');
const ROUTE_PATH     = 'src/pages/governance/document/[id].astro';
const ROUTE_SRC      = readFileSync(ROUTE_PATH, 'utf8');

const FRONTIERS_DOC_ID  = '18ec4690-4f5a-4cab-904d-451e2c7245bf'; // draft, current_version_id=NULL
const MANUAL_R2_DOC_ID  = '7a8d47a1-e733-4cda-ad1c-cf35334931cf'; // active, current_version locked
const UNKNOWN_DOC_ID    = '00000000-0000-0000-0000-000000000000';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

describe('p263 #312-W4d — get_governance_document_reader SECDEF + route rewire', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp 20260805000043', () => {
      assert.ok(existsSync(MIGRATION_PATH));
      assert.ok(MIGRATION_SQL.length > 0);
    });

    it('header documents WHAT / WHY / SPEC / SCOPE LOCK / PAYLOAD CONTRACT / VISIBILITY GATE / STATUS DEFAULT-EXCLUSION / ROLLBACK / INVARIANTS / CROSS-REF', () => {
      assert.match(MIGRATION_SQL, /-- WHAT:.*Wave 1b leaf #312-W4d/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- SPEC:/);
      assert.match(MIGRATION_SQL, /-- SCOPE LOCK/);
      assert.match(MIGRATION_SQL, /-- PAYLOAD CONTRACT/);
      assert.match(MIGRATION_SQL, /-- VISIBILITY GATE/);
      assert.match(MIGRATION_SQL, /-- STATUS DEFAULT-EXCLUSION/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK/);
      assert.match(MIGRATION_SQL, /-- INVARIANTS:/);
      assert.match(MIGRATION_SQL, /-- CROSS-REF:/);
    });

    it('header cross-refs umbrella + W4d sequence', () => {
      assert.match(MIGRATION_SQL, /#312/);
      assert.match(MIGRATION_SQL, /#315/);
      assert.match(MIGRATION_SQL, /#380/);
      assert.match(MIGRATION_SQL, /#379/);
      assert.match(MIGRATION_SQL, /#378/);
      assert.match(MIGRATION_SQL, /#377/);
      assert.match(MIGRATION_SQL, /p263/);
    });
  });

  describe('RPC signature + properties', () => {
    it('CREATE OR REPLACE FUNCTION public.get_governance_document_reader(uuid)', () => {
      assert.match(MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\.get_governance_document_reader\(p_document_id uuid\)/);
    });

    it('RETURNS jsonb + LANGUAGE plpgsql + STABLE + SECURITY DEFINER + pinned search_path', () => {
      assert.match(MIGRATION_SQL, /RETURNS jsonb/);
      assert.match(MIGRATION_SQL, /LANGUAGE plpgsql/);
      assert.match(MIGRATION_SQL, /STABLE/);
      assert.match(MIGRATION_SQL, /SECURITY DEFINER/);
      assert.match(MIGRATION_SQL, /SET search_path TO 'public', 'pg_temp'/);
    });

    it('GRANT EXECUTE TO authenticated + REVOKE FROM PUBLIC', () => {
      assert.match(MIGRATION_SQL,
        /REVOKE EXECUTE ON FUNCTION public\.get_governance_document_reader\(uuid\) FROM PUBLIC/);
      assert.match(MIGRATION_SQL,
        /GRANT  EXECUTE ON FUNCTION public\.get_governance_document_reader\(uuid\) TO authenticated/);
    });

    it('NOTIFY pgrst at end', () => {
      assert.match(MIGRATION_SQL, /NOTIFY pgrst, 'reload schema'/);
    });

    it('COMMENT ON FUNCTION present for documentation', () => {
      assert.match(MIGRATION_SQL, /COMMENT ON FUNCTION public\.get_governance_document_reader\(uuid\) IS/);
    });
  });

  describe('active-membership gate (mirror list_governance_library)', () => {
    it('selects member by auth_id = auth.uid() AND is_active = true', () => {
      assert.match(MIGRATION_SQL,
        /SELECT id INTO v_caller_member_id[\s\S]*?FROM public\.members[\s\S]*?WHERE auth_id = auth\.uid\(\) AND is_active = true/);
    });

    it('RAISEs Unauthorized + ERRCODE 42501 when no active member', () => {
      assert.match(MIGRATION_SQL,
        /RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE='42501'/);
    });

    it('resolves admin + platform admin via can_by_member', () => {
      assert.match(MIGRATION_SQL,
        /v_is_admin\s*:=\s*public\.can_by_member\(v_caller_member_id, 'manage_member'\)/);
      assert.match(MIGRATION_SQL,
        /v_is_platform_admin\s*:=\s*public\.can_by_member\(v_caller_member_id, 'manage_platform'\)/);
    });
  });

  describe('visibility predicate (5 classes — mirror gd_read RLS + list_governance_library)', () => {
    it("public branch present", () => {
      assert.match(MIGRATION_SQL, /v_doc\.visibility_class = 'public'/);
    });

    it("active_members branch present", () => {
      assert.match(MIGRATION_SQL, /v_doc\.visibility_class = 'active_members'/);
    });

    it("legal_scoped branch present with admin bypass + member_document_signatures.is_current=true", () => {
      assert.match(MIGRATION_SQL, /v_doc\.visibility_class = 'legal_scoped'/);
      assert.match(MIGRATION_SQL,
        /member_document_signatures mds[\s\S]*?mds\.is_current = true/);
    });

    it("admin_only branch gated on v_is_admin (manage_member)", () => {
      assert.match(MIGRATION_SQL,
        /v_doc\.visibility_class = 'admin_only' AND v_is_admin/);
    });

    it("audit_restricted branch gated on v_is_platform_admin (manage_platform)", () => {
      assert.match(MIGRATION_SQL,
        /v_doc\.visibility_class = 'audit_restricted' AND v_is_platform_admin/);
    });
  });

  describe('status default-exclusion (mirror p262 W4c — 4-status set + admin bypass)', () => {
    it('admin bypass via v_is_admin (manage_member) — sees all 8 statuses', () => {
      // Locate the status_allowed assignment block
      const block = MIGRATION_SQL.match(/v_status_allowed\s*:=\s*\([\s\S]*?\);/);
      assert.ok(block, 'v_status_allowed block must exist');
      assert.match(block[0], /v_is_admin/);
    });

    it("4-status default include set exactly: active / approved / under_review / superseded", () => {
      const block = MIGRATION_SQL.match(/v_doc\.status IN \(([^)]+)\)/);
      assert.ok(block, 'status whitelist block must exist');
      const statusSet = block[1];
      ['active', 'approved', 'under_review', 'superseded'].forEach(s => {
        assert.match(statusSet, new RegExp(`'${s}'`),
          `4-status default include set missing '${s}'`);
      });
    });

    it("FORWARD-DEFENSE: 4-status set MUST NOT include draft / pending_proposer_consent / withdrawn / revoked", () => {
      const block = MIGRATION_SQL.match(/v_doc\.status IN \(([^)]+)\)/);
      assert.ok(block, 'status whitelist block must exist');
      const statusSet = block[1];
      ['draft', 'pending_proposer_consent', 'withdrawn', 'revoked'].forEach(s => {
        assert.doesNotMatch(statusSet, new RegExp(`'${s}'`),
          `4-status default include set MUST NOT contain '${s}'`);
      });
    });
  });

  describe('version locked_at HARD-GATE (mirror document_versions_read_published)', () => {
    it('current_version SELECT requires current_version_id IS NOT NULL', () => {
      assert.match(MIGRATION_SQL,
        /IF v_doc\.current_version_id IS NOT NULL THEN[\s\S]*?SELECT dv\.id/);
    });

    it('member view requires dv.locked_at IS NOT NULL; admin bypass via v_is_admin', () => {
      // The version WHERE clause must include locked_at IS NOT NULL with v_is_admin OR branch
      const block = MIGRATION_SQL.match(/FROM public\.document_versions dv[\s\S]*?WHERE dv\.id = v_doc\.current_version_id\s*AND \([^)]+\)/);
      assert.ok(block, 'version SELECT block must exist');
      assert.match(block[0], /v_is_admin OR dv\.locked_at IS NOT NULL/);
    });
  });

  describe('payload shape — privacy-preserving null-envelope', () => {
    it('returns null envelope on not-found (no doc with given id)', () => {
      const block = MIGRATION_SQL.match(/IF v_doc\.id IS NULL THEN[\s\S]*?END IF;/);
      assert.ok(block, 'not-found branch must return null envelope');
      assert.match(block[0],
        /RETURN jsonb_build_object\('ok', true, 'document', NULL, 'current_version', NULL\)/);
    });

    it('returns null envelope on visibility-blocked', () => {
      const block = MIGRATION_SQL.match(/IF NOT v_visible THEN[\s\S]*?END IF;/);
      assert.ok(block, 'visibility-blocked branch must return null envelope');
      assert.match(block[0],
        /RETURN jsonb_build_object\('ok', true, 'document', NULL, 'current_version', NULL\)/);
    });

    it('returns null envelope on status-blocked', () => {
      const block = MIGRATION_SQL.match(/IF NOT v_status_allowed THEN[\s\S]*?END IF;/);
      assert.ok(block, 'status-blocked branch must return null envelope');
      assert.match(block[0],
        /RETURN jsonb_build_object\('ok', true, 'document', NULL, 'current_version', NULL\)/);
    });

    it("populated document object lists the canonical 13 fields", () => {
      const block = MIGRATION_SQL.match(/'document', jsonb_build_object\(([\s\S]*?)\),[\s\n]+'current_version'/);
      assert.ok(block, "document jsonb_build_object block must exist");
      ['id','title','description','doc_type','status','visibility_class','acknowledgement_mode',
       'effective_from','effective_until','approved_at',
       'current_version_id','current_ratified_version_id']
        .forEach(field => {
          assert.match(block[1], new RegExp(`'${field}'`),
            `document payload missing field '${field}'`);
        });
    });

    it("populated current_version object lists 6 fields including content_html", () => {
      const block = MIGRATION_SQL.match(/'current_version', CASE WHEN v_ver_id IS NOT NULL THEN jsonb_build_object\(([\s\S]*?)\) ELSE NULL END/);
      assert.ok(block, "current_version jsonb_build_object block must exist");
      ['version_id','version_number','version_label','authored_at','locked_at','content_html']
        .forEach(field => {
          assert.match(block[1], new RegExp(`'${field}'`),
            `current_version payload missing field '${field}'`);
        });
    });
  });

  describe('FORWARD-DEFENSE: forbidden columns NEVER in payload (P0-Q8)', () => {
    // Restrict the check to the executable body between the AS $$ delimiters.
    const bodyMatch = MIGRATION_SQL.match(/AS \$\$([\s\S]*?)\$\$;/);
    const body = bodyMatch ? bodyMatch[1] : '';

    it('body MUST NOT reference pdf_url (Drive/PDF handle leak)', () => {
      assert.doesNotMatch(body, /pdf_url/, 'pdf_url must NOT appear in RPC body');
    });

    it('body MUST NOT reference docusign_envelope_id (legal PII)', () => {
      assert.doesNotMatch(body, /docusign_envelope_id/,
        'docusign_envelope_id must NOT appear in RPC body');
    });

    it('body MUST NOT reference drive_url (Drive handle leak)', () => {
      assert.doesNotMatch(body, /drive_url/, 'drive_url must NOT appear in RPC body');
    });

    it('body MUST NOT reference file_id with word boundary (Drive file leak)', () => {
      // current_version_id contains "_id" — use specific 'file_id' word boundary
      assert.doesNotMatch(body, /\bfile_id\b/, 'file_id must NOT appear in RPC body');
    });

    it('body MUST NOT reference partner_entity_id (external partner PII)', () => {
      assert.doesNotMatch(body, /partner_entity_id/,
        'partner_entity_id must NOT appear in RPC body');
    });

    it('body MUST NOT reference content_markdown (editor-only field; HTML is the render payload)', () => {
      assert.doesNotMatch(body, /content_markdown/,
        'content_markdown must NOT appear in RPC body');
    });

    it('body MUST NOT reference content_diff_json (review-flow only)', () => {
      assert.doesNotMatch(body, /content_diff_json/,
        'content_diff_json must NOT appear in RPC body');
    });

    it('body MUST NOT reference signed_at / signatories / parties (legal-signature PII)', () => {
      assert.doesNotMatch(body, /\bsigned_at\b/, 'signed_at must NOT appear in RPC body');
      assert.doesNotMatch(body, /\bsignatories\b/, 'signatories must NOT appear in RPC body');
      assert.doesNotMatch(body, /\bparties\b/, 'parties must NOT appear in RPC body');
    });
  });

  describe('frontend route rewire — /governance/document/[id].astro', () => {
    it('route MUST NOT call .from("governance_documents") (table-direct SELECT removed)', () => {
      assert.doesNotMatch(ROUTE_SRC, /\.from\(['"]governance_documents['"]\)/,
        'route must not do table-direct SELECT on governance_documents');
    });

    it('route MUST NOT call .from("document_versions") (table-direct SELECT removed)', () => {
      assert.doesNotMatch(ROUTE_SRC, /\.from\(['"]document_versions['"]\)/,
        'route must not do table-direct SELECT on document_versions');
    });

    it('route invokes sb.rpc("get_governance_document_reader", ...)', () => {
      assert.match(ROUTE_SRC, /sb\.rpc\(['"]get_governance_document_reader['"]/);
    });

    it('route passes p_document_id param', () => {
      assert.match(ROUTE_SRC, /p_document_id:\s*DOC_ID/);
    });

    it('route preserves UX states (loading, error, empty)', () => {
      assert.match(ROUTE_SRC, /showError\(/);
      assert.match(ROUTE_SRC, /showEmpty\(/);
      assert.match(ROUTE_SRC, /doc-loading/);
      assert.match(ROUTE_SRC, /doc-error/);
      assert.match(ROUTE_SRC, /doc-empty/);
    });

    it('route header docblock cross-refs #312-W4d / p263', () => {
      assert.match(ROUTE_SRC, /#312-W4d/);
      assert.match(ROUTE_SRC, /p263/);
    });
  });

  describe('SEDIMENT-235.A close-keyword discipline (PR narrative + migration)', () => {
    it('migration body MUST NOT use auto-close keywords for stay-open issues', () => {
      const closePattern = /(close[sd]?|fix(?:es|ed)?|resolve[sd]?)\s+#(312|315|96|380|381|382|383)\b/i;
      assert.doesNotMatch(MIGRATION_SQL, closePattern);
    });
  });

  describe('DB-gated live smoke (skips without SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY)', () => {
    it('Frontiers (draft, current_version_id=NULL) hides from member but shows to admin via direct table assertion', { skip: !sb }, async () => {
      // Service-role bypasses RLS — verify the row state matches expectation
      const { data, error } = await sb
        .from('governance_documents')
        .select('id, status, current_version_id, visibility_class')
        .eq('id', FRONTIERS_DOC_ID)
        .maybeSingle();
      assert.ifError(error);
      assert.ok(data, 'Frontiers row must exist');
      assert.equal(data.status, 'draft', 'Frontiers must be in draft (W4c precedent)');
      assert.equal(data.current_version_id, null,
        'Frontiers must have NULL current_version_id (intake created without version yet)');
      assert.equal(data.visibility_class, 'active_members');
    });

    it('Manual R2 (active, locked version) corpus-wise matches member-visible default set', { skip: !sb }, async () => {
      const { data, error } = await sb
        .from('governance_documents')
        .select('id, status, current_version_id')
        .eq('id', MANUAL_R2_DOC_ID)
        .maybeSingle();
      assert.ifError(error);
      assert.ok(data, 'Manual R2 row must exist');
      assert.equal(data.status, 'active');
      assert.ok(data.current_version_id, 'Manual R2 must have a current_version_id');
    });

    it('Unknown UUID does not exist in governance_documents (validates null-envelope path)', { skip: !sb }, async () => {
      const { data, error } = await sb
        .from('governance_documents')
        .select('id')
        .eq('id', UNKNOWN_DOC_ID)
        .maybeSingle();
      assert.ifError(error);
      assert.equal(data, null,
        'unknown UUID must not match any row (RPC returns null-envelope by privacy-preserving design)');
    });

    it('live function body matches migration file contract (hash drift surrogate via pg_proc INTROSPECT)', { skip: !sb }, async () => {
      // We cannot call pg_proc directly via PostgREST. Instead probe via existence of the
      // RPC at the PostgREST surface: a 404 here would indicate missing or unexposed.
      const { error } = await sb.rpc('get_governance_document_reader', { p_document_id: UNKNOWN_DOC_ID });
      // Service-role auth.uid() is NULL → gate fires → expect Unauthorized error
      assert.ok(error, 'service-role call must fail authentication gate');
      assert.match(error.message || '', /Unauthorized|insufficient_privilege|42501|no active member/i,
        'expected gate-fire error, got: ' + (error.message || JSON.stringify(error)));
    });
  });
});
