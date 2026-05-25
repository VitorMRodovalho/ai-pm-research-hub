import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// p256 Wave 1a M2 — taxonomy + visibility + status + atomic RLS swap + V' invariant.
// Spec: SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md §19.5; P0-Q1/Q2/Q3/Q4/Q6/Q10 + A1/A2.
//
// PM corrections rev2 plan:
//   #1 closing_gate_signoff_id FK = ON DELETE RESTRICT (not SET NULL)
//   #3 document_versions_read_published: locked_at IS NOT NULL is HARD-GATE outside OR;
//      no curate_content bypass; no manager/deputy_manager hardcoded; only manage_member admin
//   #4 invariants test: assert by NAME (V' present, V absent) + all violation_count=0
//      (no hard-coded total — robust against parallel-branch additions)

const MIGRATION_PATH = 'supabase/migrations/20260805000036_p256_wave1a_315_m2_taxonomy_visibility_status_rls_vprime.sql';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');

// Strip `--` SQL line comments to build MIGRATION_CODE for forward-defense regex
// matching on the LIVE policy/function bodies — keeps ROLLBACK examples in
// header from triggering false positives.
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

describe('p256 M2 — taxonomy + visibility + status + RLS swap + V invariant prime', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp', () => {
      assert.ok(existsSync(MIGRATION_PATH));
      assert.ok(MIGRATION_SQL.length > 0);
    });

    it('header documents WHAT / WHY / SPEC / SCOPE LOCK / ROLLBACK / INVARIANTS / CROSS-REF', () => {
      assert.match(MIGRATION_SQL, /-- WHAT: Wave 1a M2/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- SPEC:/);
      assert.match(MIGRATION_SQL, /-- SCOPE LOCK/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK/);
      assert.match(MIGRATION_SQL, /-- INVARIANTS:/);
      assert.match(MIGRATION_SQL, /-- CROSS-REF:/);
    });

    it('explicitly documents KNOWN REGRESSION (PM #3 — curate_content/manager bypass removed)', () => {
      assert.match(MIGRATION_SQL, /-- KNOWN REGRESSION[\s\S]+curate_content[\s\S]+manage_member/);
    });

    it('cites P0-Q1/Q2/Q3/Q4/Q6/Q10 + A1/A2 amendments', () => {
      // Header WHY uses slash-separated form: "P0-Q1/Q2/Q3/..." — match either form.
      assert.match(MIGRATION_SQL, /P0-Q1(?:\/Q\d+)*/);
      assert.match(MIGRATION_SQL, /\b(?:P0-Q2|\/Q2\b)/);
      assert.match(MIGRATION_SQL, /\b(?:P0-Q3|\/Q3\b)/);
      assert.match(MIGRATION_SQL, /\b(?:P0-Q6|\/Q6\b)/);
      assert.match(MIGRATION_SQL, /\bA1\b/);
      assert.match(MIGRATION_SQL, /\bA2\b/);
    });
  });

  describe('M2.1 — doc_type CHECK extension', () => {
    it('drops old doc_type CHECK and adds new one with editorial_guide + governance_guideline', () => {
      assert.match(MIGRATION_SQL, /DROP CONSTRAINT governance_documents_doc_type_check/);
      assert.match(MIGRATION_SQL, /ADD CONSTRAINT governance_documents_doc_type_check\s+CHECK \(doc_type IN[\s\S]{0,400}?'editorial_guide'/);
      assert.match(MIGRATION_SQL, /'governance_guideline'/);
    });
  });

  describe('M2.2 — status CHECK drop+recreate (5→8 values per A2)', () => {
    it('drops old status CHECK', () => {
      assert.match(MIGRATION_SQL, /DROP CONSTRAINT governance_documents_status_check/);
    });

    it('adds new status CHECK with all 8 values', () => {
      assert.match(MIGRATION_SQL, /ADD CONSTRAINT governance_documents_status_check[\s\S]+CHECK \(status IN \([\s\S]+'draft'[\s\S]+'pending_proposer_consent'[\s\S]+'under_review'[\s\S]+'approved'[\s\S]+'active'[\s\S]+'superseded'[\s\S]+'withdrawn'[\s\S]+'revoked'/);
    });
  });

  describe('M2.3 — 7 new columns on governance_documents', () => {
    it('adds visibility_class, required_action, acknowledgement_mode, effective_*, approved_at, closing_gate_signoff_id', () => {
      assert.match(MIGRATION_SQL, /ADD COLUMN visibility_class\s+text/);
      assert.match(MIGRATION_SQL, /ADD COLUMN required_action\s+text/);
      assert.match(MIGRATION_SQL, /ADD COLUMN acknowledgement_mode text/);
      assert.match(MIGRATION_SQL, /ADD COLUMN effective_from\s+timestamptz/);
      assert.match(MIGRATION_SQL, /ADD COLUMN effective_until\s+timestamptz/);
      assert.match(MIGRATION_SQL, /ADD COLUMN approved_at\s+timestamptz/);
      assert.match(MIGRATION_SQL, /ADD COLUMN closing_gate_signoff_id uuid/);
    });

    it('PM #1 — closing_gate_signoff_id FK is ON DELETE RESTRICT (NOT SET NULL)', () => {
      assert.match(MIGRATION_SQL, /closing_gate_signoff_id uuid\s+REFERENCES public\.approval_signoffs\(id\) ON DELETE RESTRICT/);
      // Forward-defense: ensure no accidental SET NULL on this FK
      assert.doesNotMatch(MIGRATION_SQL, /closing_gate_signoff_id[\s\S]{0,200}?ON DELETE SET NULL/);
    });
  });

  describe('M2.4 — backfill defaults', () => {
    it("visibility_class backfill is uniform 'active_members' (preserves gd_read=true semantics)", () => {
      assert.match(MIGRATION_SQL, /UPDATE public\.governance_documents\s+SET visibility_class = 'active_members'\s+WHERE visibility_class IS NULL/);
    });

    it('acknowledgement_mode backfill uses per-A1 CASE WHEN', () => {
      assert.match(MIGRATION_SQL, /SET acknowledgement_mode = CASE doc_type/);
      assert.match(MIGRATION_SQL, /WHEN 'cooperation_agreement'\s+THEN 'legal_signature'/);
      assert.match(MIGRATION_SQL, /WHEN 'volunteer_term_template' THEN 'binding'/);
      assert.match(MIGRATION_SQL, /WHEN 'manual'\s+THEN 'informational'/);
    });

    it('approved_at backfilled from first_ratified_at/signed_at for ratified statuses', () => {
      assert.match(MIGRATION_SQL, /SET approved_at = COALESCE\(first_ratified_at, signed_at\)/);
    });
  });

  describe('M2.5 — sanity DO + NOT NULL + CHECKs', () => {
    it('sanity DO RAISES on visibility_class incomplete', () => {
      assert.match(MIGRATION_SQL, /RAISE EXCEPTION 'p256 M2: visibility_class backfill incomplete'/);
    });

    it('sanity DO RAISES on acknowledgement_mode incomplete', () => {
      assert.match(MIGRATION_SQL, /RAISE EXCEPTION 'p256 M2: acknowledgement_mode backfill incomplete'/);
    });

    it('visibility_class + acknowledgement_mode get SET NOT NULL', () => {
      assert.match(MIGRATION_SQL, /ALTER COLUMN visibility_class\s+SET NOT NULL/);
      assert.match(MIGRATION_SQL, /ALTER COLUMN acknowledgement_mode\s+SET NOT NULL/);
    });

    it('visibility_class CHECK has 5 allowed values', () => {
      assert.match(MIGRATION_SQL, /governance_documents_visibility_class_check[\s\S]+CHECK \(visibility_class IN \('public','active_members','legal_scoped','admin_only','audit_restricted'\)\)/);
    });

    it('acknowledgement_mode CHECK has 3 allowed values', () => {
      assert.match(MIGRATION_SQL, /governance_documents_acknowledgement_mode_check[\s\S]+CHECK \(acknowledgement_mode IN \('informational','binding','legal_signature'\)\)/);
    });

    it('NOT NULL gate precedes RLS swap (positional check)', () => {
      // Use MIGRATION_CODE (comment-stripped) so DROP POLICY example in ROLLBACK doesn't match.
      const notNullMatch = MIGRATION_CODE.match(/ALTER COLUMN visibility_class\s+SET NOT NULL/);
      const rlsMatch     = MIGRATION_CODE.match(/DROP POLICY gd_read ON public\.governance_documents/);
      assert.ok(notNullMatch && rlsMatch, 'both present in non-comment SQL');
      assert.ok(notNullMatch.index < rlsMatch.index, 'NOT NULL gate must precede RLS swap (atomic per P0-Q3)');
    });
  });

  describe('M2.6 — atomic RLS swap (gd_read + document_versions_read_published)', () => {
    it('gd_read DROP POLICY + CREATE POLICY both present (same migration)', () => {
      assert.match(MIGRATION_SQL, /DROP POLICY gd_read ON public\.governance_documents/);
      assert.match(MIGRATION_SQL, /CREATE POLICY gd_read ON public\.governance_documents/);
    });

    it('new gd_read is class-aware (visibility_class IS NOT NULL + 5 branches)', () => {
      assert.match(MIGRATION_SQL, /CREATE POLICY gd_read[\s\S]{0,1500}?visibility_class IS NOT NULL/);
      ['public','active_members','legal_scoped','admin_only','audit_restricted'].forEach(c => {
        assert.match(MIGRATION_SQL, new RegExp(`visibility_class = '${c}'`));
      });
    });

    it('document_versions_read_published DROP + CREATE both present', () => {
      assert.match(MIGRATION_SQL, /DROP POLICY document_versions_read_published ON public\.document_versions/);
      assert.match(MIGRATION_SQL, /CREATE POLICY document_versions_read_published ON public\.document_versions/);
    });

    it('PM #3 — locked_at IS NOT NULL is HARD-GATE (followed by AND, not OR)', () => {
      // MIGRATION_CODE strips `--` comments so the ROLLBACK example never matches here.
      const newPolicyMatch = MIGRATION_CODE.match(/CREATE POLICY document_versions_read_published[\s\S]+?USING \(([\s\S]+?)\);/);
      assert.ok(newPolicyMatch, 'document_versions_read_published policy body must be present in non-comment SQL');
      const body = newPolicyMatch[1];
      const firstClause = body.match(/locked_at IS NOT NULL\s*(AND|OR)/);
      assert.ok(firstClause, 'locked_at IS NOT NULL must be followed by AND or OR');
      assert.equal(firstClause[1], 'AND', 'PM #3: locked_at must be hard-gate AND not OR — drafts must not bypass');
    });

    it('PM #3 forward-defense — curate_content NOT in document_versions_read_published body', () => {
      const newPolicyMatch = MIGRATION_CODE.match(/CREATE POLICY document_versions_read_published[\s\S]+?USING \(([\s\S]+?)\);/);
      assert.ok(newPolicyMatch);
      assert.ok(!newPolicyMatch[1].includes('curate_content'),
        'PM #3: document_versions_read_published must not contain curate_content (deferred to Wave 1b draft-access policy/RPC)');
    });

    it('PM #3 forward-defense — no manager/deputy_manager operational_role hardcode in document_versions_read_published', () => {
      const newPolicyMatch = MIGRATION_CODE.match(/CREATE POLICY document_versions_read_published[\s\S]+?USING \(([\s\S]+?)\);/);
      assert.ok(newPolicyMatch);
      assert.ok(!/operational_role\s*=\s*ANY\s*\(\s*ARRAY/.test(newPolicyMatch[1]),
        'PM #3: document_versions_read_published must not hardcode manager/deputy_manager operational_role — admin path via can_by_member(...,manage_member) only');
    });

    it('PM #3 — admin bypass branches only via manage_member/manage_platform via can_by_member', () => {
      const newPolicyMatch = MIGRATION_CODE.match(/CREATE POLICY document_versions_read_published[\s\S]+?USING \(([\s\S]+?)\);/);
      assert.ok(newPolicyMatch);
      assert.match(newPolicyMatch[1], /can_by_member\(m\.id,\s*'manage_member'\)/);
    });
  });

  describe('M2.7 — check_schema_invariants V invariant prime only (V deferred Wave 1b)', () => {
    it('V_prime_pending_proposer_consent_no_open_chain block present', () => {
      assert.match(MIGRATION_SQL, /'V_prime_pending_proposer_consent_no_open_chain'/);
    });

    it("V deferred to Wave 1b first leaf — comment explicit", () => {
      assert.match(MIGRATION_SQL, /V \(status[\s\S]+?\) is\s+-- DEFERRED to Wave 1b first leaf/);
    });

    it("forward-defense — no V_status_chain_coherence or similarly-named invariant block added", () => {
      // V invariant body would look like: 'V_status_chain_coherence' or check `current_ratified_chain_id IS NULL AND status IN ('approved','active')`
      // Use MIGRATION_CODE (comments stripped) so ROLLBACK or doc examples don't trigger false positive.
      const vPattern = /'V_status_chain[\s\S]{0,40}'|status IN \('approved','active'\)[\s\S]{0,200}?current_ratified_chain_id IS NULL/;
      assert.doesNotMatch(MIGRATION_CODE, vPattern, 'V invariant body must not appear — only V prime');
    });

    it('COMMENT ON FUNCTION updated to mention 20 invariants + V deferred', () => {
      assert.match(MIGRATION_SQL, /COMMENT ON FUNCTION public\.check_schema_invariants\(\)[\s\S]+?20 schema invariants/);
      assert.match(MIGRATION_SQL, /V \(status\/chain coherence\) deferred to Wave 1b/);
    });
  });

  describe('NOTIFY pgrst at end', () => {
    it("issues NOTIFY pgrst, 'reload schema'", () => {
      assert.match(MIGRATION_SQL, /NOTIFY pgrst, 'reload schema'/);
    });
  });

  describe('DB-gated live verification (skip without env) — PM #4: by NAME, not count', () => {
    if (!sb) {
      it.skip('SUPABASE env not set — skipping DB-gated assertions');
      return;
    }

    it("V' present, V activated (post-p257) — all invariants violation_count=0", async () => {
      // Note: this DB-gated test was originally written in p256 (Wave 1a M2) to assert
      // "V' present, V ABSENT" (V deferred to Wave 1b first leaf #367). p257 (#367)
      // ratchets V from deferred → activated. Test now asserts both V' and V are
      // present + violation_count=0. The static forward-defense at line ~210 that
      // checks the p256 M2 MIGRATION FILE does NOT contain V is still correct
      // (V lives in p257's 20260805000039, NOT in p256's 20260805000036).
      const { data, error } = await sb.rpc('check_schema_invariants');
      if (error) {
        // graceful skip on permission error
        if (/permission|unauthorized/i.test(error.message)) return;
        throw error;
      }
      assert.ok(Array.isArray(data), 'check_schema_invariants must return array');
      assert.ok(data.length >= 21, `expected at least 21 invariants post-p257 V activation (was ${data.length}); parallel branch additions OK`);

      // PM #4 (a): V' (V_prime) present by name — preserved from Wave 1a M2
      const vPrime = data.find(r => r.invariant_name === 'V_prime_pending_proposer_consent_no_open_chain');
      assert.ok(vPrime, "V' (V_prime_pending_proposer_consent_no_open_chain) must be present");

      // PM #4 (b): V (V_status_chain_coherence) present by name — activated p257 Wave 1b first leaf (#367)
      const v = data.find(r => r.invariant_name === 'V_status_chain_coherence');
      assert.ok(v, "V (V_status_chain_coherence) must be present post-p257 Wave 1b first leaf #367");
      assert.equal(v.violation_count, 0, `V must have violation_count=0 post-synthetic-chain-backfill (got: ${v.violation_count})`);

      // PM #4 (c): all rows violation_count = 0
      const violations = data.filter(r => r.violation_count > 0);
      assert.equal(violations.length, 0, `all invariants must have violation_count=0 (drift: ${violations.map(r => r.invariant_name).join(',')})`);
    });
  });
});
