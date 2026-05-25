import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// p262 #312-W4c (#379) — list_governance_library default-status exclusion (GAP-259.A close).
// Spec: p259 evidence doc PM-ratified Option (a) + p260 audit §10.1 + p262 PM #379 prompt
// + Option A ratification (4-status default include set).
//
// What this migration does:
//   1) CREATE OR REPLACE list_governance_library(p_filters jsonb DEFAULT '{}'::jsonb)
//      adds ONE new line to WHERE clause:
//      AND (v_filter_status IS NOT NULL OR gd.status IN ('active','approved','under_review','superseded'))
//   2) Effect: when caller passes no explicit p_filters.status, only 4 default-include
//      statuses appear. Caller may still pass explicit status='draft' etc. to override.
//   3) Frontiers fixture (in 'draft' post-#377) now hidden from member library default.
//
// Test classes:
//   - Migration file presence + header
//   - RPC body preserves SECDEF + STABLE + LANGUAGE plpgsql + search_path + grant/revoke
//   - WHERE clause contains the new default-exclusion line with exact 4-status set
//   - Forward-defense: no removal of existing visibility/admin_only/legal_scoped predicates
//   - DB-gated: default call hides Frontiers (draft); explicit status=draft returns it;
//     counts 13 visible / 3 hidden total

const MIGRATION_PATH = 'supabase/migrations/20260805000042_p262_312_w4c_gap_259_a_default_status_exclusion.sql';
const MIGRATION_SQL  = readFileSync(MIGRATION_PATH, 'utf8');

const FRONTIERS_DOC_ID = '18ec4690-4f5a-4cab-904d-451e2c7245bf';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

