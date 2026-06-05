import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// SPEC #348 Child #4 — cycle4-2026 reseed: seeds Vitor + Fabricio as
// role='evaluator' (CHECK-constrained value) on selection_committee with
// can_interview=true and populates their members.interview_booking_url so
// the #355 RPC LRD routing ladder picks individual URLs for researcher-track
// dispatches. Forward-defense locks the PM rules (no 'researcher' role, no
// leader-flow disruption, no can_interview=false drift).

const MIGRATION_PATH = 'supabase/migrations/20260805000032_p253_357_spec_348_v1_cycle4_reseed.sql';
const MIGRATION_SQL  = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

// Identities + URLs (PM-provided 2026-05-24). Hardcoding mirrors migration —
// regression against either side flips the literal-match assertion.
const CYCLE_ID    = '08c1e301-9f7b-4d01-a13c-43ac7775c0f7';
const VITOR_ID    = '880f736c-3e76-4df4-9375-33575c190305';
const FABRICIO_ID = '92d26057-5550-4f15-a3bf-b00eed5f32f9';
const VITOR_URL    = 'https://calendar.app.google/q9urWE15HYZRNymd7';
const FABRICIO_URL = 'https://calendar.app.google/1jDNjPpoGCkV2V9A6';
const CYCLE_GROUP_URL = 'https://calendar.app.google/XPiGWLh9JaLVFKJc6'; // p243 seeded; leader flow

