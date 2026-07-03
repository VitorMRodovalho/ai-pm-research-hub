import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// #1034 + #1028: write-time DB guards.
//  #1034 — a BEFORE trigger clamps an expiring engagement's null/future end_date to today
//          so invariant Q_expired_engagement_end_date can't be violated by any write path.
//  #1028-A — a BEFORE trigger rejects NEW member_status='observer' (retired #1022-C),
//          grandfathering pre-existing observer rows.
const MIGRATION_PATH = 'supabase/migrations/20260805000325_1034_1028_lifecycle_write_guards.sql';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY;

describe('#1034/#1028 — lifecycle write-time guards', () => {
  describe('migration static assertions', () => {
    it('#1034: clamp trigger on engagements (BEFORE INSERT OR UPDATE), null/future → today', () => {
      assert.match(MIGRATION_SQL, /FUNCTION public\._trg_clamp_expired_engagement_end_date/);
      assert.match(MIGRATION_SQL, /NEW\.status = 'expired' AND \(NEW\.end_date IS NULL OR NEW\.end_date > CURRENT_DATE\)/);
      assert.match(MIGRATION_SQL, /NEW\.end_date := CURRENT_DATE/);
      assert.match(MIGRATION_SQL, /CREATE TRIGGER trg_clamp_expired_engagement_end_date\s+BEFORE INSERT OR UPDATE ON public\.engagements/);
    });

    it('#1028-A: observer-reject trigger on members, grandfathers historical rows', () => {
      assert.match(MIGRATION_SQL, /FUNCTION public\._trg_reject_new_observer_member_status/);
      assert.match(MIGRATION_SQL, /NEW\.member_status = 'observer'/);
      // grandfathering: only reject on INSERT or a transition INTO observer.
      assert.match(MIGRATION_SQL, /TG_OP = 'INSERT' OR OLD\.member_status IS DISTINCT FROM 'observer'/);
      assert.match(MIGRATION_SQL, /RAISE EXCEPTION[^;]*observer is retired/);
      assert.match(MIGRATION_SQL, /CREATE TRIGGER trg_reject_new_observer_member_status\s+BEFORE INSERT OR UPDATE OF member_status ON public\.members/);
    });
  });

  describe('DB-gated: live behavior', () => {
    const gated = SUPABASE_URL && SERVICE_ROLE ? it : it.skip;

    gated('#1034: invariant Q_expired_engagement_end_date reports 0 violations', async () => {
      const sb = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
      const { data, error } = await sb.rpc('check_schema_invariants');
      assert.ifError(error);
      const q = (data || []).find((r) => r.invariant === 'Q_expired_engagement_end_date'
        || r.name === 'Q_expired_engagement_end_date'
        || r.invariant_name === 'Q_expired_engagement_end_date');
      assert.ok(q, 'invariant Q must be present in check_schema_invariants output');
      const violations = q.violation_count ?? q.violations ?? q.count ?? q.total_violations;
      assert.equal(Number(violations), 0, `Q must have 0 violations, got ${JSON.stringify(q)}`);
    });

    gated('#1028-A: a direct member_status=observer write is rejected (self-healing)', async () => {
      const sb = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
      const { data: rows, error: selErr } = await sb
        .from('members').select('id, member_status').eq('member_status', 'active').limit(1);
      assert.ifError(selErr);
      assert.ok(rows?.length, 'need an active member to probe');
      const m = rows[0];
      const { error } = await sb.from('members').update({ member_status: 'observer' }).eq('id', m.id);
      try {
        assert.ok(error, 'observer write must be rejected by the guard');
      } finally {
        // If the guard were broken and the write slipped through, restore immediately.
        if (!error) await sb.from('members').update({ member_status: m.member_status }).eq('id', m.id);
      }
    });
  });
});