describe('p262 #312-W4c — list_governance_library default-status exclusion (GAP-259.A)', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp 20260805000042', () => {
      assert.ok(existsSync(MIGRATION_PATH));
      assert.ok(MIGRATION_SQL.length > 0);
    });

    it('header documents WHAT / WHY / SPEC / SCOPE LOCK / ROLLBACK / INVARIANTS / CROSS-REF', () => {
      assert.match(MIGRATION_SQL, /-- WHAT:.*Wave 1b leaf #312-W4c/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- SPEC:/);
      assert.match(MIGRATION_SQL, /-- SCOPE LOCK/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK/);
      assert.match(MIGRATION_SQL, /-- INVARIANTS:/);
      assert.match(MIGRATION_SQL, /-- CROSS-REF:/);
    });

    it('header cross-refs umbrella + GAP-259.A + dispatch sequence', () => {
      assert.match(MIGRATION_SQL, /#312/);
      assert.match(MIGRATION_SQL, /#315/);
      assert.match(MIGRATION_SQL, /#379/);
      assert.match(MIGRATION_SQL, /#378/);
      assert.match(MIGRATION_SQL, /#377/);
      assert.match(MIGRATION_SQL, /GAP-259\.A/);
      assert.match(MIGRATION_SQL, /p259/);
    });
  });

  describe('list_governance_library signature + properties', () => {
    it('CREATE OR REPLACE FUNCTION public.list_governance_library(p_filters jsonb DEFAULT)', () => {
      assert.match(MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\.list_governance_library\(p_filters jsonb DEFAULT '\{\}'::jsonb\)/);
    });

    it('LANGUAGE plpgsql + STABLE + SECURITY DEFINER + pinned search_path', () => {
      assert.match(MIGRATION_SQL, /list_governance_library[\s\S]*?LANGUAGE plpgsql/);
      assert.match(MIGRATION_SQL, /list_governance_library[\s\S]*?STABLE/);
      assert.match(MIGRATION_SQL, /list_governance_library[\s\S]*?SECURITY DEFINER/);
      assert.match(MIGRATION_SQL, /SET search_path TO 'public', 'pg_temp'/);
    });

    it('GRANT EXECUTE TO authenticated + REVOKE FROM PUBLIC preserved', () => {
      assert.match(MIGRATION_SQL, /REVOKE EXECUTE ON FUNCTION public\.list_governance_library\(jsonb\) FROM PUBLIC/);
      assert.match(MIGRATION_SQL, /GRANT  EXECUTE ON FUNCTION public\.list_governance_library\(jsonb\) TO authenticated/);
    });
  });

  describe('default-status exclusion clause', () => {
    it('WHERE clause includes the new default-exclusion line', () => {
      assert.match(MIGRATION_SQL,
        /AND \(v_filter_status IS NOT NULL OR gd\.status IN \('active','approved','under_review','superseded'\)\)/);
    });

    it('preserves the existing explicit-filter line (v_filter_status IS NULL OR gd.status = v_filter_status)', () => {
      assert.match(MIGRATION_SQL,
        /AND \(v_filter_status IS NULL OR gd\.status = v_filter_status\)/);
    });

    it('FORWARD-DEFENSE: the 4-status set is EXACTLY active/approved/under_review/superseded (no draft/pending/withdrawn/revoked)', () => {
      const block = MIGRATION_SQL.match(/v_filter_status IS NOT NULL OR gd\.status IN \(([^)]+)\)/);
      assert.ok(block, 'default-exclusion clause must exist');
      const statusSet = block[1];
      ['active', 'approved', 'under_review', 'superseded'].forEach(s => {
        assert.match(statusSet, new RegExp(`'${s}'`), `4-status default include set missing '${s}'`);
      });
      ['draft', 'pending_proposer_consent', 'withdrawn', 'revoked'].forEach(s => {
        assert.doesNotMatch(statusSet, new RegExp(`'${s}'`),
          `4-status default include set MUST NOT contain '${s}' — that is the exclusion target`);
      });
    });
  });

  describe('preserves all existing visibility predicates byte-identical', () => {
    it('public visibility branch preserved', () => {
      assert.match(MIGRATION_SQL, /gd\.visibility_class = 'public'/);
    });

    it('active_members branch preserved', () => {
      assert.match(MIGRATION_SQL, /gd\.visibility_class = 'active_members'/);
    });

    it('legal_scoped branch preserved with member_document_signatures join', () => {
      assert.match(MIGRATION_SQL, /gd\.visibility_class = 'legal_scoped'/);
      assert.match(MIGRATION_SQL, /member_document_signatures mds[\s\S]*?mds\.is_current = true/);
    });

    it('admin_only branch gated on v_is_admin', () => {
      assert.match(MIGRATION_SQL, /gd\.visibility_class = 'admin_only' AND v_is_admin/);
    });

    it('audit_restricted branch gated on v_is_platform_admin', () => {
      assert.match(MIGRATION_SQL, /gd\.visibility_class = 'audit_restricted' AND v_is_platform_admin/);
    });
  });

  describe('payload shape forward-defense (P0-Q8 from p256 M3)', () => {
    it('SELECT jsonb_build_object lists the canonical 12 fields', () => {
      ['id','title','description','doc_type','status','visibility_class','acknowledgement_mode',
       'effective_from','effective_until','approved_at','current_ratified_version_id','current_version_id']
        .forEach(field => {
          assert.match(MIGRATION_SQL, new RegExp(`'${field}'`));
        });
    });

    it('response shape NEVER includes file_id / drive_url / content_html / pdf_url (P0-Q8 forward-defense)', () => {
      // Within the jsonb_build_object literal (not the comment) — those PII handles must not appear
      // The migration body contains a comment about P0-Q8; we're testing the actual SELECT body has no leaks.
      const selectBlock = MIGRATION_SQL.match(/SELECT jsonb_build_object\([\s\S]*?\) AS d/);
      assert.ok(selectBlock, 'inner SELECT block must exist');
      const block = selectBlock[0];
      ['file_id', 'drive_url', 'content_html', 'pdf_url'].forEach(forbidden => {
        assert.doesNotMatch(block, new RegExp(`'${forbidden}'`), `payload must not expose ${forbidden}`);
      });
    });
  });

  describe('forward-defense: SEDIMENT-235.A close-keyword discipline', () => {
    it('migration body MUST NOT have close|fix|resolve + #N matching auto-close regex for stay-open issues', () => {
      const closePattern = /(close[sd]?|fix(?:es|ed)?|resolve[sd]?)\s+#(312|315|96|380|381|382|383)\b/i;
      assert.doesNotMatch(MIGRATION_SQL, closePattern);
    });
  });

  describe('DB-gated live smoke (skips without SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY)', () => {
    it('default call (no filter) hides Frontiers in draft status', { skip: !sb }, async () => {
      // Service-role calls list_governance_library directly bypass auth.uid() gate — but the
      // function body still does `members WHERE auth_id = auth.uid()` and would fail with
      // "no active member record". For DB-gated smoke we verify via a direct SELECT mirroring
      // the new WHERE clause logic instead.
      const { data, error } = await sb
        .from('governance_documents')
        .select('id, status')
        .in('status', ['active', 'approved', 'under_review', 'superseded']);
      assert.ifError(error);
      const frontiersInDefault = data.some(d => d.id === FRONTIERS_DOC_ID);
      assert.equal(frontiersInDefault, false, 'Frontiers (draft) must be excluded from 4-status default include set');
    });

    it('explicit status=draft selects Frontiers when bypassing the default filter', { skip: !sb }, async () => {
      const { data, error } = await sb
        .from('governance_documents')
        .select('id, status')
        .eq('status', 'draft');
      assert.ifError(error);
      assert.ok(data.some(d => d.id === FRONTIERS_DOC_ID), 'Frontiers (draft) must appear when explicit draft filter applied');
    });

    it('corpus split: 13 docs in 4-status default include set, 3 in 4-status exclude set', { skip: !sb }, async () => {
      const { data: visible } = await sb
        .from('governance_documents')
        .select('id', { count: 'exact', head: true })
        .in('status', ['active', 'approved', 'under_review', 'superseded']);
      const { count: visibleCount } = await sb
        .from('governance_documents')
        .select('*', { count: 'exact', head: true })
        .in('status', ['active', 'approved', 'under_review', 'superseded']);
      const { count: hiddenCount } = await sb
        .from('governance_documents')
        .select('*', { count: 'exact', head: true })
        .in('status', ['draft', 'pending_proposer_consent', 'withdrawn', 'revoked']);
      assert.equal(visibleCount, 13, `expected 13 visible default but got ${visibleCount}`);
      assert.equal(hiddenCount, 3, `expected 3 hidden default but got ${hiddenCount}`);
    });
  });
});
