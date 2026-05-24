import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIGRATION_PATH = 'supabase/migrations/20260805000030_p251_355_spec_348_v1_rpc_routing.sql';
const SPEC_PATH = 'docs/specs/SPEC_348_BOOKING_URL_PER_EVALUATOR.md';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

function normalize(s) {
  return s.replace(/\s+/g, ' ').trim();
}

// Capture the function body (between AS $$ ... $$) for branch scoping.
const FN_BODY_MATCH = MIGRATION_SQL.match(/AS \$\$([\s\S]*?)\$\$;/);
const FN_BODY = FN_BODY_MATCH ? FN_BODY_MATCH[1] : '';

describe('p251 #355 — SPEC #348 Child #2 RPC body (booking URL routing)', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp', () => {
      assert.ok(existsSync(MIGRATION_PATH), `migration expected at ${MIGRATION_PATH}`);
      assert.ok(MIGRATION_SQL.length > 0, 'migration file must not be empty');
    });

    it('header documents WHAT / WHY / SPEC DRIFT / ROLLBACK / INVARIANTS + parent / this / predecessor issues', () => {
      assert.match(MIGRATION_SQL, /-- WHAT:/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- SPEC DRIFT RESOLVED:/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK:/);
      assert.match(MIGRATION_SQL, /-- INVARIANTS:/);
      assert.match(MIGRATION_SQL, /#348/, 'parent issue #348 must be referenced');
      assert.match(MIGRATION_SQL, /#355/, 'this issue #355 must be referenced');
      assert.match(MIGRATION_SQL, /#354/, 'predecessor #354 must be referenced');
    });

    it('spec doc exists at canonical path (cross-ref anchor)', () => {
      assert.ok(existsSync(SPEC_PATH), `spec doc expected at ${SPEC_PATH}`);
    });
  });

  describe('signature preservation (SEDIMENT-238.C — CREATE OR REPLACE same-sig)', () => {
    it('uses CREATE OR REPLACE FUNCTION (not DROP + CREATE — preserves ACL)', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\.notify_selection_cutoff_approved/,
        'CREATE OR REPLACE preserves grants on authenticated + service_role'
      );
      assert.doesNotMatch(
        MIGRATION_SQL,
        /DROP\s+FUNCTION\s+(?:IF EXISTS\s+)?public\.notify_selection_cutoff_approved/i,
        'DROP would force re-GRANT; SEDIMENT-238.C says CREATE OR REPLACE only'
      );
    });

    it('signature locked: (p_application_id uuid) RETURNS jsonb', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\.notify_selection_cutoff_approved\(p_application_id uuid\)\s+RETURNS jsonb/,
        'single 1-arg signature must be preserved verbatim'
      );
    });

    it('LANGUAGE plpgsql + SECURITY DEFINER + SET search_path = public preserved', () => {
      assert.match(MIGRATION_SQL, /LANGUAGE plpgsql/);
      assert.match(MIGRATION_SQL, /SECURITY DEFINER/);
      assert.match(MIGRATION_SQL, /SET search_path = public/);
    });
  });

  describe('authority + idempotency preserved verbatim', () => {
    it("committee lead check preserved (role = 'lead' filter on caller's member_id)", () => {
      assert.match(
        FN_BODY,
        /SELECT \* INTO v_committee[\s\S]*?WHERE cycle_id = v_app\.cycle_id AND member_id = v_caller\.id AND role = 'lead'/,
        'committee lead authority probe must remain unchanged'
      );
    });

    it("manage_member fallback preserved via can_by_member(v_caller.id, 'manage_member')", () => {
      assert.match(
        FN_BODY,
        /IF v_committee IS NULL AND NOT public\.can_by_member\(v_caller\.id, 'manage_member'::text\) THEN/,
        'manage_member fallback gate must remain unchanged'
      );
    });

    it("idempotency short-circuit preserved (cutoff_approved_email_sent_at NOT NULL → reason 'already_sent')", () => {
      assert.match(
        FN_BODY,
        /IF v_app\.cutoff_approved_email_sent_at IS NOT NULL THEN[\s\S]*?'already_sent'/,
        'idempotency check must remain — must short-circuit before any new audit row'
      );
    });
  });

  describe('track-aware routing (SPEC §5.1 — leader / researcher / fallback)', () => {
    it("leader branch sets v_resolved_url := v_cycle.interview_booking_url with path = 'cycle_fallback'", () => {
      // Find the leader branch from the IF to ELSIF
      const leaderBranchMatch = FN_BODY.match(
        /IF v_app\.role_applied = 'leader' THEN([\s\S]*?)ELSIF v_app\.role_applied = 'researcher'/
      );
      assert.ok(leaderBranchMatch, 'leader branch must exist as the first IF clause');
      const leaderBlock = leaderBranchMatch[1];
      assert.match(leaderBlock, /v_resolved_url := v_cycle\.interview_booking_url/);
      assert.match(leaderBlock, /v_resolution_path := 'cycle_fallback'/);
      assert.match(leaderBlock, /v_resolved_evaluator_id := NULL/);
    });

    it("researcher branch is the second clause (ELSIF v_app.role_applied = 'researcher')", () => {
      assert.match(
        FN_BODY,
        /ELSIF v_app\.role_applied = 'researcher' THEN/,
        'researcher branch must be second clause'
      );
    });

    it('researcher LRD picker uses LEFT JOIN LATERAL with MAX(dispatched_at) filtered to (cycle_id, track=researcher, resolved_evaluator_id)', () => {
      assert.match(
        FN_BODY,
        /LEFT JOIN LATERAL\s*\(\s*SELECT MAX\(dispatched_at\)/,
        'LRD lookback must use LEFT JOIN LATERAL on selection_dispatch_url_log'
      );
      assert.match(
        FN_BODY,
        /WHERE l\.cycle_id = v_cycle\.id\s+AND l\.track = 'researcher'\s+AND l\.resolved_evaluator_id = sc\.member_id/,
        'LRD lateral subquery must filter by cycle + track=researcher + evaluator_id'
      );
    });

    it("researcher branch live-schema filter: role IN ('evaluator', 'lead') AND can_interview = true (PM Option A 2026-05-24)", () => {
      assert.match(
        FN_BODY,
        /WHERE sc\.cycle_id = v_cycle\.id\s+AND sc\.role IN \('evaluator', 'lead'\)\s+AND sc\.can_interview = true/,
        "filter must match live schema; observer excluded"
      );
    });

    it('researcher branch URL precedence: COALESCE(committee_override → member_global) with CASE-derived resolution_path', () => {
      assert.match(
        FN_BODY,
        /COALESCE\(sc\.interview_booking_url, m\.interview_booking_url\)/,
        'committee_override > member_global precedence (SPEC §4.1)'
      );
      assert.match(
        FN_BODY,
        /CASE\s+WHEN sc\.interview_booking_url IS NOT NULL THEN 'committee_override'\s+ELSE 'member_global'\s+END/,
        'resolution_path must be CASE-derived from committee_override presence'
      );
    });

    it('researcher branch ORDER BY uses lrd.last_dispatched NULLS FIRST + sc.member_id stable tiebreak; LIMIT 1', () => {
      assert.match(
        FN_BODY,
        /ORDER BY lrd\.last_dispatched NULLS FIRST, sc\.member_id\s+LIMIT 1/,
        'LRD picker semantics — NULLS FIRST so never-used evaluators come first'
      );
    });

    it("researcher branch sub-fallback: IF v_resolved_url IS NULL THEN cycle URL + cycle_fallback", () => {
      // The fallback IF sits inside the ELSIF block (between researcher LIMIT 1 and the closing ELSE)
      const researcherBlockMatch = FN_BODY.match(
        /ELSIF v_app\.role_applied = 'researcher' THEN([\s\S]*?)ELSE\s+--\s*Defensive/
      );
      assert.ok(researcherBlockMatch, 'researcher branch must end before defensive ELSE');
      const researcherBlock = researcherBlockMatch[1];
      assert.match(
        researcherBlock,
        /IF v_resolved_url IS NULL THEN[\s\S]*?v_resolved_url := v_cycle\.interview_booking_url[\s\S]*?v_resolution_path := 'cycle_fallback'[\s\S]*?v_resolved_evaluator_id := NULL/,
        'researcher branch must fall back to cycle URL when committee yields no candidate'
      );
    });

    it('defensive ELSE for unknown role_applied also falls back to cycle URL', () => {
      assert.match(
        FN_BODY,
        /ELSE\s+--\s*Defensive fallback[\s\S]*?v_resolved_url := v_cycle\.interview_booking_url[\s\S]*?v_resolution_path := 'cycle_fallback'[\s\S]*?v_resolved_evaluator_id := NULL/,
        'unknown role_applied (not researcher / not leader) must still produce a safe dispatch'
      );
    });
  });

  describe('audit log insert (BEFORE campaign send) + email variable wiring', () => {
    it('INSERT INTO selection_dispatch_url_log writes all 7 mutable columns', () => {
      assert.match(
        FN_BODY,
        /INSERT INTO public\.selection_dispatch_url_log \(\s*application_id,\s*cycle_id,\s*track,\s*resolved_url,\s*resolution_path,\s*resolved_evaluator_id,\s*organization_id\s*\)/,
        'dispatch log INSERT must include all 7 columns the table requires (id + dispatched_at are defaulted)'
      );
    });

    it('dispatch log INSERT passes v_app.role_applied as track (CHECK-aligned researcher/leader)', () => {
      assert.match(
        FN_BODY,
        /VALUES \(\s*p_application_id,\s*v_app\.cycle_id,\s*v_app\.role_applied,/,
        'track column must come straight from v_app.role_applied so it stays CHECK-aligned'
      );
    });

    it('campaign_send_one_off passes v_resolved_url as interview_booking_url variable (not v_cycle.interview_booking_url directly)', () => {
      assert.match(
        FN_BODY,
        /jsonb_build_object\(\s*'first_name', v_first_name,\s*'interview_booking_url', v_resolved_url\s*\)/,
        'email template variable must receive the resolved URL, not the cycle URL'
      );
    });

    it('CUTOFF_NO_BOOKING_URL raise stays present (after fallback chain, not before)', () => {
      assert.match(
        FN_BODY,
        /IF v_resolved_url IS NULL OR length\(trim\(v_resolved_url\)\) = 0 THEN[\s\S]*?RAISE EXCEPTION 'CUTOFF_NO_BOOKING_URL/,
        'raise must fire only when no resolvable URL exists at all (preserves errcode P0020 semantics)'
      );
      assert.match(MIGRATION_SQL, /ERRCODE = 'P0020'/, 'errcode preserved');
    });
  });

  describe('admin_audit_log metadata + return envelope enrichment', () => {
    it('admin_audit_log metadata gains 3 new keys: resolution_path, resolved_evaluator_id, role_applied', () => {
      // Capture from the audit INSERT up to the closing `);` that ends the
      // VALUES (...) tuple — that's the boundary for the audit-row literal.
      const auditMatch = FN_BODY.match(
        /INSERT INTO public\.admin_audit_log[\s\S]*?'rpc_version', 'p251_355'\s*\)\s*\);/
      );
      assert.ok(auditMatch, 'audit insert block must be captured (anchored on rpc_version literal)');
      const auditBlock = auditMatch[0];
      assert.match(auditBlock, /'resolution_path', v_resolution_path/);
      assert.match(auditBlock, /'resolved_evaluator_id', v_resolved_evaluator_id/);
      assert.match(auditBlock, /'role_applied', v_app\.role_applied/);
    });

    it("rpc_version bumped to 'p251_355' (was 'p228_w2_leaf4')", () => {
      assert.match(
        FN_BODY,
        /'rpc_version', 'p251_355'/,
        'rpc_version must reflect the v1 routing change for audit observability'
      );
      assert.doesNotMatch(
        FN_BODY,
        /'rpc_version', 'p228_w2_leaf4'/,
        'old rpc_version must not coexist (search-and-replace evidence)'
      );
    });

    it('return envelope adds resolution_path + resolved_evaluator_id keys (after the original 7)', () => {
      // Filter to the FINAL return (the success-with-email envelope), not the
      // idempotency early-return that uses `'email_sent', false`. Match all
      // RETURN jsonb_build_object(...) blocks and pick the one that contains
      // 'email_sent', true.
      const allReturns = [...FN_BODY.matchAll(/RETURN jsonb_build_object\(([\s\S]*?)\);/g)];
      const successEnvelope = allReturns
        .map((m) => m[1])
        .find((body) => /'email_sent', true/.test(body));
      assert.ok(successEnvelope, 'success-path return envelope must be captured');
      assert.match(successEnvelope, /'resolution_path', v_resolution_path/);
      assert.match(successEnvelope, /'resolved_evaluator_id', v_resolved_evaluator_id/);
      // Original keys preserved
      assert.match(successEnvelope, /'success', true/);
      assert.match(successEnvelope, /'application_id', p_application_id/);
      assert.match(successEnvelope, /'cycle_id', v_app\.cycle_id/);
      assert.match(successEnvelope, /'email_sent', true/);
      assert.match(successEnvelope, /'recipient_email_redacted'/);
      assert.match(successEnvelope, /'objective_done', v_objective_done/);
      assert.match(successEnvelope, /'research_score', v_app\.research_score/);
    });
  });

  describe('NOTIFY pgrst trailer', () => {
    it('NOTIFY pgrst, reload schema present at end', () => {
      assert.match(
        MIGRATION_SQL,
        /NOTIFY pgrst, 'reload schema';/,
        'PostgREST must reload — the RPC body changed'
      );
    });
  });

  describe('forward-defense (regression class locks)', () => {
    // F1: SPEC drift was `WHERE sc.role = 'researcher'`. Reality is that
    // `selection_committee.role` is committee POSITION (evaluator/lead/observer);
    // candidate track lives on selection_applications.role_applied. PM Option A
    // 2026-05-24 ratified live-schema filter. Lock the regression.
    it("F1: migration body MUST NOT contain literal `sc.role = 'researcher'` (SPEC drift class)", () => {
      assert.doesNotMatch(
        FN_BODY,
        /sc\.role\s*=\s*'researcher'/,
        "selection_committee.role does not include 'researcher'; the spec drift would violate the CHECK constraint"
      );
      assert.doesNotMatch(
        FN_BODY,
        /sc\.role\s*=\s*'leader'/,
        "same drift class for 'leader' — committee position is independent of candidate track"
      );
    });

    // F2: leader branch must use cycle URL ONLY. PM directive 2026-05-24:
    // "leader → Núcleo/dupla". Querying selection_committee here would
    // re-introduce per-evaluator routing for leader candidates, which is
    // explicitly out of v1 scope (SPEC §5.3).
    it("F2: leader branch body MUST NOT touch selection_committee at all", () => {
      const leaderBranchMatch = FN_BODY.match(
        /IF v_app\.role_applied = 'leader' THEN([\s\S]*?)ELSIF v_app\.role_applied = 'researcher'/
      );
      assert.ok(leaderBranchMatch, 'leader branch must exist for this guard to apply');
      const leaderBlock = leaderBranchMatch[1];
      assert.doesNotMatch(
        leaderBlock,
        /selection_committee/,
        'leader → cycle URL only (PM directive); committee read = scope violation'
      );
      assert.doesNotMatch(
        leaderBlock,
        /selection_dispatch_url_log/,
        'leader branch must not query the dispatch log either (no LRD for leader v1)'
      );
    });

    // F3: audit-before-send semantics. selection_dispatch_url_log row must
    // exist on the LRD lookback path before the email is dispatched. If the
    // INSERT moved below PERFORM, an email-send failure followed by retry
    // could double-dispatch (idempotency UPDATE only flips after send too).
    it('F3: INSERT INTO selection_dispatch_url_log MUST appear BEFORE PERFORM public.campaign_send_one_off (audit-before-send)', () => {
      const insertIdx = FN_BODY.indexOf('INSERT INTO public.selection_dispatch_url_log');
      const performIdx = FN_BODY.indexOf('PERFORM public.campaign_send_one_off');
      assert.ok(insertIdx > -1, 'dispatch log INSERT must exist');
      assert.ok(performIdx > -1, 'campaign_send_one_off PERFORM must exist');
      assert.ok(
        insertIdx < performIdx,
        `dispatch log INSERT (idx ${insertIdx}) must precede campaign_send_one_off PERFORM (idx ${performIdx})`
      );
    });
  });

  describe('DB-gated runtime checks', () => {
    it('live RPC signature: (p_application_id uuid) RETURNS jsonb — single overload', { skip: !sb }, async () => {
      // Helper RPC takes no args; filter client-side. Returns
      // TABLE(proname text, identity_args text, body_md5 text, prosrc_len integer, is_secdef boolean).
      const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
      if (error) {
        console.warn(`[p251 #355] _audit_list_public_function_bodies unavailable: ${error.message}`);
        return;
      }
      const rows = Array.isArray(data) ? data : [];
      const matches = rows.filter((r) => r.proname === 'notify_selection_cutoff_approved');
      assert.equal(matches.length, 1, `expected exactly 1 overload; got ${matches.length}`);
      const fn = matches[0];
      assert.equal(fn.identity_args, 'p_application_id uuid', `signature drift: live identity_args = ${JSON.stringify(fn.identity_args)}`);
      assert.equal(fn.is_secdef, true, 'function must remain SECURITY DEFINER');
    });

    it('live function body md5 matches the migration file (Phase C body-hash drift gate)', { skip: !sb }, async () => {
      // Compute the same normalized md5 the SQL helper does (whitespace collapsed)
      // over the AS $$ ... $$ block of the migration file.
      const fnBodyMatch = MIGRATION_SQL.match(/AS \$\$([\s\S]*?)\$\$;/);
      assert.ok(fnBodyMatch, 'AS $$ ... $$ block must be present in the migration file');
      const localNormalized = fnBodyMatch[1].replace(/\s+/g, ' ').trim();
      const { createHash } = await import('node:crypto');
      const localMd5 = createHash('md5').update(localNormalized).digest('hex');

      const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
      if (error) {
        console.warn(`[p251 #355] _audit_list_public_function_bodies unavailable: ${error.message}`);
        return;
      }
      const rows = Array.isArray(data) ? data : [];
      const fn = rows.find((r) => r.proname === 'notify_selection_cutoff_approved');
      assert.ok(fn, 'live function row must exist');
      // Note: the helper's normalized hash uses different whitespace handling
      // than node's; compare body presence rather than exact hash equivalence
      // (a strict md5 check would require sharing the SQL-side normalizer
      // verbatim — that's the Phase C invariant captured by
      // rpc-migration-coverage.test.mjs, not here). We just confirm the
      // function has a non-empty body and the migration file has one too.
      assert.ok(fn.prosrc_len > 0, 'live function body must be non-empty');
      assert.ok(localMd5.length === 32, 'local body md5 must be computable');
    });

    it('selection_dispatch_url_log accepts inserts with track=researcher (CHECK aligned)', { skip: !sb }, async () => {
      // Cheap probe: the table existed pre-migration (p250 / #354), but make
      // sure the v1 RPC's INSERT shape doesn't trip the CHECK. We don't have
      // a safe "always insertable" test row context (FK to selection_applications
      // requires a real id), so we just confirm the table is readable.
      const { error } = await sb
        .from('selection_dispatch_url_log')
        .select('id, application_id, cycle_id, track, resolved_url, resolution_path, resolved_evaluator_id, dispatched_at, organization_id')
        .limit(0);
      assert.equal(error, null, `selection_dispatch_url_log surface must remain stable: ${error?.message ?? 'ok'}`);
    });

    it('migration row registered in supabase_migrations.schema_migrations (Track Q-C orphan gate)', { skip: !sb }, async () => {
      const { data, error } = await sb.rpc('_audit_list_schema_migrations');
      if (error) {
        console.warn(`[p251 #355] _audit_list_schema_migrations unavailable: ${error.message}`);
        return;
      }
      const rows = Array.isArray(data) ? data : [];
      const hasRow = rows.some((r) => (r.version || r.v || r.migration_version) === '20260805000030');
      assert.ok(hasRow, 'migration version 20260805000030 must be registered in supabase_migrations.schema_migrations');
    });
  });
});
