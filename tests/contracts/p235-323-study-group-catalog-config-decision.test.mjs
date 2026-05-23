/**
 * Forward-defense: p235 #323 / Gap C of #230 reframe —
 *   study_group_* engagement_kinds catalog config decision.
 *
 * Origin: p230 audit (2026-05-23) of #230 reframe surfaced Gap C:
 *   2 catalog rows (study_group_owner + study_group_participant) declared
 *   requires_agreement=true with agreement_template=NULL. That state means
 *   any consumer of `engagement_kinds.agreement_template` cannot mint a
 *   termo for those kinds, and the p203 pending_agreement queue routes
 *   the rows to 'decide_template_for_kind_then_issue' indefinitely.
 *
 * PM decision (#323 close, 2026-05-23):
 *   - study_group_owner: KEEP requires_agreement=true, assign placeholder
 *     slug 'study_group_owner_agreement_v1'. Mirrors ADR-0078 D5
 *     external_reviewer placeholder precedent (slug forward-declared,
 *     template body via follow-up legal-counsel issue).
 *   - study_group_participant: FLIP requires_agreement=false. Course
 *     enrollee model; ADR-0008 "termo de uso" read as platform-wide TOS.
 *     legal_basis stays contract (curso execution).
 *
 * Migration: supabase/migrations/20260805000021_p235_323_study_group_catalog_config_decision.sql
 *
 * Asserts:
 *   - Static (12): migration file present + owner UPDATE assigns placeholder
 *     slug with idempotency guard + participant UPDATE flips requires_agreement
 *     with idempotency guard + audit log INSERT with canonical action +
 *     audit metadata mentions both kinds + sanity DO RAISE EXCEPTION on
 *     invariant violation + sanity uses correct allowlist (volunteer only)
 *     + NOTIFY pgrst issued + header cross-refs #323/ADR-0006/ADR-0008/
 *     ADR-0078 + header documents ROLLBACK strategy + transaction wrapper.
 *   - Forward-defense (2): no future migration re-flips
 *     study_group_owner.agreement_template back to NULL; no future migration
 *     re-flips study_group_participant.requires_agreement back to TRUE.
 *   - DB-gated (1): live catalog has 0 rows where requires_agreement=true
 *     AND agreement_template IS NULL AND slug NOT IN ('volunteer').
 *
 * PM directives (2026-05-23):
 *   - Do NOT mint Herlon term (Herlon's engagements are ambassador +
 *     observer, neither requires_agreement; this migration does not touch).
 *   - Fernando double-engagement (owner + participant same initiative) is
 *     a separate data-quality carry, NOT a #323 blocker.
 *   - Goal metric: 0 catalog rows violating the invariant post-apply.
 *
 * Cross-ref:
 *   - GH #323 (this issue, Gap C of #230 reframe)
 *   - GH #230 (parent umbrella; close-trigger once #323 ships)
 *   - GH #321 (closed p233, Gap A)
 *   - GH #322 (closed p234, Gap B)
 *   - ADR-0006 line 56 (Herlon as study_group_owner canonical V4 example)
 *   - ADR-0008 (per-kind engagement lifecycle)
 *   - ADR-0078 D5 (external_reviewer placeholder slug precedent)
 *   - Migration 20260413500000 (original lifecycle setup)
 *   - Migration 20260725000000 (p203 pending_agreement queue)
 *   - Migration 20260803000001 (p217 #160 ambassador catalog fix —
 *     same forward-defense + sanity DO pattern reused here)
 *   - tests/contracts/engagement-kinds-catalog-invariants.test.mjs
 *     (sibling catalog-level invariant suite from #160 path A')
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const MIGRATION_FILE = resolve(
  MIGRATIONS_DIR,
  '20260805000021_p235_323_study_group_catalog_config_decision.sql'
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ===================================================================
// STATIC migration body assertions (always run — forward-defense)
// ===================================================================

test('p235 #323: migration file present at canonical path', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) =>
    f.startsWith('20260805000021_')
  );
  assert.equal(
    files.length,
    1,
    'Exactly one migration file must exist for version 20260805000021 (p235 #323 Gap C)'
  );
  assert.match(
    files[0],
    /^20260805000021_p235_323_study_group_catalog_config_decision\.sql$/,
    'Migration filename must follow `<timestamp>_<descriptive_name>.sql` per CLAUDE.md GC-097'
  );
});

test('p235 #323: header documents PM decision + cross-refs #323/ADR-0006/ADR-0008/ADR-0078/ROLLBACK', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /PM decision/i, 'Header must document PM decision');
  assert.match(body, /#323/, 'Header must reference issue #323');
  assert.match(body, /ADR-0006/i, 'Header must cross-ref ADR-0006');
  assert.match(body, /ADR-0008/i, 'Header must cross-ref ADR-0008');
  assert.match(body, /ADR-0078/i, 'Header must cross-ref ADR-0078 (placeholder slug precedent)');
  assert.match(body, /ROLLBACK/i, 'Header must include ROLLBACK section');
  // PM directive may wrap across SQL comment lines — tolerate `\n--    ` between words
  assert.match(body, /Do NOT mint Herlon[\s\S]{0,40}?term/i, 'Header must carry the PM directive about Herlon');
});

test('p235 #323: owner UPDATE assigns placeholder slug with idempotency guard', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // Pattern-agnostic: tolerates whitespace + comment lines between SET and WHERE
  const ownerPattern =
    /UPDATE\s+public\.engagement_kinds[\s\S]*?SET[\s\S]*?agreement_template\s*=\s*'study_group_owner_agreement_v1'[\s\S]*?WHERE\s+slug\s*=\s*'study_group_owner'[\s\S]*?AND\s+agreement_template\s+IS\s+NULL/i;
  assert.match(
    body,
    ownerPattern,
    'Must UPDATE study_group_owner SET agreement_template=study_group_owner_agreement_v1 WHERE slug=study_group_owner AND agreement_template IS NULL (idempotent)'
  );
});

test('p235 #323: participant UPDATE flips requires_agreement=false with idempotency guard', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  const participantPattern =
    /UPDATE\s+public\.engagement_kinds[\s\S]*?SET[\s\S]*?requires_agreement\s*=\s*false[\s\S]*?WHERE\s+slug\s*=\s*'study_group_participant'[\s\S]*?AND\s+requires_agreement\s*=\s*true/i;
  assert.match(
    body,
    participantPattern,
    'Must UPDATE study_group_participant SET requires_agreement=false WHERE slug=study_group_participant AND requires_agreement=true (idempotent)'
  );
});

test('p235 #323: audit log INSERT writes canonical engagement_kind.catalog_config_decision action for both kinds', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(
    body,
    /INSERT\s+INTO\s+public\.admin_audit_log/i,
    'Must INSERT INTO public.admin_audit_log for the catalog change audit trail'
  );
  assert.match(
    body,
    /'engagement_kind\.catalog_config_decision'/,
    "Audit action must be the canonical 'engagement_kind.catalog_config_decision' (matches admin_audit_log_action_pattern CHECK)"
  );
  assert.match(
    body,
    /'engagement_kinds'/,
    "Audit target_type must be 'engagement_kinds' (established canonical value)"
  );
  assert.match(
    body,
    /'study_group_owner'[\s\S]*?'assign_placeholder_template_slug'/,
    'Audit metadata must reference study_group_owner with assign_placeholder_template_slug change tag'
  );
  assert.match(
    body,
    /'study_group_participant'[\s\S]*?'flip_requires_agreement_false'/,
    'Audit metadata must reference study_group_participant with flip_requires_agreement_false change tag'
  );
  assert.match(
    body,
    /'migration',\s*'20260805000021'/,
    'Audit metadata must carry the migration version for targeted rollback'
  );
});

test('p235 #323: sanity DO block RAISES EXCEPTION on catalog invariant violation', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /DO\s*\$\$/i, 'Must include DO $$ ... $$ sanity block');
  assert.match(body, /RAISE\s+EXCEPTION/i, 'Sanity block must RAISE EXCEPTION when invariant breaks');
});

test('p235 #323: sanity DO block enforces requires_agreement + agreement_template + allowlist invariant', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // Must check requires_agreement = true AND agreement_template IS NULL AND slug NOT IN ('volunteer')
  // Pattern-agnostic: scan the sanity block region.
  assert.match(
    body,
    /requires_agreement\s*=\s*true[\s\S]*?AND\s+agreement_template\s+IS\s+NULL[\s\S]*?AND\s+slug\s+NOT\s+IN\s*\(\s*'volunteer'\s*\)/i,
    "Sanity must check requires_agreement=true AND agreement_template IS NULL AND slug NOT IN ('volunteer') — non-template mint allowlist"
  );
});

test('p235 #323: NOTIFY pgrst issued (defensive schema cache reload)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /NOTIFY\s+pgrst,?\s*'reload schema'/i, "Must NOTIFY pgrst, 'reload schema'");
});

test('p235 #323: migration wraps changes in BEGIN/COMMIT transaction', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /^BEGIN;/m, 'Must open with BEGIN; to wrap migration in a transaction');
  assert.match(body, /^COMMIT;/m, 'Must close with COMMIT; — sanity DO is inside the transaction');
});

// ===================================================================
// FORWARD-DEFENSE: ratchet down regressions in future migrations
// ===================================================================

test('p235 #323 forward-defense: no future migration re-flips study_group_owner.agreement_template back to NULL', () => {
  const migrations = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  const fixIdx = migrations.findIndex(
    (f) => f === '20260805000021_p235_323_study_group_catalog_config_decision.sql'
  );
  assert.ok(fixIdx >= 0, 'Fix migration must be in the registry to anchor the invariant');

  const subsequent = migrations.slice(fixIdx + 1).map((f) => ({
    name: f,
    body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8'),
  }));

  // UPDATE form: SET agreement_template = NULL ... WHERE slug = 'study_group_owner'
  const reflipPattern =
    /UPDATE\s+public\.engagement_kinds[\s\S]*?SET[\s\S]*?agreement_template\s*=\s*NULL[\s\S]*?WHERE\s+slug\s*=\s*'study_group_owner'/i;

  const offenders = subsequent.filter((m) => reflipPattern.test(m.body));
  assert.equal(
    offenders.length,
    0,
    `Future migrations must not re-flip study_group_owner.agreement_template to NULL. Offenders: ${offenders.map((m) => m.name).join(', ')}`
  );
});

test('p235 #323 forward-defense: no future migration re-flips study_group_participant.requires_agreement back to TRUE', () => {
  const migrations = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  const fixIdx = migrations.findIndex(
    (f) => f === '20260805000021_p235_323_study_group_catalog_config_decision.sql'
  );
  assert.ok(fixIdx >= 0, 'Fix migration must be in the registry to anchor the invariant');

  const subsequent = migrations.slice(fixIdx + 1).map((f) => ({
    name: f,
    body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8'),
  }));

  // UPDATE form: SET requires_agreement = true ... WHERE slug = 'study_group_participant'
  const reflipUpdatePattern =
    /UPDATE\s+public\.engagement_kinds[\s\S]*?SET[\s\S]*?requires_agreement\s*=\s*true[\s\S]*?WHERE\s+slug\s*=\s*'study_group_participant'/i;
  // VALUES-tuple form (per code-reviewer LOW from PR #250 against the ambassador
  // invariant) — anchors to a single VALUES(...) tuple to avoid multi-row
  // false-positives where participant=false but a sibling row in the same
  // VALUES block has true.
  const valuesReflipPattern = /VALUES\s*\([^)]*'study_group_participant'[^)]*,\s*true[^)]*\)/i;
  // ON CONFLICT DO UPDATE form
  const onConflictReflipPattern =
    /ON\s+CONFLICT[\s\S]*?DO\s+UPDATE\s+SET[\s\S]*?requires_agreement\s*=\s*true[\s\S]*?WHERE\s+(public\.engagement_kinds\.slug|slug)\s*=\s*'study_group_participant'/i;

  const offenders = subsequent.filter(
    (m) =>
      reflipUpdatePattern.test(m.body) ||
      valuesReflipPattern.test(m.body) ||
      onConflictReflipPattern.test(m.body)
  );
  assert.equal(
    offenders.length,
    0,
    `Future migrations must not re-flip study_group_participant.requires_agreement to TRUE. Offenders: ${offenders.map((m) => m.name).join(', ')}`
  );
});

// ===================================================================
// DB-GATED: live catalog invariant (skipped offline)
// ===================================================================

test(
  'p235 #323: live catalog has 0 rows with requires_agreement=true AND agreement_template IS NULL AND slug NOT IN (volunteer)',
  { skip: !dbGated ? skipMsg : false },
  async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data, error } = await sb
      .from('engagement_kinds')
      .select('slug, requires_agreement, agreement_template')
      .eq('requires_agreement', true)
      .is('agreement_template', null);

    assert.equal(error, null, `Live query must succeed: ${error?.message || ''}`);

    const offenders = (data || []).filter((row) => row.slug !== 'volunteer');
    assert.equal(
      offenders.length,
      0,
      `Live catalog goal metric violated: ${JSON.stringify(offenders)} (allowlist: ['volunteer'])`
    );
  }
);
