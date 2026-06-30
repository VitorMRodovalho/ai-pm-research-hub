// tests/contracts/965-secdef-public-grant-drift.test.mjs
//
// #965 forward-defense (ratchet): SECURITY DEFINER functions in `public` that do a
// write / http_post and are reachable by anon/PUBLIC EXECUTE through PostgREST are a
// systemic privilege-drift class (Postgres CREATE FUNCTION grants EXECUTE to PUBLIC by
// default). The worst (campaign_send_one_off open-relay) was fixed in #963; this PR
// revokes 6 verified cron/trigger/SECDEF-only side-effect functions, and installs THIS
// test so a NEW ungated PUBLIC grant fails CI (issue #965 "Proposed forward-defense").
//
// _audit_secdef_public_grant_drift() (the live sweep, has_function_privilege per-oid)
// MUST return a name-set EQUAL to the categorized allowlist below. To make this pass
// when you add such a function, do ONE of:
//   (a) add an authority gate / token check to its body (it leaves the sweep), OR
//   (b) revoke its PUBLIC/anon/authenticated EXECUTE (it leaves the sweep), OR
//   (c) add it to the allowlist below WITH a justification comment (by-design anon).
// Mechanically mass-revoking is forbidden ([LL] #588: orthogonal gates).
//
// Two layers: (A) static migration-file guard (always runs); (B) DB-aware ratchet
// (skipped without SUPABASE_URL + SERVICE_ROLE_KEY). ADR-0118.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(
  __dirname,
  '../../supabase/migrations/20260805000306_965_secdef_public_grant_drift_revoke.sql',
);
// Defensive read (684 pattern): a missing file becomes a clean assertion, not an ENOENT module crash.
const sql = existsSync(MIGRATION_PATH) ? readFileSync(MIGRATION_PATH, 'utf8') : '';

// The 6 side-effect functions revoked by this PR (cron + trigger + SECDEF-only caller graph).
const REVOKED = [
  'process_pending_email_queue()',
  'analyze_application_video_async(uuid, text, boolean)',
  'retry_pending_ai_analyses()',
  'retry_pending_ai_triages()',
  'generate_weekly_leader_digest_cron()',
  '_grant_auto_xp(text, uuid, uuid, text, boolean)',
];
const REVOKED_NAMES = ['process_pending_email_queue', 'analyze_application_video_async', 'retry_pending_ai_analyses', 'retry_pending_ai_triages', 'generate_weekly_leader_digest_cron', '_grant_auto_xp'];

// The flagged set that legitimately remains anon/PUBLIC-reachable AFTER this PR.
// Set EQUALITY is asserted below — keep this in sync as the class ratchets down.
const ALLOWLIST = new Set([
  // ── Token-gated (anon-with-token IS the design; body validates a token + RAISEs on invalid) ──
  'request_application_enrichment',       // onboarding_tokens 'profile_completion' — EnrichmentCard.tsx (#965: NOT drift)
  'opt_out_all_pillars',                  // onboarding_tokens 'video_screening' — interview opt-out flow (review F1)
  'confirm_account_claim',
  'confirm_secondary_email',
  'consume_onboarding_token',
  'give_consent_via_token',
  'revoke_consent_via_token',
  'update_application_profile_via_token',
  'update_pmi_onboarding_step',
  'validate_interview_booking_token',
  'revert_interview_optout',
  // ── Public counter / lead capture (anon by design) ──
  'capture_visitor_lead',
  'increment_blog_view',
  'increment_publication_view',
  'log_topic_view',
  // ── Own person-scoped path (by design). NOTE: the 4-arg overload still carries a leftover explicit
  //    `anon` grant (the 6-arg overload was revoked in mig 20260805000234); tracked for a dedicated
  //    caller-graph review before revoking — NOT mass-revoked here ([LL] #588). ──
  'create_initiative',
  // ── Lower-severity internal / cron helpers exposed to PostgREST (issue #965 triage). PENDING revoke —
  //    each needs its own caller-graph check (e.g. recompute_all_active_pert_cutoffs has an MCP-wrapper hint;
  //    record_milestone/register_video_screening/create_notification may have authenticated callers). Ratchet DOWN. ──
  '_audit_secdef_initiative_reader_gates',
  '_compute_pert_cutoff_core',
  '_enqueue_engagement_welcome',
  '_log_gate_attempt',
  '_recompute_application_pert',
  '_refresh_preview_gate_eligibles_for_member',
  '_sync_interview_to_event',
  'create_notification',
  'log_cron_run_complete',
  'log_cron_run_start',
  'log_mcp_usage',
  'recompute_all_active_pert_cutoffs',
  'record_milestone',
  'register_video_screening',
]);

