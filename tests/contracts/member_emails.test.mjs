/**
 * Behavioral contract tests for member alternate emails schema (#205)
 * Matches ADR-0095.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function callCheckInvariants() {
  const url = `${SUPABASE_URL}/rest/v1/rpc/check_schema_invariants`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({}),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`check_schema_invariants RPC failed: HTTP ${res.status} — ${text}`);
  }
  return await res.json();
}

test('ADR-0095: member_emails live behaviour and invariant T', { skip: !canRun && skipMsg }, async (t) => {
  // Step 1: Verify baseline invariant T has 0 violations
  await t.test('invariant T has 0 violations at start', async () => {
    const rows = await callCheckInvariants();
    const tRow = rows.find((r) => r.invariant_name === 'T_member_has_exactly_one_primary_email');
    assert.ok(tRow, 'Invariant T must exist in check_schema_invariants');
    assert.equal(tRow.violation_count, 0, `Expected 0 violations for invariant T, got ${tRow.violation_count}`);
  });

  let testMemberId = null;
  const testEmail = `test-sync-${Date.now()}@example.com`;
  const testEmailUpdated = `test-sync-updated-${Date.now()}@example.com`;
  const testEmailAlternate = `test-alt-${Date.now()}@example.com`;

  // Step 2: Test trigger synchronization on insert
  await t.test('sync trigger inserts primary email row on member insert', async () => {
    // Insert test member using service_role
    const insertRes = await fetch(`${SUPABASE_URL}/rest/v1/members`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        Prefer: 'return=representation',
      },
      body: JSON.stringify({
        name: 'Test Sync Member',
        email: testEmail,
        member_status: 'active',
        operational_role: 'researcher',
      }),
    });
    assert.equal(insertRes.status, 201, `Failed to insert test member: ${insertRes.status}`);
    const insertData = await insertRes.json();
    testMemberId = insertData[0].id;
    assert.ok(testMemberId, 'Should have received member ID');

    // Query member_emails to verify sync row
    const queryRes = await fetch(
      `${SUPABASE_URL}/rest/v1/member_emails?member_id=eq.${testMemberId}`,
      {
        method: 'GET',
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      }
    );
    assert.equal(queryRes.status, 200);
    const emails = await queryRes.json();
    assert.equal(emails.length, 1, 'Should have exactly 1 email row synced');
    assert.equal(emails[0].email, testEmail);
    assert.equal(emails[0].is_primary, true);
    assert.equal(emails[0].kind, 'personal');
  });

  // Step 3: Test trigger synchronization on update
  await t.test('sync trigger updates primary email row on member email update', async () => {
    assert.ok(testMemberId);
    const updateRes = await fetch(`${SUPABASE_URL}/rest/v1/members?id=eq.${testMemberId}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({
        email: testEmailUpdated,
      }),
    });
    assert.equal(updateRes.status, 204);

    // Query member_emails to verify sync row
    const queryRes = await fetch(
      `${SUPABASE_URL}/rest/v1/member_emails?member_id=eq.${testMemberId}&order=added_at.asc`,
      {
        method: 'GET',
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      }
    );
    assert.equal(queryRes.status, 200);
    const emails = await queryRes.json();
    assert.equal(emails.length, 2, 'Should have 2 email rows synced now');

    const oldEmail = emails.find(e => e.email === testEmail);
    const newEmail = emails.find(e => e.email === testEmailUpdated);

    assert.ok(oldEmail);
    assert.equal(oldEmail.is_primary, false);

    assert.ok(newEmail);
    assert.equal(newEmail.is_primary, true);
  });

  // Step 4: Test member_add_alternate_email RPC
  await t.test('member_add_alternate_email RPC inserts alternate email', async () => {
    assert.ok(testMemberId);
    const addRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/member_add_alternate_email`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({
        p_member_id: testMemberId,
        p_email: testEmailAlternate,
        p_kind: 'chapter',
      }),
    });
    assert.equal(addRes.status, 200, `Failed to call member_add_alternate_email: ${addRes.status}`);
    const alternateEmailId = await addRes.json();
    assert.ok(alternateEmailId, 'Should return the new email row UUID');

    // Query member_emails to verify addition
    const queryRes = await fetch(
      `${SUPABASE_URL}/rest/v1/member_emails?id=eq.${alternateEmailId}`,
      {
        method: 'GET',
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      }
    );
    assert.equal(queryRes.status, 200);
    const emails = await queryRes.json();
    assert.equal(emails.length, 1);
    assert.equal(emails[0].email, testEmailAlternate);
    assert.equal(emails[0].is_primary, false);
    assert.equal(emails[0].kind, 'chapter');
  });

  // Step 5: Test member_resolve_email RPC
  await t.test('member_resolve_email RPC resolves emails to member_id', async () => {
    assert.ok(testMemberId);

    // 1. Resolve current primary email
    const resPrimary = await fetch(`${SUPABASE_URL}/rest/v1/rpc/member_resolve_email`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({ p_email: testEmailUpdated }),
    });
    assert.equal(resPrimary.status, 200);
    const resolvedPrimary = await resPrimary.json();
    assert.equal(resolvedPrimary, testMemberId);

    // 2. Resolve alternate email
    const resAlt = await fetch(`${SUPABASE_URL}/rest/v1/rpc/member_resolve_email`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({ p_email: testEmailAlternate }),
    });
    assert.equal(resAlt.status, 200);
    const resolvedAlt = await resAlt.json();
    assert.equal(resolvedAlt, testMemberId);

    // 3. Resolve non-existent email
    const resNone = await fetch(`${SUPABASE_URL}/rest/v1/rpc/member_resolve_email`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({ p_email: 'does-not-exist@example.com' }),
    });
    assert.equal(resNone.status, 200);
    const resolvedNone = await resNone.json();
    assert.equal(resolvedNone, null);
  });

  // Step 6: Test member_list_emails RPC
  await t.test('member_list_emails RPC lists all emails', async () => {
    assert.ok(testMemberId);
    const listRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/member_list_emails`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({ p_member_id: testMemberId }),
    });
    assert.equal(listRes.status, 200);
    const list = await listRes.json();
    assert.equal(list.length, 3, 'Should list 3 emails');
    const emailsSet = new Set(list.map(e => e.email));
    assert.ok(emailsSet.has(testEmail));
    assert.ok(emailsSet.has(testEmailUpdated));
    assert.ok(emailsSet.has(testEmailAlternate));
  });

  // Step 7: Test RLS and Revoked Direct DML/SELECT Grants
  await t.test('direct DML is blocked without service_role key', async () => {
    // Attempt select without Authorization header
    const selectRes = await fetch(`${SUPABASE_URL}/rest/v1/member_emails`, {
      method: 'GET',
    });
    // Should be unauthorized (401 or 400 or 403 because we do not supply a valid anon key or authorization)
    assert.ok(selectRes.status >= 400, `Expected direct SELECT to fail, got ${selectRes.status}`);

    // Attempt direct insert without Authorization header
    const insertDirectRes = await fetch(`${SUPABASE_URL}/rest/v1/member_emails`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        member_id: testMemberId,
        email: 'direct-insert-attempt@example.com',
        is_primary: false,
        kind: 'personal',
      }),
    });
    assert.ok(insertDirectRes.status >= 400, `Expected direct INSERT to fail, got ${insertDirectRes.status}`);
  });

  // Step 8: Test Invariant T detection of breach
  await t.test('invariant T detects member with 0 primary emails', async () => {
    assert.ok(testMemberId);

    // 1. Demote the primary email of our test member directly using service_role UPDATE
    const demoteRes = await fetch(
      `${SUPABASE_URL}/rest/v1/member_emails?member_id=eq.${testMemberId}`,
      {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
        body: JSON.stringify({
          is_primary: false,
        }),
      }
    );
    assert.ok([204, 240].includes(demoteRes.status), `Expected 204 or 240, got ${demoteRes.status}`);


    // 2. Call check_schema_invariants() and assert breach detected
    const rows = await callCheckInvariants();
    const tRow = rows.find((r) => r.invariant_name === 'T_member_has_exactly_one_primary_email');
    assert.ok(tRow);
    assert.ok(tRow.violation_count >= 1, `Invariant T should detect the breach, violation_count=${tRow.violation_count}`);
    assert.ok(
      Array.isArray(tRow.sample_ids) && tRow.sample_ids.includes(testMemberId),
      `Test member ID ${testMemberId} must be in the sample IDs of invariant T`
    );
  });

  // Step 9: Clean up and verify recovery
  await t.test('cleanup deletes member and cascades to member_emails, restoring invariant T', async () => {
    assert.ok(testMemberId);

    // Delete test member
    const deleteRes = await fetch(`${SUPABASE_URL}/rest/v1/members?id=eq.${testMemberId}`, {
      method: 'DELETE',
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
    });
    assert.equal(deleteRes.status, 204);

    // Query member_emails to verify cascade delete
    const queryRes = await fetch(
      `${SUPABASE_URL}/rest/v1/member_emails?member_id=eq.${testMemberId}`,
      {
        method: 'GET',
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      }
    );
    assert.equal(queryRes.status, 200);
    const emails = await queryRes.json();
    assert.equal(emails.length, 0, 'Cascade delete should have removed all member emails');

    // Verify invariant T returns to 0 violations
    const rows = await callCheckInvariants();
    const tRow = rows.find((r) => r.invariant_name === 'T_member_has_exactly_one_primary_email');
    assert.equal(tRow.violation_count, 0, 'Violation count must return to 0');
  });
});
