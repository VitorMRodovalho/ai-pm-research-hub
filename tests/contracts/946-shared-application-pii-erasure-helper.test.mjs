/**
 * Contract test for #946 — unify LGPD erasure of a selection application's PII across BOTH
 * anonymization paths via a shared helper _erase_application_pii(uuid).
 *
 * Before #946: anonymize_inactive_members (the ACTIVE 5y cron, jobid 15) scrubbed only the
 * selection_applications mother row LIGHTLY (7 fields) and left ALL child-table PII + the AI/VEP/
 * profile mother-row fields + ai_calibration_runs.sample_payload applicant_name un-erased. The #905
 * pre-member path DID follow PII into children but the logic was duplicated. #946 extracts the
 * per-application erasure into a shared SECDEF helper that both anonymizers call, so erasure is
 * uniform (and adds the ai_calibration_runs.sample_payload name scrub both paths lacked).
 *
 * Two layers:
 *  (A) STATIC migration guard (always runs, offline): the regression ratchet — if a future edit
 *      removes a child-table DELETE/scrub, the helper lockdown, or a caller's helper invocation,
 *      CI fails. Non-no-op: against the pre-#946 tree (no helper, member path with only the light
 *      scrub) every assertion below fails.
 *  (B) DB-aware grant ratchet (skipped without SUPABASE_URL + SERVICE_ROLE_KEY): the helper is a
 *      SECDEF side-effect function; it MUST NOT be anon/PUBLIC-reachable (#965 / ADR-0118). It does
 *      writes and has no auth gate, so IF anon held EXECUTE it WOULD surface in the
 *      _audit_secdef_public_grant_drift() sweep — asserting its ABSENCE positively proves the
 *      REVOKE took (a check the #965 sweep-equality test alone does not make for this new fn).
 *
 * The behavioral non-no-op proof (INSERT synthetic application -> _erase_application_pii -> assert
 * scrubbed -> ROLLBACK) is run out-of-band via execute_sql (RAISE 'SMOKE_PASS' rollback pattern,
 * documented in the PR) — a multi-statement transaction is not reachable through a PostgREST RPC.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION = join(
  __dirname,
  '../../supabase/migrations/20260805000313_946_shared_application_pii_erasure_helper.sql',
);
// Defensive read (LL #684): a missing file becomes a clean assertion, not an ENOENT module crash.
const sql = existsSync(MIGRATION) ? readFileSync(MIGRATION, 'utf8') : '';

// ─────────────────────────────────────────────────────────────────────────
// (A) Static migration-file guard — always runs
// ─────────────────────────────────────────────────────────────────────────

test('#946 migration defines the shared _erase_application_pii(uuid) helper (SECDEF)', () => {
  assert.ok(sql, `migration file missing at expected path: ${MIGRATION}`);
  assert.ok(
    sql.includes('CREATE OR REPLACE FUNCTION public._erase_application_pii(p_application_id uuid)'),
    'must define _erase_application_pii(p_application_id uuid)',
  );
  assert.ok(/SECURITY\s+DEFINER/i.test(sql), 'helper must be SECURITY DEFINER');
});

test('#946 helper is locked down (REVOKE PUBLIC/anon/authenticated, keep service_role) — no #965 drift', () => {
  assert.ok(sql);
  assert.ok(
    sql.includes('REVOKE ALL ON FUNCTION public._erase_application_pii(uuid) FROM PUBLIC;'),
    'must REVOKE ALL ... FROM PUBLIC',
  );
  assert.ok(
    sql.includes('REVOKE ALL ON FUNCTION public._erase_application_pii(uuid) FROM anon, authenticated;'),
    'must REVOKE ALL ... FROM anon, authenticated',
  );
  assert.ok(
    sql.includes('GRANT EXECUTE ON FUNCTION public._erase_application_pii(uuid) TO service_role;'),
    'must keep service_role EXECUTE',
  );
});

test('#946 BOTH anonymizers are (re)defined and call the shared helper', () => {
  assert.ok(sql);
  assert.ok(
    sql.includes('CREATE OR REPLACE FUNCTION public.anonymize_inactive_members('),
    'member anonymizer must be redefined',
  );
  assert.ok(
    sql.includes('CREATE OR REPLACE FUNCTION public.anonymize_premember_applications('),
    'pre-member anonymizer must be redefined',
  );
  // both bodies must invoke the helper; expect >= 2 call sites (one per anonymizer)
  const calls = (sql.match(/public\._erase_application_pii\(/g) || []).length;
  assert.ok(calls >= 3, `expected the helper definition + >=2 call sites, found ${calls} occurrences of public._erase_application_pii(`);
});

test('#946 helper DELETEs every candidate-derived child table (biometric + 9 pure children)', () => {
  assert.ok(sql);
  const deleteTables = [
    'pmi_video_screenings',            // biometric-adjacent (transcription + Drive/YouTube)
    'ai_analysis_runs',
    'ai_processing_log',
    'ai_score_validations',
    'selection_evaluation_ai_suggestions',
    'selection_membership_snapshots',
    'selection_application_service_history',
    'selection_topic_views',
    'selection_dispatch_url_log',
    'onboarding_progress',
  ];
  for (const t of deleteTables) {
    const re = new RegExp(`DELETE\\s+FROM\\s+public\\.${t}\\s+WHERE\\s+application_id\\s*=\\s*p_application_id`, 'i');
    assert.ok(re.test(sql), `helper must DELETE FROM public.${t} WHERE application_id = p_application_id (silent erasure-scope reduction otherwise)`);
  }
});

test('#946 helper SCRUBs free-text-bearing children (keep structured scores)', () => {
  assert.ok(sql);
  // each of these is UPDATE ... WHERE application_id = p_application_id
  for (const t of ['selection_evaluations', 'selection_interviews', 'gate_attempts', 'selection_evaluation_anomalies']) {
    const re = new RegExp(`UPDATE\\s+public\\.${t}[\\s\\S]*?WHERE\\s+application_id\\s*=\\s*p_application_id`, 'i');
    assert.ok(re.test(sql), `helper must scrub public.${t} by application_id`);
  }
  // mother-row scrub sets the sentinel name + the anonymized_at marker
  assert.ok(/UPDATE\s+public\.selection_applications\s+SET/i.test(sql), 'helper must scrub the selection_applications mother row');
  assert.ok(sql.includes("applicant_name = 'Candidato Anonimizado'"), 'mother row must set the anonymized sentinel name');
  assert.ok(/anonymized_at\s*=\s*now\(\)/i.test(sql), 'mother row must stamp anonymized_at');
});

test('#946 helper scrubs ai_calibration_runs.sample_payload applicant_name (keeps scores)', () => {
  assert.ok(sql);
  assert.ok(/UPDATE\s+public\.ai_calibration_runs/i.test(sql), 'must UPDATE ai_calibration_runs');
  assert.ok(sql.includes("jsonb_build_object('applicant_name', 'Candidato Anonimizado')"), 'must overwrite applicant_name in the jsonb element');
  assert.ok(sql.includes("e->>'application_id' = p_application_id::text"), 'must match array elements by application_id');
  // the numeric calibration keys must NOT be nulled — the scrub keeps them (merge overwrites only applicant_name)
  assert.ok(!/human_score_normalized\s*=\s*NULL/i.test(sql), 'must not null the calibration scores');
});

test('#946 member path resolves applications by email, snapshots ids, and guards the FOREACH', () => {
  assert.ok(sql);
  assert.ok(
    /SELECT\s+array_agg\(id\)\s+INTO\s+v_app_ids[\s\S]*?WHERE\s+email\s*=\s*v_candidate\.email/i.test(sql),
    'member path must snapshot application ids by the candidate email before the loop',
  );
  assert.ok(/IF\s+v_app_ids\s+IS\s+NOT\s+NULL\s+THEN/i.test(sql), 'FOREACH must be guarded by IF v_app_ids IS NOT NULL');
  assert.ok(/FOREACH\s+v_app_id\s+IN\s+ARRAY\s+v_app_ids/i.test(sql), 'must FOREACH over the snapshotted id array');
});

test('#946 member path preserves the #976 IP-license CONTINUE guard and the #625 affiliation scrub', () => {
  assert.ok(sql);
  // #976 PR-4: skip members holding a current IP-license signature
  assert.ok(sql.includes('member_document_signatures'), '#976 license guard must be preserved');
  assert.ok(/mds\.is_current\s*=\s*true/i.test(sql), '#976 must check signature is_current');
  assert.ok(sql.includes('lgpd.anonymization_deferred_ip_license'), '#976 DPO-visibility audit action must be preserved');
  // #625: affiliation verification de-identification
  assert.ok(sql.includes('member_affiliation_verifications'), '#625 affiliation scrub must be preserved');
});

test('#946 both return shapes expose the new calibration counter (additive, no keys removed)', () => {
  assert.ok(sql);
  const occ = (sql.match(/calibration_runs_scrubbed_total/g) || []).length;
  assert.ok(occ >= 2, `calibration_runs_scrubbed_total must appear in both anonymizer return payloads, found ${occ}`);
  // pre-existing keys must remain (spot-check the ones a cron/consumer might read)
  assert.ok(sql.includes('resume_objects_deleted_total'), 'resume_objects_deleted_total return key preserved');
  assert.ok(sql.includes("'license_preserved'"), '#976 license_preserved return key preserved (member path)');
});

// ─────────────────────────────────────────────────────────────────────────
// (B) DB-aware grant ratchet — require live DB
// ─────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

test('#946 _erase_application_pii is NOT anon/PUBLIC-reachable (absent from the #965 SECDEF sweep)', { skip: !canRun && skipMsg }, async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_audit_secdef_public_grant_drift`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` },
    body: JSON.stringify({}),
  });
  assert.ok(res.ok, `audit RPC failed: HTTP ${res.status}`);
  const rows = await res.json();
  const names = new Set(rows.map((r) => r.proname));
  assert.ok(
    !names.has('_erase_application_pii'),
    '_erase_application_pii is a SECDEF side-effect fn — its presence in the sweep means anon holds EXECUTE (revoke it). It must be absent.',
  );
});
