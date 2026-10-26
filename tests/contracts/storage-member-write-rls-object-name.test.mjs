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
 *
 * 2026-10-26 (item interno): the member-photos policies no longer key on the e-mail at all. The
 * CURRENT capture is the newest migration that creates member_photos_own_upload, found on disk (not
 * named here, so the placeholder can be renamed to its registered version). It must key on the
 * caller's opaque per-member key, by EQUALITY, in every one of the three policies. The assertions
 * below cut each policy statement out and assert inside it, with SQL line comments masked.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

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

// ── current capture: the opaque-key policies (item interno, 2026-10-26) ──────────────────────────────
const MIG_DIR = 'supabase/migrations';
const CURRENT = (() => {
  const files = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort();
  const hits = files.filter((f) =>
    /CREATE POLICY "?member_photos_own_upload"?/.test(maskLineComments(readFileSync(`${MIG_DIR}/${f}`, 'utf8'))));
  assert.ok(hits.length > 0, 'some migration must create member_photos_own_upload');
  const file = hits[hits.length - 1];
  return { file, sql: maskLineComments(readFileSync(`${MIG_DIR}/${file}`, 'utf8')) };
})();

/** One statement, from its head to the terminating semicolon (no semicolons inside these policies). */
function statement(sql, headRe) {
  const m = sql.match(headRe);
  assert.ok(m, `missing statement ${headRe}`);
  const end = sql.indexOf(';', m.index);
  return sql.slice(m.index, end + 1);
}

const KEYED = String.raw`bucket_id = 'member-photos'\s+AND storage\.objects\.name IN \(\s*'avatars/' \|\| \(SELECT public\.member_photo_key_of_caller\(\)\) \|\| '\.jpg',\s*'avatars/' \|\| \(SELECT public\.member_photo_key_of_caller\(\)\) \|\| '\.png'\s*\)`;

describe('member-photos write RLS keys on the caller opaque key (current capture)', () => {
  it('the newest member_photos_own_upload capture is the opaque-key one', () => {
    assert.match(CURRENT.file, /_member_photos_opaque_names\.sql$/);
  });

  for (const [pol, cmd, clauses] of [
    ['member_photos_own_upload', 'INSERT', ['WITH CHECK']],
    ['member_photos_own_update', 'UPDATE', ['USING', 'WITH CHECK']],
    ['member_photos_own_delete', 'DELETE', ['USING']],
  ]) {
    it(`${pol}: FOR ${cmd} TO authenticated, ${clauses.join(' + ')} bound to the key by equality`, () => {
      const st = statement(CURRENT.sql, new RegExp(`CREATE POLICY ${pol} ON storage\\.objects`));
      assert.match(st, new RegExp(`FOR ${cmd} TO authenticated\\b`));
      for (const clause of clauses) {
        assert.match(st, new RegExp(`${clause}\\s*\\(\\s*${KEYED}\\s*\\)`), `${pol}: ${clause} must be the key equality`);
      }
      // nothing in the deciding block reads the e-mail or uses a LIKE wildcard
      assert.doesNotMatch(st, /email/i, `${pol} must not read the e-mail`);
      assert.doesNotMatch(st, /~~\*?|\bI?LIKE\b/i, `${pol} must compare by equality, not LIKE`);
      // the old policy of the same name is dropped right before (re-create, not a second permissive policy)
      assert.match(CURRENT.sql, new RegExp(`DROP POLICY IF EXISTS ${pol} ON storage\\.objects;\\s*CREATE POLICY ${pol} ON storage\\.objects`));
    });
  }

  it('the key is 128 random bits from the database, and the table is closed to client roles', () => {
    const t = statement(CURRENT.sql, /CREATE TABLE IF NOT EXISTS public\.member_photo_keys/);
    assert.match(t, /object_key text NOT NULL DEFAULT encode\(extensions\.gen_random_bytes\(16\), 'hex'\)/);
    assert.match(t, /CHECK \(object_key ~ '\^\[0-9a-f\]\{32\}\$'\)/);
    assert.match(t, /UNIQUE \(object_key\)/);
    assert.match(CURRENT.sql, /REVOKE ALL ON TABLE public\.member_photo_keys FROM PUBLIC, anon, authenticated, service_role;\s*GRANT SELECT, INSERT ON TABLE public\.member_photo_keys TO service_role;/);
    assert.doesNotMatch(CURRENT.sql, /GRANT[^;]*\bUPDATE\b[^;]*member_photo_keys/, 'nobody may UPDATE a key');
  });

  it('the postcondition exercises the policies as a member and fails the migration on any other outcome', () => {
    assert.match(CURRENT.sql,
      /IF v_results !~ '\^own_jpg=t,own_png=t,other=f,legacy=f,webp=f,no_member=f,rename_to_other=\[f0\]\$' THEN\s+RAISE EXCEPTION/);
    // the probe writes as authenticated and every sub-block ends in an exception (nothing is kept)
    assert.match(CURRENT.sql, /EXECUTE 'SET LOCAL ROLE authenticated';\s+BEGIN\s+INSERT INTO storage\.objects \(bucket_id, name\)/);
    assert.match(CURRENT.sql, /RAISE EXCEPTION 'probe-rollback' USING ERRCODE = 'P0001';\s+EXCEPTION\s+WHEN insufficient_privilege THEN v_outcome := 'f';/);
  });
});
