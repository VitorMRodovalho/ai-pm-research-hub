/**
 * #420 — Bucket-A metric defects regression-lock (STATIC).
 *
 * SEDIMENT-244.A: #420's defects were verified live (2026-06-04) to be ALREADY
 * FIXED by the #419 M3 canonical-attendance refactor (stale readiness tag). This
 * locks the fixes against regression at the migration-file level (the live body is
 * separately guaranteed to match the file by the Phase-C md5 drift gate in CI).
 *
 *   - D14 get_dropout_risk_members: no longer matches ENGLISH event-type tokens
 *         (live events.type is 100% Portuguese); derives eligible events from the
 *         canonical _attendance_eligible_events helper + presence via present IS TRUE.
 *         Previously returned 0 rows always (dead alert).
 *   - D6  get_attendance_grid: present_count counts the 'present' status bucket
 *         (cs.status='present', which requires a.present=true) — NOT bare row-existence.
 *   - D12 get_events_with_attendance.attendee_count filters a.present = true.
 *
 * D10 (exec_portfolio_health hardcoded 'cycle3-2026' default) is NOT a data bug —
 * cycle3-2026 is the only/current portfolio_kpi_targets cycle + a most-recent fallback
 * exists; left as documented maintainability, not locked here.
 *
 * Static (migration files, comments stripped, latest-declarer) — reliable and offline.
 * NOTE: an earlier draft used `_audit_list_public_function_bodies` via PostgREST, but
 * that RPC takes NO args and returns body_md5/prosrc_len (not prosrc) — it can't surface
 * the body for these checks. The static + Phase-C combination is the correct guard.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const MIG_DIR = resolve(process.cwd(), 'supabase/migrations');
const stripComments = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

// the comment-stripped body of the LATEST migration that declares `fnName` (robust to re-declaration)
function latestDeclarerCode(fnName) {
  const files = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort();
  const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fnName}\\b`);
  const decls = files.filter((f) => re.test(readFileSync(join(MIG_DIR, f), 'utf8')));
  assert.ok(decls.length >= 1, `${fnName}: at least one declaring migration`);
  const file = decls[decls.length - 1];
  return { file, code: stripComments(readFileSync(join(MIG_DIR, file), 'utf8')) };
}

test('D14: get_dropout_risk_members has no English event-type tokens + uses the canonical eligible-events helper', () => {
  const { file, code } = latestDeclarerCode('get_dropout_risk_members');
  for (const tok of ['general_meeting', 'tribe_meeting', 'leadership_meeting']) {
    assert.ok(!code.includes(tok),
      `${file}: must not match the English event-type token '${tok}' (live events.type is Portuguese — caused 0 rows always)`);
  }
  assert.match(code, /_attendance_eligible_events/, `${file}: must derive eligible events from the canonical helper`);
  assert.match(code, /present IS TRUE/i, `${file}: must detect presence via present IS TRUE`);
});

test("D6: get_attendance_grid present_count counts status='present' (which requires a.present=true)", () => {
  const { file, code } = latestDeclarerCode('get_attendance_grid');
  assert.match(code, /FILTER \(WHERE cs\.status = 'present'\)/, `${file}: present_count must count the 'present' status bucket`);
  assert.match(code, /a\.present/, `${file}: the 'present' status classification must require a.present`);
});

test('D12: get_events_with_attendance.attendee_count filters a.present = true', () => {
  const { file, code } = latestDeclarerCode('get_events_with_attendance');
  assert.match(code, /a\.present = true\) AS attendee_count/,
    `${file}: attendee_count must count only present=true rows (not all attendance rows incl absent/excused)`);
});

// ── #420 follow-up (2026-05-31 comment): 3 present-blind consumers (mig 20260805000122) ──
// get_public_impact_data + get_member_attendance_hours summed/counted attendance without filtering
// present=true (registered-but-absent rows inflated hours by 78.5h: impact 1656→1577.5, total 896→817.7).
// (get_admin_dashboard's dropout present-blindness + dead detractor query were the deferred 3rd
//  consumer — now resolved by #555 / mig 20260805000123; locked below.)

test('#420 follow-up: get_member_attendance_hours filters a.present (streak EXISTS + hours aggregate)', () => {
  const { file, code } = latestDeclarerCode('get_member_attendance_hours');
  assert.match(code, /EXISTS\(SELECT 1 FROM public\.attendance a WHERE a\.event_id = e\.id AND a\.member_id = p_member_id AND a\.present\)/,
    `${file}: streak presence-EXISTS must require a.present (not bare attendance-row existence)`);
  assert.match(code, /WHERE a\.member_id = p_member_id AND a\.present/,
    `${file}: total_hours/total_events aggregate must filter a.present (absent rows earn no hours/credit)`);
});

test('#420 follow-up: get_public_impact_data hours metrics filter a.present', () => {
  const { file, code } = latestDeclarerCode('get_public_impact_data');
  assert.match(code, /WHERE e\.date >= '2026-03-01' AND a\.present/,
    `${file}: total_attendance_hours must filter a.present`);
  assert.match(code, /FROM attendance a JOIN events e ON e\.id = a\.event_id\s+WHERE a\.present/,
    `${file}: impact_hours must filter a.present`);
});

// ── #555 (deferred 3rd consumer from #420/#554; mig 20260805000123) ──
// get_admin_dashboard had TWO present-blind/broken attendance alerts deferred by mig ...122's header.

test('#555: get_admin_dashboard dropout alert filters a.present (Option A) + detractor alert revived (no dead self-negating query)', () => {
  const { file, code } = latestDeclarerCode('get_admin_dashboard');
  // Part 1 — dropout-risk 60d subquery must exclude only members who were actually PRESENT
  // (no-shows now count as at-risk; PM Option A 2026-06-07).
  assert.match(code, /WHERE e\.date > now\(\) - interval '60 days'\s+AND a\.present IS TRUE/,
    `${file}: dropout-risk alert must add the present-filter (registered no-shows count as at-risk)`);
  // Part 2 — detractor alert must use the canonical present-aware eligible-events streak ...
  assert.match(code, /_attendance_eligible_events/,
    `${file}: detractor alert must derive eligible events from the canonical helper`);
  // ... and must NOT contain the dead self-negating NOT EXISTS anti-pattern that never fired.
  assert.ok(!code.includes('NOT EXISTS (SELECT 1 FROM public.attendance ax'),
    `${file}: the dead self-negating detractor NOT EXISTS must be gone (it never matched any data)`);
});
