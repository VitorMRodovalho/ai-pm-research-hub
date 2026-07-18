/**
 * Contract: #1422 — critical identity/authority views must stay security_invoker=true.
 *
 * Migration: supabase/migrations/20260805000465_1422_restore_security_invoker_*.sql (the fix)
 *            supabase/migrations/20260805000466_1422_followup_audit_view_security_invoker.sql (this guard's RPC)
 *
 * Recurrence guard for the security_definer_view drift class. In #1422, auth_engagements
 * regressed from invoker back to SECURITY DEFINER because 20260805000341 used
 * CREATE OR REPLACE VIEW without restating the reloption (Postgres resets reloptions
 * silently); v_active_members was DEFINER since creation. As DEFINER these views bypass
 * the caller's RLS on the underlying identity tables (members/engagements/persons).
 *
 * The Supabase advisor-check catches this class too, but it is external (Management API,
 * broke via a path change on 2026-07-18) and non-required. This test asserts the invariant
 * with an in-repo RPC inside the required `validate` suite, so a future regression is
 * merge-blocking without coupling the gate to a third-party API.
 *
 * If this fails: a listed view is DEFINER (or missing). Re-flip with
 *   ALTER VIEW public.<view> SET (security_invoker = true);
 * (NOT CREATE OR REPLACE VIEW, which re-drops the reloption). See #1422.
 *
 * Requires: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY. Skipped otherwise.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

// Views over identity/authority/attendance/cert data that MUST be invoker (never
// SECURITY DEFINER) — a DEFINER regression makes them bypass the caller's RLS on the
// underlying sensitive tables. auth_engagements + v_active_members are the two #1422
// flipped; the rest were flipped in the Onda 1 security sweep (20260508030000 / p40).
// NOT included: impact_hours_total + public_members — those are accepted-DEFINER
// (ADR-0096 / issue #82), tracked in scripts/advisor_baseline.json instead.
// This is the full set of sensitive-data views that are invoker as of #1422; keep it in
// sync when a new sensitive view is intentionally flipped (query: public views with
// reloptions security_invoker=true that read members/persons/engagements).
const CRITICAL_INVOKER_VIEWS = [
  'auth_engagements',
  'v_active_members',
  'active_members',
  'impact_hours_summary',
  'member_attendance_summary',
  'members_public_safe',
  'v_initiative_roster',
  'vw_exec_cert_timeline',
  'vw_exec_skills_radar',
];

async function auditViews(views) {
  const url = `${SUPABASE_URL}/rest/v1/rpc/_audit_view_security_invoker`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({ p_views: views }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`RPC failed: HTTP ${res.status} — ${text}`);
  }
  return res.json();
}

test('#1422: critical identity/authority views are security_invoker (not DEFINER)', { skip: !canRun && skipMsg }, async (t) => {
  const rows = await auditViews(CRITICAL_INVOKER_VIEWS);
  assert.ok(Array.isArray(rows), 'RPC must return an array');

  const byName = Object.fromEntries(rows.map((r) => [r.view_name, r]));

  for (const view of CRITICAL_INVOKER_VIEWS) {
    await t.test(view, () => {
      const row = byName[view];
      assert.ok(row, `RPC returned no row for ${view}`);
      assert.strictEqual(row.view_exists, true, `${view} must exist (renamed/dropped?)`);
      assert.strictEqual(
        row.is_invoker,
        true,
        `${view} is SECURITY DEFINER — a CREATE OR REPLACE VIEW likely reset security_invoker. ` +
          `Re-flip with: ALTER VIEW public.${view} SET (security_invoker = true); (see #1422)`,
      );
    });
  }
});
