/**
 * Contract: Wave 3b-i (#740 / ADR-0104) — member-facing entry-chapter choice.
 *
 * The member picks ONE of their BR chapter affiliations (FACT) as their entry
 * chapter (governance), via set_my_entry_chapter, which promotes it to primary
 * through the single-home upsert RPC and records members.entry_chapter_code.
 * get_my_chapter_affiliations lists the affiliations for the /perfil choice card.
 * Live behavior (demote-then-promote, source preservation, restriction to own
 * affiliations, unknown/non-BR raises, anon denied) was validated at apply time
 * via a rolled-back probe; this static test guards the DDL + FE wiring.
 *
 * Static-only (reads source) → runs without DB env.
 *
 * Cross-ref: #740 Wave 3, ADR-0104, ADR-0006 (person_id), ADR-0095 (locked-table RPC).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIG_PATH = 'supabase/migrations/20260805000194_w3b_i_set_my_entry_chapter.sql';
const ADR_PATH = 'docs/adr/ADR-0104-chapter-affiliations-ssot.md';
const PROFILE_PATH = 'src/pages/profile.astro';
const CHAPTERS_PATH = 'src/lib/chapters.ts';
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'];

const MIG = readFileSync(MIG_PATH, 'utf8');
const PROFILE = readFileSync(PROFILE_PATH, 'utf8');
const CHAPTERS = readFileSync(CHAPTERS_PATH, 'utf8');

describe('w3b-i — set_my_entry_chapter RPC', () => {
  it('migration exists and defines the SECDEF RPC, granted to authenticated only', () => {
    assert.ok(existsSync(MIG_PATH));
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.set_my_entry_chapter\(p_chapter_code text\)/);
    assert.match(MIG, /SECURITY DEFINER/);
    assert.match(MIG, /SET search_path TO 'public', 'pg_temp'/);
    assert.match(MIG, /REVOKE EXECUTE ON FUNCTION public\.set_my_entry_chapter\(text\) FROM anon/);
    assert.match(MIG, /GRANT\s+EXECUTE ON FUNCTION public\.set_my_entry_chapter\(text\) TO authenticated/);
  });

  it('resolves the caller self-scoped via auth.uid() → members', () => {
    assert.match(MIG, /IF auth\.uid\(\) IS NULL THEN/);
    assert.match(MIG, /SELECT id, person_id INTO v_member_id, v_person_id\s*\n\s*FROM public\.members WHERE auth_id = auth\.uid\(\)/);
  });

  it('validates the chosen chapter is a Brazil chapter and active', () => {
    assert.match(MIG, /SELECT \(country = 'BR'\), is_active INTO v_is_br, v_is_active/);
    assert.match(MIG, /Entry chapter must be a Brazil chapter/);
    assert.match(MIG, /Chapter % is not active/);
  });

  it('restricts the choice to the member\'s OWN affiliation (PM decision) and preserves its source', () => {
    // must already be an affiliation of this person
    assert.match(MIG, /SELECT source INTO v_existing_source\s*\n\s*FROM public\.member_chapter_affiliations\s*\n\s*WHERE person_id = v_person_id AND chapter_code = v_code/);
    assert.match(MIG, /You are not affiliated with chapter %/);
    // promote via the single-home RPC passing the EXISTING source (no relabel to self_declared)
    assert.match(MIG, /PERFORM public\.upsert_chapter_affiliation\(v_person_id, v_code, v_existing_source, true\)/);
  });

  it('records the governance choice on members.entry_chapter_code (bare code)', () => {
    assert.match(MIG, /v_code\s+text := regexp_replace\(coalesce\(p_chapter_code, ''\), '\^PMI-', ''\)/);
    assert.match(MIG, /UPDATE public\.members\s*\n\s*SET entry_chapter_code = v_code/);
  });
});

describe('w3b-i — get_my_chapter_affiliations RPC', () => {
  it('is SECDEF, self-scoped, authenticated-only, with is_entry flag', () => {
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_my_chapter_affiliations\(\)/);
    assert.match(MIG, /\(mca\.chapter_code = m\.entry_chapter_code\) AS is_entry/);
    assert.match(MIG, /JOIN public\.member_chapter_affiliations mca ON mca\.person_id = m\.person_id/);
    assert.match(MIG, /WHERE m\.auth_id = auth\.uid\(\)/);
    assert.match(MIG, /GRANT\s+EXECUTE ON FUNCTION public\.get_my_chapter_affiliations\(\) TO authenticated/);
    assert.match(MIG, /REVOKE EXECUTE ON FUNCTION public\.get_my_chapter_affiliations\(\) FROM anon/);
  });

  it('enforces its BR contract in SQL (defensive cr.country = BR filter)', () => {
    assert.match(MIG, /WHERE m\.auth_id = auth\.uid\(\)\s*\n\s*AND cr\.country = 'BR'/);
  });

  it('reloads PostgREST (new RPCs on the exposed surface)', () => {
    assert.match(MIG, /NOTIFY pgrst, 'reload schema'/);
  });
});

describe('w3b-i — /perfil choice screen wiring', () => {
  it('renders the entry-chapter card and derives the headline from affiliations (is_entry)', () => {
    assert.match(PROFILE, /function entryChapterHtml\(m: any\): string/);
    assert.match(PROFILE, /\$\{entryChapterHtml\(m\)\}/);
    // current entry derived from the freshly-loaded affiliations, not get_member_by_auth
    // (which omits entry_chapter_code) — correct on first load and after a write.
    assert.match(PROFILE, /function currentEntryCode\(m: any\)/);
    assert.match(PROFILE, /\.find\(\(a: any\) => a\.is_entry\)\?\.chapter_code/);
    assert.match(PROFILE, /currentEntryCode\(m\) \? 'PMI-' \+ escapeHtmlSafe\(currentEntryCode\(m\)\)/);
  });

  it('loads affiliations via get_my_chapter_affiliations and writes via set_my_entry_chapter', () => {
    assert.match(PROFILE, /rpc\('get_my_chapter_affiliations'\)/);
    assert.match(PROFILE, /rpc\('set_my_entry_chapter', \{ p_chapter_code: code \}\)/);
    // post-save: carry entry_chapter_code into the re-rendered member object
    assert.match(PROFILE, /updated\.entry_chapter_code = data\.entry_chapter_code/);
  });

  it('dispatches the set-entry-chapter action and escapes rendered chapter codes', () => {
    assert.match(PROFILE, /case 'set-entry-chapter':/);
    assert.match(PROFILE, /data-action="set-entry-chapter" data-chapter-code="\$\{code\}"/);
    assert.match(PROFILE, /const code = escapeHtmlSafe\(a\.chapter_code\)/);
  });

  it('C5 — shows the empty-affiliations guidance farol (hidden PMI profile symptom)', () => {
    assert.match(PROFILE, /entryChapterEmptyGuide/);
    assert.match(PROFILE, /if \(affils\.length === 0\)/);
  });
});

describe('w3b-i — lib/chapters.ts fallback refreshed (5 → 13)', () => {
  it('fallback now mirrors the 13 BR registry chapters (incl. the new ones)', () => {
    for (const code of ['PMI-PE', 'PMI-PR', 'PMI-RJ', 'PMI-SP', 'PMI-BA', 'PMI-ES', 'PMI-SC', 'PMI-SE']) {
      assert.match(CHAPTERS, new RegExp(`display_code: '${code}'`));
    }
    assert.match(CHAPTERS, /display_order: 13/);
  });
});

describe('w3b-i — i18n parity (3 dicts)', () => {
  for (const dict of DICTS) {
    it(`${dict} has the profile.entryChapter.* keys`, () => {
      const body = readFileSync(dict, 'utf8');
      for (const key of ['title', 'desc', 'setBtn', 'badge', 'emptyGuide', 'saved', 'errorPrefix', 'brOnlyNote']) {
        assert.match(body, new RegExp(`'profile\\.entryChapter\\.${key}'`));
      }
    });
  }
});

describe('w3b-i — ADR-0104 amended', () => {
  it('ADR documents the 3b-i delivery + the migration', () => {
    assert.ok(existsSync(ADR_PATH));
    const adr = readFileSync(ADR_PATH, 'utf8');
    assert.match(adr, /Amendment — Wave 3b-i/);
    assert.match(adr, /20260805000194/);
  });
});
