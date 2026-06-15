/**
 * Contract: #625 Camada 2 — /admin/members V4-native (Frontend / Fatia 2).
 *
 * Fatia 1 (DB) shipped the data layer (migs 180/181 — see p625-c2-members-v4.test.mjs).
 * This file covers the island + i18n chrome wiring:
 *  - D3=C1: shared lib/initiatives.ts loader over list_initiatives (no hardcoded fallback).
 *  - D1=C: engagement categories rendered with locale-aware catalog labels
 *    (display_i18n {en,es} with display_name PT-BR fallback).
 *  - D2=B1: term-status farol column 🟢 green / 🟡 amber (🔴 vencido deferred → #571).
 *  - Iniciativa / Capítulo / Ciclo filter selects passing the new RPC params.
 *  - 3-dict i18n parity for the new chrome keys.
 *
 * Static-only (reads source) → runs without DB env.
 *
 * Cross-ref: #625, #571 (term validity → 🔴), ADR-0009 (config-driven kinds).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LIB_INIT_PATH = 'src/lib/initiatives.ts';
const ISLAND_PATH = 'src/components/admin/members/MemberListIsland.tsx';
const LIB_INIT = readFileSync(LIB_INIT_PATH, 'utf8');
const ISLAND = readFileSync(ISLAND_PATH, 'utf8');

const DICTS = {
  'pt-BR': readFileSync('src/i18n/pt-BR.ts', 'utf8'),
  'en-US': readFileSync('src/i18n/en-US.ts', 'utf8'),
  'es-LATAM': readFileSync('src/i18n/es-LATAM.ts', 'utf8'),
};

describe('p625-c2 Fatia 2 — lib/initiatives.ts (D3=C1)', () => {
  it('exists and exports loadInitiatives over the list_initiatives RPC', () => {
    assert.ok(existsSync(LIB_INIT_PATH));
    assert.match(LIB_INIT, /export async function loadInitiatives/);
    assert.match(LIB_INIT, /\.rpc\('list_initiatives'/);
  });

  it('mirrors the chapters loader pattern (module cache + navGetSb fallback + reset)', () => {
    assert.match(LIB_INIT, /let _cache: Initiative\[\] \| null = null/);
    assert.match(LIB_INIT, /navGetSb\?\.\(\)/);
    assert.match(LIB_INIT, /export function resetInitiativesCache/);
  });

  it('has NO hardcoded fallback list — returns [] on failure (initiatives are dynamic config)', () => {
    assert.doesNotMatch(LIB_INIT, /getFallbackInitiatives/);
    // both the no-client and the error branches resolve to an empty array
    assert.match(LIB_INIT, /if \(!client\) return \[\];/);
    assert.match(LIB_INIT, /if \(error \|\| !Array\.isArray\(data\)\) return \[\];/);
  });
});

describe('p625-c2 Fatia 2 — MemberListIsland V4 wiring', () => {
  it('imports the shared loader + locale resolver', () => {
    assert.match(ISLAND, /import \{ loadInitiatives, type Initiative \} from '\.\.\/\.\.\/\.\.\/lib\/initiatives'/);
    assert.match(ISLAND, /import \{ getEffectiveLocale \} from '\.\.\/\.\.\/\.\.\/i18n\/utils'/);
  });

  it('passes the 3 new V4 params to admin_list_members', () => {
    assert.match(ISLAND, /p_initiative_id: initiativeFilter \|\| null/);
    assert.match(ISLAND, /p_chapter: chapterFilter \|\| null/);
    assert.match(ISLAND, /p_cycle: cycleFilter \|\| null/);
  });

  it('kindLabel (D1=C): locale picks display_i18n with display_name PT-BR fallback', () => {
    assert.match(ISLAND, /if \(locale === 'en-US'\) return e\.kind_display_i18n\?\.en \|\| e\.kind_display_name/);
    assert.match(ISLAND, /if \(locale === 'es-LATAM'\) return e\.kind_display_i18n\?\.es \|\| e\.kind_display_name/);
    assert.match(ISLAND, /return e\.kind_display_name;/);
  });

  it('termFarol (D2=B1): renders 🟡 amber / 🟢 green and NEVER 🔴 (deferred to #571)', () => {
    // Scope the assertion to termFarol's body (affiliationFarol legitimately uses 🔴).
    const termBody = (ISLAND.match(/function termFarol[\s\S]*?\n\}/) || [])[0] ?? '';
    assert.ok(termBody, 'termFarol function not found');
    assert.match(termBody, /status === 'amber'/);
    assert.match(termBody, /emoji: '🟡'/);
    assert.match(termBody, /emoji: '🟢'/);
    assert.doesNotMatch(termBody, /🔴/);
  });

  it('reads the new V4 fields from each row (engagements[]/cycles[]/term_status)', () => {
    assert.match(ISLAND, /engagements: EngagementRow\[\]/);
    assert.match(ISLAND, /cycles: CycleRow\[\]/);
    assert.match(ISLAND, /term_status: string/);
  });

  it('renders Iniciativa / Capítulo / Ciclo filter selects with i18n labels', () => {
    assert.match(ISLAND, /value=\{initiativeFilter\}/);
    assert.match(ISLAND, /value=\{chapterFilter\}/);
    assert.match(ISLAND, /value=\{cycleFilter\}/);
    assert.match(ISLAND, /comp\.memberList\.allInitiatives/);
    assert.match(ISLAND, /comp\.memberList\.allChapters/);
    assert.match(ISLAND, /comp\.memberList\.allCycles/);
  });

  it('renders the term-status column header + engagement category chips + cycle tags', () => {
    assert.match(ISLAND, /comp\.memberList\.thTerm/);
    assert.match(ISLAND, /kindLabel\(e, locale\)/);
    assert.match(ISLAND, /m\.cycles\.map/);
  });
});

describe('p625-c2 Fatia 2 — i18n chrome parity (3 dicts)', () => {
  const KEYS = ['thTerm', 'termGreen', 'termAmber', 'allInitiatives', 'allChapters', 'allCycles'];
  for (const [lang, src] of Object.entries(DICTS)) {
    it(`${lang} has all new comp.memberList chrome keys`, () => {
      for (const k of KEYS) {
        assert.match(src, new RegExp(`'comp\\.memberList\\.${k}':`), `${lang} missing comp.memberList.${k}`);
      }
    });
  }
});
