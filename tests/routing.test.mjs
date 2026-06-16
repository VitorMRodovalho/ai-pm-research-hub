import test from 'node:test';
import assert from 'node:assert/strict';
import { buildLanguageHref, shouldRedirectFromProfile, isRegisteredMember } from '../src/lib/routing.js';

test('buildLanguageHref keeps index paths correct', () => {
  assert.equal(buildLanguageHref('/', ''), '/');
  assert.equal(buildLanguageHref('/', 'en'), '/en/');
  assert.equal(buildLanguageHref('/en/', 'es'), '/es/');
});

test('buildLanguageHref preserves non-index path across locale switches', () => {
  assert.equal(buildLanguageHref('/artifacts', 'en'), '/en/artifacts');
  assert.equal(buildLanguageHref('/en/artifacts', 'es'), '/es/artifacts');
  assert.equal(buildLanguageHref('/es/attendance', ''), '/attendance');
});

test('shouldRedirectFromProfile redirects only when there is no member record', () => {
  // No member at all → genuine "not registered" (handled via WS-B account-claim).
  assert.equal(shouldRedirectFromProfile(undefined), true);
  assert.equal(shouldRedirectFromProfile(null), true);
  // Payload without an id is not a real member record → redirect.
  assert.equal(shouldRedirectFromProfile({ role: 'guest' }), true);
  assert.equal(shouldRedirectFromProfile({ operational_role: 'guest' }), true);
});

test('shouldRedirectFromProfile allows authenticated non-guest members', () => {
  assert.equal(shouldRedirectFromProfile({ id: 'm1', operational_role: 'manager' }), false);
  assert.equal(shouldRedirectFromProfile({ id: 'm2', operational_role: 'researcher' }), false);
});

test('pre-onboarding guest members (real member record, guest role) reach their profile', () => {
  // The bug class fixed here: a returned member record with operational_role='guest'
  // is a registered pre-onboarding member and MUST NOT be redirected to the
  // "not registered" dead-end. They need /profile to complete consent, Credly,
  // alternate emails, name fixes and term signature before promotion.
  const preOnb = { id: 'm3', operational_role: 'guest', member_status: 'active' };
  assert.equal(isRegisteredMember(preOnb), true);
  assert.equal(shouldRedirectFromProfile(preOnb), false);
});

test('isRegisteredMember distinguishes member record from null/sentinel', () => {
  assert.equal(isRegisteredMember(null), false);
  assert.equal(isRegisteredMember(undefined), false);
  assert.equal(isRegisteredMember({ operational_role: 'guest' }), false); // no id → not a record
  assert.equal(isRegisteredMember({ id: 'm4', operational_role: 'researcher' }), true);
});
