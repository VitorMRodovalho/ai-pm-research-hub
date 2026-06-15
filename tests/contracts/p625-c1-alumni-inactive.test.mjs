/**
 * Contract: #625 Camada 1 — alumni × inactive semantics surfaced in /admin/members (Fatia 3).
 *
 * The two terminal states were rendered as bare, unexplained chips. This slice surfaces the
 * canonical rule (frontend + docs only, no schema change):
 *  - membershipBadge() helper renders every terminal state as a labeled chip + tooltip.
 *  - alumni → eligible for re-engagement pipeline; inactive → outside it (sabbatical path).
 *  - Progressive-disclosure legend above the table states the distinction.
 *  - 3-dict i18n parity for the new comp.memberList.status* + legendLabel keys.
 *  - ADR-0071 Amendment 2 documents the as-built rule + the live audit snapshot.
 *
 * Static-only (reads source) → runs without DB env.
 *
 * Cross-ref: #625, ADR-0071 (member lifecycle state machine), ADR-0009 (config-driven kinds).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const ISLAND_PATH = 'src/components/admin/members/MemberListIsland.tsx';
const ADR_PATH = 'docs/adr/ADR-0071-member-lifecycle-state-machine.md';
const ISLAND = readFileSync(ISLAND_PATH, 'utf8');
const ADR = readFileSync(ADR_PATH, 'utf8');

const DICTS = {
  'pt-BR': readFileSync('src/i18n/pt-BR.ts', 'utf8'),
  'en-US': readFileSync('src/i18n/en-US.ts', 'utf8'),
  'es-LATAM': readFileSync('src/i18n/es-LATAM.ts', 'utf8'),
};

describe('p625-c1 Fatia 3 — membershipBadge helper', () => {
  const body = (ISLAND.match(/function membershipBadge[\s\S]*?^}/m) || [])[0] ?? '';

  it('exists and branches on alumni / inactive / observer with a labeled active default', () => {
    assert.ok(body, 'membershipBadge function not found');
    assert.match(body, /case 'observer':/);
    assert.match(body, /case 'alumni':/);
    assert.match(body, /case 'inactive':/);
    assert.match(body, /default:/);
  });

  it('every branch carries a tooltip hint sourced from i18n', () => {
    assert.match(body, /hint: t\('comp\.memberList\.statusAlumniHint'/);
    assert.match(body, /hint: t\('comp\.memberList\.statusInactiveHint'/);
    assert.match(body, /hint: t\('comp\.memberList\.statusObserverHint'/);
    assert.match(body, /hint: t\('comp\.memberList\.statusActiveHint'/);
  });

  it('alumni and inactive are visually distinct (not collapsed to the same chip)', () => {
    assert.match(body, /emoji: '🎓'/); // alumni
    assert.match(body, /emoji: '⏸'/);  // inactive (no longer a bare 🔴)
  });
});

describe('p625-c1 Fatia 3 — status cell + legend wiring', () => {
  it('status cell routes terminal states through membershipBadge with a title tooltip', () => {
    assert.match(ISLAND, /const b = membershipBadge\(m\.member_status, t\)/);
    assert.match(ISLAND, /title=\{b\.hint\}/);
  });

  it('renders the alumni×inactive legend via progressive disclosure', () => {
    assert.match(ISLAND, /comp\.memberList\.legendLabel/);
    assert.match(ISLAND, /<details/);
  });
});

describe('p625-c1 Fatia 3 — i18n parity (3 dicts)', () => {
  const KEYS = [
    'statusActive', 'statusActiveHint',
    'statusObserver', 'statusObserverHint',
    'statusAlumni', 'statusAlumniHint',
    'statusInactive', 'statusInactiveHint',
    'legendLabel',
  ];
  for (const [lang, src] of Object.entries(DICTS)) {
    it(`${lang} has all new comp.memberList status keys`, () => {
      for (const k of KEYS) {
        assert.match(src, new RegExp(`'comp\\.memberList\\.${k}':`), `${lang} missing comp.memberList.${k}`);
      }
    });
  }
});

describe('p625-c1 Fatia 3 — canonical rule documented (ADR-0071)', () => {
  it('records the as-built explicit-choice rule + the stage_alumni gate', () => {
    assert.match(ADR, /Amendment 2 — Canonical alumni×inactive rule/);
    assert.match(ADR, /stage_alumni_for_re_engagement/);
    assert.match(ADR, /admin_offboard_member\(p_new_status\)/);
  });
});
