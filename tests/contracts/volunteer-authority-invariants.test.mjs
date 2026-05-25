/**
 * Issue #180 / p204 — V4 graph invariants for volunteer authority (static contract)
 *
 * Verifies that `check_schema_invariants()` defines TWO new invariants:
 *   R_approved_application_has_member — status=approved must map to a member row
 *   S_approved_member_has_person_id   — approved member must be V4-graph-anchored
 *
 * Both are forward-defenses against bypass of the canonical
 * `approve_selection_application()` RPC introduced in Issue #179. Production
 * baseline at p204 close: both invariants 0 violations.
 *
 * Scope note: status='converted' is INTENTIONALLY out-of-scope for R. The 1
 * converted-without-member case in production (Adalberto Neris) is an explicit
 * non-active state documented in `conversion_reason`. See migration header.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => ({ name: f, content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8') }));
}

function findFunctionBody(funcName, sql) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  const matches = [...sql.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][2] : null;
}

const migrations = loadAllMigrations();
const allSQL = migrations.map(m => m.content).join('\n');
const checkBody = findFunctionBody('check_schema_invariants', allSQL);

// ─── 1. Both new invariants are defined in the latest body ───
test('check_schema_invariants includes R_approved_application_has_member', () => {
  assert.ok(checkBody, 'check_schema_invariants function body must be present');
  assert.ok(/'R_approved_application_has_member'::text/.test(checkBody),
    'Missing R invariant label. Did the latest migration regress check_schema_invariants?');
});

test('check_schema_invariants includes S_approved_member_has_person_id', () => {
  assert.ok(/'S_approved_member_has_person_id'::text/.test(checkBody),
    'Missing S invariant label');
});

// Helper: capture the WITH-drift-AS block immediately preceding the labelled SELECT.
// (Non-greedy regex would match from A1's WITH all the way to R's SELECT, picking up
// every interim invariant body and breaking scope assertions.)
function captureInvariantBlock(label) {
  const labelIdx = checkBody.indexOf(`'${label}'::text`);
  if (labelIdx < 0) return null;
  const upToLabel = checkBody.slice(0, labelIdx);
  const withIdx = upToLabel.lastIndexOf('WITH drift AS (');
  if (withIdx < 0) return null;
  return checkBody.slice(withIdx, labelIdx);
}

// ─── 2. R correctly scopes to status=approved only (NOT converted) ───
test('R invariant scopes to status=approved only — converted is intentionally excluded', () => {
  const rWith = captureInvariantBlock('R_approved_application_has_member');
  assert.ok(rWith, 'R WITH drift block not found');
  assert.ok(/a\.status\s*=\s*'approved'/.test(rWith),
    'R must filter on status=\'approved\' (singular, not approved/converted)');
  assert.ok(!/'converted'/.test(rWith),
    'R must NOT include status=\'converted\' — that\'s a dual-track conversion offer state, see migration header');
});

// ─── 3. R uses case-insensitive email lookup ───
test('R uses lower(email) for case-insensitive member match', () => {
  const rWith = captureInvariantBlock('R_approved_application_has_member');
  assert.ok(/lower\(m\.email\)\s*=\s*lower\(a\.email\)/.test(rWith),
    'R must match by lower(m.email) = lower(a.email)');
});

// ─── 4. S checks person_id NOT NULL on members of approved applications ───
test('S checks members.person_id IS NULL for approved members', () => {
  const sWith = captureInvariantBlock('S_approved_member_has_person_id');
  assert.ok(sWith, 'S WITH drift block not found');
  assert.ok(/a\.status\s*=\s*'approved'/.test(sWith),
    'S must filter applications by status=approved');
  assert.ok(/m\.person_id IS NULL/.test(sWith),
    'S must detect person_id IS NULL on the joined member');
});

// Helper: capture the SELECT projection (label + description + severity) for a labelled invariant
function captureInvariantSelect(label) {
  const re = new RegExp(`'${label}'::text,([\\s\\S]+?)FROM drift`);
  const m = re.exec(checkBody);
  return m ? m[1] : null;
}

// ─── 5. Both invariants are 'high' severity (V4 graph integrity is critical) ───
test('R and S are tagged high severity', () => {
  const rSel = captureInvariantSelect('R_approved_application_has_member');
  const sSel = captureInvariantSelect('S_approved_member_has_person_id');
  assert.ok(/'high'::text/.test(rSel), 'R must be high severity');
  assert.ok(/'high'::text/.test(sSel), 'S must be high severity');
});

// ─── 6. Invariants reference Issue #180 in description (auditability) ───
test('R and S descriptions reference Issue #180 for traceability', () => {
  const rSel = captureInvariantSelect('R_approved_application_has_member');
  const sSel = captureInvariantSelect('S_approved_member_has_person_id');
  assert.ok(/#180/.test(rSel), 'R description must reference Issue #180');
  assert.ok(/#180/.test(sSel), 'S description must reference Issue #180');
});

// ─── 7. R description references the canonical RPC from #179 (forward-defense framing) ───
test('R description names approve_selection_application as the canonical contract being defended', () => {
  const rSel = captureInvariantSelect('R_approved_application_has_member');
  assert.ok(/approve_selection_application/.test(rSel),
    'R must reference approve_selection_application (the canonical RPC it defends)');
});

// ─── 8. Function COMMENT cites the new count (20 invariants — V' added p256) ───
test('check_schema_invariants COMMENT cites 20 invariants', () => {
  // Multiple migrations may COMMENT ON the function; pick the LATEST
  // (highest-timestamp migration that sets the comment).
  const commentMatches = [...allSQL.matchAll(/COMMENT ON FUNCTION public\.check_schema_invariants\(\)\s+IS\s+'([^']+)'/g)];
  assert.ok(commentMatches.length > 0, 'COMMENT ON FUNCTION must be set in some migration');
  const latest = commentMatches[commentMatches.length - 1];
  assert.ok(/20 schema invariants/i.test(latest[1]),
    'Latest COMMENT must reflect the new count (19 → 20); got: ' + latest[1].slice(0, 80));
  assert.ok(/V_prime|Wave 1a|#315/.test(latest[1]),
    'Latest COMMENT must reference V_prime / Wave 1a / #315 as the source of V prime');
});

// ─── 9. Invariant block ordering: R + S come after the original 16 ───
test('R appears AFTER the original Q invariant (preserves naming order)', () => {
  const qIndex = checkBody.indexOf("'Q_expired_engagement_end_date'");
  const rIndex = checkBody.indexOf("'R_approved_application_has_member'");
  const sIndex = checkBody.indexOf("'S_approved_member_has_person_id'");
  assert.ok(qIndex > 0, 'Q invariant must still exist');
  assert.ok(rIndex > qIndex, 'R must appear after Q (alphabetical order)');
  assert.ok(sIndex > rIndex, 'S must appear after R');
});
