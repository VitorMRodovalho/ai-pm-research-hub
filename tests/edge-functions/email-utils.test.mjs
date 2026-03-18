import test from 'node:test';
import assert from 'node:assert/strict';
import { isSandboxMode, renderTemplate } from '../../supabase/functions/_shared/email-utils.ts';

// ── isSandboxMode ──
test('isSandboxMode: detects resend sandbox address', () => {
  assert.equal(isSandboxMode('onboarding@resend.dev'), true);
});

test('isSandboxMode: returns false for real domain', () => {
  assert.equal(isSandboxMode('noreply@nucleoia.org'), false);
});

test('isSandboxMode: returns false for empty string', () => {
  assert.equal(isSandboxMode(''), false);
});

test('isSandboxMode: detects sandbox even with prefix', () => {
  assert.equal(isSandboxMode('Test Name <onboarding@resend.dev>'), true);
});

// ── renderTemplate ──
test('renderTemplate: replaces single variable', () => {
  const result = renderTemplate('Hello {member.name}!', { '{member.name}': 'Alice' });
  assert.equal(result, 'Hello Alice!');
});

test('renderTemplate: replaces multiple variables', () => {
  const result = renderTemplate('{member.name} from {member.tribe}', {
    '{member.name}': 'Bob',
    '{member.tribe}': 'Alpha',
  });
  assert.equal(result, 'Bob from Alpha');
});

test('renderTemplate: replaces all occurrences of same variable', () => {
  const result = renderTemplate('{x} and {x}', { '{x}': 'Y' });
  assert.equal(result, 'Y and Y');
});

test('renderTemplate: no-op when no vars match', () => {
  const result = renderTemplate('No vars here', { '{foo}': 'bar' });
  assert.equal(result, 'No vars here');
});

test('renderTemplate: handles empty template', () => {
  const result = renderTemplate('', { '{x}': 'y' });
  assert.equal(result, '');
});
