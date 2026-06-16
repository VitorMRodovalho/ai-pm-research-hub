/**
 * Contract: member-signatures + member-photos write RLS must reference the OBJECT path
 * (storage.objects.name), not the member's name.
 *
 * Regression guard for the 2026-06-16 hotfix (mig 20260805000192): the original policies
 * (20260423090000) used an unqualified `name ILIKE 'signatures|avatars/<email>.%'` inside
 * `EXISTS (SELECT 1 FROM members m ...)`, which resolved to members.name (the person name)
 * instead of the uploaded object path → every signature/photo upload failed with
 * "new row violates row-level security policy". The fix qualifies it as
 * `storage.objects.name` and adds WITH CHECK to the UPDATE policies.
 *
 * Static-only (reads migration source) → runs without DB env.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIG_PATH = 'supabase/migrations/20260805000192_fix_member_signatures_upload_rls.sql';
const MIG = readFileSync(MIG_PATH, 'utf8');

describe('storage member-write RLS references the object path', () => {
  it('migration exists', () => {
    assert.ok(existsSync(MIG_PATH));
  });

  it('qualifies the path as storage.objects.name in all four policies', () => {
    const matches = MIG.match(/storage\.objects\.name ILIKE/g) || [];
    assert.ok(matches.length >= 4, `expected >=4 storage.objects.name checks, got ${matches.length}`);
  });

  it('recreates both signatures and photos write policies', () => {
    for (const pol of [
      'member_signatures_own_upload', 'member_signatures_own_update',
      'member_photos_own_upload', 'member_photos_own_update',
    ]) {
      assert.match(MIG, new RegExp(`CREATE POLICY "${pol}"`), `missing CREATE for ${pol}`);
    }
  });

  it('UPDATE policies carry WITH CHECK (post-image validated, not only pre-image)', () => {
    // both update policies + (the file has 2 WITH CHECK on inserts too) → >= 4 WITH CHECK total
    const withChecks = MIG.match(/WITH CHECK \(/g) || [];
    assert.ok(withChecks.length >= 4, `expected >=4 WITH CHECK clauses, got ${withChecks.length}`);
  });

  it('does not reintroduce the bare/member-name predicate', () => {
    // the bug was an unqualified `name ILIKE` resolving to members.name; ensure every
    // ILIKE on the object path is table-qualified.
    assert.doesNotMatch(MIG, /\n\s*AND name ILIKE/);
    assert.doesNotMatch(MIG, /m\.name ILIKE/);
  });
});
