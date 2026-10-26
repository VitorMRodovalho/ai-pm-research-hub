#!/usr/bin/env node
/**
 * Moves the existing member photos to opaque object names (item interno, GP 26/10/2026).
 *
 * The bucket `member-photos` is PUBLIC and `members.photo_url` / `persons.photo_url` carry the object
 * URL. Before this change the object name was the member's e-mail (or, for a few old objects, the
 * member's name). The new name is `avatars/<key>.<jpg|png>`, `<key>` being the member's row in
 * `public.member_photo_keys` (see supabase/functions/upload-member-asset/photo-path.ts, imported below
 * so the rule lives in one file).
 *
 * THE ORCHESTRATOR RUNS THIS, in this order (each step is safe to repeat):
 *   1. --dry-run (default)   counts only, writes nothing.
 *   2. --apply               per member: copy the object to its opaque name, verify the copy as the
 *                            consumer sees it (public HEAD 200, same byte length, same content type),
 *                            then swap the URL in members AND persons in one transaction
 *                            (public._member_photo_swap_url). Every step is appended to the mapping
 *                            file BEFORE the next one, so a crash leaves a record. Never deletes.
 *   3. --delete-originals    refuses unless every mapped copy verifies and no members/persons row
 *                            still references a mapped original; prints the count; deletes only with
 *                            --confirm=<that count>.
 *   4. --delete-orphans      optional, GP's call: objects no members/persons row references. Same
 *                            count-then-confirm gate.
 *   --rollback               puts the old URLs back (copying an original back first if it was already
 *                            deleted). Count-then-confirm gate.
 *
 * Output is COUNTS ONLY: no name, e-mail, object name, URL or id is ever printed. The mapping file
 * holds the old object names, so it must live OUTSIDE the repository (checked) and is written 0600.
 *
 * The cached-URL columns handled here are the ones a full read-only enumeration of every text/json
 * column found on 26/10/2026: public.members.photo_url and public.persons.photo_url. That enumeration
 * is too slow for a PostgREST call, so the orchestrator re-runs it with execute_sql before --apply and
 * before --delete-originals (the query is in the PR body); if it ever names a third column, stop.
 *
 * Env:
 *   SUPABASE_URL (or PUBLIC_SUPABASE_URL)
 *   SUPABASE_SERVICE_ROLE_KEY     required for everything except the partial dry-run
 *   PUBLIC_SUPABASE_ANON_KEY      (or SUPABASE_PUBLISHABLE_KEY) enough for a PARTIAL dry-run that
 *                                 reads only what a visitor can read (public_members + public HEAD)
 *   MEMBER_PHOTOS_MAPPING_FILE    absolute path outside the repo; required for --apply, --delete-originals, --delete-orphans and --rollback
 *
 * Usage (from the main clone, which has .env):
 *   node --env-file=.env scripts/member-photos-opaque.mjs [--dry-run]
 *   MEMBER_PHOTOS_MAPPING_FILE=~/member-photos-map.jsonl node --env-file=.env scripts/member-photos-opaque.mjs --apply
 *   ... --delete-originals            (prints the count, refuses)
 *   ... --delete-originals --confirm=N
 */
import { appendFileSync, chmodSync, existsSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, isAbsolute, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  OPAQUE_PHOTO_PATH_RE,
  PHOTO_KEY_RE,
  isOwnOpaquePhotoPath,
} from '../supabase/functions/upload-member-asset/photo-path.ts';

export const BUCKET = 'member-photos';
export const PUBLIC_MARKER = `/storage/v1/object/public/${BUCKET}/`;
export const URL_COLUMNS = ['members.photo_url', 'persons.photo_url'];
const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// ── pure helpers (exported for the guard) ──────────────────────────────────────────────────────────────

/** Object name inside the bucket for a stored URL, without the query string. Null if not this bucket. */
export function pathFromPublicUrl(url) {
  if (typeof url !== 'string') return null;
  const i = url.indexOf(PUBLIC_MARKER);
  if (i < 0) return null;
  const raw = url.slice(i + PUBLIC_MARKER.length).split('?')[0].split('#')[0];
  if (!raw) return null;
  try { return decodeURIComponent(raw); } catch { return null; }
}

