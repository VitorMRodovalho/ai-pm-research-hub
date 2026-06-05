import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// p264 #312-W4e (#381) — Curator draft-read mitigation for Roberto Macêdo + Sarah
// Faria post-p256 Wave 1a M2 RLS swap. Extends p263 W4d reader
// get_governance_document_reader(uuid) with a 3rd bypass dimension
// "v_is_curator_assigned" — bypass status default-exclusion + version locked_at
// hard-gate ONLY for members eligible as 'curator' on the doc_type when an
// OPEN approval_chain exists on the specific document. Visibility predicate
// UNCHANGED — no curate_content blanket grant; review/audit context preserved.
//
// Test classes:
//   - Migration file presence + header (W4e cross-refs)
//   - RPC signature (same as W4d — CREATE OR REPLACE preserves contract)
//   - W4e v_is_curator_assigned declaration + scoped compute (non-admin only)
//   - Assignment predicate: open chain (closed_at IS NULL) AND (cache hit OR
//     _can_sign_gate fallback) with 'curator' in eligible_gates
//   - Status default-exclusion: bypass widened to v_is_admin OR v_is_curator_assigned
//   - Version locked_at hard-gate: bypass widened to v_is_admin OR v_is_curator_assigned
//   - FORWARD-DEFENSE: visibility predicate NOT widened (5-class ladder unchanged;
//     v_is_curator_assigned absent from visibility branches)
//   - FORWARD-DEFENSE: 4-status include set preserved byte-identical (W4c contract)
//   - FORWARD-DEFENSE: 8 forbidden columns ABSENT (P0-Q8 — same as W4d)
//   - FORWARD-DEFENSE: null-envelope shape preserved (privacy-preserving error parity)
//   - FORWARD-DEFENSE: blanket curate_content grant NOT introduced (assignment
//     predicate REQUIRES open chain — capability alone is insufficient)
//   - GRANT/REVOKE preserved + NOTIFY pgrst + COMMENT
//   - SEDIMENT-235.A close-keyword discipline
//   - DB-gated smoke: Roberto/Sarah curator-eligibility evidence; open chains
//     exist on chained docs; W4e bypass invocation surfaces (service-role gate
//     verification surrogate).

const MIGRATION_PATH = 'supabase/migrations/20260805000044_p264_312_w4e_curator_draft_read_assigned.sql';
const MIGRATION_SQL  = readFileSync(MIGRATION_PATH, 'utf8');

// Body-only slice for forbidden-column checks (mirror W4d pattern).
const BODY_MATCH = MIGRATION_SQL.match(/AS \$\$([\s\S]*?)\$\$;/);
const BODY = BODY_MATCH ? BODY_MATCH[1] : '';

// Visibility-block-only slice (forward-defense: v_is_curator_assigned must NOT
// appear in visibility branches).
const VISIBILITY_BLOCK_MATCH = MIGRATION_SQL.match(
  /v_visible\s*:=\s*\(([\s\S]*?)\);/
);
const VISIBILITY_BLOCK = VISIBILITY_BLOCK_MATCH ? VISIBILITY_BLOCK_MATCH[1] : '';

// Live fixtures — live state snapshot at p264 close (2026-05-26).
// Member UUIDs (NOT auth UUIDs — auth_id is the application-internal session
// reference; tests only need member.id which is the public domain anchor.)
const ROBERTO_MEMBER_ID = '49836a70-a41e-4a0b-85b0-aa05b13d3f25';
const SARAH_MEMBER_ID   = '19b7ff75-bcb1-4a15-a8e1-006fc6822069';
const TAP_CPMAI_DOC_ID = 'd7447a94-ca3c-4cf6-8b6e-5e604136522c'; // draft, project_charter, unlocked, OPEN chain
const UNKNOWN_DOC_ID   = '00000000-0000-0000-0000-000000000000';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

