/**
 * Contract: Wave 3a (DB foundation) #740 — member_chapter_affiliations + entry_chapter_code.
 *
 * Per ADR-0104, the durable chapter model's schema + backfill (additive, zero
 * behavior change). Live invariants were validated at apply time (72/73 active
 * members backfilled, 1 'Outro' skipped, one primary per person, RLS on); this
 * static test guards the migration DDL against regression.
 *
 *  - New N:N FACT table keyed on person_id (ADR-0006), FK chapter_registry,
 *    source CHECK, one-primary partial unique index, RLS rpc_only_deny_all.
 *  - members.entry_chapter_code added (FK chapter_registry, nullable).
 *  - chapter_registry seeded with the BR chapters present in live data.
 *  - Backfill from legacy members.chapter (strip PMI-, skip non-registry like 'Outro').
 *  - ADR-0104 amended with the 3a delivery.
 *
 * Static-only (reads source) → runs without DB env.
 *
 * Cross-ref: #740 Wave 3, ADR-0104, ADR-0006 (person_id), ADR-0095 (rpc_only pattern).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIG_PATH = 'supabase/migrations/20260805000190_w3a_member_chapter_affiliations_model.sql';
const ADR_PATH = 'docs/adr/ADR-0104-chapter-affiliations-ssot.md';
const MIG = readFileSync(MIG_PATH, 'utf8');

describe('w3a — member_chapter_affiliations table', () => {
  it('migration exists and creates the FACT table keyed on person_id', () => {
    assert.ok(existsSync(MIG_PATH));
    assert.match(MIG, /CREATE TABLE IF NOT EXISTS public\.member_chapter_affiliations/);
    assert.match(MIG, /person_id\s+uuid NOT NULL REFERENCES public\.persons\(id\) ON DELETE CASCADE/);
    assert.match(MIG, /chapter_code text NOT NULL REFERENCES public\.chapter_registry\(chapter_code\)/);
  });

  it('constrains source and enforces one primary per person', () => {
    assert.match(MIG, /source\s+text NOT NULL CHECK \(source IN \('pmi_vep', 'admin_import', 'self_declared', 'legacy'\)\)/);
    assert.match(MIG, /UNIQUE \(person_id, chapter_code\)/);
    assert.match(MIG, /CREATE UNIQUE INDEX IF NOT EXISTS member_chapter_affiliations_one_primary_idx[\s\S]*?WHERE \(is_primary = true\)/);
  });

  it('enables RLS rpc_only_deny_all + fully revokes anon AND authenticated (LGPD, mirrors member_emails)', () => {
    assert.match(MIG, /ALTER TABLE public\.member_chapter_affiliations ENABLE ROW LEVEL SECURITY/);
    assert.match(MIG, /CREATE POLICY rpc_only_deny_all[\s\S]*?USING \(false\)/);
    assert.match(MIG, /REVOKE ALL ON public\.member_chapter_affiliations FROM anon/);
    assert.match(MIG, /REVOKE ALL ON public\.member_chapter_affiliations FROM authenticated/);
  });
});

describe('w3a — members.entry_chapter_code', () => {
  it('adds the nullable governance column with FK', () => {
    assert.match(MIG, /ALTER TABLE public\.members\s*\n\s*ADD COLUMN IF NOT EXISTS entry_chapter_code text REFERENCES public\.chapter_registry\(chapter_code\) ON DELETE SET NULL/);
  });
});

describe('w3a — chapter_registry seed + backfill', () => {
  it('seeds the BR chapters present in live data (PE/PR/RJ/SP/BA/ES/SC/SE)', () => {
    for (const code of ['PE', 'PR', 'RJ', 'SP', 'BA', 'ES', 'SC', 'SE']) {
      assert.match(MIG, new RegExp(`'${code}',`), `seed missing ${code}`);
    }
    assert.match(MIG, /ON CONFLICT \(chapter_code\) DO NOTHING/);
  });

  it('backfills legacy primary from members.chapter, stripping PMI- and skipping non-registry', () => {
    assert.match(MIG, /INSERT INTO public\.member_chapter_affiliations \(person_id, chapter_code, source, is_primary\)/);
    assert.match(MIG, /regexp_replace\(m\.chapter, '\^PMI-', ''\)/);
    assert.match(MIG, /IN \(SELECT chapter_code FROM public\.chapter_registry\)/);
    assert.match(MIG, /DISTINCT ON \(m\.person_id\)/);
    assert.match(MIG, /'legacy'/);
  });
});

describe('w3a — ADR-0104 amended', () => {
  it('ADR documents the 3a DB foundation delivery', () => {
    assert.ok(existsSync(ADR_PATH));
    const adr = readFileSync(ADR_PATH, 'utf8');
    assert.match(adr, /Amendment — Wave 3a \(DB foundation\)/);
    assert.match(adr, /20260805000190/);
  });
});
