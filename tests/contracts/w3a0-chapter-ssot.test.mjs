/**
 * Contract: Wave 3a-0 #740 — chapter SSOT display (retire chapter_canonical guess).
 *
 * The chapter display in /admin/selection used `chapter_canonical` — the FIRST
 * non-"PMI Global" token of the free-text service_history_chapters string — an
 * arbitrary, order-dependent guess that was wrong for multi-chapter members.
 * This step derives the display from the reliable `pmi_memberships` snapshot and
 * never endorses the form-declared value as "canonical".
 *
 *  - Migration surfaces pmi_canonical.pmi_memberships in get_selection_dashboard.
 *  - selection.astro derives BR affiliations from pmi_memberships (robust BR
 *    suffix detection) and no longer reads chapter_canonical as the headline.
 *  - Sergipe (the one BR token missing from the name→code map) is mapped.
 *  - 3-dict i18n parity for the new chrome keys.
 *  - ADR-0104 documents the SSOT direction.
 *
 * Static-only (reads source) → runs without DB env.
 *
 * Cross-ref: #740 Wave 3, ADR-0104, ADR-0009.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIG_PATH = 'supabase/migrations/20260805000189_w3a0_get_selection_dashboard_pmi_memberships.sql';
const SEL_PATH = 'src/pages/admin/selection.astro';
const ADR_PATH = 'docs/adr/ADR-0104-chapter-affiliations-ssot.md';
const MIG = readFileSync(MIG_PATH, 'utf8');
const SEL = readFileSync(SEL_PATH, 'utf8');

const DICTS = {
  'pt-BR': readFileSync('src/i18n/pt-BR.ts', 'utf8'),
  'en-US': readFileSync('src/i18n/en-US.ts', 'utf8'),
  'es-LATAM': readFileSync('src/i18n/es-LATAM.ts', 'utf8'),
};

const NEW_KEYS = [
  'admin.selection.modal.chapterAffiliationsTitle',
  'admin.selection.modal.chapterNonBrLabel',
  'admin.selection.modal.chapterFormDeclaredLabel',
];

describe('w3a0 — migration surfaces pmi_memberships', () => {
  it('migration file exists and adds the additive key in pmi_canonical', () => {
    assert.ok(existsSync(MIG_PATH));
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_selection_dashboard/);
    assert.match(MIG, /'pmi_memberships', COALESCE\(a\.pmi_memberships, '\[\]'::jsonb\)/);
  });

  it('keeps chapter_canonical in the payload (backward compat, additive change)', () => {
    assert.match(MIG, /'chapter_canonical',/);
  });
});

describe('w3a0 — selection.astro derives from pmi_memberships', () => {
  it('reads pmi_memberships from the row, not chapter_canonical as headline', () => {
    assert.match(SEL, /pmiCanonical\.pmi_memberships/);
    // chapterDisplay must derive from the headline (affiliations), not chapterCanonicalCode
    assert.match(SEL, /const chapterDisplay = headline/);
    assert.doesNotMatch(SEL, /const chapterDisplay = chapterCanonicalCode/);
  });

  it('uses robust BR detection by ", Brazil Chapter" suffix in a shared helper', () => {
    // The BR/non-BR partition lives in one helper (no duplicated loop) that uses the
    // robust suffix check, and is called from both the list row and the modal.
    assert.match(SEL, /function parsePmiMembershipsBr/);
    assert.match(SEL, /name\.endsWith\(', Brazil Chapter'\)/);
    const callSites = SEL.match(/parsePmiMembershipsBr\(/g) || [];
    assert.ok(callSites.length >= 3, `expected helper def + >=2 call sites, got ${callSites.length}`);
  });

  it('maps Sergipe (the missing BR token) to a PMI code', () => {
    assert.match(SEL, /'Sergipe, Brazil Chapter': 'PMI-SE'/);
  });

  it('surfaces non-BR affiliations instead of dropping them', () => {
    assert.match(SEL, /nonBrAffiliations/);
    assert.match(SEL, /modalNonBrAffiliations/);
  });
});

describe('w3a0 — i18n 3-dict parity for new chrome keys', () => {
  for (const key of NEW_KEYS) {
    for (const [loc, body] of Object.entries(DICTS)) {
      it(`${loc} has ${key}`, () => {
        assert.ok(body.includes(`'${key}'`), `${loc} missing ${key}`);
      });
    }
  }
});

describe('w3a0 — ADR-0104 documents the SSOT direction', () => {
  it('ADR exists and names the canonical sources', () => {
    assert.ok(existsSync(ADR_PATH));
    const adr = readFileSync(ADR_PATH, 'utf8');
    assert.match(adr, /member_chapter_affiliations/);
    assert.match(adr, /entry_chapter_code/);
    assert.match(adr, /is retired as the authoritative display/i);
  });
});
