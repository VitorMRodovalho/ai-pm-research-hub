/**
 * Contract: #472 correction #5 — selection-pipeline CONSISTENCY / DETECTION cron.
 *
 * Complements corr-4 (recompute auto-heal): selection_consistency_report(p_cycle_id)
 * surfaces the divergences recompute can't auto-fix + data-integrity anomalies, and
 * _selection_consistency_cron() writes a daily report to admin_audit_log and alerts
 * leads ONLY on high-confidence integrity anomalies (never on the noisy dispatch gap,
 * which the email-campaign path legitimately bypasses).
 *
 * Cross-ref: issue #472 (B6 + the consistency-check opportunity); migration
 * 20260805000090 (corr-4 recompute, the sibling cron pattern); 20260805000097.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000097_472_corr5_selection_consistency_cron.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const mig = migRaw.replace(/^\s*--.*$/gm, ''); // strip line comments for body asserts

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

function fnBody(src, name) {
  const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\b[\\s\\S]*?\\$function\\$([\\s\\S]*?)\\$function\\$`, 'i');
  const m = src.match(re);
  return m ? m[1] : null;
}

// ── STATIC ──────────────────────────────────────────────────────────────────
test('472-c5 static: migration 20260805000097 exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000097 present');
});

test('472-c5 static: report computes the total as a DEDUPLICATED distinct-app count, not a sum', () => {
  const body = fnBody(mig, 'selection_consistency_report');
  assert.ok(body, 'selection_consistency_report defined');
  // the headline total must be the distinct count + bookings, NOT the overlapping sum
  assert.match(body, /'integrity_anomaly_total',\s*\(v_distinct_apps \+ v_e_n\)/,
    'total = distinct apps (A/B/C/D dedup) + unmatched bookings (E)');
  assert.match(body, /'has_integrity_anomaly',\s*\(v_distinct_apps \+ v_e_n\) > 0/, 'flag derives from the deduped total');
  // forward-defense: the naive double-counting sum must NOT come back
  assert.ok(!/v_a_n \+ v_b_n \+ v_c_n \+ v_d_n \+ v_e_n/.test(body),
    'REGRESSION: total summed overlapping per-class counts (B ⊆ D → double-count)');
  assert.match(body, /count\(DISTINCT o\.id\) INTO v_distinct_apps/, 'distinct-app count computed over the union of A/B/C/D predicates');
});

test('472-c5 static: dispatch gap is informational-only and scoped to links-still-needed', () => {
  const body = fnBody(mig, 'selection_consistency_report');
  // narrowed to the two statuses where the link still matters
  assert.match(body, /a\.status IN \('interview_pending','interview_scheduled'\)\s*\n?\s*AND NOT EXISTS \(SELECT 1 FROM public\.selection_dispatch_url_log/,
    'dispatch gap scoped to interview_pending/interview_scheduled (interview_done/final_eval excluded)');
  // never folded into the integrity total / alert
  assert.match(body, /'dispatch_gap_informational'/, 'dispatch gap reported under an informational key');
  assert.ok(!/v_disp_n/.test(fnBody(mig, '_selection_consistency_cron')),
    'cron must NOT read the dispatch-gap count (never alerts on it)');
});

test('472-c5 static: interview_phase_no_row excludes final_eval (manual off-platform final is legit)', () => {
  const body = fnBody(mig, 'selection_consistency_report');
  assert.match(body, /a\.status IN \('interview_scheduled','interview_done'\)/,
    'anomaly C limited to interview_scheduled/interview_done — final_eval excluded (recompute-legitimate)');
});

test('472-c5 static: cron alerts leads ONLY when integrity total > 0; always records the report', () => {
  const cron = fnBody(mig, '_selection_consistency_cron');
  assert.ok(cron, '_selection_consistency_cron defined');
  assert.match(cron, /INSERT INTO public\.admin_audit_log[\s\S]*?'selection\.consistency_check'/, 'always records the report (observability)');
  assert.match(cron, /IF v_total > 0 THEN/, 'alerts gated on integrity anomalies present');
  assert.match(cron, /sc\.role = 'lead'/, 'notifies open/active cycle leads');
});

test('472-c5 static: grant ladder — SERVICE_ROLE ONLY on both functions (minimal privilege)', () => {
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.selection_consistency_report\(uuid\) FROM PUBLIC, anon, authenticated/, 'report: anon+authenticated revoked');
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.selection_consistency_report\(uuid\) TO service_role\b/, 'report: service_role only');
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\.selection_consistency_report\(uuid\)[^;]*\bauthenticated\b/.test(mig),
    'REGRESSION: report granted to authenticated (applicant_name PII enumeration surface)');
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\._selection_consistency_cron\(\) TO service_role/, 'cron: service_role only');
});

test('472-c5 static: SECURITY DEFINER + search_path + manage_platform gate + cron schedule', () => {
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.selection_consistency_report[\s\S]*?SECURITY DEFINER[\s\S]*?SET search_path TO 'public', 'pg_temp'/);
  assert.match(fnBody(mig, 'selection_consistency_report'), /can_by_member\(v_caller_id, 'manage_platform'\)/, 'authenticated callers gated on manage_platform');
  assert.match(mig, /cron\.schedule\(\s*\n?\s*'selection-consistency-check-daily',\s*\n?\s*'30 13 \* \* \*'/, 'daily 13:30 UTC, after the 13:00 recompute');
});

test('472-c5 static: selection_topic_views documented (NOT dropped — live committee feature)', () => {
  assert.match(mig, /COMMENT ON TABLE public\.selection_topic_views IS/, 'table documented, not dropped');
  assert.ok(!/DROP TABLE[\s\S]*selection_topic_views/i.test(mig), 'selection_topic_views must NOT be dropped (live RLS committee feature)');
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/);
});

// ── BEHAVIOURAL (DB-gated) ───────────────────────────────────────────────────
test('472-c5 behavioural: report is callable and returns the expected shape (read-only)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('selection_consistency_report', { p_cycle_id: null });
  assert.ifError(error);
  assert.equal(data?.success, true);
  assert.ok(data.integrity_anomalies?.scored_not_advanced, 'integrity_anomalies block present');
  assert.equal(typeof data.integrity_anomaly_total, 'number', 'deduped total present');
  assert.equal(typeof data.affected_applications_distinct, 'number', 'distinct-app headline present');
  assert.ok(data.dispatch_gap_informational?.qualified_no_dispatch_log, 'dispatch gap reported as informational');
  // the deduped total can never exceed the naive per-class sum
  const ia = data.integrity_anomalies;
  const naiveSum = ia.scored_not_advanced.count + ia.interview_completed_app_behind.count +
    ia.interview_phase_no_row.count + ia.orphan_interview_row.count + ia.unmatched_calendar_bookings_7d.count;
  assert.ok(data.integrity_anomaly_total <= naiveSum, 'deduped total <= naive per-class sum (no double-count inflation)');
});
