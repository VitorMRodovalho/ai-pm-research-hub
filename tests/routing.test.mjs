import test from 'node:test';
import assert from 'node:assert/strict';
import { buildLanguageHref, shouldRedirectFromProfile } from '../src/lib/routing.js';

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

test('shouldRedirectFromProfile redirects guest or missing member', () => {
  assert.equal(shouldRedirectFromProfile(undefined), true);
  assert.equal(shouldRedirectFromProfile(null), true);
  assert.equal(shouldRedirectFromProfile({ role: 'guest' }), true);
  assert.equal(shouldRedirectFromProfile({ operational_role: 'guest' }), true);
});

test('shouldRedirectFromProfile allows authenticated non-guest members', () => {
  assert.equal(shouldRedirectFromProfile({ role: 'researcher' }), false);
  assert.equal(shouldRedirectFromProfile({ operational_role: 'manager' }), false);
});
