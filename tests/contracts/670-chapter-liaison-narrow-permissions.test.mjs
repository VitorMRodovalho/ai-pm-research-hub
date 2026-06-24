import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();

/**
 * #670 — chapter_liaison (Ponto Focal do Capítulo) gets VISIBILITY, never the full admin
 * shell. Originally this was asserted against the SSR middleware's CHAPTER_LIAISON_ADMIN_PATHS
 * allowlist — but that middleware (src/middleware/index.ts) was dead/shadowed and was RETIRED
 * in #856 (ADR-0106). The real, live enforcement is the V4 capability allowlist in
 * src/lib/permissions.ts (consumed by canFor(), ADR-0011): chapter_liaison's capability sets
 * must exclude `admin.access` (the admin-shell entry ticket) and stay read-only.
 *
 * Repointed here so the test guards the surface that actually runs in prod.
 */

const permissions = readFileSync(resolve(ROOT, 'src/lib/permissions.ts'), 'utf8');

// Every read-only capability chapter_liaison is currently allowed to hold. The point of
// #670 is that this stays a VISIBILITY allowlist — adding `admin.access` or any
// write/manage capability here must trip this test and force a conscious decision.
const ALLOWED_READONLY_CAPS = new Set([
  'admin.analytics',
  'admin.analytics.chapter',
  'admin.portfolio',
  'admin.partners',
  'admin.sustainability',
  'admin.governance.view',
  'data.view_analytics',
  'content.view_publications',
  'workspace.access',
]);

// The escalation capability that would turn visibility into the full admin shell.
const ADMIN_SHELL_TICKET = 'admin.access';

function chapterLiaisonBlocks(src) {
  // Match every `chapter_liaison: [ ... ]` capability array (tier map + designation map).
  const blocks = [];
  const re = /chapter_liaison:\s*\[([^\]]*)\]/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const caps = m[1]
      .split(',')
      .map((s) => s.trim().replace(/^['"]|['"]$/g, ''))
      .filter((s) => s.length > 0 && !s.startsWith('//'));
    blocks.push(caps);
  }
  return blocks;
}

test('#670 chapter_liaison capability sets are present (tier + designation maps)', () => {
  const blocks = chapterLiaisonBlocks(permissions);
  assert.ok(
    blocks.length >= 2,
    `expected >=2 chapter_liaison capability arrays in src/lib/permissions.ts, found ${blocks.length}`,
  );
});

test('#670 chapter_liaison never holds admin.access (no full admin shell)', () => {
  for (const caps of chapterLiaisonBlocks(permissions)) {
    assert.equal(
      caps.includes(ADMIN_SHELL_TICKET),
      false,
      `chapter_liaison must NOT include "${ADMIN_SHELL_TICKET}" — it grants visibility only, ` +
        `never the full admin shell (#670). Caps: ${JSON.stringify(caps)}`,
    );
  }
});

test('#670 chapter_liaison stays read-only (every capability is on the visibility allowlist)', () => {
  for (const caps of chapterLiaisonBlocks(permissions)) {
    for (const cap of caps) {
      assert.ok(
        ALLOWED_READONLY_CAPS.has(cap),
        `chapter_liaison capability "${cap}" is not on the #670 read-only allowlist. ` +
          `If this is a deliberate, still-read-only addition, add it to ALLOWED_READONLY_CAPS here; ` +
          `if it is a write/manage capability, it must NOT be granted to chapter_liaison.`,
      );
    }
  }
});
