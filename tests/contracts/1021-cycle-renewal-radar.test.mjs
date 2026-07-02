/**
 * #1021 — cycle-close renewal radar: get_cycle_renewal_radar(p_as_of date).
 *
 * The renewal radar was blind at cycle close because service-end was only reachable through the
 * engagement's FK-linked application; volunteers whose engagement pointed at an older/different app
 * (NULL date on that row) fell dark even though an EMAIL-MATCHED app carried the real VEP date.
 *
 * Guards:
 *   (A) Static (offline) — the RPC exists, resolves service-end by MEMBER EMAIL across all matched
 *       applications (the fix), is LGPD-gated (manage_member OR service_role/postgres), and is
 *       REVOKE'd from anon. This is the structural regression guard for the fix — data-independent.
 *   (B) DB-aware (skipped without SUPABASE_URL + SERVICE_ROLE_KEY) — the operator/service_role path
 *       succeeds and returns a well-formed report whose classification invariants hold: the members
 *       array length matches the summary total, resolved==unknown partitions the cohort, and
 *       service_end_source is coherent with linked vs resolved dates (email_matched ⇒ the linked date
 *       was NOT the furthest; linked ⇒ it was). The email_matched coherence branch only executes while
 *       email_matched rows exist in the live data; Layer A is the permanent data-independent guard for
 *       the email-resolution logic.
 *
 * The gate's DENY path (authenticated non-GP → 'Unauthorized: requires manage_member action') was
 * proven out-of-band via a set_config JWT + RAISE-rollback smoke, documented in the PR. Live==file is
 * enforced by the Phase C body-drift gate (this new function is not on the p175 allowlist).
 *
 * Cross-ref: #1021, #999 (persisted service_latest_end_date), #1004 (cycle-turn cohort procedure),
 * p170 (engagement→application FK linkage).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  return files.map((f) => readFileSync(join(MIGRATIONS_DIR, f), 'utf8'));
}
const allSQL = loadAllMigrations().join('\n');

// Escape set includes backslash → fully sanitized RegExp (reused from 963/991).
function latestFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi',
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][2] : null;
}

// ── Layer A: static migration-body guards (offline) ──────────────────────────
test('#1021 static: get_cycle_renewal_radar exists and resolves service-end by member email', () => {
  const body = latestFunctionBody('get_cycle_renewal_radar');
  assert.ok(body, 'get_cycle_renewal_radar must be defined in a migration');
  // The fix: resolve service-end across the member's FULL email set (member_emails, p277 inv. R),
  // via a LATERAL over selection_applications — not only the FK-linked app, not only the primary email.
  assert.match(body, /member_emails/, 'must resolve across the member email set (member_emails), not only the primary');
  assert.match(
    body,
    /lower\(a\.email\)\s*=\s*ANY\(av\.email_set\)[\s\S]*service_latest_end_date IS NOT NULL/,
    'must resolve service-end across ALL applications matched to the member email set (the #1021 fix)',
  );
  // It must still read the FK-linked app date for the diagnostic comparison.
  assert.match(body, /linked_service_end/, 'must surface the FK-linked service-end for comparison');
  // Honest unknown state — no fabricated fallback to the uniform cert period.
  assert.match(body, /'unknown'/, 'must classify the no-date case as unknown');
});

test('#1021 static: LGPD dual-consumer gate (manage_member OR service_role/postgres); anon revoked', () => {
  const body = latestFunctionBody('get_cycle_renewal_radar');
  assert.match(body, /can_by_member\(v_caller_id, 'manage_member'\)/, 'in-app path must require manage_member');
  assert.match(
    body,
    /current_setting\('role', true\) NOT IN \('service_role', 'postgres'\)/,
    'operator/cron path must allow service_role/postgres',
  );
  // REVOKE from anon lives in the migration (outside the function body).
  const mig = allSQL;
  assert.match(
    mig,
    /REVOKE ALL ON FUNCTION public\.get_cycle_renewal_radar\(date\) FROM PUBLIC, anon/,
    'the RPC must be revoked from PUBLIC + anon',
  );
  // service_role is the non-obvious half of the dual-consumer design (the MCP operator path); guard it.
  assert.match(
    mig,
    /GRANT EXECUTE ON FUNCTION public\.get_cycle_renewal_radar\(date\) TO authenticated, service_role/,
    'must grant EXECUTE to both authenticated and service_role (dual-consumer design)',
  );
});

test('#1021 static: the PII read is instrumented (LGPD Art. 37) via log_pii_access_batch', () => {
  const body = latestFunctionBody('get_cycle_renewal_radar');
  assert.match(body, /log_pii_access_batch\(/, 'must log the nominal member name/email read (Art. 37)');
});

// ── Layer B: DB-aware operator-path + classification invariants (skip offline) ─
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1021 runtime: operator (service_role) gets a well-formed report with coherent classification', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  // service_role → auth.uid() IS NULL → operator allowance path (NOT the deny path). Fixed as_of so
  // the renews_signal partition is deterministic for the cycle turn.
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data, error } = await sb.rpc('get_cycle_renewal_radar', { p_as_of: '2026-07-09' });
  assert.equal(error, null, error?.message);
  assert.ok(data && typeof data === 'object', 'must return a jsonb object');
  assert.equal(data.as_of, '2026-07-09');

  const s = data.summary;
  const members = data.members;
  assert.ok(s && Array.isArray(members), 'summary + members[] must be present');

  // Members array length matches the reported total (rows are per-engagement).
  assert.equal(members.length, s.total_active_volunteer_engagements, 'members[] length must equal total_active_volunteer_engagements');
  assert.ok(s.distinct_members <= s.total_active_volunteer_engagements, 'distinct_members cannot exceed engagement rows');

  // Partition invariants: resolved + unknown = total; recovered_by_email ⊆ resolved.
  assert.equal(s.service_end_resolved + s.unknown, s.total_active_volunteer_engagements, 'resolved + unknown must partition the cohort');
  assert.ok(s.recovered_by_email <= s.service_end_resolved, 'recovered_by_email cannot exceed resolved');

  // Per-member source coherence — only holds if the email resolution actually runs:
  const bySource = { linked: 0, email_matched: 0, unknown: 0 };
  for (const m of members) {
    assert.ok(['linked', 'email_matched', 'unknown'].includes(m.service_end_source), `bad source ${m.service_end_source}`);
    assert.ok(['active_future', 'lapsing', 'unknown'].includes(m.renews_signal), `bad signal ${m.renews_signal}`);
    assert.equal(typeof m.renewal_link_present, 'boolean', 'renewal_link_present must be a boolean (per-engagement FK signal)');
    bySource[m.service_end_source]++;
    if (m.service_end_source === 'unknown') {
      assert.equal(m.resolved_service_end, null, 'unknown source must carry a null resolved_service_end');
      assert.equal(m.renews_signal, 'unknown', 'unknown source must map to an unknown renews_signal');
    } else {
      assert.ok(m.resolved_service_end, 'a resolved source must carry a non-null resolved_service_end');
      if (m.service_end_source === 'email_matched') {
        // The fix's signature: the FK-linked date was NOT the furthest (null, or an earlier date).
        assert.notEqual(m.linked_service_end, m.resolved_service_end,
          'email_matched implies the FK-linked date was not the resolved (furthest) one');
      } else {
        // linked source ⇒ the FK-linked date IS the resolved furthest date.
        assert.equal(m.linked_service_end, m.resolved_service_end,
          'linked source implies the FK-linked date equals the resolved one');
      }
    }
  }
  assert.equal(bySource.unknown, s.unknown, 'summary.unknown must match counted unknown members');
  assert.equal(bySource.email_matched, s.recovered_by_email, 'summary.recovered_by_email must match counted email_matched members');
});
