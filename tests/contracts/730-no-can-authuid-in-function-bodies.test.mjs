// #730 forward-defense: no public-schema function body may resolve authority via
// can(auth.uid(...)). can() joins auth_engagements.person_id = persons.id, so an auth user id
// can never match — passing auth.uid() makes the gate fail closed (view_pii / manage_member
// silently denied for legitimate holders). The correct pattern resolves the caller's person_id
// (via persons.legacy_member_id / persons.auth_id) FIRST and passes that to can().
//
// This contract asserts the LIVE database has zero such function bodies, via the
// _audit_can_authuid_function_bodies() audit RPC (returns offending function identities only —
// no bodies, no PII). A live check (not a static migration grep) is deliberate: historical
// migrations (p178 drift-capture, p195) still contain the literal pattern in captured bodies,
// but only the CURRENT live bodies matter. Skipped without DB credentials.
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function callAuditRpc() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_audit_can_authuid_function_bodies`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({}),
  });
  if (!res.ok) throw new Error(`audit RPC failed: HTTP ${res.status} — ${await res.text()}`);
  return res.json();
}

test(
  '#730 no live function body resolves authority via can(auth.uid(...))',
  { skip: canRun ? false : skipMsg },
  async () => {
    const offenders = await callAuditRpc();
    assert.deepEqual(
      offenders,
      [],
      `Functions must resolve the caller person_id before calling can() — see #730. ` +
        `Offenders: ${JSON.stringify(offenders)}`
    );
  }
);
