// #333 (Wave 4 of #221/#218): invariant AK_voice_biometric_consent_enforcement in
// check_schema_invariants() — periodic detector that every transcribed pmi_video_screenings row
// has valid voice-biometric consent (LGPD Art.11), complementing the write-time trigger
// trg_pmi_video_screening_voice_consent.
//
// Path (b) (PM decision 2026-06-27, per #332's pre-documented tree): the invariant ships reporting
// the TRUE violation count against a 1-row allowlist baseline — the single #332 retroactive-
// notification candidate under tacit Art.18 retention (deletion remains exercisable indefinitely).
// The baseline RATCHETS to 0 when that row is finally deleted (then AK joins the schema-invariants
// all-zero `expected` list).
//
// AK is deliberately NOT in schema-invariants.test.mjs's all-zero `expected` list while the
// baseline is non-zero; this dedicated test owns its assertion. Requires DB creds; skipped otherwise.
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

// AK reports 0 in the healthy state: the 1 acknowledged pre-block row (#332 retroactive-notification
// candidate, tacit Art.18 retention; PM path (b) 2026-06-27) is EXCLUDED via its documented retention
// record in pii_access_log — not via a hardcoded id. Any AK > 0 means a NEW non-consented
// transcription with no retention basis (real drift), which the project's "0 total violations"
// contract must surface.
const INVARIANT = 'AK_voice_biometric_consent_enforcement';

async function callInvariantRpc() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/check_schema_invariants`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({}),
  });
  if (!res.ok) throw new Error(`RPC failed: HTTP ${res.status} — ${await res.text()}`);
  return res.json();
}

test('#333 AK_voice_biometric_consent_enforcement is registered (severity high)', { skip: canRun ? false : skipMsg }, async () => {
  const rows = await callInvariantRpc();
  const ak = rows.find(r => r.invariant_name === INVARIANT);
  assert.ok(ak, `${INVARIANT} must be present in check_schema_invariants()`);
  assert.equal(ak.severity, 'high', 'AK severity must be high');
});

test('#333 AK reports 0 violations (acknowledged #332 row excluded via documented retention)', { skip: canRun ? false : skipMsg }, async () => {
  const rows = await callInvariantRpc();
  const ak = rows.find(r => r.invariant_name === INVARIANT);
  assert.ok(ak, `${INVARIANT} missing`);
  if (ak.violation_count > 0) {
    assert.fail(
      `NEW voice-biometric consent drift: ${ak.violation_count} transcribed row(s) lack valid consent ` +
      `AND have no documented Art.18 retention record. A transcription exists without ` +
      `consent_voice_biometric_at and is not acknowledged — investigate ` +
      `trg_pmi_video_screening_voice_consent or a raw-SQL bypass. sample_ids: ${JSON.stringify(ak.sample_ids)}`
    );
  }
  assert.equal(ak.violation_count, 0, 'AK must report 0 (project-wide "0 total violations" contract)');
});