/** Shape class of an object name. Never returns the name. */
export function classifyObjectName(name) {
  if (OPAQUE_PHOTO_PATH_RE.test(name)) return 'opaque';
  if (name.startsWith('avatars/')) return 'legacy_avatar';
  if (!name.includes('/')) return 'legacy_root';
  return 'other';
}

/** Heuristic: stem ends like a sanitized e-mail (`local_domain_tld`). Used for the count only. */
export function looksEmailShaped(name) {
  const stem = String(name).split('/').pop().replace(/\.[A-Za-z0-9]+$/, '');
  return /^[^_]+(_[^_]+)*_[a-z0-9-]+_[a-z]{2,24}$/i.test(stem);
}

/** Opaque target for an existing object: same key, extension normalized to jpg|png. Null if unsupported. */
export function opaqueTargetFor(oldPath, objectKey) {
  if (!PHOTO_KEY_RE.test(objectKey)) return null;
  const ext = String(oldPath).split('.').pop().toLowerCase();
  const norm = ext === 'jpg' || ext === 'jpeg' ? 'jpg' : ext === 'png' ? 'png' : null;
  return norm ? `avatars/${objectKey}.${norm}` : null;
}

/** What to do for one member row. */
export function planMember({ photoUrl, objectKey }) {
  const oldPath = pathFromPublicUrl(photoUrl);
  if (!oldPath) return { state: 'not_in_bucket' };
  if (!objectKey || !PHOTO_KEY_RE.test(objectKey)) return { state: 'no_key', oldPath };
  if (isOwnOpaquePhotoPath(oldPath, objectKey)) return { state: 'already_opaque', oldPath };
  if (OPAQUE_PHOTO_PATH_RE.test(oldPath)) return { state: 'opaque_not_own', oldPath };
  const newPath = opaqueTargetFor(oldPath, objectKey);
  if (!newPath) return { state: 'unsupported_ext', oldPath };
  return { state: 'legacy', oldPath, newPath };
}

/** The mapping file must be absolute and outside the repository. */
export function assertOutsideRepo(file, repoRoot = REPO_ROOT) {
  if (!file || !isAbsolute(file)) throw new Error('MEMBER_PHOTOS_MAPPING_FILE must be an absolute path');
  const dir = existsSync(dirname(file)) ? realpathSync(dirname(file)) : resolve(dirname(file));
  const root = existsSync(repoRoot) ? realpathSync(repoRoot) : resolve(repoRoot);
  const rel = relative(root, dir);
  if (rel === '' || (!rel.startsWith('..') && !isAbsolute(rel))) {
    throw new Error('MEMBER_PHOTOS_MAPPING_FILE must be OUTSIDE the repository');
  }
  return file;
}

/**
 * Latest state per member from the JSONL mapping. `swapped` follows the LAST swap/rollback line, so a
 * member rolled back and applied again reads as swapped.
 */
export function foldMapping(lines) {
  const byMember = new Map();
  for (const line of lines) {
    if (!line.trim()) continue;
    const e = JSON.parse(line);
    const cur = byMember.get(e.member_id) || { swapped: false, originalDeleted: false };
    const next = { ...cur, ...e };
    if (e.step === 'swapped') next.swapped = true;
    if (e.step === 'rolled_back') next.swapped = false;
    if (e.step === 'deleted_original') next.originalDeleted = true;
    if (e.step === 'copied_back') next.originalDeleted = false;
    delete next.step;
    byMember.set(e.member_id, next);
  }
  return byMember;
}

/**
 * The delete gate. `entries` are the mapped members; for each the caller measured whether the copy
 * verifies, whether the original still exists, and whether any members/persons row still references
 * the original. Returns { refuse } or { toDelete }.
 */
export function decideOriginalsDeletion(entries, confirm) {
  if (entries.length === 0) return { refuse: 'nothing mapped' };
  const unverified = entries.filter((e) => !e.copyVerified).length;
  if (unverified > 0) return { refuse: `${unverified} mapped copy(ies) do not verify` };
  const referenced = entries.filter((e) => e.originalReferenced).length;
  if (referenced > 0) return { refuse: `${referenced} original(s) still referenced by a DB row` };
  const toDelete = entries.filter((e) => e.originalExists).map((e) => e.oldPath);
  if (confirm !== toDelete.length) return { refuse: `confirm with --confirm=${toDelete.length}`, count: toDelete.length };
  return { toDelete };
}

