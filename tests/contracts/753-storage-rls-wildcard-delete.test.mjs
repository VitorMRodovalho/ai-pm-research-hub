/**
 * #753 Parts 2+4 — storage member-write RLS hardening (post-#752 security review).
 *
 * Guards:
 *  - Part 2: the 4 owner policies (+ 2 new DELETE) escape the `_`/`%`/`\` LIKE wildcards that the
 *    @/. email-sanitization injected, so one member can no longer fuzzy-match/overwrite another's file.
 *  - Part 4: owner-scoped DELETE policies exist + profile.astro removes the storage object (not just the DB field).
 *
 * Static source-parse (no DB) — flake-free. The live policies were proven functionally in the PR
 * (own legit path matches; cross path does not).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..', '..');

const MIG = (() => {
  const dir = join(ROOT, 'supabase/migrations');
  const f = readdirSync(dir).find((x) => x.includes('753_storage_rls_wildcard'));
  assert.ok(f, 'the #753 storage RLS migration must exist');
  return readFileSync(join(dir, f), 'utf8');
})();

test('all 6 owner storage policies escape the LIKE wildcards (no fuzzy cross-member match)', () => {
  const escChains = (MIG.match(/replace\(replace\(replace\(/g) || []).length;
  assert.ok(escChains >= 6, `expected >=6 escape chains (4 altered + 2 delete policies), got ${escChains}`);
  // the vulnerable bare form (sanitized email concatenated straight onto '.%') must be gone:
  assert.doesNotMatch(MIG, /regexp_replace\(m\.email, '\[@\.\]', '_', 'g'\)\s*\|\|\s*'\.%'/,
    'must not concat the sanitized email directly to .% (that leaves the injected _ as a LIKE wildcard)');
  // the escaped-underscore replacement target must be present
  assert.match(MIG, /'_',\s*E'\\\\_'/, 'must replace _ with the escaped \\_ token');
});

test('owner-scoped DELETE policies added for both member buckets (LGPD Art.16 minimization)', () => {
  assert.match(MIG, /CREATE POLICY member_signatures_own_delete[\s\S]*?FOR DELETE/,
    'member_signatures_own_delete (FOR DELETE) must be created');
  assert.match(MIG, /CREATE POLICY member_photos_own_delete[\s\S]*?FOR DELETE/,
    'member_photos_own_delete (FOR DELETE) must be created');
});

test('profile.astro signature-remove also deletes the storage object (not just the DB field)', () => {
  const src = readFileSync(join(ROOT, 'src/pages/profile.astro'), 'utf8');
  assert.match(src, /from\('member-signatures'\)\.remove\(/,
    'the remove handler must call storage.from(member-signatures).remove()');
  // the object path must be captured BEFORE the signature_url field is cleared
  assert.match(src, /curSrc[\s\S]*?update_my_profile[\s\S]*?signature_url:\s*''/,
    'must capture the storage path (curSrc) before clearing signature_url');
});