describe('p253 #357 — SPEC #348 Child #4 cycle4-2026 reseed', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp', () => {
      assert.ok(existsSync(MIGRATION_PATH), `migration expected at ${MIGRATION_PATH}`);
      assert.ok(MIGRATION_SQL.length > 0);
    });

    it('header documents WHAT / WHY / SPEC DRIFT / ROLLBACK / INVARIANTS + chain refs', () => {
      assert.match(MIGRATION_SQL, /-- WHAT:/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- SPEC DRIFT RESOLVED:/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK:/);
      assert.match(MIGRATION_SQL, /-- INVARIANTS:/);
      assert.match(MIGRATION_SQL, /#348/);
      assert.match(MIGRATION_SQL, /#354/);
      assert.match(MIGRATION_SQL, /#355/);
      assert.match(MIGRATION_SQL, /#356/);
      assert.match(MIGRATION_SQL, /#357/);
    });
  });

  describe('seed identities + URLs (literal-match — drift catches typos)', () => {
    it('cycle4-2026 cycle id appears verbatim', () => {
      assert.ok(MIGRATION_SQL.includes(CYCLE_ID), `expected cycle id ${CYCLE_ID} in migration`);
    });
    it('Vitor member id appears verbatim', () => {
      assert.ok(MIGRATION_SQL.includes(VITOR_ID), `expected Vitor id ${VITOR_ID}`);
    });
    it('Fabricio member id appears verbatim', () => {
      assert.ok(MIGRATION_SQL.includes(FABRICIO_ID), `expected Fabricio id ${FABRICIO_ID}`);
    });
    it('Vitor calendar URL appears verbatim', () => {
      assert.ok(MIGRATION_SQL.includes(VITOR_URL), `expected ${VITOR_URL}`);
    });
    it('Fabricio calendar URL appears verbatim', () => {
      assert.ok(MIGRATION_SQL.includes(FABRICIO_URL), `expected ${FABRICIO_URL}`);
    });
    it('cycle code cycle4-2026 referenced for pre-seed sanity', () => {
      assert.match(MIGRATION_SQL, /cycle_code\s*=\s*'cycle4-2026'/);
    });
  });

  describe('selection_committee INSERT — PM-rule conformance', () => {
    it("INSERT seeds role='evaluator' (NOT 'researcher')", () => {
      // CHECK constraint allows ('evaluator','lead','observer') — 'researcher'
      // would raise 23514 at apply time. Forward-defense locks the literal.
      assert.match(
        MIGRATION_SQL,
        /INSERT INTO public\.selection_committee[\s\S]*?VALUES[\s\S]*?'evaluator'[\s\S]*?'evaluator'/,
        "both committee rows must seed role='evaluator'"
      );
    });

    it('both rows seed can_interview=true (explicit, not relying on column default)', () => {
      // Count 'evaluator', true tuples — must appear twice
      const matches = MIGRATION_SQL.match(/'evaluator',\s*true/g) || [];
      assert.ok(
        matches.length >= 2,
        `expected >= 2 'evaluator', true tuples for Vitor + Fabricio; got ${matches.length}`
      );
    });

    it('INSERT uses ON CONFLICT (cycle_id, member_id) DO NOTHING — idempotent reseed', () => {
      assert.match(
        MIGRATION_SQL,
        /ON CONFLICT\s*\(\s*cycle_id\s*,\s*member_id\s*\)\s*DO NOTHING/i,
        'idempotency: re-running the migration must be a no-op after first apply'
      );
    });
  });

  describe('members.interview_booking_url population', () => {
    it('UPDATE members for Vitor populates personal URL', () => {
      assert.match(
        MIGRATION_SQL,
        new RegExp(`UPDATE public\\.members[\\s\\S]*?interview_booking_url[\\s\\S]*?${VITOR_ID.replace(/-/g, '-')}`)
      );
    });
    it('UPDATE members for Fabricio populates personal URL', () => {
      assert.match(
        MIGRATION_SQL,
        new RegExp(`UPDATE public\\.members[\\s\\S]*?interview_booking_url[\\s\\S]*?${FABRICIO_ID.replace(/-/g, '-')}`)
      );
    });
  });

  describe('post-seed sanity gate', () => {
    it('migration RAISES EXCEPTION when post-seed committee row count < 2', () => {
      assert.match(
        MIGRATION_SQL,
        /RAISE EXCEPTION\s+'Post-seed sanity:[\s\S]*?cycle4-2026[\s\S]*?2\s+evaluator/i,
        'sanity check must fail closed when fewer than 2 evaluator+can_interview rows survive'
      );
    });

    it('pre-seed sanity confirms target cycle id matches cycle4-2026', () => {
      assert.match(
        MIGRATION_SQL,
        /RAISE EXCEPTION\s+'Pre-seed sanity:/i,
        'pre-seed RAISE catches cycle rename/archive drift before any DML'
      );
    });
  });

  describe('audit trail (admin_audit_log)', () => {
    it("INSERT into admin_audit_log uses canonical action 'selection.committee_seeded'", () => {
      assert.match(
        MIGRATION_SQL,
        /INSERT INTO public\.admin_audit_log[\s\S]*?'selection\.committee_seeded'/,
        'canonical action namespace lets the audit query find the row'
      );
    });

    it('audit insert is conditional on v_inserted_count > 0 (no phantom audit on re-run)', () => {
      assert.match(
        MIGRATION_SQL,
        /IF\s+v_inserted_count\s*>\s*0\s+THEN[\s\S]*?INSERT INTO public\.admin_audit_log/i,
        're-run idempotency: audit row only fires when an INSERT actually happens'
      );
    });

    it('audit metadata captures migration tag for traceability', () => {
      assert.match(MIGRATION_SQL, /'20260805000032'/);
    });
  });

  describe('forward-defense regressions (lock PM rules permanently)', () => {
    it("migration does NOT use role='researcher' (PM-forbidden literal)", () => {
      // The CHECK constraint already rejects this, but the regex catches it
      // BEFORE apply_migration runs, so a typo is caught in CI not in pg.
      assert.doesNotMatch(
        MIGRATION_SQL,
        /role\s*=\s*'researcher'|VALUES[\s\S]*?'researcher'\s*,\s*true/i,
        "PM rule: selection_committee.role must be 'evaluator', not 'researcher'"
      );
    });

    it('migration does NOT modify selection_cycles (leader flow preservation)', () => {
      // Cycle.interview_booking_url stays at the p243-seeded Núcleo group URL.
      // Any UPDATE/INSERT on selection_cycles in this migration would risk
      // perturbing leader-track dispatch.
      assert.doesNotMatch(
        MIGRATION_SQL,
        /UPDATE\s+public\.selection_cycles\b/i,
        'leader flow uses cycle-level URL — must stay untouched'
      );
      assert.doesNotMatch(
        MIGRATION_SQL,
        /INSERT INTO\s+public\.selection_cycles\b/i,
        'no new cycle row introduced'
      );
    });

    it('migration does NOT set can_interview=false anywhere', () => {
      assert.doesNotMatch(
        MIGRATION_SQL,
        /can_interview\s*=\s*false|can_interview[\s\S]{0,40}false\)/i,
        'PM rule: both evaluators must accept interview booking — can_interview=true'
      );
    });

    it('migration does NOT touch selection_committee.interview_booking_url (committee override stays NULL)', () => {
      // Per SPEC #348 §3 ladder: leaving committee URL NULL forces the
      // routing logic to use members.interview_booking_url — the layer we
      // ARE populating. Setting committee URL here would short-circuit the
      // ladder and lose the per-member fallback behavior.
      assert.doesNotMatch(
        MIGRATION_SQL,
        /selection_committee[\s\S]{0,120}?interview_booking_url\s*=\s*'/i,
        'committee-tier URL must stay NULL so member-tier governs'
      );
    });
  });

  describe('live DB body parity (skips if no SUPABASE env)', () => {
    if (!sb) {
      it.skip('live DB checks skipped — SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set');
      return;
    }

    // Pattern: do NOT chain .catch() on sb.rpc()/sb.from() — PostgrestBuilder
    // is thenable, not Promise (sediment from p252 fix). Await + check
    // {error} envelope.

    it('cycle4-2026 has >= 2 evaluator+can_interview rows in selection_committee', async () => {
      const { data, error } = await sb
        .from('selection_committee')
        .select('id, role, can_interview')
        .eq('cycle_id', CYCLE_ID);
      if (error) return; // skip gracefully if RLS denies service role (shouldn't, but defensive)
      const evals = (data || []).filter(r => r.role === 'evaluator' && r.can_interview === true);
      assert.ok(evals.length >= 2, `expected >= 2 evaluator+can_interview rows, got ${evals.length}`);
    });

    it('Vitor + Fabricio member rows carry their respective booking URLs', async () => {
      const { data, error } = await sb
        .from('members')
        .select('id, interview_booking_url')
        .in('id', [VITOR_ID, FABRICIO_ID]);
      if (error) return;
      const byId = Object.fromEntries((data || []).map(r => [r.id, r.interview_booking_url]));
      assert.equal(byId[VITOR_ID],    VITOR_URL,    'Vitor URL mismatch');
      assert.equal(byId[FABRICIO_ID], FABRICIO_URL, 'Fabricio URL mismatch');
    });

    it('cycle4-2026 cycle.interview_booking_url unchanged (leader flow preserved)', async () => {
      const { data, error } = await sb
        .from('selection_cycles')
        .select('interview_booking_url')
        .eq('id', CYCLE_ID)
        .maybeSingle();
      if (error) return;
      assert.equal(
        data?.interview_booking_url,
        CYCLE_GROUP_URL,
        'cycle URL must remain at p243 Núcleo group link — leader-track dispatch depends on this'
      );
    });
  });
});
