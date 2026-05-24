import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIGRATION_PATH = 'supabase/migrations/20260805000029_p250_354_spec_348_v1_foundation_booking_url_per_evaluator.sql';
const SPEC_PATH = 'docs/specs/SPEC_348_BOOKING_URL_PER_EVALUATOR.md';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');
// Active SQL (line-comments stripped) — used by forward-defense regexes so the
// migration header's RLS NOTE can document the dropped-typo path without
// tripping the "must NOT reference view_selection" assertion below.
const MIGRATION_SQL_ACTIVE = MIGRATION_SQL.split('\n')
  .filter((l) => !l.trimStart().startsWith('--'))
  .join('\n');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;

const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

describe('p250 #354 — SPEC #348 Child #1 Foundation (booking URL per evaluator, DDL only)', () => {
  describe('migration file presence', () => {
    it('migration file exists at canonical timestamp', () => {
      assert.ok(existsSync(MIGRATION_PATH), `migration file expected at ${MIGRATION_PATH}`);
      assert.ok(MIGRATION_SQL.length > 0, 'migration file must not be empty');
    });

    it('migration header documents WHAT / WHY / ROLLBACK + parent + this issue', () => {
      assert.match(MIGRATION_SQL, /-- WHAT:/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK:/);
      assert.match(MIGRATION_SQL, /#348/, 'parent issue #348 must be referenced');
      assert.match(MIGRATION_SQL, /#354/, 'this issue #354 must be referenced');
    });

    it('spec doc exists at canonical path (cross-ref anchor)', () => {
      assert.ok(existsSync(SPEC_PATH), `spec doc expected at ${SPEC_PATH}`);
    });
  });

  describe('ALTER members + ALTER selection_committee', () => {
    it('ALTER members ADD COLUMN interview_booking_url text', () => {
      assert.match(
        MIGRATION_SQL,
        /ALTER TABLE public\.members\s+ADD COLUMN interview_booking_url text;/,
        'members.interview_booking_url column add must be present'
      );
    });

    it('ALTER selection_committee ADD COLUMN interview_booking_url text', () => {
      assert.match(
        MIGRATION_SQL,
        /ALTER TABLE public\.selection_committee\s+ADD COLUMN interview_booking_url text;/,
        'selection_committee.interview_booking_url column add must be present'
      );
    });

    it('both ALTER targets carry COMMENT ON COLUMN', () => {
      assert.match(
        MIGRATION_SQL,
        /COMMENT ON COLUMN public\.members\.interview_booking_url IS/,
        'members.interview_booking_url comment must be present (documents usage)'
      );
      assert.match(
        MIGRATION_SQL,
        /COMMENT ON COLUMN public\.selection_committee\.interview_booking_url IS/,
        'selection_committee.interview_booking_url comment must be present (documents override semantics)'
      );
    });
  });

  describe('CREATE TABLE selection_dispatch_url_log', () => {
    it('table created with IF NOT EXISTS guard', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE TABLE IF NOT EXISTS public\.selection_dispatch_url_log\s*\(/,
        'CREATE TABLE IF NOT EXISTS is required (re-run safety)'
      );
    });

    it('all 9 columns declared (id, application_id, cycle_id, track, resolved_url, resolution_path, resolved_evaluator_id, dispatched_at, organization_id)', () => {
      const createBlock = MIGRATION_SQL.match(/CREATE TABLE IF NOT EXISTS public\.selection_dispatch_url_log\s*\(([\s\S]*?)\);/);
      assert.ok(createBlock, 'CREATE TABLE block must be captured');
      const body = createBlock[1];
      assert.match(body, /\bid uuid PRIMARY KEY DEFAULT gen_random_uuid\(\)/);
      assert.match(body, /application_id uuid NOT NULL REFERENCES public\.selection_applications\(id\)/);
      assert.match(body, /cycle_id uuid NOT NULL REFERENCES public\.selection_cycles\(id\)/);
      assert.match(body, /track text NOT NULL CHECK \(track IN \('researcher', 'leader'\)\)/);
      assert.match(body, /resolved_url text NOT NULL/);
      assert.match(body, /resolution_path text NOT NULL CHECK \(resolution_path IN \(/);
      assert.match(body, /resolved_evaluator_id uuid REFERENCES public\.members\(id\)/);
      assert.match(body, /dispatched_at timestamptz NOT NULL DEFAULT now\(\)/);
      assert.match(body, /organization_id uuid NOT NULL REFERENCES public\.organizations\(id\)/);
    });

    it('CHECK track enum must be exactly {researcher, leader}', () => {
      assert.match(
        MIGRATION_SQL,
        /CHECK \(track IN \('researcher', 'leader'\)\)/,
        'track enum must be exactly the v1 dichotomy'
      );
    });

    it('CHECK resolution_path enum must be exactly {committee_override, member_global, cycle_fallback}', () => {
      assert.match(
        MIGRATION_SQL,
        /CHECK \(resolution_path IN \(\s*'committee_override', 'member_global', 'cycle_fallback'\s*\)\)/,
        'resolution_path enum must match SPEC §5.1 precedence labels'
      );
    });

    it('resolved_evaluator_id FK must be nullable (no NOT NULL) — cycle_fallback / leader rows leave it NULL', () => {
      const createBlock = MIGRATION_SQL.match(/CREATE TABLE IF NOT EXISTS public\.selection_dispatch_url_log\s*\(([\s\S]*?)\);/);
      assert.ok(createBlock, 'CREATE TABLE block must be captured');
      // assert the resolved_evaluator_id line does NOT have NOT NULL
      const rowLine = createBlock[1].split('\n').find(l => l.includes('resolved_evaluator_id'));
      assert.ok(rowLine, 'resolved_evaluator_id column line must be present');
      assert.doesNotMatch(
        rowLine,
        /NOT NULL/,
        'resolved_evaluator_id must be nullable (cycle_fallback/leader cases require NULL)'
      );
    });

    it('table COMMENT documents the dispatch audit role', () => {
      assert.match(
        MIGRATION_SQL,
        /COMMENT ON TABLE public\.selection_dispatch_url_log IS/,
        'selection_dispatch_url_log must have a documenting comment'
      );
    });
  });

  describe('indexes', () => {
    it('app_idx exists on (application_id)', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE INDEX selection_dispatch_url_log_app_idx\s+ON public\.selection_dispatch_url_log \(application_id\);/,
        'app_idx for application_id lookups must be present'
      );
    });

    it('cycle_round_robin_idx is a partial index on researcher track for LRD picker', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE INDEX selection_dispatch_url_log_cycle_round_robin_idx\s+ON public\.selection_dispatch_url_log \(cycle_id, track, resolved_evaluator_id, dispatched_at DESC\)\s+WHERE track = 'researcher';/,
        'round-robin partial index must use the exact (cycle_id, track, resolved_evaluator_id, dispatched_at DESC) tuple with WHERE track=researcher'
      );
    });
  });

  describe('RLS (V4 canonical pair — matches every other selection_* table)', () => {
    it('ENABLE ROW LEVEL SECURITY issued', () => {
      assert.match(
        MIGRATION_SQL,
        /ALTER TABLE public\.selection_dispatch_url_log ENABLE ROW LEVEL SECURITY;/
      );
    });

    it('rpc_only_deny_all policy (FOR ALL USING false)', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE POLICY rpc_only_deny_all\s+ON public\.selection_dispatch_url_log\s+FOR ALL\s+USING \(false\);/,
        'deny-all baseline policy must use FOR ALL USING (false)'
      );
    });

    it('v4_org_scope policy uses (organization_id = auth_org()) OR (organization_id IS NULL)', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE POLICY selection_dispatch_url_log_v4_org_scope\s+ON public\.selection_dispatch_url_log\s+FOR ALL\s+USING \(\(organization_id = auth_org\(\)\) OR \(organization_id IS NULL\)\);/,
        'org-scope policy must match the V4 convention (auth_org() OR IS NULL)'
      );
    });
  });

  describe('sanity DO + NOTIFY trailer', () => {
    it('sanity DO block raises if any artifact is missing', () => {
      assert.match(MIGRATION_SQL, /RAISE EXCEPTION 'p250 #354: members\.interview_booking_url not created'/);
      assert.match(MIGRATION_SQL, /RAISE EXCEPTION 'p250 #354: selection_committee\.interview_booking_url not created'/);
      assert.match(MIGRATION_SQL, /RAISE EXCEPTION 'p250 #354: selection_dispatch_url_log not created'/);
      assert.match(MIGRATION_SQL, /RAISE EXCEPTION 'p250 #354: required indexes missing/);
      assert.match(MIGRATION_SQL, /RAISE EXCEPTION 'p250 #354: RLS V4 pair missing/);
    });

    it('NOTIFY pgrst trailer present (PostgREST schema cache reload)', () => {
      assert.match(
        MIGRATION_SQL,
        /NOTIFY pgrst, 'reload schema';/,
        'NOTIFY pgrst is required for PostgREST to pick up the new columns / table'
      );
    });
  });

  describe('forward-defense: scope discipline', () => {
    it('active SQL must NOT modify any RPC body (RPC extension is Child #2 / #355 scope)', () => {
      assert.doesNotMatch(
        MIGRATION_SQL_ACTIVE,
        /CREATE OR REPLACE FUNCTION/,
        'Child #1 Foundation is DDL only — RPC bodies live in Child #2'
      );
      assert.doesNotMatch(
        MIGRATION_SQL_ACTIVE,
        /\bCREATE FUNCTION\b/,
        'Child #1 Foundation must not introduce any new RPC — that belongs to Child #2'
      );
    });

    it('active SQL must NOT reference the dropped-typo action "view_selection"', () => {
      // RLS DRAFT in spec used rls_can('view_selection') but that action does not exist
      // in engagement_kind_permissions. V4 canonical pair (deny_all + org_scope) is the
      // canonical shipped pattern. Lock the regression class so a future re-introduction
      // is caught at CI. We strip line-comments so the header's RLS NOTE can document
      // the rejected path without tripping this assertion.
      assert.doesNotMatch(
        MIGRATION_SQL_ACTIVE,
        /rls_can\(\s*'view_selection'\s*\)/,
        "rls_can('view_selection') is a non-existent action — V4 deny_all + org_scope is the canonical pattern (see migration header RLS NOTE)"
      );
    });

    it('members.interview_booking_url column must NOT have a DB-level CHECK / regex (per SPEC Q2 — validation is app-level)', () => {
      // Q2 ratified app-level ^https?:// regex (admin form). DB CHECK would trap future
      // deep-link providers. Make sure no one accidentally adds one in this migration.
      const membersAlterBlock = MIGRATION_SQL.match(/ALTER TABLE public\.members[\s\S]*?ADD COLUMN interview_booking_url text[^;]*;/);
      assert.ok(membersAlterBlock, 'members ALTER block must be captured');
      assert.doesNotMatch(
        membersAlterBlock[0],
        /CHECK\b/,
        'members.interview_booking_url must not carry a DB CHECK (Q2: validation app-level)'
      );
      const committeeAlterBlock = MIGRATION_SQL.match(/ALTER TABLE public\.selection_committee[\s\S]*?ADD COLUMN interview_booking_url text[^;]*;/);
      assert.ok(committeeAlterBlock, 'selection_committee ALTER block must be captured');
      assert.doesNotMatch(
        committeeAlterBlock[0],
        /CHECK\b/,
        'selection_committee.interview_booking_url must not carry a DB CHECK either'
      );
    });

    it('migration must NOT touch the cycle_id / selection_cycles.interview_booking_url column (left intact for fallback)', () => {
      // p243 populated selection_cycles.interview_booking_url. v1 is additive; the
      // cycle-level URL stays as fallback. Ensure no DROP / ALTER on that column.
      assert.doesNotMatch(
        MIGRATION_SQL,
        /ALTER TABLE\s+(?:public\.)?selection_cycles\s+DROP COLUMN\s+interview_booking_url/i,
        'cycle-level URL must remain intact (researcher fallback + leader default)'
      );
      assert.doesNotMatch(
        MIGRATION_SQL,
        /ALTER TABLE\s+(?:public\.)?selection_cycles\s+ALTER COLUMN\s+interview_booking_url/i,
        'cycle-level URL definition must remain intact'
      );
    });
  });

  describe('DB-gated runtime presence checks', () => {
    it('members.interview_booking_url column readable via PostgREST surface', { skip: !sb }, async () => {
      // PostgREST exposes the column if it exists. limit(0) returns [] cheap.
      const { error } = await sb.from('members').select('interview_booking_url').limit(0);
      assert.equal(error, null, `members.interview_booking_url must be readable: ${error?.message ?? 'ok'}`);
    });

    it('selection_committee.interview_booking_url column readable via PostgREST surface', { skip: !sb }, async () => {
      const { error } = await sb.from('selection_committee').select('interview_booking_url').limit(0);
      assert.equal(error, null, `selection_committee.interview_booking_url must be readable: ${error?.message ?? 'ok'}`);
    });

    it('selection_dispatch_url_log table readable via PostgREST surface with all 9 columns', { skip: !sb }, async () => {
      const { error } = await sb
        .from('selection_dispatch_url_log')
        .select('id, application_id, cycle_id, track, resolved_url, resolution_path, resolved_evaluator_id, dispatched_at, organization_id')
        .limit(0);
      assert.equal(error, null, `selection_dispatch_url_log surface must expose all 9 declared columns: ${error?.message ?? 'ok'}`);
    });

    it('migration row registered in supabase_migrations.schema_migrations (Track Q-C orphan gate)', { skip: !sb }, async () => {
      const { data, error } = await sb.rpc('_audit_list_schema_migrations');
      if (error) {
        // helper RPC may not be exposed in this environment; skip gracefully
        console.warn(`[p250 #354] _audit_list_schema_migrations unavailable: ${error.message}`);
        return;
      }
      const rows = Array.isArray(data) ? data : [];
      const hasRow = rows.some((r) => (r.version || r.v || r.migration_version) === '20260805000029');
      assert.ok(hasRow, 'migration version 20260805000029 must be registered in supabase_migrations.schema_migrations');
    });
  });
});