describe('p264 #312-W4e — get_governance_document_reader assigned-curator bypass', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp 20260805000044', () => {
      assert.ok(existsSync(MIGRATION_PATH));
      assert.ok(MIGRATION_SQL.length > 0);
    });

    it('header documents WHAT / WHY / SPEC / SCOPE LOCK / ASSIGNMENT DEFINITION / PAYLOAD CONTRACT / VISIBILITY GATE / STATUS DEFAULT-EXCLUSION / LOCKED_AT HARD-GATE / ROLLBACK / INVARIANTS / CROSS-REF', () => {
      assert.match(MIGRATION_SQL, /-- WHAT:.*Wave 1b leaf #312-W4e/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- SPEC:/);
      assert.match(MIGRATION_SQL, /-- SCOPE LOCK/);
      assert.match(MIGRATION_SQL, /-- ASSIGNMENT DEFINITION/);
      assert.match(MIGRATION_SQL, /-- PAYLOAD CONTRACT/);
      assert.match(MIGRATION_SQL, /-- VISIBILITY GATE/);
      assert.match(MIGRATION_SQL, /-- STATUS DEFAULT-EXCLUSION/);
      assert.match(MIGRATION_SQL, /-- VERSION LOCKED_AT HARD-GATE/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK/);
      assert.match(MIGRATION_SQL, /-- INVARIANTS:/);
      assert.match(MIGRATION_SQL, /-- CROSS-REF:/);
    });

    it('header cross-refs umbrella + W4e sequence + p256 origin + W4d predecessor', () => {
      assert.match(MIGRATION_SQL, /#381/);
      assert.match(MIGRATION_SQL, /#312/);
      assert.match(MIGRATION_SQL, /#315/);
      assert.match(MIGRATION_SQL, /#96/);
      assert.match(MIGRATION_SQL, /#380/);
      assert.match(MIGRATION_SQL, /#379/);
      assert.match(MIGRATION_SQL, /#378/);
      assert.match(MIGRATION_SQL, /#377/);
      assert.match(MIGRATION_SQL, /p256/);
      assert.match(MIGRATION_SQL, /p263/);
      assert.match(MIGRATION_SQL, /p264/);
    });

    it('header names Roberto Macêdo + Sarah Faria personas (regression provenance)', () => {
      assert.match(MIGRATION_SQL, /Roberto/);
      assert.match(MIGRATION_SQL, /Sarah Faria/);
    });

    it('header names p256 Wave 1a M2 (origin of regression) + W4d (predecessor reader)', () => {
      assert.match(MIGRATION_SQL, /Wave 1a M2/);
      assert.match(MIGRATION_SQL, /W4d/);
      assert.match(MIGRATION_SQL, /20260805000036/);
    });
  });

  describe('RPC signature + properties (preserved from W4d via CREATE OR REPLACE)', () => {
    it('CREATE OR REPLACE FUNCTION public.get_governance_document_reader(p_document_id uuid)', () => {
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

    it('COMMENT ON FUNCTION refreshed to mention W4e assigned-curator bypass', () => {
      assert.match(MIGRATION_SQL,
        /COMMENT ON FUNCTION public\.get_governance_document_reader\(uuid\) IS/);
      assert.match(MIGRATION_SQL, /assigned-curator bypass/);
      assert.match(MIGRATION_SQL, /Roberto Mac/);
      assert.match(MIGRATION_SQL, /Sarah Faria/);
    });
  });

  describe('active-membership gate (mirror list_governance_library — preserved from W4d)', () => {
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

  describe('W4e: v_is_curator_assigned declaration + scoped compute', () => {
    it('v_is_curator_assigned boolean declared with default false in DECLARE block', () => {
      assert.match(MIGRATION_SQL,
        /v_is_curator_assigned boolean\s*:=\s*false/);
    });

    it('v_is_curator_assigned compute block is gated on NOT v_is_admin (efficiency)', () => {
      assert.match(MIGRATION_SQL,
        /IF NOT v_is_admin THEN[\s\S]*?v_is_curator_assigned\s*:=\s*EXISTS/);
    });

    it('assignment predicate uses approval_chains with closed_at IS NULL (canonical open-chain pattern)', () => {
      const block = MIGRATION_SQL.match(/v_is_curator_assigned\s*:=\s*EXISTS \(([\s\S]*?)\)\s*AND \(/);
      assert.ok(block, 'curator-assigned EXISTS block must exist');
      assert.match(block[1], /FROM public\.approval_chains ac/);
      assert.match(block[1], /WHERE ac\.document_id = p_document_id/);
      assert.match(block[1], /AND ac\.closed_at IS NULL/);
    });

    it('cache path uses preview_gate_eligibles_cache + 4-tuple predicate (member + doc_type + curator gate)', () => {
      assert.match(MIGRATION_SQL,
        /FROM public\.preview_gate_eligibles_cache pgec[\s\S]*?WHERE pgec\.member_id = v_caller_member_id[\s\S]*?AND pgec\.doc_type = v_doc\.doc_type[\s\S]*?AND 'curator' = ANY\(pgec\.eligible_gates\)/);
    });

    it("fallback path uses _can_sign_gate(member_id, NULL, 'curator', doc_type, NULL)", () => {
      assert.match(MIGRATION_SQL,
        /OR public\._can_sign_gate\(v_caller_member_id, NULL, 'curator', v_doc\.doc_type, NULL\)/);
    });

    it('cache + fallback combine via OR inside the AND (cache miss is invisible to caller)', () => {
      // Pattern: EXISTS ... approval_chains ... ) AND ( EXISTS ... preview_gate_eligibles_cache ... ) OR public._can_sign_gate(...) )
      assert.match(MIGRATION_SQL,
        /\)\s*AND \(\s*EXISTS \([\s\S]*?preview_gate_eligibles_cache[\s\S]*?\)\s*OR public\._can_sign_gate/);
    });
  });

  describe('status default-exclusion: bypass widened to (v_is_admin OR v_is_curator_assigned)', () => {
    it('v_status_allowed includes v_is_curator_assigned in the OR ladder', () => {
      const block = MIGRATION_SQL.match(/v_status_allowed\s*:=\s*\(([\s\S]*?)\);/);
      assert.ok(block, 'v_status_allowed block must exist');
      assert.match(block[1], /v_is_admin/);
      assert.match(block[1], /OR v_is_curator_assigned/);
    });

    it('4-status default include set preserved byte-identical: active / approved / under_review / superseded', () => {
      const block = MIGRATION_SQL.match(/v_doc\.status IN \(([^)]+)\)/);
      assert.ok(block, 'status whitelist block must exist');
      const statusSet = block[1];
      ['active', 'approved', 'under_review', 'superseded'].forEach(s => {
        assert.match(statusSet, new RegExp(`'${s}'`),
          `4-status include set must contain '${s}'`);
      });
    });

    it('FORWARD-DEFENSE: 4-status set MUST NOT include draft / pending_proposer_consent / withdrawn / revoked', () => {
      const block = MIGRATION_SQL.match(/v_doc\.status IN \(([^)]+)\)/);
      assert.ok(block, 'status whitelist block must exist');
      const statusSet = block[1];
      ['draft', 'pending_proposer_consent', 'withdrawn', 'revoked'].forEach(s => {
        assert.doesNotMatch(statusSet, new RegExp(`'${s}'`),
          `4-status include set MUST NOT contain '${s}'`);
      });
    });
  });

  describe('version locked_at HARD-GATE: bypass widened to (v_is_admin OR v_is_curator_assigned)', () => {
    it('current_version SELECT gated on current_version_id IS NOT NULL', () => {
      assert.match(MIGRATION_SQL,
        /IF v_doc\.current_version_id IS NOT NULL THEN[\s\S]*?SELECT dv\.id/);
    });

    it("WHERE clause: (v_is_admin OR v_is_curator_assigned OR dv.locked_at IS NOT NULL)", () => {
      // Find the version SELECT WHERE clause
      const block = MIGRATION_SQL.match(
        /FROM public\.document_versions dv[\s\S]*?WHERE dv\.id = v_doc\.current_version_id\s*AND \(([^)]+)\)/
      );
      assert.ok(block, 'version SELECT block must exist');
      assert.match(block[1], /v_is_admin/);
      assert.match(block[1], /OR v_is_curator_assigned/);
      assert.match(block[1], /OR dv\.locked_at IS NOT NULL/);
    });
  });

  describe('FORWARD-DEFENSE: visibility predicate UNCHANGED — v_is_curator_assigned NOT widened into visibility', () => {
    it('visibility predicate block does NOT reference v_is_curator_assigned', () => {
      // The visibility block is the 5-class ladder; curator bypass must NOT widen visibility.
      assert.ok(VISIBILITY_BLOCK.length > 0, 'visibility block must be locatable');
      assert.doesNotMatch(VISIBILITY_BLOCK, /v_is_curator_assigned/,
        'FORWARD-DEFENSE: visibility predicate MUST NOT reference v_is_curator_assigned (review/audit context preserved; legal_scoped + admin_only + audit_restricted still gated normally)');
    });

    it('5-class visibility ladder preserved byte-identical (public / active_members / legal_scoped + admin_or_signer / admin_only / audit_restricted)', () => {
      assert.match(VISIBILITY_BLOCK, /'public'/);
      assert.match(VISIBILITY_BLOCK, /'active_members'/);
      assert.match(VISIBILITY_BLOCK, /'legal_scoped'/);
      assert.match(VISIBILITY_BLOCK, /'admin_only'/);
      assert.match(VISIBILITY_BLOCK, /'audit_restricted'/);
      assert.match(VISIBILITY_BLOCK, /member_document_signatures/);
      assert.match(VISIBILITY_BLOCK, /mds\.is_current = true/);
      assert.match(VISIBILITY_BLOCK, /v_is_admin/);
      assert.match(VISIBILITY_BLOCK, /v_is_platform_admin/);
    });
  });

  describe('FORWARD-DEFENSE: blanket curate_content grant NOT introduced (assignment requires open chain)', () => {
    it('curator bypass MUST NOT be a bare can_by_member(member_id, \'curate_content\') check', () => {
      // The Pattern A from the issue body (`can_by_member` direct on curate_content) was
      // REJECTED per PM dispatch. The migration must use _can_sign_gate (which encapsulates
      // gate-eligibility semantics) AND open-chain gating.
      assert.doesNotMatch(BODY,
        /v_is_curator_assigned\s*:=\s*public\.can_by_member\([^,]+,\s*'curate_content'\)/,
        'W4e MUST gate on assignment (open chain + gate eligibility), not bare curate_content capability');
    });

    it('participate_in_governance_review is NOT used as the curator bypass predicate (issue Pattern B rejected in favor of cache+_can_sign_gate)', () => {
      // Issue body Pattern B used `participate_in_governance_review`. PM ratified the
      // cache + _can_sign_gate hybrid instead. participate_in_governance_review must NOT
      // appear as the curator bypass anchor.
      assert.doesNotMatch(BODY,
        /v_is_curator_assigned\s*:=[\s\S]*?'participate_in_governance_review'/,
        "W4e MUST anchor on _can_sign_gate / cache lookup, not participate_in_governance_review");
    });
  });

  describe('payload shape — privacy-preserving null-envelope (preserved from W4d)', () => {
    it('returns null envelope on not-found', () => {
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

  describe('FORWARD-DEFENSE: forbidden columns NEVER in payload (P0-Q8 — preserved from W4d)', () => {
    it('body MUST NOT reference pdf_url', () => {
      assert.doesNotMatch(BODY, /pdf_url/);
    });

    it('body MUST NOT reference docusign_envelope_id', () => {
      assert.doesNotMatch(BODY, /docusign_envelope_id/);
    });

    it('body MUST NOT reference drive_url', () => {
      assert.doesNotMatch(BODY, /drive_url/);
    });

    it('body MUST NOT reference file_id with word boundary', () => {
      assert.doesNotMatch(BODY, /\bfile_id\b/);
    });

    it('body MUST NOT reference partner_entity_id', () => {
      assert.doesNotMatch(BODY, /partner_entity_id/);
    });

    it('body MUST NOT reference content_markdown', () => {
      assert.doesNotMatch(BODY, /content_markdown/);
    });

    it('body MUST NOT reference content_diff_json', () => {
      assert.doesNotMatch(BODY, /content_diff_json/);
    });

    it('body MUST NOT reference signed_at / signatories / parties', () => {
      assert.doesNotMatch(BODY, /\bsigned_at\b/);
      assert.doesNotMatch(BODY, /\bsignatories\b/);
      assert.doesNotMatch(BODY, /\bparties\b/);
    });
  });

  describe('SEDIMENT-235.A close-keyword discipline (migration body)', () => {
    it('migration body MUST NOT use auto-close keywords adjacent to non-target issue numbers', () => {
      const closePattern = /(close[sd]?|fix(?:es|ed)?|resolve[sd]?)\s+#(312|315|96|380|382|383)\b/i;
      assert.doesNotMatch(MIGRATION_SQL, closePattern,
        'SEDIMENT-235.A: migration body MUST NOT contain close|fix|resolve adjacent to non-target issues (#312/#315/#96/#380/#382/#383 stay open)');
    });
  });

  describe('DB-gated live smoke (skips without SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY)', () => {
    it('Roberto Macêdo exists with curate_content + NOT manage_member', { skip: !sb }, async () => {
      const { data: m, error } = await sb
        .from('members')
        .select('id, name, is_active')
        .eq('id', ROBERTO_MEMBER_ID)
        .maybeSingle();
      assert.ifError(error);
      assert.ok(m, 'Roberto member row must exist');
      assert.equal(m.is_active, true, 'Roberto must be active');

      const { data: canCurate } = await sb.rpc('can_by_member', { p_member_id: ROBERTO_MEMBER_ID, p_action: 'curate_content' });
      const { data: canAdmin }  = await sb.rpc('can_by_member', { p_member_id: ROBERTO_MEMBER_ID, p_action: 'manage_member' });
      assert.equal(canCurate, true,  'Roberto must have curate_content');
      assert.equal(canAdmin,  false, 'Roberto must NOT have manage_member (regression provenance)');
    });

    it('Sarah Faria exists with curate_content + NOT manage_member', { skip: !sb }, async () => {
      const { data: m, error } = await sb
        .from('members')
        .select('id, name, is_active')
        .eq('id', SARAH_MEMBER_ID)
        .maybeSingle();
      assert.ifError(error);
      assert.ok(m, 'Sarah member row must exist');
      assert.equal(m.is_active, true, 'Sarah must be active');

      const { data: canCurate } = await sb.rpc('can_by_member', { p_member_id: SARAH_MEMBER_ID, p_action: 'curate_content' });
      const { data: canAdmin }  = await sb.rpc('can_by_member', { p_member_id: SARAH_MEMBER_ID, p_action: 'manage_member' });
      assert.equal(canCurate, true,  'Sarah must have curate_content');
      assert.equal(canAdmin,  false, 'Sarah must NOT have manage_member (regression provenance)');
    });

    it('TAP CPMAI exists with status=draft + visibility_class=active_members (regression target)', { skip: !sb }, async () => {
      const { data, error } = await sb
        .from('governance_documents')
        .select('id, status, doc_type, visibility_class, current_version_id')
        .eq('id', TAP_CPMAI_DOC_ID)
        .maybeSingle();
      assert.ifError(error);
      assert.ok(data, 'TAP CPMAI doc must exist');
      assert.equal(data.status, 'draft', 'TAP CPMAI must be in draft (status default-exclusion target)');
      assert.equal(data.doc_type, 'project_charter');
      assert.equal(data.visibility_class, 'active_members');
    });

    it('Open approval_chain exists for TAP CPMAI (assignment predicate prerequisite)', { skip: !sb }, async () => {
      const { data, error } = await sb
        .from('approval_chains')
        .select('id, closed_at')
        .eq('document_id', TAP_CPMAI_DOC_ID)
        .is('closed_at', null);
      assert.ifError(error);
      assert.ok(data && data.length > 0, 'OPEN approval_chain must exist on TAP CPMAI');
    });

    it('get_governance_document_reader is registered + service-role gate fires (existence + gate proof)', { skip: !sb }, async () => {
      const { error } = await sb.rpc('get_governance_document_reader', { p_document_id: UNKNOWN_DOC_ID });
      assert.ok(error, 'service-role call must fail authentication gate');
      assert.match(error.message || '', /Unauthorized|insufficient_privilege|42501|no active member/i,
        'expected gate-fire error, got: ' + (error.message || JSON.stringify(error)));
    });
  });
});
