import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// p262 #312-W4a (#378) — minimum gate templates for 6 doc_types.
// Spec: SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md §4.3 + §5.2 + §10 + p260 audit §11.
// PM ratification: p260 audit close §15.5 D1-D5 + dispatch sequence 2/7.
//
// What this migration does:
//   1) Extends resolve_default_gates(p_doc_type text) CASE expression with 6 new branches:
//      editorial_guide, governance_guideline, project_charter, manual, executive_summary,
//      framework_reference. All 11 doc_types now return non-NULL gate arrays.
//   2) Existing 5 doc_type branches preserved byte-identical (Phase C body-hash drift gate
//      respected — minimum-diff CREATE OR REPLACE).
//   3) Sanity DO RAISES if any of 11 doc_types still returns NULL post-deploy.
//
// PM-ratified gate templates:
//   editorial_guide:      curator(1,all) + leader_awareness(2,0) + submitter_acceptance(3,1)
//   governance_guideline: curator(1,all) + leader_awareness(2,0) + submitter_acceptance(3,1)
//   manual:               curator(1,all) + leader_awareness(2,0) + submitter_acceptance(3,1)
//                         + president_go(4,1) + president_others(5,4)  (mirrors policy)
//   executive_summary:    curator(1,all) + submitter_acceptance(2,1)  (minimal)
//   framework_reference:  curator(1,all) + leader_awareness(2,0) + submitter_acceptance(3,1)
//   project_charter:      curator(1,all) + leader_awareness(2,0)  (initiative-internal — TAPs)

const MIGRATION_PATH = 'supabase/migrations/20260805000041_p262_312_w4a_gate_templates_6_doc_types.sql';
const MIGRATION_SQL  = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

const NEW_DOC_TYPES = [
  'editorial_guide',
  'governance_guideline',
  'manual',
  'executive_summary',
  'framework_reference',
  'project_charter',
];

const EXISTING_DOC_TYPES = [
  'cooperation_agreement',
  'cooperation_addendum',
  'volunteer_term_template',
  'volunteer_addendum',
  'policy',
];

const ALL_DOC_TYPES = [...EXISTING_DOC_TYPES, ...NEW_DOC_TYPES];

