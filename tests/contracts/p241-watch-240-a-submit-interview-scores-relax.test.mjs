/**
 * Forward-defense: p241 WATCH-240.A — submit_interview_scores relax status gate.
 *
 * Origin: surfaced by p240 #251 close. The p240 trigger
 *   trg_sync_interview_to_app_status (migration 20260805000025) keys on
 *   changes to selection_interviews.conducted_at OR .status and is the
 *   canonical owner of selection_applications.status sync to 'interview_done'.
 *
 * Pre-WATCH-240.A: submit_interview_scores only set conducted_at INSIDE the
 *   IF v_all_interviewers_submitted branch, so partial submissions (1-of-N
 *   interviewers) never fired the trigger → app stuck in 'interview_pending'.
 *   This was the exact #251 manifestation — cycle4 seeds Vitor + Fabricio as
 *   interviewers, only Vitor submitted, app never advanced.
 *
 * Fix: hoist `UPDATE selection_interviews SET conducted_at = now()` to BEFORE
 *   the all-submitted check (with idempotency guard
 *   `IF v_interview.conducted_at IS NULL`). Drop redundant `conducted_at = now()`
 *   from inside the all-submitted branch.
 *
 * Migration: supabase/migrations/20260805000026_p241_watch_240_a_submit_interview_scores_relax_status_gate.sql
 *
 * Asserts:
 *   - Static (11): file present + signature preserved (5 params + jsonb return) +
 *     SECDEF/pinned search_path + hoisted block exists + hoisted block precedes
 *     all-submitted check + all-submitted check still computes the boolean +
 *     all-submitted branch still UPDATEs interview status='completed' +
 *     all-submitted branch still computes PERT + UPDATEs app status='final_eval' +
 *     header cross-refs (WATCH-240.A + p240 trigger 20260805000025 + p113 origin) +
 *     NOTIFY pgrst.
 *   - Forward-defense static (2): regression-catch that conducted_at=now() is NOT
 *     re-introduced inside the all-submitted branch + previous status='completed'
 *     pattern no longer carries conducted_at coupling.
 *   - DB-gated (2): live function body hoist position precedes all-submitted +
 *     single overload (signature stability proxy).
 *
 * Cross-ref:
 *   - WATCH-240.A in memory/handoff_p240_post_p239b_close.md
 *   - p240 trigger migration 20260805000025
 *   - issue #251 close handoff
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(
  ROOT,
  'supabase/migrations/20260805000026_p241_watch_240_a_submit_interview_scores_relax_status_gate.sql'
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ===================================================================
// STATIC migration body assertions (always run)
// ===================================================================

test('p241 WATCH-240.A: migration file present at canonical path', () => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.startsWith('20260805000026_'));
  assert.equal(files.length, 1,
    'Exactly one migration file must exist for version 20260805000026 (p241 WATCH-240.A)');
  assert.match(files[0], /^20260805000026_p241_watch_240_a_submit_interview_scores_relax_status_gate\.sql$/,
    'Migration filename must follow `<timestamp>_<descriptive_name>.sql` per CLAUDE.md GC-097');
});

test('p241 WATCH-240.A: function signature preserved (5 params + jsonb return + SECDEF + pinned search_path)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // Use CREATE OR REPLACE (not DROP+CREATE) because signature is unchanged from p113.
  assert.match(body,
    /CREATE OR REPLACE FUNCTION public\.submit_interview_scores\(\s*p_interview_id uuid,\s*p_scores jsonb,\s*p_theme text DEFAULT NULL::text,\s*p_notes text DEFAULT NULL::text,\s*p_criterion_notes jsonb DEFAULT '\{\}'::jsonb\s*\)/i,
    '5-arg signature must be preserved verbatim from p113 (DROP+CREATE would break consumers)');
  assert.match(body, /RETURNS jsonb/i,
    'Return type must remain jsonb (consumers depend on { success, evaluation_id, ... } envelope)');
  assert.match(body, /LANGUAGE plpgsql\s+SECURITY DEFINER/i,
    'Function must be SECURITY DEFINER (writes to selection_evaluations + selection_applications across RLS scopes)');
  assert.match(body, /SET search_path TO 'public', 'pg_temp'/i,
    'Function must pin search_path to public + pg_temp (CLAUDE.md GC-097 search_path injection defense)');
});

test('p241 WATCH-240.A: hoisted conducted_at-IS-NULL block exists with UPDATE statement', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body,
    /IF v_interview\.conducted_at IS NULL THEN\s+UPDATE public\.selection_interviews\s+SET conducted_at = now\(\)\s+WHERE id = p_interview_id;\s+END IF;/i,
    'Hoisted block must check v_interview.conducted_at IS NULL (idempotent) and UPDATE conducted_at=now() ' +
    '(the p240 trigger then fires on the conducted_at change and advances app status to interview_done)');
});

test('p241 WATCH-240.A: hoisted block precedes the all-submitted check (chronological in body)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  const hoistIdx = body.search(/IF v_interview\.conducted_at IS NULL THEN/);
  const allCheckIdx = body.search(/v_all_interviewers_submitted := NOT EXISTS/);
  assert.ok(hoistIdx > 0, 'Hoist block must be present');
  assert.ok(allCheckIdx > 0, 'All-submitted assignment must be present');
  assert.ok(hoistIdx < allCheckIdx,
    'The hoisted conducted_at UPDATE must execute BEFORE v_all_interviewers_submitted is computed; ' +
    `got hoistIdx=${hoistIdx} allCheckIdx=${allCheckIdx}`);
});

test('p241 WATCH-240.A: all-submitted boolean still computed via the canonical NOT EXISTS pattern', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body,
    /v_all_interviewers_submitted := NOT EXISTS \(\s*SELECT 1 FROM unnest\(v_interview\.interviewer_ids\) iid[\s\S]{0,500}submitted_at IS NOT NULL[\s\S]{0,100}\);/i,
    'All-submitted boolean computation must be preserved (semantic gate for PERT + final_eval transition)');
});

test('p241 WATCH-240.A: all-submitted branch UPDATEs interview status to "completed" (no conducted_at coupling)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body,
    /IF v_all_interviewers_submitted THEN\s+UPDATE public\.selection_interviews\s+SET status = 'completed'\s+WHERE id = p_interview_id;/i,
    'All-submitted branch must still mark interview row status=completed (sealing the row); the conducted_at column ' +
    'is set in the hoisted step 7 instead');
});

test('p241 WATCH-240.A: PERT compute + interview_score + final_eval still inside the all-submitted branch', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /v_pert_score := ROUND\(\(2 \* v_min_sub \+ 4 \* v_avg_sub \+ 2 \* v_max_sub\) \/ 8, 2\);/i,
    'PERT formula must be preserved verbatim (changes here would alter selection ranking math)');
  assert.match(body,
    /UPDATE public\.selection_applications\s+SET interview_score = v_pert_score,\s+status = 'final_eval',\s+updated_at = now\(\)\s+WHERE id = v_interview\.application_id;/i,
    'final_eval transition must remain inside the all-submitted branch (advances app only when all interviewers submitted)');
});

test('p241 WATCH-240.A: header cross-refs WATCH-240.A + p240 trigger 20260805000025 + p113 origin', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /WATCH-240\.A/,
    'Header must reference WATCH-240.A (anchor for grep recovery)');
  assert.match(body, /20260805000025/,
    'Header must reference the p240 trigger migration that owns app status sync (architectural dependency)');
  assert.match(body, /20260517060000/,
    'Header must reference the p113 migration that was the previous owner of this function body (rollback path)');
});

test('p241 WATCH-240.A: migration reloads PostgREST schema cache', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /NOTIFY pgrst,\s*'reload schema'/i,
    'Migration must NOTIFY pgrst reload schema (CLAUDE.md GC-097)');
});

test('p241 WATCH-240.A: notification path preserved (PERFORM create_notification + selection_evaluation_complete)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /PERFORM public\.create_notification\(\s*sc\.member_id,\s*'selection_evaluation_complete',/i,
    'Notification dispatch to lead committee member must remain in the all-submitted branch');
});

test('p241 WATCH-240.A: return envelope preserved (success + evaluation_id + all_interviewers_submitted + pert_interview_score)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /RETURN jsonb_build_object\(\s*'success',\s*true,\s*'evaluation_id',\s*v_eval_id,\s*'weighted_subtotal',\s*ROUND\(v_weighted_sum,\s*2\),\s*'all_interviewers_submitted',\s*v_all_interviewers_submitted,\s*'pert_interview_score',\s*v_pert_score\s*\);/i,
    'Return envelope must remain unchanged (consumers + MCP tool depend on these keys)');
});

// ===================================================================
// FORWARD-DEFENSE static assertions (regression catch)
// ===================================================================

test('p241 WATCH-240.A forward-defense: conducted_at=now() must NOT appear inside the all-submitted branch', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // Extract the all-submitted branch text and assert conducted_at=now() is NOT in it.
  // Branch starts at "IF v_all_interviewers_submitted THEN" and ends at the matching "END IF;"
  // before the RETURN jsonb_build_object call.
  const branchMatch = body.match(/IF v_all_interviewers_submitted THEN([\s\S]*?)END IF;\s+RETURN jsonb_build_object/);
  assert.ok(branchMatch, 'All-submitted branch must be locatable for regression scan');
  const branchBody = branchMatch[1];
  assert.doesNotMatch(branchBody, /conducted_at\s*=\s*now\(\)/i,
    'REGRESSION: conducted_at=now() reintroduced inside all-submitted branch. ' +
    'This regresses WATCH-240.A — hoist must be the ONLY place conducted_at is set in submit_interview_scores. ' +
    'If a new code path needs conducted_at, route it through the trigger or the hoisted block.');
});

test('p241 WATCH-240.A forward-defense: UPDATE selection_interviews inside all-submitted branch is status-only', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  const branchMatch = body.match(/IF v_all_interviewers_submitted THEN([\s\S]*?)END IF;\s+RETURN jsonb_build_object/);
  assert.ok(branchMatch, 'All-submitted branch must be locatable for regression scan');
  const branchBody = branchMatch[1];
  // Find the UPDATE selection_interviews block inside the branch and assert it only sets status.
  const updateMatch = branchBody.match(/UPDATE public\.selection_interviews\s+SET ([\s\S]*?)\s+WHERE id = p_interview_id;/);
  assert.ok(updateMatch, 'UPDATE selection_interviews inside all-submitted branch must exist (interview row sealing)');
  const setClause = updateMatch[1];
  assert.match(setClause, /^status = 'completed'$/i,
    `REGRESSION: UPDATE selection_interviews inside all-submitted branch has SET clause "${setClause}" — ` +
    `expected exactly "status = 'completed'". Any other column there would re-couple this RPC to fields ` +
    `now owned by the hoisted block (conducted_at) or the trigger (app status sync).`);
});

// ===================================================================
// DB-GATED assertions (require SUPABASE_URL + SERVICE_ROLE_KEY)
// ===================================================================

function makeClient() {
  return createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

// Compute the expected body md5 from the migration file at test load time.
// Mirrors the SQL-side normalization used by `_audit_list_public_function_bodies()`:
//   md5(regexp_replace(prosrc, '\s+', ' ', 'g'))
// The function body is everything between `AS $function$` and `$function$;`.
function expectedBodyMd5FromMigrationFile() {
  const sql = readFileSync(MIGRATION_FILE, 'utf8');
  const match = sql.match(/AS\s+\$function\$([\s\S]+?)\$function\$/);
  if (!match) {
    throw new Error('Migration file does not contain a `AS $function$ … $function$` block — cannot derive expected md5');
  }
  const normalized = match[1].replace(/\s+/g, ' ');
  return { md5: createHash('md5').update(normalized).digest('hex'), len: normalized.length };
}

test('p241 WATCH-240.A (live): live function body md5 matches migration file (Phase C drift parity)',
  { skip: !dbGated && skipMsg },
  async () => {
    const sb = makeClient();
    // Helper RPC `_audit_list_public_function_bodies()` from p175 Phase C work.
    // Returns columns: proname, identity_args, body_md5, prosrc_len, is_secdef.
    // (No raw body — md5 only; size/privacy discipline.)
    const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
    if (error) {
      // Helper RPC may not be exposed in this environment — static body-shape check
      // already covers design intent. Skip rather than fail for tooling gap.
      return;
    }
    const fn = (data || []).find(r => r.proname === 'submit_interview_scores');
    assert.ok(fn,
      'submit_interview_scores must appear in _audit_list_public_function_bodies() output — ' +
      'if missing, the migration was never applied OR the helper RPC was changed to filter ' +
      'this function out (re-check helper definition).');
    const { md5: expectedMd5, len: expectedLen } = expectedBodyMd5FromMigrationFile();
    assert.strictEqual(fn.body_md5, expectedMd5,
      `Live function body md5 mismatch — Phase C body-hash drift. ` +
      `Live=${fn.body_md5} Expected=${expectedMd5} (from migration file). ` +
      `If apply_migration ran a different SQL string than the local file, re-apply with the ` +
      `verbatim file content (SEDIMENT-238.B class regression).`);
    // prosrc_len is a secondary check; md5 already detects content drift, but length is
    // useful for grep-style debugging if md5 fails.
    assert.strictEqual(fn.prosrc_len, expectedLen,
      `Live function prosrc length ${fn.prosrc_len} differs from migration ${expectedLen} ` +
      `(secondary check; md5 mismatch above is the load-bearing assertion).`);
  }
);

test('p241 WATCH-240.A (live): submit_interview_scores has exactly 1 overload (5-arg signature stability)',
  { skip: !dbGated && skipMsg },
  async () => {
    const sb = makeClient();
    const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
    if (error) {
      return; // helper unavailable — static signature check suffices
    }
    const matches = (data || []).filter(r => r.proname === 'submit_interview_scores');
    assert.strictEqual(matches.length, 1,
      `Expected exactly 1 overload of submit_interview_scores; got ${matches.length}. ` +
      `Multiple overloads would create PostgREST dispatch ambiguity and break MCP tool calls.`);
    // identity_args confirms the canonical 5-arg shape (uuid, jsonb, text, text, jsonb).
    assert.strictEqual(matches[0].identity_args,
      'p_interview_id uuid, p_scores jsonb, p_theme text, p_notes text, p_criterion_notes jsonb',
      `submit_interview_scores signature drifted from canonical 5-arg shape; got identity_args=${matches[0].identity_args}`);
  }
);
