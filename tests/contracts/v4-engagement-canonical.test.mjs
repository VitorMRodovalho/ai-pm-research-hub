/**
 * ADR-0080 — V4 Engagement Canonical (anti-drift)
 *
 * Contract: src/ should NOT add NEW reads of the V3 legacy mirror column
 * `members.initiative_id`. The canonical V4 reads are:
 *   - RPC `get_member_tribe(member_id)` — single member's primary tribe
 *   - RPC `get_initiative_members(initiative_id)` — roster of an initiative
 *   - JOIN on `engagements` (e.g. WHERE e.person_id = m.person_id AND status='active')
 *
 * ADR-0080 is PROPOSED (pending PM sign-off + Phase A frontend cutover). Until
 * cutover, this test pins the legacy V3 read surface to the **current p166 baseline**
 * via per-file allowlist. Any read introduced in a file NOT in the allowlist is a
 * violation. The allowlist is expected to shrink monotonically as Phase A
 * migrations land — when both allowlists are empty, ADR-0080 I-V4-1 (zero V3
 * reads) holds and Phase B (DB shadow + invariant) can start.
 *
 * See: docs/adr/ADR-0080-v4-engagement-canonical-deprecate-members-initiative-id.md
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Files currently reading `member.initiative_id` via JS field access. Each
// entry maps to a Phase A migration task in ADR-0080. Remove when migrated.
// (Type definition in src/lib/admin/types.ts L12 is a separate Phase A item —
// not enforced here because the regex targets field access, not interface defs.)
const V3_FIELD_READ_ALLOWLIST = new Set([
  'src/hooks/useBoardPermissions.ts', // ~L117 effectiveInitiativeId simulation fallback
  'src/lib/permissions.ts',           // ~L594 getEffectiveInitiativeId helper
]);

// Files currently filtering `public_members.initiative_id` via supabase-js .eq().
// Phase A target: replace with get_initiative_members(initiative_id) RPC.
const V3_PUBLIC_MEMBERS_FILTER_ALLOWLIST = new Set([
  'src/components/boards/TribeKanbanIsland.tsx', // ~L398 sb.from('public_members').eq('initiative_id', ...)
  'src/pages/tribe/[id].astro',                  // ~L1688 sb.from('public_members').eq('initiative_id', ...)
]);

function grepFiles(pattern) {
  try {
    const out = execSync(`grep -rEln ${JSON.stringify(pattern)} src/`, { encoding: 'utf8' });
    return new Set(out.trim().split('\n').filter(Boolean));
  } catch (e) {
    if (e.status === 1) return new Set(); // grep exits 1 when no matches
    throw e;
  }
}

function fileMatchesPublicMembersFilter(absPath) {
  const src = readFileSync(absPath, 'utf8');
  return /from\(['"]public_members['"]\)[\s\S]{0,800}\.eq\(['"]initiative_id['"]/.test(src);
}

test('ADR-0080 I-V4-1a: no NEW JS reads of member.initiative_id (allowlist ratchets to zero in Phase A)', () => {
  const files = grepFiles('\\bmember\\.initiative_id\\b');
  const violations = [...files].filter(f => !V3_FIELD_READ_ALLOWLIST.has(f));

  if (violations.length > 0) {
    assert.fail([
      'ADR-0080 violation: new JS read(s) of `member.initiative_id` detected.',
      'Canonical V4 reads: RPC `get_member_tribe(member_id)` or `engagements` join.',
      'If this is intentional Phase A migration, remove the old file from V3_FIELD_READ_ALLOWLIST',
      'in tests/contracts/v4-engagement-canonical.test.mjs — do not add new entries.',
      ...violations.map(f => `  - ${f}`),
    ].join('\n'));
  }
});

test('ADR-0080 I-V4-1b: no NEW supabase select of public_members.initiative_id', () => {
  const candidates = grepFiles("from\\(['\"]public_members['\"]\\)");
  const violations = [];
  for (const f of candidates) {
    if (V3_PUBLIC_MEMBERS_FILTER_ALLOWLIST.has(f)) continue;
    if (fileMatchesPublicMembersFilter(resolve(process.cwd(), f))) {
      violations.push(f);
    }
  }

  if (violations.length > 0) {
    assert.fail([
      'ADR-0080 violation: new `public_members.initiative_id` filter detected.',
      'Canonical V4 read: RPC `get_initiative_members(initiative_id)`.',
      ...violations.map(f => `  - ${f}`),
    ].join('\n'));
  }
});

test('ADR-0080: allowlists stay honest (no stale entries)', () => {
  const fieldReadFiles = grepFiles('\\bmember\\.initiative_id\\b');
  const staleField = [...V3_FIELD_READ_ALLOWLIST].filter(f => !fieldReadFiles.has(f));

  const psCandidates = grepFiles("from\\(['\"]public_members['\"]\\)");
  const stalePm = [...V3_PUBLIC_MEMBERS_FILTER_ALLOWLIST].filter(f => {
    if (!psCandidates.has(f)) return true;
    return !fileMatchesPublicMembersFilter(resolve(process.cwd(), f));
  });

  if (staleField.length > 0 || stalePm.length > 0) {
    assert.fail([
      'ADR-0080: stale allowlist entries (file no longer contains the pattern — remove it):',
      ...staleField.map(f => `  - V3_FIELD_READ_ALLOWLIST: ${f}`),
      ...stalePm.map(f => `  - V3_PUBLIC_MEMBERS_FILTER_ALLOWLIST: ${f}`),
    ].join('\n'));
  }
});