export function parseArgs(argv) {
  const modes = ['--dry-run', '--apply', '--delete-originals', '--delete-orphans', '--rollback'];
  const picked = argv.filter((a) => modes.includes(a));
  if (picked.length > 1) throw new Error(`pick one mode, got ${picked.length}`);
  const unknown = argv.filter((a) => !modes.includes(a) && !/^--confirm=\d+$/.test(a));
  if (unknown.length) throw new Error(`unknown argument(s): ${unknown.length}`);
  const c = argv.find((a) => a.startsWith('--confirm='));
  return { mode: (picked[0] || '--dry-run').slice(2), confirm: c ? Number(c.split('=')[1]) : null };
}

// ── I/O ────────────────────────────────────────────────────────────────────────────────────────────────

function env() {
  const url = (process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL || '').replace(/\/+$/, '');
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
  const publishable = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_PUBLISHABLE_KEY || '';
  return { url, service, publishable };
}

const encPath = (p) => p.split('/').map(encodeURIComponent).join('/');

function client({ url, key }) {
  const headers = { apikey: key, Authorization: `Bearer ${key}` };
  const call = async (path, init = {}) => {
    const res = await fetch(`${url}${path}`, { ...init, headers: { ...headers, ...(init.headers || {}) } });
    return res;
  };
  return {
    async restGet(route) {
      const res = await call(`/rest/v1/${route}`, { headers: { Accept: 'application/json' } });
      if (!res.ok) throw new Error(`GET rest ${route.split('?')[0]} -> ${res.status}`);
      return res.json();
    },
    async restPost(route, body, prefer = 'return=minimal') {
      return call(`/rest/v1/${route}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Prefer: prefer }, body: JSON.stringify(body) });
    },
    async rpc(fn, args) {
      const res = await call(`/rest/v1/rpc/${fn}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
      const text = await res.text();
      if (!res.ok) throw new Error(`rpc ${fn} -> ${res.status}`);
      return text ? JSON.parse(text) : null;
    },
    /** The consumer's view: the public URL. */
    async publicHead(path) {
      const res = await fetch(`${url}${PUBLIC_MARKER}${encPath(path)}`, { method: 'HEAD' });
      return { status: res.status, length: Number(res.headers.get('content-length') ?? NaN), type: res.headers.get('content-type') || '' };
    },
    /** The origin's view (service role, no CDN): HEAD /object/<bucket>/<path>. */
    async originHead(path) {
      const res = await call(`/storage/v1/object/${BUCKET}/${encPath(path)}`, { method: 'HEAD' });
      return { status: res.status, length: Number(res.headers.get('content-length') ?? NaN) };
    },
    async copy(from, to) {
      const res = await call('/storage/v1/object/copy', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ bucketId: BUCKET, sourceKey: from, destinationKey: to }) });
      return res.status;
    },
    async remove(paths) {
      const res = await call(`/storage/v1/object/${BUCKET}`, { method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ prefixes: paths }) });
      if (!res.ok) throw new Error(`delete -> ${res.status}`);
      return res.json();
    },
    async list(prefix) {
      const out = [];
      for (let offset = 0; ; offset += 1000) {
        const res = await call(`/storage/v1/object/list/${BUCKET}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: 'name', order: 'asc' } }) });
        if (!res.ok) throw new Error(`list -> ${res.status}`);
        const page = await res.json();
        out.push(...page);
        if (page.length < 1000) return out;
      }
    },
  };
}

async function listAllObjects(c) {
  const names = [];
  const walk = async (prefix) => {
    for (const e of await c.list(prefix)) {
      const full = prefix ? `${prefix}/${e.name}` : e.name;
      if (e.id == null) await walk(full); else names.push(full);
    }
  };
  await walk('');
  return names;
}

const LIKE = `like.*${PUBLIC_MARKER}*`;
async function readRefs(c) {
  const q = (cols) => `${cols}&photo_url=${encodeURIComponent(LIKE)}`;
  const members = await c.restGet(`members?select=${q('id,person_id,photo_url')}`);
  const persons = await c.restGet(`persons?select=${q('id,photo_url')}`);
  const keys = await c.restGet('member_photo_keys?select=member_id,object_key');
  return { members, persons, keyOf: new Map(keys.map((k) => [k.member_id, k.object_key])), keyCount: keys.length };
}

function newUrlFor(oldUrl, newPath) {
  const base = oldUrl.slice(0, oldUrl.indexOf(PUBLIC_MARKER) + PUBLIC_MARKER.length);
  return `${base}${encPath(newPath)}`;
}

const tally = () => new Proxy({}, { get: (t, k) => (k in t ? t[k] : 0) });
function print(title, counts) {
  console.log(`\n${title}`);
  for (const [k, v] of Object.entries(counts)) console.log(`  ${k.padEnd(34)} ${v}`);
}

function mappingFile() {
  return assertOutsideRepo(process.env.MEMBER_PHOTOS_MAPPING_FILE || '');
}
function record(file, entry) {
  appendFileSync(file, `${JSON.stringify({ ts: new Date().toISOString(), ...entry })}\n`, { mode: 0o600 });
  chmodSync(file, 0o600);
}
function readMapping(file) {
  if (!existsSync(file)) throw new Error('mapping file not found');
  return foldMapping(readFileSync(file, 'utf8').split('\n'));
}

// ── modes ──────────────────────────────────────────────────────────────────────────────────────────────

async function dryRunPartial(e) {
  const c = client({ url: e.url, key: e.publishable });
  const rows = await c.restGet(`public_members?select=photo_url&photo_url=${encodeURIComponent(LIKE)}`);
  const t = tally();
  t.public_members_rows_with_bucket_url = rows.length;
  for (const r of rows) {
    const p = pathFromPublicUrl(r.photo_url);
    if (!p) { t.url_unparseable += 1; continue; }
    t[`path_${classifyObjectName(p)}`] += 1;
    if (looksEmailShaped(p)) t.path_email_shaped += 1;
    const h = await c.publicHead(p);
    if (h.status === 200) t.public_head_200 += 1; else t[`public_head_${h.status}`] += 1;
    // what --apply compares: a finite byte length and an image content type on the consumer's HEAD
    if (h.status === 200 && Number.isFinite(h.length) && h.length > 0) t.public_head_with_byte_length += 1;
    if (h.status === 200 && /^image\//.test(h.type)) t.public_head_with_image_type += 1;
  }
  print('PARTIAL dry-run (publishable key: visitor view only; objects, persons, keys and orphans NOT counted)', { ...t });
}

async function dryRun(e) {
  const c = client({ url: e.url, key: e.service });
  const objects = await listAllObjects(c);
  const { members, persons, keyOf, keyCount } = await readRefs(c);
  const o = tally();
  o.objects_total = objects.length;
  for (const n of objects) {
    o[`objects_${classifyObjectName(n)}`] += 1;
    if (looksEmailShaped(n)) o.objects_email_shaped += 1;
  }
  const referenced = new Set([...members, ...persons].map((r) => pathFromPublicUrl(r.photo_url)).filter(Boolean));
  o.objects_referenced = objects.filter((n) => referenced.has(n)).length;
  o.objects_orphan = objects.length - o.objects_referenced;
  o.objects_orphan_legacy = objects.filter((n) => !referenced.has(n) && classifyObjectName(n) !== 'opaque').length;
  print('objects in member-photos', { ...o });

  const m = tally();
  m.member_photo_keys_rows = keyCount;
  m['members.photo_url rows in bucket'] = members.length;
  const legacyPaths = new Set();
  const objectSet = new Set(objects);
  for (const r of members) {
    const plan = planMember({ photoUrl: r.photo_url, objectKey: keyOf.get(r.id) });
    m[`members_${plan.state}`] += 1;
    if (plan.state === 'legacy') {
      legacyPaths.add(plan.oldPath);
      if (!objectSet.has(plan.oldPath)) m.members_legacy_source_missing += 1;
      if (objectSet.has(plan.newPath)) m.members_legacy_target_exists += 1;
    }
  }
  m['persons.photo_url rows in bucket'] = persons.length;
  for (const r of persons) {
    const p = pathFromPublicUrl(r.photo_url);
    const cls = p ? classifyObjectName(p) : 'unparseable';
    if (cls !== 'opaque') {
      m.persons_legacy += 1;
      if (!legacyPaths.has(p)) m.persons_legacy_not_covered_by_a_member += 1;
    } else m.persons_opaque += 1;
  }
  print(`rows (columns handled: ${URL_COLUMNS.join(', ')})`, { ...m });
}

async function apply(e) {
  const file = mappingFile();
  const c = client({ url: e.url, key: e.service });
  let { members, keyOf } = await readRefs(c);
  const t = tally();
  // members without a key row (created after the migration and never uploaded): create it, value from the DB default
  for (const r of members.filter((x) => !keyOf.get(x.id))) {
    const res = await c.restPost('member_photo_keys', { member_id: r.id });
    if (res.ok || res.status === 409) t.keys_created_or_present += 1; else t.keys_create_failed += 1;
  }
  if (t.keys_created_or_present) ({ members, keyOf } = await readRefs(c));

  for (const r of members) {
    const plan = planMember({ photoUrl: r.photo_url, objectKey: keyOf.get(r.id) });
    if (plan.state !== 'legacy') { t[`skipped_${plan.state}`] += 1; continue; }
    const src = await c.publicHead(plan.oldPath);
    if (src.status !== 200 || !Number.isFinite(src.length)) { t.source_not_200 += 1; continue; }
    const dstOrigin = await c.originHead(plan.newPath);
    if (dstOrigin.status === 200) {
      if (dstOrigin.length !== src.length) { t.target_exists_different_size += 1; continue; }
      t.target_already_copied += 1;
    } else {
      const st = await c.copy(plan.oldPath, plan.newPath);
      if (st !== 200) { t[`copy_failed_${st}`] += 1; continue; }
      t.copied += 1;
    }
    const dst = await c.publicHead(plan.newPath);
    if (dst.status !== 200 || dst.length !== src.length || dst.type !== src.type) { t.verify_failed += 1; continue; }
    const newUrl = newUrlFor(r.photo_url, plan.newPath);
    record(file, { step: 'copied', member_id: r.id, old_path: plan.oldPath, new_path: plan.newPath, old_url: r.photo_url, new_url: newUrl, bytes: src.length, content_type: src.type });
    try {
      const out = await c.rpc('_member_photo_swap_url', { p_member_id: r.id, p_from_url: r.photo_url, p_to_url: newUrl });
      record(file, { step: 'swapped', member_id: r.id, persons: out?.persons ?? null });
      t.swapped += 1;
      t.persons_rows_swapped += Number(out?.persons ?? 0);
    } catch { t.swap_failed += 1; }
  }
  print('apply', { ...t });
  await dryRun(e);
}

async function measureMapped(c, byMember) {
  const { members, persons } = await readRefs(c);
  const live = new Set([...members, ...persons].map((r) => pathFromPublicUrl(r.photo_url)).filter(Boolean));
  const entries = [];
  for (const m of byMember.values()) {
    if (!m.swapped) continue;
    const dst = await c.publicHead(m.new_path);
    const orig = await c.originHead(m.old_path);
    entries.push({
      memberId: m.member_id,
      oldPath: m.old_path,
      newPath: m.new_path,
      copyVerified: dst.status === 200 && dst.length === m.bytes,
      originalReferenced: live.has(m.old_path),
      originalExists: orig.status === 200,
    });
  }
  return entries;
}

async function deleteOriginals(e, confirm) {
  const file = mappingFile();
  const c = client({ url: e.url, key: e.service });
  const entries = await measureMapped(c, readMapping(file));
  print('delete-originals: measured', {
    mapped: entries.length,
    copies_verified: entries.filter((x) => x.copyVerified).length,
    originals_still_referenced: entries.filter((x) => x.originalReferenced).length,
    originals_existing: entries.filter((x) => x.originalExists).length,
  });
  const d = decideOriginalsDeletion(entries, confirm);
  if (d.refuse) { console.log(`\nREFUSED: ${d.refuse}`); process.exitCode = 3; return; }
  // positive control for the post-delete check: the origin HEAD must say 200 for a copy we know exists
  const control = await c.originHead(entries[0].newPath);
  if (control.status !== 200) { console.log('\nREFUSED: origin HEAD cannot see a known copy; instrument not trusted'); process.exitCode = 3; return; }
  let deleted = 0;
  for (let i = 0; i < d.toDelete.length; i += 100) deleted += (await c.remove(d.toDelete.slice(i, i + 100))).length;
  let gone = 0;
  for (const p of d.toDelete) if ((await c.originHead(p)).status !== 200) gone += 1;
  for (const x of entries) {
    if (d.toDelete.includes(x.oldPath) && (await c.originHead(x.oldPath)).status !== 200) record(file, { step: 'deleted_original', member_id: x.memberId });
  }
  print('delete-originals: done', { requested: d.toDelete.length, storage_reported_deleted: deleted, origin_head_not_200_after: gone });
  if (gone !== d.toDelete.length) process.exitCode = 1;
}

async function deleteOrphans(e, confirm) {
  // the mapped originals become unreferenced after --apply; they go through --delete-originals, never here
  const mapped = new Set([...readMapping(mappingFile()).values()].map((m) => m.old_path));
  const c = client({ url: e.url, key: e.service });
  const objects = await listAllObjects(c);
  const { members, persons } = await readRefs(c);
  const referenced = new Set([...members, ...persons].map((r) => pathFromPublicUrl(r.photo_url)).filter(Boolean));
  const orphans = objects.filter((n) => !referenced.has(n) && !mapped.has(n));
  print('delete-orphans: measured', { objects: objects.length, referenced: objects.length - orphans.length - objects.filter((n) => mapped.has(n) && !referenced.has(n)).length, mapped_originals_left_for_delete_originals: objects.filter((n) => mapped.has(n) && !referenced.has(n)).length, orphans: orphans.length });
  if (confirm !== orphans.length) { console.log(`\nREFUSED: confirm with --confirm=${orphans.length}`); process.exitCode = 3; return; }
  let deleted = 0;
  for (let i = 0; i < orphans.length; i += 100) deleted += (await c.remove(orphans.slice(i, i + 100))).length;
  print('delete-orphans: done', { requested: orphans.length, storage_reported_deleted: deleted });
}

async function rollback(e, confirm) {
  const file = mappingFile();
  const c = client({ url: e.url, key: e.service });
  const todo = [...readMapping(file).values()].filter((m) => m.swapped);
  console.log(`\nrollback: ${todo.length} member(s) to put back`);
  if (confirm !== todo.length) { console.log(`REFUSED: confirm with --confirm=${todo.length}`); process.exitCode = 3; return; }
  const t = tally();
  for (const m of todo) {
    if ((await c.originHead(m.old_path)).status !== 200) {
      const st = await c.copy(m.new_path, m.old_path);
      if (st !== 200) { t[`copy_back_failed_${st}`] += 1; continue; }
      record(file, { step: 'copied_back', member_id: m.member_id });
      t.copied_back += 1;
    }
    try {
      await c.rpc('_member_photo_swap_url', { p_member_id: m.member_id, p_from_url: m.new_url, p_to_url: m.old_url });
      record(file, { step: 'rolled_back', member_id: m.member_id });
      t.rolled_back += 1;
    } catch { t.swap_back_failed += 1; }
  }
  print('rollback: done', { ...t });
}

async function main() {
  let args;
  try { args = parseArgs(process.argv.slice(2)); } catch (err) { console.error(String(err.message)); process.exit(2); }
  const e = env();
  if (!e.url) { console.error('SUPABASE_URL (or PUBLIC_SUPABASE_URL) is required'); process.exit(2); }
  // the context goes INSIDE the output: which project this measured
  console.log(`project host: ${new URL(e.url).host}   mode: ${args.mode}   key: ${e.service ? 'service_role' : e.publishable ? 'publishable' : 'none'}`);
  if (!e.service) {
    if (args.mode === 'dry-run' && e.publishable) return dryRunPartial(e);
    console.error('SUPABASE_SERVICE_ROLE_KEY is required for this mode'); process.exit(2);
  }
  if (args.mode === 'dry-run') return dryRun(e);
  if (args.mode === 'apply') return apply(e);
  if (args.mode === 'delete-originals') return deleteOriginals(e, args.confirm);
  if (args.mode === 'delete-orphans') return deleteOrphans(e, args.confirm);
  if (args.mode === 'rollback') return rollback(e, args.confirm);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => { console.error(`failed: ${String(err.message).slice(0, 200)}`); process.exit(1); });
}
