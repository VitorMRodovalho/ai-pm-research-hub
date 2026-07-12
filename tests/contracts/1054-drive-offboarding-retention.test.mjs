/**
 * #1054 — LGPD 5y retention + anonymization of permission_email in
 * drive_offboarding_audit (ADR-0014 extension of purge_expired_logs).
 *
 * Pre-GO-LIVE follow-up of #1039 (drive auto-revoke kill-switch).
 *
 * Static assertions (always run) parse the migration that (re)defines
 * purge_expired_logs and pin the anonymization contract:
 *   - a drive_offboarding_audit block anonymizes (not drops) at 5y (1825d)
 *   - only TERMINAL rows (revoked/failed/already_absent/skipped) are touched
 *   - SHA-256 + fixed salt via extensions.digest, hex-encoded
 *   - 'sha256:' sentinel prefix + NOT LIKE guard => idempotent re-runs
 *
 * The destructive runtime path (old→hashed, recent/pending→intact, stable
 * across re-runs) was verified live in-session with a rolled-back DO block.
 *
 * DB-aware assertion (needs SUPABASE_URL + SERVICE_ROLE_KEY) calls the RPC
 * dry-run and asserts drive_offboarding_audit surfaces with mode 'anonymize'
 * and no error. Dry-run is read-only.
 *
 * ⚠️ Known infra flake: the audit RPC path through Cloudflare occasionally
 * returns an error page; a rerun / isolated run resolves it (not a regression).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const MIG_DIR = join(REPO_ROOT, 'supabase/migrations');

// Latest migration that (re)defines purge_expired_logs.
function latestPurgeMigration() {
  const files = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort();
  let src = null;
  for (const f of files) {
    const s = readFileSync(join(MIG_DIR, f), 'utf8');
    if (s.includes('FUNCTION public.purge_expired_logs(')) src = s;
  }
  return src;
}

// Slice the drive_offboarding_audit BEGIN…END anonymize block out of the body.
function driveBlock(src) {
  const anchor = src.indexOf('drive_offboarding_audit: 5y anonymize');
  if (anchor === -1) return null;
  const end = src.indexOf('-- Meta-log', anchor);
  return end === -1 ? src.slice(anchor) : src.slice(anchor, end);
}

test('#1054: latest purge_expired_logs migration defines the drive block', () => {
  const src = latestPurgeMigration();
  assert.ok(src, 'a migration must (re)define purge_expired_logs');
  const block = driveBlock(src);
  assert.ok(block, 'the drive_offboarding_audit anonymize block must exist');
});

test('#1054: anonymizes (not drops) at 5y on terminal rows only', () => {
  const block = driveBlock(latestPurgeMigration());
  assert.match(block, /v_drive_audit_anonymize_days/, 'uses the 5y retention constant');
  assert.match(
    block,
    /status IN \('revoked','failed','already_absent','skipped'\)/,
    'restricts to terminal statuses',
  );
  assert.match(block, /RETURN QUERY SELECT 'drive_offboarding_audit'::text, 'anonymize'::text/,
    'reports purge_mode anonymize');
  assert.doesNotMatch(block, /DELETE FROM public\.drive_offboarding_audit/,
    'must not DELETE audit rows (anonymize-in-place)');
});

test('#1054: hashes with SHA-256 + salt via extensions.digest (not NULL, not plaintext)', () => {
  const src = latestPurgeMigration();
  const block = driveBlock(src);
  assert.match(src, /v_drive_audit_salt\s+constant text/, 'declares a fixed salt constant');
  assert.match(
    block,
    /encode\(extensions\.digest\(permission_email::text \|\| v_drive_audit_salt, 'sha256'\), 'hex'\)/,
    'SHA-256(email||salt) hex via schema-qualified extensions.digest',
  );
});

test('#1054: sentinel prefix makes anonymization idempotent', () => {
  const block = driveBlock(latestPurgeMigration());
  assert.match(block, /'sha256:' \|\| encode\(/, "prefixes the pseudonym with 'sha256:'");
  const guards = block.match(/permission_email NOT LIKE 'sha256:%'/g) || [];
  assert.ok(guards.length >= 2,
    "both the dry-run count and the UPDATE must exclude already-anonymized rows");
});

test('#1054: retention window is 1825 days (5 years)', () => {
  const src = latestPurgeMigration();
  assert.match(src, /v_drive_audit_anonymize_days\s+constant integer := 1825;/,
    '5y = 1825 days');
});

// ---- DB-aware dry-run (optional) --------------------------------------------
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

test('#1054: live dry-run surfaces drive_offboarding_audit as anonymize (no error)',
  { skip: !canRun && skipMsg }, async () => {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/purge_expired_logs`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SERVICE_ROLE_KEY,
        'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({ p_dry_run: true, p_limit: 10000 }),
    });
    assert.ok(res.ok, `RPC dry-run must succeed (HTTP ${res.status})`);
    const rows = await res.json();
    const drive = rows.filter((r) => r.table_name === 'drive_offboarding_audit');
    assert.strictEqual(drive.length, 1, 'exactly one drive_offboarding_audit row');
    assert.strictEqual(drive[0].purge_mode, 'anonymize', 'mode must be anonymize');
    assert.notStrictEqual(drive[0].purge_mode, 'error', 'block must not error');
  });
