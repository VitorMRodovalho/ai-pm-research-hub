/**
 * Contract: #1087 Onda 3 — gamification ledger is APPEND-ONLY for business logic.
 *
 * Before mig 20260805000333, THREE RPCs hard-deleted gamification_points rows
 * (revoke_champion, revoke_agenda_block_xp, remove_event_showcase), destroying the
 * audit trail. Since then, revocation INSERTS an estorno row (negative points netting
 * the award, same ref_id, granted_by = revoker). Rollups are raw SUM, so the net
 * absorbs the estorno; get_my_points_statement labels is_reversal = points < 0.
 *
 * THE INVARIANT: no business-logic RPC deletes gamification_points rows.
 * Deliberate exception: LGPD erasure (member deletion) is data-subject-rights
 * plumbing, not business logic — this is why the invariant is a contract test on
 * function bodies, NOT a BEFORE DELETE trigger.
 *
 * Enforcement is transitive and offline-first:
 *   (a) this test scans the LATEST CREATE FUNCTION capture per function across all
 *       local migrations — none may delete from the ledger (offline, runs everywhere);
 *   (b) Phase C (rpc-migration-coverage.test.mjs) pins live prosrc md5 == latest
 *       capture, so (a) extends to the live DB — a live redefinition adding a DELETE
 *       would surface as NEW drift and go red;
 *   (c) DB-gated here: the three converted functions' live body hashes equal the
 *       mig-333 capture directly (no reliance on the Phase C allowlist for them).
 *
 * Companion live parity: p277-419-m7-champions-parity.test.mjs (repinned: revoked
 * champions keep original + estorno rows, netting to zero).
 *
 * LGPD erasure carve-out in the scan: functions matching the documented erasure
 * allowlist below may delete ledger rows (Art. 18 right-to-deletion must remove the
 * member's rows). Anything else is a violation.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { parseMigration } from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIG_DIR = resolve(ROOT, 'supabase/migrations');
const WAVE3_MIG = resolve(MIG_DIR, '20260805000333_1087_wave3_ledger_append_only.sql');
const wave3 = existsSync(WAVE3_MIG) ? readFileSync(WAVE3_MIG, 'utf8') : '';

const CONVERTED = ['revoke_champion', 'revoke_agenda_block_xp', 'remove_event_showcase'];

// LGPD erasure plumbing WOULD be allowed to delete ledger rows (data-subject rights, not
// business logic) — but grounded 2026-07-03, no captured LGPD function touches the ledger
// with DELETE (erasure exports/anonymizes). Add a function name here ONLY for a real
// Art. 18 erasure path, never for a business revoke.
const LGPD_ERASURE_ALLOWLIST = new Set([]);

const LEDGER_DELETE_RE = /delete\s+from\s+(public\.)?gamification_points\b/i;

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

/** Latest CREATE FUNCTION capture per `${name}@${args}` across all migrations (with raw body). */
function loadLatestBodies() {
  const latest = new Map();
  const files = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort();
  for (const f of files) {
    const sql = readFileSync(join(MIG_DIR, f), 'utf8');
    for (const b of parseMigration(f, sql)) {
      latest.set(`${b.name}@${b.args}`, b);
    }
  }
  return latest;
}

// ── STATIC: mig 333 converts all three deleters to estorno ───────────────────────
test('wave3 static: mig 333 redefines the 3 ledger-deleting RPCs with estorno inserts and no DELETE', () => {
  assert.ok(wave3.length > 0, 'wave-3 migration exists');
  for (const fn of CONVERTED) {
    assert.match(wave3, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(`), `${fn} redefined`);
  }
  const estornos = (wave3.match(/INSERT INTO (public\.)?gamification_points/g) || []).length;
  assert.ok(estornos >= 3, `expected >=3 estorno INSERTs (one per converted RPC); got ${estornos}`);
  assert.match(wave3, /HAVING SUM\(gp\.points\) <> 0/,
    'net<>0 guard present (idempotent + net-zero-safe reversal)');
  assert.doesNotMatch(wave3, LEDGER_DELETE_RE, 'no DELETE on the ledger anywhere in the migration');
});

test('wave3 static: remove_event_showcase reversal matches granular slugs (latent bare-showcase bug fix)', () => {
  // The old DELETE matched only category = 'showcase' (bare, legacy 2026-04 rows); current
  // writes use showcase_<type> (p165 config-driven), so removal left XP orphaned. The
  // reversal must match by ref_id with LIKE 'showcase%' to cover legacy + granular.
  const seg = wave3.slice(
    wave3.indexOf('CREATE OR REPLACE FUNCTION public.remove_event_showcase'),
    wave3.indexOf('CREATE OR REPLACE FUNCTION public.get_member_xp_pillars'),
  );
  assert.match(seg, /gp\.category LIKE 'showcase%'/, 'reversal covers all showcase slugs by ref_id');
});

test('wave3 static: xp pillar drill does not count estorno rows as earned', () => {
  assert.match(wave3, /COUNT\(p\.points\) FILTER \(WHERE p\.points > 0\)/,
    'get_member_xp_pillars earned_count excludes reversals; pts stays raw SUM (net)');
});

// ── OFFLINE: no latest-captured function body deletes from the ledger ─────────────
// Scope note: the scan is FUNCTION-BODY-only by design — the invariant governs RPC
// business logic. A raw one-shot `DELETE FROM gamification_points` statement in a
// migration (outside any function body) is a data operation, governed by review and
// the Q-C/Phase C gates, not by this scan.
test('wave3 offline: latest capture of every migration-defined function is ledger-append-only', () => {
  const latest = loadLatestBodies();
  assert.ok(latest.size > 100, `sanity: parsed a real catalog (got ${latest.size} functions)`);
  const offenders = [];
  for (const [key, block] of latest) {
    if (LGPD_ERASURE_ALLOWLIST.has(block.name)) continue;
    if (LEDGER_DELETE_RE.test(block.body)) offenders.push(`${key} (${block.file})`);
  }
  assert.deepEqual(offenders, [],
    `latest-captured function bodies must not DELETE from gamification_points (LGPD erasure is the only carve-out): ${offenders.join(', ')}`);
});

// ── DB-gated: the three converted functions are live exactly as captured in mig 333 ──
test('wave3 live: converted RPCs live bodies == mig-333 capture (no drift loophole)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
  assert.ifError(error);

  const captures = parseMigration('20260805000333', wave3);
  for (const fn of CONVERTED) {
    const cap = captures.find((b) => b.name === fn);
    assert.ok(cap, `${fn} captured in mig 333`);
    const liveRows = (data || []).filter((r) => r.proname === fn);
    assert.equal(liveRows.length, 1, `${fn} has exactly one live overload`);
    assert.equal(liveRows[0].body_md5, cap.bodyHash,
      `${fn}: live body must match the mig-333 capture (apply_migration byte-fidelity)`);
  }
});
