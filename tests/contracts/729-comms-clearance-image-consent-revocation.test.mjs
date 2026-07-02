/**
 * #729 — get_member_comms_card must honor an image/voice publicity consent REVOCATION.
 *
 * Before: comms_clearance came ONLY from member_is_pre_onboarding (Cláusula 11 signed term). A
 * signed-term volunteer who revoked their image-use authorization still returned comms_clearance=true.
 * Fix: add an `image_consent_revoked` branch reading the IMMUTABLE consent_records ledger (#570 SSOT,
 * policy_type='image_voice_publicity') — block only on an explicit revocation with NO later active
 * opt-in. Behavior-neutral today (0 image_voice_publicity rows; #570 dormant, gated on legal G12).
 *
 * Static migration guard (offline). Non-no-op: against migration 182 (pre-#729) the image_consent_revoked
 * assertions fail. The behavioral proof (baseline signed_term -> revoked blocks -> re-consent restores)
 * was run out-of-band via a RAISE-rollback smoke (documented in the PR); a DB-aware assertion is
 * deferred to #570 go-live (0 rows today so it would be a no-op).
 *
 * NOTE: #729 does NOT close on this migration — the read branch is only reachable once a revocation can
 * be RECORDED (self-service #570 at go-live, or the pending admin RPC gp_record_image_consent_revocation).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION = join(
  __dirname,
  '../../supabase/migrations/20260805000314_729_comms_clearance_honor_image_consent_revocation.sql',
);
// Defensive read (LL #684): a missing file becomes a clean assertion, not an ENOENT module crash.
const sql = existsSync(MIGRATION) ? readFileSync(MIGRATION, 'utf8') : '';
// Executable code only (strip `-- ...` comment lines) — the header/notes discuss consent_status/the
// #570 model; the gate must not actually USE consent_status (p697 pattern, line 58 there).
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');

test('#729 (a) migration re-anchors get_member_comms_card as SECDEF with pinned search_path', () => {
  assert.ok(sql, `migration file missing at expected path: ${MIGRATION}`);
  assert.match(sql, /CREATE OR REPLACE FUNCTION public\.get_member_comms_card\(/);
  assert.match(sql, /SECURITY DEFINER/);
  assert.match(sql, /SET search_path TO 'public', 'pg_temp'/);
});

test('#729 (b) all four clearance_reason values are present', () => {
  for (const reason of ['no_member_record', 'pre_onboarding', 'image_consent_revoked', 'signed_term']) {
    assert.ok(sql.includes(`'${reason}'`), `clearance_reason ${reason} must be present`);
  }
});

test('#729 (c) honors the #570 consent_records ledger (policy_type image_voice_publicity), not a persons.* field', () => {
  assert.match(code, /FROM\s+public\.consent_records/i);
  assert.ok(code.includes("policy_type = 'image_voice_publicity'"), "must key on policy_type='image_voice_publicity'");
  // must NOT introduce a duplicate SSOT field on persons (the stale issue-body proposal)
  assert.doesNotMatch(code, /image_consent_revoked_at/i, 'must not add a persons.image_consent_revoked_at field (reuse #570 consent_records SSOT)');
});

test('#729 (d)+(e) blocks only when revoked AND not re-consented (both arms present)', () => {
  // (d) revoked arm
  assert.match(code, /EXISTS\s*\([\s\S]*?revoked_at\s+IS\s+NOT\s+NULL/i);
  // (e) active counter-arm — its absence would make ANY historical revocation block permanently
  //     even after a later re-grant (the immutable-ledger re-consent case).
  assert.match(code, /NOT\s+EXISTS\s*\([\s\S]*?revoked_at\s+IS\s+NULL/i);
});

test('#729 (f) does NOT gate comms on consent_status (a different LGPD purpose — p697 invariant)', () => {
  assert.doesNotMatch(code, /consent_status/, 'consent_status must not be used in the comms gate');
});

test('#729 (g) return shape unchanged (comms_clearance + clearance_reason keys preserved)', () => {
  assert.match(sql, /'comms_clearance', v_clear/);
  assert.match(sql, /'clearance_reason', v_reason/);
});