// ─────────────────────────────────────────────────────────────────────────
// (A) Static migration-file guard — always runs
// ─────────────────────────────────────────────────────────────────────────
test('#965 migration revokes PUBLIC/anon/authenticated on the 6 side-effect fns + keeps service_role', () => {
  assert.ok(sql, `migration file missing at expected path: ${MIGRATION_PATH}`);
  for (const sig of REVOKED) {
    const esc = sig.replace(/[()]/g, '\\$&');
    assert.match(sql, new RegExp(`REVOKE EXECUTE ON FUNCTION public\\.${esc} FROM PUBLIC, anon, authenticated`), `must revoke ${sig}`);
    assert.match(sql, new RegExp(`GRANT  ?EXECUTE ON FUNCTION public\\.${esc} TO service_role`), `must keep service_role on ${sig}`);
  }
  // token-gated dispatchers must NOT be revoked here
  assert.doesNotMatch(sql, /REVOKE EXECUTE ON FUNCTION public\.request_application_enrichment/, 'token-gated request_application_enrichment must NOT be revoked');
  assert.doesNotMatch(sql, /REVOKE EXECUTE ON FUNCTION public\.opt_out_all_pillars/, 'token-gated opt_out_all_pillars must NOT be revoked');
  // forward-defense audit RPC present, has_function_privilege-based, + itself locked down
  assert.match(sql, /CREATE OR REPLACE FUNCTION public\._audit_secdef_public_grant_drift\(\)/);
  assert.match(sql, /has_function_privilege\('anon', p\.oid, 'EXECUTE'\)/);
  assert.match(sql, /REVOKE EXECUTE ON FUNCTION public\._audit_secdef_public_grant_drift\(\) FROM PUBLIC, anon, authenticated/);
});

// ─────────────────────────────────────────────────────────────────────────
// (B) DB-aware ratchet — require live DB
// ─────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function audit() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_audit_secdef_public_grant_drift`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` },
    body: JSON.stringify({}),
  });
  if (!res.ok) throw new Error(`audit RPC failed: HTTP ${res.status} — ${await res.text()}`);
  return res.json();
}

test('#965 live sweep set EQUALS the categorized allowlist (ratchet)', { skip: !canRun && skipMsg }, async () => {
  const rows = await audit();
  const live = [...new Set(rows.map((r) => r.proname))].sort();
  const allow = [...ALLOWLIST].sort();
  const newDrift = live.filter((n) => !ALLOWLIST.has(n));
  const stale = allow.filter((n) => !live.includes(n));
  assert.deepEqual(
    live, allow,
    `#965 PUBLIC-grant drift mismatch.\n` +
      `NEW ungated anon/PUBLIC grant(s) — gate, revoke, or allowlist with justification: ${JSON.stringify(newDrift)}\n` +
      `Allowlist entries no longer in the sweep (revoked OR gated elsewhere — remove from allowlist to ratchet down): ${JSON.stringify(stale)}`,
  );
});

test('#965 the 6 revoked side-effect fns are no longer anon/PUBLIC-reachable', { skip: !canRun && skipMsg }, async () => {
  const rows = await audit();
  const live = new Set(rows.map((r) => r.proname));
  for (const name of REVOKED_NAMES) {
    assert.ok(!live.has(name), `${name} must have been revoked (no longer in the anon/PUBLIC sweep)`);
  }
});
