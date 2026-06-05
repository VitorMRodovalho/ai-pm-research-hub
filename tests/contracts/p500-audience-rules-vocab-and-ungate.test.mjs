/**
 * #500 — recurring/single modal audience scopes must write an event_audience rule.
 *
 * Bug: the modals emit `all | tribe | initiative | leadership | curators`, but
 * buildAudienceRules only handled `all_active_operational | tribe | role |
 * specific_members`, so all/leadership/curators fell through to [] → no
 * event_audience_rules row → register_own_presence self-checkin fell open
 * (live: 79/139 leadership events). The recurring path additionally gated the
 * audience write on `tagIds.length`, so tag-less series wrote nothing.
 *
 * Fix (frontend-only, no migration):
 *  1. buildAudienceRules maps the modal vocab (all→all_active_operational,
 *     leadership→role[mgr/dep/leader], curators→role[curate_content designation],
 *     tribe→tribe, initiative→all_active_operational).
 *  2. The recurring create path writes the audience rule for EVERY created event
 *     (no longer gated on tagIds.length); set_event_audience replaces (DELETE+INSERT).
 *
 * curate_content works because register_own_presence matches a target_type='role'
 * rule against operational_role OR the member's designations[] (verified live).
 *
 * Static source assertions (.astro inline fn — house convention). DEFERRED to the
 * issue: backfill of the 79 existing rule-less leadership events (data decision).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SRC = readFileSync(resolve(process.cwd(), 'src/pages/attendance.astro'), 'utf8');

// isolate the buildAudienceRules function body
function fnBody() {
  const i = SRC.indexOf('function buildAudienceRules');
  assert.ok(i >= 0, 'buildAudienceRules present');
  // buildAudienceRules is the only function in this file that `return rules;` — first occurrence after
  // its declaration is its own return (relies on source order; fine for this single-writer helper).
  const end = SRC.indexOf('return rules;', i);
  assert.ok(end > i, 'buildAudienceRules end (return rules;) found');
  return SRC.slice(i, end + 'return rules;'.length);
}

test('#500: buildAudienceRules maps the leadership scope to role rules', () => {
  const body = fnBody();
  assert.match(body, /audienceValue === 'role' \|\| audienceValue === 'leadership'/,
    "'leadership' (modal vocab) must be accepted alongside the internal 'role'.");
  assert.match(body, /\['manager', 'deputy_manager', 'tribe_leader'\]/,
    'leadership must expand to the three leadership operational roles.');
});

test('#500: buildAudienceRules maps curators to the curate_content designation', () => {
  const body = fnBody();
  assert.match(body, /audienceValue === 'curators'/, "'curators' scope must have a branch.");
  assert.match(body, /target_type: 'role', target_value: 'curate_content'/,
    "curators must gate via a role rule on the curate_content designation (matched by register_own_presence).");
});

test('#500: buildAudienceRules maps all/initiative to all_active_operational', () => {
  const body = fnBody();
  assert.match(
    body,
    /audienceValue === 'all_active_operational' \|\| audienceValue === 'all' \|\| audienceValue === 'initiative'/,
    "'all' and 'initiative' modal scopes must gate as all_active_operational (no target_type=initiative exists).");
});

test('#500: the previously-dropped modal scopes no longer fall through to []', () => {
  // regression guard: none of the live-affected scopes may be absent from the builder
  const body = fnBody();
  for (const scope of ["'all'", "'leadership'", "'curators'"]) {
    assert.ok(body.includes(scope), `buildAudienceRules must handle the ${scope} modal scope`);
  }
});

test('#500: recurring create writes the audience rule for every event (not tag-gated)', () => {
  // the old guard `if (tagIds.length && data.event_ids?.length)` around the
  // assignEventTagsAndAudience loop must be gone.
  assert.doesNotMatch(SRC, /if \(tagIds\.length && data\.event_ids\?\.length\)/,
    'the recurring audience write must not be gated on tagIds.length (caused tag-less series to fall open).');
  // the loop must now run under an event-only guard
  assert.match(SRC, /if \(data\.event_ids\?\.length\)\s*\{[\s\S]{0,400}?assignEventTagsAndAudience\(eid/,
    'recurring create must call assignEventTagsAndAudience(eid, …) under an event-only guard.');
});