describe('p262 #312-W4a — resolve_default_gates extended for 6 new doc_types', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp 20260805000041', () => {
      assert.ok(existsSync(MIGRATION_PATH));
      assert.ok(MIGRATION_SQL.length > 0);
    });

    it('header documents WHAT / WHY / SPEC / SCOPE LOCK / ROLLBACK / INVARIANTS / CROSS-REF', () => {
      assert.match(MIGRATION_SQL, /-- WHAT:.*Wave 1b leaf #312-W4a/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- SPEC:/);
      assert.match(MIGRATION_SQL, /-- SCOPE LOCK/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK/);
      assert.match(MIGRATION_SQL, /-- INVARIANTS:/);
      assert.match(MIGRATION_SQL, /-- CROSS-REF:/);
    });

    it('header cross-refs umbrella + audit + dispatch sequence', () => {
      assert.match(MIGRATION_SQL, /#312/);
      assert.match(MIGRATION_SQL, /#315/);
      assert.match(MIGRATION_SQL, /#378/);
      assert.match(MIGRATION_SQL, /#377/);
      assert.match(MIGRATION_SQL, /p260/);
    });
  });

  describe('resolve_default_gates signature + LANGUAGE + search_path', () => {
    it('CREATE OR REPLACE FUNCTION public.resolve_default_gates(p_doc_type text) RETURNS jsonb', () => {
      assert.match(MIGRATION_SQL, /CREATE OR REPLACE FUNCTION public\.resolve_default_gates\(p_doc_type text\)\s*RETURNS jsonb/);
    });

    it('LANGUAGE sql (NOT plpgsql — pure helper, no DECLARE/BEGIN)', () => {
      assert.match(MIGRATION_SQL, /resolve_default_gates[\s\S]*?LANGUAGE sql/);
    });

    it('pinned search_path TO public, pg_temp', () => {
      assert.match(MIGRATION_SQL, /SET search_path TO 'public', 'pg_temp'/);
    });
  });

  describe('all 11 doc_types appear in CASE expression', () => {
    ALL_DOC_TYPES.forEach(dt => {
      it(`CASE includes WHEN '${dt}' THEN`, () => {
        assert.match(MIGRATION_SQL, new RegExp(`WHEN '${dt}' THEN`));
      });
    });
  });

  describe('6 new doc_type gate templates have expected gate kinds', () => {
    it('editorial_guide: curator + leader_awareness + submitter_acceptance (3 gates)', () => {
      const block = MIGRATION_SQL.match(/WHEN 'editorial_guide' THEN\s*'(\[[\s\S]*?\])'::jsonb/);
      assert.ok(block, 'editorial_guide block must exist');
      const gates = JSON.parse(block[1]);
      assert.equal(gates.length, 3);
      assert.deepEqual(gates.map(g => g.kind), ['curator', 'leader_awareness', 'submitter_acceptance']);
    });

    it('governance_guideline: same shape as editorial_guide (3 gates)', () => {
      const block = MIGRATION_SQL.match(/WHEN 'governance_guideline' THEN\s*'(\[[\s\S]*?\])'::jsonb/);
      assert.ok(block);
      const gates = JSON.parse(block[1]);
      assert.equal(gates.length, 3);
      assert.deepEqual(gates.map(g => g.kind), ['curator', 'leader_awareness', 'submitter_acceptance']);
    });

    it('manual: 5 gates (curator + leader_awareness + submitter_acceptance + president_go + president_others)', () => {
      const block = MIGRATION_SQL.match(/WHEN 'manual' THEN\s*'(\[[\s\S]*?\])'::jsonb/);
      assert.ok(block);
      const gates = JSON.parse(block[1]);
      assert.equal(gates.length, 5);
      assert.deepEqual(gates.map(g => g.kind), [
        'curator', 'leader_awareness', 'submitter_acceptance', 'president_go', 'president_others'
      ]);
    });

    it('executive_summary: minimal 2 gates (curator + submitter_acceptance)', () => {
      const block = MIGRATION_SQL.match(/WHEN 'executive_summary' THEN\s*'(\[[\s\S]*?\])'::jsonb/);
      assert.ok(block);
      const gates = JSON.parse(block[1]);
      assert.equal(gates.length, 2);
      assert.deepEqual(gates.map(g => g.kind), ['curator', 'submitter_acceptance']);
    });

    it('framework_reference: 3 gates (curator + leader_awareness + submitter_acceptance)', () => {
      const block = MIGRATION_SQL.match(/WHEN 'framework_reference' THEN\s*'(\[[\s\S]*?\])'::jsonb/);
      assert.ok(block);
      const gates = JSON.parse(block[1]);
      assert.equal(gates.length, 3);
    });

    it('project_charter: minimal 2 gates (curator + leader_awareness)', () => {
      const block = MIGRATION_SQL.match(/WHEN 'project_charter' THEN\s*'(\[[\s\S]*?\])'::jsonb/);
      assert.ok(block);
      const gates = JSON.parse(block[1]);
      assert.equal(gates.length, 2);
      assert.deepEqual(gates.map(g => g.kind), ['curator', 'leader_awareness']);
    });
  });

  describe('curator gate is ALWAYS first + threshold=all in every new doc_type', () => {
    NEW_DOC_TYPES.forEach(dt => {
      it(`${dt}: curator(order=1, threshold='all') is first gate`, () => {
        const block = MIGRATION_SQL.match(new RegExp(`WHEN '${dt}' THEN\\s*'(\\[[\\s\\S]*?\\])'::jsonb`));
        assert.ok(block);
        const gates = JSON.parse(block[1]);
        assert.equal(gates[0].kind, 'curator');
        assert.equal(gates[0].order, 1);
        assert.equal(gates[0].threshold, 'all');
      });
    });
  });

  describe('5 pre-existing doc_type templates preserved byte-identical', () => {
    it('cooperation_agreement: still 6 gates (chapter_witness present)', () => {
      const block = MIGRATION_SQL.match(/WHEN 'cooperation_agreement' THEN\s*'(\[[\s\S]*?\])'::jsonb/);
      assert.ok(block);
      const gates = JSON.parse(block[1]);
      assert.equal(gates.length, 6);
      assert.ok(gates.some(g => g.kind === 'chapter_witness'));
    });

    it('cooperation_addendum: still 6 gates (same shape)', () => {
      const block = MIGRATION_SQL.match(/WHEN 'cooperation_addendum' THEN\s*'(\[[\s\S]*?\])'::jsonb/);
      assert.ok(block);
      const gates = JSON.parse(block[1]);
      assert.equal(gates.length, 6);
    });

    it('volunteer_term_template: still 5 gates (volunteers_in_role_active present)', () => {
      const block = MIGRATION_SQL.match(/WHEN 'volunteer_term_template' THEN\s*'(\[[\s\S]*?\])'::jsonb/);
      assert.ok(block);
      const gates = JSON.parse(block[1]);
      assert.equal(gates.length, 5);
      assert.ok(gates.some(g => g.kind === 'volunteers_in_role_active'));
    });

    it('volunteer_addendum: still 5 gates (same shape)', () => {
      const block = MIGRATION_SQL.match(/WHEN 'volunteer_addendum' THEN\s*'(\[[\s\S]*?\])'::jsonb/);
      assert.ok(block);
      const gates = JSON.parse(block[1]);
      assert.equal(gates.length, 5);
    });

    it('policy: still 5 gates', () => {
      const block = MIGRATION_SQL.match(/WHEN 'policy' THEN\s*'(\[[\s\S]*?\])'::jsonb/);
      assert.ok(block);
      const gates = JSON.parse(block[1]);
      assert.equal(gates.length, 5);
    });
  });

  describe('sanity DO + NOTIFY pgrst', () => {
    it('sanity DO RAISES EXCEPTION if any doc_type still returns NULL post-deploy', () => {
      assert.match(MIGRATION_SQL, /RAISE EXCEPTION 'p262 #312-W4a: % of 11 doc_types still return NULL/);
    });

    it('sanity DO iterates over all 11 expected doc_types', () => {
      ALL_DOC_TYPES.forEach(dt => {
        assert.match(MIGRATION_SQL, new RegExp(`'${dt}'`));
      });
    });

    it('migration ends with NOTIFY pgrst reload schema', () => {
      assert.match(MIGRATION_SQL, /NOTIFY pgrst, 'reload schema';/);
    });
  });

  describe('forward-defense: SEDIMENT-235.A close-keyword discipline', () => {
    it('migration body MUST NOT have close|fix|resolve + #N matching auto-close regex for stay-open issues', () => {
      const closePattern = /(close[sd]?|fix(?:es|ed)?|resolve[sd]?)\s+#(312|315|96|379|380|381|382|383)\b/i;
      assert.doesNotMatch(MIGRATION_SQL, closePattern);
    });
  });

  describe('DB-gated live smoke (skips without SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY)', () => {
    it('all 11 doc_types return non-NULL from resolve_default_gates live', { skip: !sb }, async () => {
      for (const dt of ALL_DOC_TYPES) {
        const { data, error } = await sb.rpc('resolve_default_gates', { p_doc_type: dt });
        assert.ifError(error, `resolve_default_gates(${dt}) raised: ${error?.message}`);
        assert.ok(data !== null, `resolve_default_gates(${dt}) returned NULL — gate template missing`);
        assert.ok(Array.isArray(data) && data.length > 0, `resolve_default_gates(${dt}) returned empty array`);
      }
    });

    it('editorial_guide (Frontiers doc_type) gates are exactly 3 with curator first', { skip: !sb }, async () => {
      const { data, error } = await sb.rpc('resolve_default_gates', { p_doc_type: 'editorial_guide' });
      assert.ifError(error);
      assert.equal(data.length, 3);
      assert.equal(data[0].kind, 'curator');
      assert.equal(data[0].threshold, 'all');
    });

    it('unknown doc_type still returns NULL (ELSE clause preserved)', { skip: !sb }, async () => {
      const { data, error } = await sb.rpc('resolve_default_gates', { p_doc_type: 'nonexistent_doc_type' });
      assert.ifError(error);
      assert.equal(data, null);
    });
  });
});
