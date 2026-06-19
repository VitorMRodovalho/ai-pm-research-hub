// G3 — workspace tier resolution must use the canonical SSOT, not a divergent
// local map. The pre-onboarding discovery (gap G3) flagged that workspace.astro
// resolved tier with a LOCAL function that mapped guest→'member', defaulted
// unknown roles to 'member', and ignored designations — diverging from
// src/lib/admin/constants.ts getAccessTier (guest/unknown → 'visitor'). This
// contract locks the fix so a future edit can't silently reintroduce the drift.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repo = resolve(__dirname, '..', '..');
const ws = readFileSync(resolve(repo, 'src/pages/workspace.astro'), 'utf8');
const constants = readFileSync(resolve(repo, 'src/lib/admin/constants.ts'), 'utf8');

test('workspace imports the canonical tier resolver (not a local map)', () => {
  assert.match(
    ws,
    /import\s*\{[^}]*\bresolveTierFromMember\b[^}]*\}\s*from\s*['"]\.\.\/lib\/admin\/constants['"]/,
    'workspace.astro must import resolveTierFromMember from src/lib/admin/constants',
  );
});

test('workspace defines NO local resolveTier function', () => {
  assert.doesNotMatch(
    ws,
    /function\s+resolveTier\s*\(/,
    'a local resolveTier() reintroduces the SSOT drift G3 removed',
  );
});

test('workspace carries no divergent guest→member tier literal', () => {
  // The old local map contained `guest: 'member'`. The canonical resolver maps
  // guest → 'visitor'; this literal must not reappear in the workspace source.
  assert.doesNotMatch(
    ws,
    /guest\s*:\s*['"]member['"]/,
    "guest must not be hard-mapped to 'member' tier in workspace.astro",
  );
});

test('workspace tier feeds checkSubprojectAccess via the canonical resolver', () => {
  assert.match(
    ws,
    /const\s+memberTier\s*=\s*resolveTierFromMember\s*\(\s*member\s*\)/,
    'memberTier must come from resolveTierFromMember(member)',
  );
});

test('workspace belonging gate uses isRegisteredMember (id-based, not truthy/role)', () => {
  assert.match(
    ws,
    /import\s*\{[^}]*\bisRegisteredMember\b[^}]*\}\s*from\s*['"]\.\.\/lib\/routing['"]/,
    'workspace.astro must import isRegisteredMember from src/lib/routing',
  );
  assert.match(
    ws,
    /if\s*\(\s*!\s*isRegisteredMember\s*\(\s*member\s*\)\s*\)/,
    'the auth gate must reject on !isRegisteredMember(member), not bare !member',
  );
});

test('canonical getAccessTier still maps guest/unknown to visitor (grounds the fix)', () => {
  // If this ever flips to 'member', the G3 premise is void — guard the SSOT.
  assert.match(
    constants,
    /return\s+['"]visitor['"]\s*;?\s*\n?\s*\}/,
    "getAccessTier's fallback must return 'visitor'",
  );
});
