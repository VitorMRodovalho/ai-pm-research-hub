/**
 * Contract: #1437 — test data must never become a real recipient.
 *
 * Measured, not inferred (2026-08-02): the member campaign for the 04/08 webinar went out with
 * 89 recipients, and one of them was `test-sync-updated-…@example.com` — a row created by
 * `tests/contracts/member_emails.test.mjs` on 31/07 that survived its own cleanup and kept
 * `is_active = true`. `admin_send_campaign` selects on `is_active AND current_cycle_active`, so
 * the synthetic row was indistinguishable from a member. Only Resend's refusal of `example.com`
 * kept it from being delivered somewhere.
 *
 * Ten such rows accumulated between 04/07 and 31/07. Nine had already been soft-retired under
 * this same issue on 20/07 — which proves that purging survivors is not the fix. The tap stays
 * open unless something fails when a survivor becomes REACHABLE again. That is this file.
 *
 * Two authoring decisions worth keeping:
 *
 *  - The invariant is "does not PERSIST reachable", not "does not exist". While
 *    member_emails.test.mjs legitimately runs, a synthetic member exists and is active for a few
 *    seconds. CI runs share the production database (#1505/#1261), so a strict existence check
 *    would go red because a CONCURRENT run was doing its job. The grace window below draws that
 *    line explicitly instead of leaving it to luck.
 *
 *  - The reachability check ITERATES the offending rows and reports them. A single
 *    `assert.match`-style existential check passes as soon as one row looks fine while others
 *    drift — the trap that burned three guards in one day (see memory: match-accepts-any).
 */

import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

/**
 * Domains reserved by RFC 2606 / RFC 6761 for documentation and testing. Mail to these can never
 * reach a person, so a row carrying one is test data by construction, whatever it is named.
 */
const RESERVED_DOMAIN = /@(?:[^@]*\.)?(?:example\.(?:com|org|net)|test|invalid|localhost)$/i;

/**
 * A run of member_emails.test.mjs is allowed to have its synthetic member alive for this long.
 * Beyond it, the row is a survivor, not work in progress.
 */
const GRACE_MINUTES = 30;

/**
 * Recipients written BEFORE this instant are the incident that motivated the guard (the 02/08
 * 13:34 UTC send) and are left as history. Anything after it is a regression.
 */
const RECIPIENT_CUTOFF = new Date('2026-08-02T14:00:00Z');

async function rest(path) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` },
  });
  // Read the body ONCE: passing `await res.text()` as the assert message consumes it even on
  // success, and the following .json() then throws "Body has already been read".
  if (!res.ok) assert.fail(`GET ${path} failed: HTTP ${res.status} — ${await res.text()}`);
  return await res.json();
}

test('#1437: a member with a reserved e-mail domain never stays reachable by a campaign', { skip: !canRun && skipMsg }, async () => {
  const members = await rest('members?select=id,name,email,is_active,current_cycle_active,created_at');
  const cutoff = Date.now() - GRACE_MINUTES * 60_000;

  const persistentlyReachable = members.filter(
    (m) =>
      m.email &&
      RESERVED_DOMAIN.test(m.email) &&
      m.is_active === true &&
      m.current_cycle_active === true &&
      new Date(m.created_at).getTime() < cutoff
  );

  assert.deepEqual(
    persistentlyReachable.map((m) => `${m.id} (${m.name}, created ${m.created_at})`),
    [],
    `Reserved-domain member(s) reachable by admin_send_campaign for more than ${GRACE_MINUTES} min. ` +
      'Soft-retire them (is_active=false, current_cycle_active=false, member_status=inactive) and ' +
      'find what created them.'
  );
});

test('#1437: no campaign recipient resolves to a reserved e-mail domain', { skip: !canRun && skipMsg }, async () => {
  const iso = RECIPIENT_CUTOFF.toISOString();
  const recipients = await rest(
    `campaign_recipients?select=id,send_id,member_id,external_email,created_at&created_at=gte.${iso}`
  );
  if (recipients.length === 0) return; // nothing sent since the cutoff yet

  const members = await rest('members?select=id,email');
  const emailById = new Map(members.map((m) => [m.id, m.email]));

  const offenders = recipients
    .map((r) => ({ id: r.id, email: r.external_email || emailById.get(r.member_id) || '' }))
    .filter((r) => RESERVED_DOMAIN.test(r.email));

  assert.deepEqual(
    offenders.map((r) => `recipient ${r.id} → ${r.email}`),
    [],
    'Test data entered a real campaign audience. The send-side filter in admin_send_campaign is ' +
      'the last line of defence and it did not hold.'
  );
});
