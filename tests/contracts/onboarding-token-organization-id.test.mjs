// BUG-224.A (#237) forward-defense: the pmi-vep-sync worker must pass
// organization_id explicitly when inserting into onboarding_tokens. The
// column is NOT NULL with default auth_org() — under SUPABASE_SERVICE_ROLE_KEY
// (no JWT) the default resolves to NULL and the insert fails with a
// constraint violation. Discovered after PR #236 (#224 observability)
// surfaced the previously-hidden error pattern from cycle4-2026 applies.
//
// Strategy: static source-level contract — assert (a) IssueTokenOpts
// declares organization_id as required, (b) the insert payload includes
// organization_id, (c) the /ingest caller in index.ts passes env.ORG_ID.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const ONBOARDING_TOKEN_FILE = join(ROOT, 'cloudflare-workers', 'pmi-vep-sync', 'src', 'onboarding-token.ts');
const WORKER_INDEX_FILE = join(ROOT, 'cloudflare-workers', 'pmi-vep-sync', 'src', 'index.ts');

test('IssueTokenOpts requires organization_id (#237)', () => {
  const src = readFileSync(ONBOARDING_TOKEN_FILE, 'utf8');
  // The field must be declared without the optional `?:` marker so callers
  // are forced to pass it. Worker has no JWT context, so auth_org() default
  // resolves to NULL and the constraint fires.
  const interfaceBlock = src.match(/interface\s+IssueTokenOpts\s*\{[\s\S]*?\n\}/);
  assert.ok(interfaceBlock, 'IssueTokenOpts interface must be findable');
  assert.ok(
    /organization_id\s*:\s*string\s*;/.test(interfaceBlock[0]),
    'IssueTokenOpts.organization_id must be declared as required string'
  );
});

test('issueOnboardingToken insert payload includes organization_id (#237)', () => {
  const src = readFileSync(ONBOARDING_TOKEN_FILE, 'utf8');
  // The insert object literal must reference organization_id explicitly.
  // Either as a key (organization_id: opts.organization_id) or via spread.
  // Pin to the literal-key form to keep the contract obvious.
  assert.ok(
    /organization_id\s*:\s*opts\.organization_id/.test(src),
    'onboarding_tokens insert must pass organization_id: opts.organization_id'
  );
});

test('worker /ingest caller passes env.ORG_ID to issueOnboardingToken (#237)', () => {
  const src = readFileSync(WORKER_INDEX_FILE, 'utf8');
  // The single issueOnboardingToken call site in index.ts (line ~553) must
  // include organization_id: env.ORG_ID. ORG_ID is already a bound env var
  // (confirmed at deploy: "env.ORG_ID (\"2b4f58ab-7c45-4170-8718-b77ee69ff906\")").
  const callPattern = /issueOnboardingToken\s*\(\s*db\s*,\s*\{[\s\S]*?organization_id\s*:\s*env\.ORG_ID[\s\S]*?\}\s*\)/;
  assert.ok(
    callPattern.test(src),
    'worker /ingest must pass organization_id: env.ORG_ID when calling issueOnboardingToken'
  );
});
