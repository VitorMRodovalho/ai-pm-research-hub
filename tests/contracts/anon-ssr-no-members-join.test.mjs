/**
 * p122d sediment — Anon SSR surfaces must not nested-join `members` directly.
 *
 * Why this exists
 * ----------------
 * The 18/Apr p27 LGPD hardening denied anon SELECT on `public.members`. Any
 * SSR or anon-callable query that uses Postgrest nested-join syntax like
 *   .from('blog_posts').select('*, members:author_member_id(name)')
 * fails with HTTP 401/42501, returning NULL/empty to the page and silently
 * breaking it. /blog/[slug].astro carried this pattern for ~3 weeks before
 * surfacing as "Artigo não encontrado" on every post (p122d).
 *
 * Fix is a two-step query: fetch the public table standalone, then fetch
 * the author from `public_members` (the LGPD-safe view designed for anon).
 *
 * This test scans every SSR/anon page for the failing pattern and fails
 * if any reappears. Per project rule: anon must read PII via public_members
 * (or a dedicated SECDEF RPC), never via direct nested-join on members.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';

const ROOTS = [
  'src/pages',
  'src/components',
  'src/lib',
];

const EXCLUDE_FILES = new Set([
  'database.gen.ts',
]);

const NESTED_MEMBERS_JOIN = /\.from\(\s*['"]([^'"]+)['"]\s*\)[\s\S]{0,200}\.select\(\s*['"`]([^'"`]*\bmembers:[^'"`]*)['"`]/g;

async function* walk(dir) {
  let entries;
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch { return; }
  for (const e of entries) {
    if (EXCLUDE_FILES.has(e.name)) continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) {
      yield* walk(full);
    } else if (e.isFile()) {
      yield full;
    }
  }
}

function isAnonOrSsrSurface(filePath) {
  // Astro pages run SSR with the anon key.
  // .tsx components run client-side via navGetSb (user JWT) — those CAN read members.
  return filePath.endsWith('.astro');
}

test('p122d: SSR/anon Astro pages must not nested-join `members` directly', async () => {
  const offenders = [];

  for (const root of ROOTS) {
    const abs = path.resolve(root);
    for await (const file of walk(abs)) {
      if (!isAnonOrSsrSurface(file)) continue;
      const src = await fs.readFile(file, 'utf-8');
      let m;
      NESTED_MEMBERS_JOIN.lastIndex = 0;
      while ((m = NESTED_MEMBERS_JOIN.exec(src)) !== null) {
        const lineNum = src.slice(0, m.index).split('\n').length;
        const rel = path.relative(path.resolve('.'), file);
        offenders.push({
          file: rel,
          line: lineNum,
          table: m[1],
          select_excerpt: m[2].slice(0, 100),
        });
      }
    }
  }

  if (offenders.length > 0) {
    const lines = offenders.map(o =>
      `  ${o.file}:${o.line}  from('${o.table}').select('${o.select_excerpt}…')`
    ).join('\n');
    assert.fail(
      `Found ${offenders.length} anon-unsafe nested-join(s) on \`members\`:\n${lines}\n\n` +
      `Fix: split into two queries — fetch the table standalone, then look up the\n` +
      `author from \`public_members\` (anon-safe LGPD view). See p122d issue log\n` +
      `entry "blog 404 universal" + commit 440ed2d for the canonical pattern.`
    );
  }
});

test('p122d: blog/[slug].astro uses the canonical two-step pattern', async () => {
  const src = await fs.readFile(path.resolve('src/pages/blog/[slug].astro'), 'utf-8');

  assert.match(
    src,
    /\.from\(\s*['"]public_members['"]/,
    'blog/[slug].astro must use public_members for author lookup (anon-safe).'
  );

  // Only flag the pattern when it appears inside a `.select(...)` call (literal Postgrest
  // nested-join syntax). The same string appearing in a comment that explains the bug
  // is OK — what we're guarding against is a real .from('blog_posts').select('..., members:...').
  assert.doesNotMatch(
    src,
    /\.select\(\s*['"`][^'"`]*members:author_member_id/,
    'blog/[slug].astro must not reintroduce the nested join `members:author_member_id` inside a .select() call (regression of p122d).'
  );
});
