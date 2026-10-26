/**
 * Member photo object names are opaque (item interno, GP 26/10/2026).
 *
 * The bucket member-photos is public and photo_url carries the object URL, so the object name was
 * public. It used to be the member's e-mail. This guard pins the three places that decide the name
 * and the one that moves the existing objects:
 *
 *   1. photo-path.ts: the only function that builds the name, exercised directly (behaviour, not text).
 *   2. upload-member-asset: the photo branch builds the path from the caller's own key, never from
 *      the e-mail, and removes the stale extension only AFTER the new URL is saved.
 *   3. profile.astro: skips its own update_my_profile when the EF already saved the URL.
 *   4. the two SQL functions, read from their CURRENT capture (latestFunctionCapture), never a pinned file.
 *   5. scripts/member-photos-opaque.mjs: pure decisions exercised directly; --apply never deletes;
 *      the delete gate runs before any removal; the output interpolates no name, path or URL; the CLI
 *      refuses before any network call when the key or the mapping file is wrong.
 *
 * Fixtures are synthetic (no real key, name, e-mail or object name). Static plus pure function calls:
 * no database, no network.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import {
  OPAQUE_PHOTO_PATH_RE,
  photoObjectPath,
  stalePhotoPaths,
  isOwnOpaquePhotoPath,
} from '../../supabase/functions/upload-member-asset/photo-path.ts';
import {
  pathFromPublicUrl,
  classifyObjectName,
  opaqueTargetFor,
  planMember,
  decideOriginalsDeletion,
  assertOutsideRepo,
  parseArgs,
  foldMapping,
} from '../../scripts/member-photos-opaque.mjs';

const ROOT = process.cwd();
const HEX_A = 'a'.repeat(32);
const HEX_B = Array.from({ length: 32 }, (_, i) => (i % 16).toString(16)).join(''); // synthetic
const BASE = 'https://example.supabase.co/storage/v1/object/public/member-photos/';
const LEGACY = 'avatars/someone_example_com.jpg'; // synthetic e-mail-shaped name

const EF = maskJsComments(readFileSync(join(ROOT, 'supabase/functions/upload-member-asset/index.ts'), 'utf8'));
const PROFILE = readFileSync(join(ROOT, 'src/pages/profile.astro'), 'utf8');
const SCRIPT = maskJsComments(readFileSync(join(ROOT, 'scripts/member-photos-opaque.mjs'), 'utf8'));

/** Body of a top-level `async function name(` in a source file, up to the next top-level declaration. */
function fnBlock(src, name) {
  const start = src.indexOf(`async function ${name}(`);
  assert.ok(start >= 0, `missing function ${name}`);
  const next = src.slice(start + 1).search(/\n(?:async function |function |export |if \(import\.meta)/);
  return next < 0 ? src.slice(start) : src.slice(start, start + 1 + next);
}

// ── 1. the name ────────────────────────────────────────────────────────────────────────────────────────
test('photoObjectPath: avatars/<key>.<jpg|png>, nothing else goes into the name', () => {
  assert.equal(photoObjectPath(HEX_A, 'image/jpeg'), `avatars/${HEX_A}.jpg`);
  assert.equal(photoObjectPath(HEX_B, 'image/png'), `avatars/${HEX_B}.png`);
  assert.match(photoObjectPath(HEX_B, 'image/png'), OPAQUE_PHOTO_PATH_RE);
});

test('photoObjectPath refuses a key that is not 32 lowercase hex, and any type but JPEG/PNG', () => {
  for (const bad of ['', HEX_A.slice(1), HEX_A.toUpperCase(), 'someone_example_com', `${HEX_A}x`, '../' + HEX_A.slice(3)]) {
    assert.throws(() => photoObjectPath(bad, 'image/jpeg'), /invalid photo object key/);
  }
  assert.throws(() => photoObjectPath(HEX_A, 'image/webp'), /unsupported photo type/);
});

test('stalePhotoPaths is the same key under the other extension; isOwnOpaquePhotoPath checks the key', () => {
  assert.deepEqual(stalePhotoPaths(`avatars/${HEX_A}.jpg`), [`avatars/${HEX_A}.png`]);
  assert.deepEqual(stalePhotoPaths(`avatars/${HEX_A}.png`), [`avatars/${HEX_A}.jpg`]);
  assert.throws(() => stalePhotoPaths(LEGACY), /not an opaque photo path/);
  assert.equal(isOwnOpaquePhotoPath(`avatars/${HEX_A}.png`, HEX_A), true);
  assert.equal(isOwnOpaquePhotoPath(`avatars/${HEX_B}.png`, HEX_A), false);
});

// ── 2. the Edge Function ───────────────────────────────────────────────────────────────────────────────
test('EF: the photo path comes from the caller own key, and the photo branch never reads the e-mail', () => {
  assert.match(EF, /\.from\("members"\)\.select\("id,email"\)\.eq\("auth_id", user\.id\)\.maybeSingle\(\)/);
  const branch = EF.slice(EF.indexOf('if (kind === "photo") {'), EF.indexOf('} else {', EF.indexOf('if (kind === "photo") {')));
  assert.match(branch, /path = photoObjectPath\(await ownPhotoKey\(admin, member\.id\), file\.type\);/);
  assert.doesNotMatch(branch, /email/);
});

test('EF: the key is read by member id and created without a value (the DB default makes it)', () => {
  const fn = fnBlock(EF, 'ownPhotoKey');
  assert.match(fn, /\.from\("member_photo_keys"\)\.select\("object_key"\)\.eq\("member_id", memberId\)/);
  assert.match(fn, /\.insert\(\{ member_id: memberId \}\)/);
  assert.match(fn, /if \(!PHOTO_KEY_RE\.test\(key\)\) throw/);
});

test('EF: the stale extension is removed only after update_my_profile saved the new URL', () => {
  assert.equal((EF.match(/\.remove\(/g) || []).length, 1, 'the EF removes objects in exactly one place');
  assert.match(EF,
    /userClient\.rpc\("update_my_profile", \{ p_fields: \{ photo_url: url \} \}\);\s*if \(saveErr \|\| [^)]*\)\?\.error\) \{\s*return json\([\s\S]*?\}\s*const \{ error: rmErr \} = await admin\.storage\.from\(cfg\.bucket\)\.remove\(stalePhotoPaths\(path\)\);\s*return json\(\{ success: true, url, path, bucket: cfg\.bucket, persisted: true/);
});

// ── 3. the page ────────────────────────────────────────────────────────────────────────────────────────
test('profile.astro: one writer per upload (the page saves only when the EF did not)', () => {
  assert.match(PROFILE, /return \{ url: data\.url as string, persisted: data\.persisted === true \};/);
  assert.match(PROFILE,
    /const \{ url: photoUrl, persisted \} = await uploadMemberAsset\(sb, 'photo', file\);\s*if \(!persisted\) await rpcChecked\(sb, 'update_my_profile', \{ p_fields: \{ photo_url: photoUrl \} \}\);/);
});

// ── 4. the SQL functions (current capture) ──────────────────────────────────────────────────────────────
test('member_photo_key_of_caller binds auth.uid() to the member and returns only that key', () => {
  const cap = latestFunctionCapture(ROOT, 'member_photo_key_of_caller');
  const body = maskLineComments(cap.body);
  assert.match(cap.block, /STABLE SECURITY DEFINER\s+SET search_path TO 'public', 'pg_temp'/);
  assert.match(body, /SELECT k\.object_key\s+FROM public\.member_photo_keys k\s+JOIN public\.members m ON m\.id = k\.member_id\s+WHERE auth\.uid\(\) IS NOT NULL\s+AND m\.auth_id = auth\.uid\(\)/);
  const mig = maskLineComments(readFileSync(join(ROOT, 'supabase/migrations', cap.file), 'utf8'));
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.member_photo_key_of_caller\(\) FROM PUBLIC, anon;/);
});

test('_member_photo_swap_url refuses REST callers and swaps exactly one member row or raises', () => {
  const cap = latestFunctionCapture(ROOT, '_member_photo_swap_url');
  const body = maskLineComments(cap.body);
  assert.match(body, /IF public\._request_is_rest_caller\(\) THEN\s+RAISE EXCEPTION/);
  assert.match(body, /UPDATE public\.members SET photo_url = p_to_url\s+WHERE id = p_member_id AND split_part\(photo_url, '\?', 1\) = v_from;\s+GET DIAGNOSTICS v_members = ROW_COUNT;\s+IF v_members <> 1 THEN\s+RAISE EXCEPTION/);
  assert.match(body, /UPDATE public\.persons SET photo_url = p_to_url\s+WHERE split_part\(photo_url, '\?', 1\) = v_from;/);
  const mig = maskLineComments(readFileSync(join(ROOT, 'supabase/migrations', cap.file), 'utf8'));
  assert.match(mig, /REVOKE ALL ON FUNCTION public\._member_photo_swap_url\(uuid, text, text\) FROM PUBLIC, anon, authenticated;\s*GRANT EXECUTE ON FUNCTION public\._member_photo_swap_url\(uuid, text, text\) TO service_role;/);
});

// ── 5. the migration script ────────────────────────────────────────────────────────────────────────────
test('script: pathFromPublicUrl strips the query; classifyObjectName and opaqueTargetFor', () => {
  assert.equal(pathFromPublicUrl(`${BASE}${LEGACY}?t=1`), LEGACY);
  assert.equal(pathFromPublicUrl('https://example.org/elsewhere.jpg'), null);
  assert.equal(classifyObjectName(`avatars/${HEX_A}.jpg`), 'opaque');
  assert.equal(classifyObjectName(LEGACY), 'legacy_avatar');
  assert.equal(classifyObjectName('some-name.jpeg'), 'legacy_root');
  assert.equal(opaqueTargetFor('some-name.jpeg', HEX_A), `avatars/${HEX_A}.jpg`);
  assert.equal(opaqueTargetFor('x.PNG', HEX_A), `avatars/${HEX_A}.png`);
  assert.equal(opaqueTargetFor('x.gif', HEX_A), null);
});

test('script: planMember decides legacy / already opaque / someone else opaque / no key', () => {
  assert.deepEqual(planMember({ photoUrl: `${BASE}${LEGACY}?t=9`, objectKey: HEX_A }),
    { state: 'legacy', oldPath: LEGACY, newPath: `avatars/${HEX_A}.jpg` });
  assert.equal(planMember({ photoUrl: `${BASE}avatars/${HEX_A}.png`, objectKey: HEX_A }).state, 'already_opaque');
  assert.equal(planMember({ photoUrl: `${BASE}avatars/${HEX_B}.png`, objectKey: HEX_A }).state, 'opaque_not_own');
  assert.equal(planMember({ photoUrl: `${BASE}${LEGACY}`, objectKey: undefined }).state, 'no_key');
  assert.equal(planMember({ photoUrl: 'https://example.org/x.jpg', objectKey: HEX_A }).state, 'not_in_bucket');
});

test('script: the delete gate refuses unverified copies, referenced originals and a wrong count', () => {
  const ok = { oldPath: 'o1', copyVerified: true, originalReferenced: false, originalExists: true };
  assert.match(decideOriginalsDeletion([], 0).refuse, /nothing mapped/);
  assert.match(decideOriginalsDeletion([{ ...ok, copyVerified: false }], 1).refuse, /do not verify/);
  assert.match(decideOriginalsDeletion([{ ...ok, originalReferenced: true }], 1).refuse, /still referenced/);
  const noConfirm = decideOriginalsDeletion([ok, { ...ok, oldPath: 'o2', originalExists: false }], null);
  assert.equal(noConfirm.count, 1);
  assert.match(noConfirm.refuse, /--confirm=1/);
  assert.deepEqual(decideOriginalsDeletion([ok, { ...ok, oldPath: 'o2', originalExists: false }], 1), { toDelete: ['o1'] });
});

test('script: the mapping file must be absolute and outside the repo; mapping state follows the last line', () => {
  assert.throws(() => assertOutsideRepo(join(ROOT, 'map.jsonl'), ROOT), /OUTSIDE the repository/);
  assert.throws(() => assertOutsideRepo(join(ROOT, 'scripts', 'map.jsonl'), ROOT), /OUTSIDE the repository/);
  assert.throws(() => assertOutsideRepo('relative/map.jsonl', ROOT), /absolute/);
  assert.equal(assertOutsideRepo(join(tmpdir(), 'map.jsonl'), ROOT), join(tmpdir(), 'map.jsonl'));
  const lines = [
    { step: 'copied', member_id: 'm1', old_path: 'o', new_path: 'n' },
    { step: 'swapped', member_id: 'm1' },
    { step: 'rolled_back', member_id: 'm1' },
    { step: 'swapped', member_id: 'm1' },
  ].map((x) => JSON.stringify(x));
  assert.equal(foldMapping(lines).get('m1').swapped, true);
  assert.equal(foldMapping(lines.slice(0, 3)).get('m1').swapped, false);
  assert.equal(foldMapping(lines).get('m1').old_path, 'o');
});

test('script: dry-run is the default and only one mode at a time', () => {
  assert.deepEqual(parseArgs([]), { mode: 'dry-run', confirm: null });
  assert.deepEqual(parseArgs(['--delete-originals', '--confirm=7']), { mode: 'delete-originals', confirm: 7 });
  assert.throws(() => parseArgs(['--apply', '--delete-originals']), /pick one mode/);
  assert.throws(() => parseArgs(['--aply']), /unknown argument/);
});

test('script: --apply never deletes; the delete gate runs before any removal', () => {
  assert.doesNotMatch(fnBlock(SCRIPT, 'apply'), /\.remove\(/);
  const del = fnBlock(SCRIPT, 'deleteOriginals');
  assert.match(del, /const d = decideOriginalsDeletion\(entries, confirm\);\s*if \(d\.refuse\) \{ console\.log\(`\\nREFUSED: \$\{d\.refuse\}`\); process\.exitCode = 3; return; \}[\s\S]*c\.remove\(d\.toDelete/);
  const orph = fnBlock(SCRIPT, 'deleteOrphans');
  assert.match(orph, /if \(confirm !== orphans\.length\) \{ console\.log\(`\\nREFUSED: confirm with --confirm=\$\{orphans\.length\}`\); process\.exitCode = 3; return; \}[\s\S]*c\.remove\(orphans/);
  assert.match(orph, /!referenced\.has\(n\) && !mapped\.has\(n\)/, 'mapped originals never go through --delete-orphans');
});

test('script: --apply records the verified copy before swapping, and swaps only after verification', () => {
  assert.match(fnBlock(SCRIPT, 'apply'),
    /if \(dst\.status !== 200 \|\| dst\.length !== src\.length \|\| dst\.type !== src\.type\) \{ t\.verify_failed \+= 1; continue; \}[\s\S]*?record\(file, \{ step: 'copied'[\s\S]*?c\.rpc\('_member_photo_swap_url'/);
});

test('script: output interpolates counts and fixed labels only, never a name, path or URL', () => {
  const allowed = new Set([
    'title', 'k.padEnd(34)', 'v', 'new URL(e.url).host', 'args.mode',
    "e.service ? 'service_role' : e.publishable ? 'publishable' : 'none'", 'd.refuse',
    'orphans.length', 'todo.length', "URL_COLUMNS.join(', ')", 'String(err.message).slice(0, 200)',
  ]);
  const calls = SCRIPT.match(/console\.(?:log|error)\((?:[^()]|\([^()]*(?:\([^()]*\)[^()]*)*\))*\)/g) || [];
  assert.ok(calls.length >= 8, `expected the script output calls, got ${calls.length}`);
  for (const call of calls) {
    for (const [, expr] of call.matchAll(/\$\{([^}]*(?:\{[^}]*\}[^}]*)?)\}/g)) {
      assert.ok(allowed.has(expr.trim()), `output interpolates ${expr.trim()}`);
    }
  }
  // error messages thrown by the I/O layer carry the table or route, never the object path
  assert.doesNotMatch(SCRIPT, /throw new Error\([^)]*\$\{[^}]*(?:Path|path\b|photo_url|url\b)[^}]*\}/);
});

test('script CLI: refuses before any network call without the service role or with the map inside the repo', () => {
  const U = ['SUPABASE', 'URL'].join('_');
  const S = ['SUPABASE', 'SERVICE', 'ROLE', 'KEY'].join('_');
  const run = (args, extra) => spawnSync(process.execPath, ['scripts/member-photos-opaque.mjs', ...args], {
    cwd: ROOT, encoding: 'utf8', env: { PATH: process.env.PATH, [U]: 'http://127.0.0.1:9', ...extra },
  });
  const noKey = run(['--apply'], {});
  assert.equal(noKey.status, 2);
  assert.match(noKey.stderr, /required for this mode/);
  const inRepo = run(['--apply'], { [S]: 'x', MEMBER_PHOTOS_MAPPING_FILE: join(ROOT, 'map.jsonl') });
  assert.equal(inRepo.status, 1);
  assert.match(inRepo.stderr, /OUTSIDE the repository/);
  assert.doesNotMatch(inRepo.stderr, /fetch failed/);
});
