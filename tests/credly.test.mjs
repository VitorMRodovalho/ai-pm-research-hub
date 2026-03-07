import test from 'node:test';
import assert from 'node:assert/strict';
import { extractCredlyUsername, normalizeCredlyUrl } from '../src/lib/credly.js';

test('extractCredlyUsername handles direct usernames', () => {
  assert.equal(extractCredlyUsername('john-doe_123'), 'john-doe_123');
});

test('extractCredlyUsername handles full urls with query and trailing slash', () => {
  assert.equal(
    extractCredlyUsername(' https://www.credly.com/users/jane.doe/?trk=public_profile '),
    'jane.doe'
  );
  assert.equal(
    extractCredlyUsername('credly.com/users/maria-silva/'),
    'maria-silva'
  );
});

test('normalizeCredlyUrl returns canonical user profile url', () => {
  assert.equal(
    normalizeCredlyUrl('credly.com/users/alex?foo=bar'),
    'https://www.credly.com/users/alex'
  );
});

test('invalid urls are rejected', () => {
  assert.equal(extractCredlyUsername('https://example.com/users/alex'), null);
  assert.equal(normalizeCredlyUrl('https://www.credly.com/organizations/openai'), null);
  assert.equal(normalizeCredlyUrl(''), null);
});
