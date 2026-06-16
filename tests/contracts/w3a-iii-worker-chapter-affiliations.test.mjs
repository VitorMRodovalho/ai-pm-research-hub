/**
 * Contract: Wave 3a-iii (#740 / ADR-0104) — worker write path for member_chapter_affiliations.
 *
 * The durable N:N FACT table (3a foundation) is now populated from the reliable
 * pmi_memberships snapshot by the pmi-vep-sync worker, through the one-primary RPC.
 * Live behavior (demote-then-insert, provisional-primary-if-none, idempotency,
 * source CHECK, service_role-only EXECUTE) was validated at apply time via a
 * rolled-back probe; this static test guards the migration DDL + worker wiring
 * against regression.
 *
 *  - upsert_chapter_affiliation: SECDEF, one-primary protocol, source CHECK,
 *    EXECUTE revoked from anon/authenticated + granted to service_role only.
 *  - updated_at trigger added before the worker starts issuing UPDATEs.
 *  - worker maps "<State>, Brazil Chapter" → bare registry code (BR-only), incl.
 *    the previously-missing Sergipe, and calls the RPC with is_primary=false.
 *  - the call is wired into the resolved-person Phase B slot; summary counts it.
 *  - ADR-0104 amended with the 3a-iii delivery.
 *
 * Static-only (reads source) → runs without DB env.
 *
 * Cross-ref: #740 Wave 3, ADR-0104, ADR-0006 (person_id), ADR-0095 (locked-table RPC).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIG_PATH = 'supabase/migrations/20260805000193_w3a_iii_upsert_chapter_affiliation_rpc.sql';
const ADR_PATH = 'docs/adr/ADR-0104-chapter-affiliations-ssot.md';
const MAPPER_PATH = 'cloudflare-workers/pmi-vep-sync/src/mapper.ts';
const DB_PATH = 'cloudflare-workers/pmi-vep-sync/src/db.ts';
const INDEX_PATH = 'cloudflare-workers/pmi-vep-sync/src/index.ts';
const TYPES_PATH = 'cloudflare-workers/pmi-vep-sync/src/types.ts';

const MIG = readFileSync(MIG_PATH, 'utf8');
const MAPPER = readFileSync(MAPPER_PATH, 'utf8');
const DB = readFileSync(DB_PATH, 'utf8');
const INDEX = readFileSync(INDEX_PATH, 'utf8');
const TYPES = readFileSync(TYPES_PATH, 'utf8');

describe('w3a-iii — upsert_chapter_affiliation RPC', () => {
  it('migration exists and defines the SECDEF RPC with the right signature', () => {
    assert.ok(existsSync(MIG_PATH));
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.upsert_chapter_affiliation\(/);
    assert.match(MIG, /p_person_id\s+uuid/);
    assert.match(MIG, /p_chapter_code text/);
    assert.match(MIG, /p_source\s+text DEFAULT 'pmi_vep'/);
    assert.match(MIG, /p_is_primary\s+boolean DEFAULT false/);
    assert.match(MIG, /SECURITY DEFINER/);
    assert.match(MIG, /SET search_path TO 'public', 'pg_temp'/);
  });

  it('implements the one-primary protocol (demote others on explicit primary)', () => {
    // explicit primary demotes any OTHER primary first (partial unique index guard)
    assert.match(MIG, /IF p_is_primary THEN[\s\S]*?SET is_primary = false[\s\S]*?is_primary = true AND chapter_code <> v_code/);
    // provisional primary only when the person has none (never overrides existing)
    assert.match(MIG, /v_make_primary := p_is_primary OR NOT EXISTS/);
    // on conflict: false-call preserves the existing is_primary (no silent demote)
    assert.match(MIG, /is_primary\s+= CASE WHEN p_is_primary THEN true\s*\n\s*ELSE public\.member_chapter_affiliations\.is_primary END/);
  });

  it('validates source against the table CHECK domain', () => {
    assert.match(MIG, /p_source NOT IN \('pmi_vep', 'admin_import', 'self_declared', 'legacy'\)/);
    assert.match(MIG, /RAISE EXCEPTION 'upsert_chapter_affiliation: invalid source/);
  });

  it('locks EXECUTE to service_role only (worker) — not anon/authenticated', () => {
    assert.match(MIG, /REVOKE EXECUTE ON FUNCTION public\.upsert_chapter_affiliation\(uuid, text, text, boolean\) FROM anon/);
    assert.match(MIG, /REVOKE EXECUTE ON FUNCTION public\.upsert_chapter_affiliation\(uuid, text, text, boolean\) FROM authenticated/);
    assert.match(MIG, /GRANT\s+EXECUTE ON FUNCTION public\.upsert_chapter_affiliation\(uuid, text, text, boolean\) TO service_role/);
  });

  it('adds the updated_at trigger using the canonical V4 helper', () => {
    assert.match(MIG, /CREATE TRIGGER member_chapter_affiliations_set_updated_at\s*\n\s*BEFORE UPDATE ON public\.member_chapter_affiliations/);
    assert.match(MIG, /EXECUTE FUNCTION public\.set_updated_at_v4\(\)/);
  });

  it('reloads PostgREST (new RPC on the exposed surface)', () => {
    assert.match(MIG, /NOTIFY pgrst, 'reload schema'/);
  });
});

describe('w3a-iii — worker name→code mapping (mapper.ts)', () => {
  it('exports parseBrChapterCode gated on the ", Brazil Chapter" suffix (BR-only)', () => {
    assert.match(MAPPER, /export function parseBrChapterCode\(/);
    assert.match(MAPPER, /Brazil Chapter\\s\*\$\/\.test\(name\)/);
    // returns the bare registry code (strips the PMI- prefix)
    assert.match(MAPPER, /pmiCode\.replace\(\/\^PMI-\/, ''\)/);
  });

  it('adds Sergipe (the BR token missing from the worker map) for registry parity', () => {
    assert.match(MAPPER, /'Sergipe': 'PMI-SE'/);
  });
});

describe('w3a-iii — worker write path (db.ts)', () => {
  it('upsertChapterAffiliations calls the RPC with is_primary=false (asserts FACT, not headline)', () => {
    assert.match(DB, /export async function upsertChapterAffiliations\(/);
    assert.match(DB, /db\.rpc\('upsert_chapter_affiliation'/);
    assert.match(DB, /p_source: 'pmi_vep'/);
    assert.match(DB, /p_is_primary: false/);
    // imports the BR mapper
    assert.match(DB, /import \{ parseBrChapterCode \} from '\.\/mapper'/);
  });

  it('tolerates the real runtime shape (array of name strings) and the declared object shape', () => {
    assert.match(DB, /typeof m === 'string'/);
    assert.match(DB, /\(m as any\)\.chapterName/);
    // dedupes codes via a Set
    assert.match(DB, /new Set<string>\(\)/);
  });
});

describe('w3a-iii — wiring (index.ts + types.ts)', () => {
  it('invokes the write only for resolved persons, inside the Phase B slot', () => {
    assert.match(INDEX, /upsertChapterAffiliations/);
    // guarded by a non-empty pmi_memberships array
    assert.match(INDEX, /upsertChapterAffiliations\(db, personId, mapped\.pmi_memberships\)/);
    assert.match(INDEX, /scope: 'chapter_affiliations'/);
  });

  it('counts the upserts in the run summary', () => {
    assert.match(INDEX, /summary\.chapter_affiliations_upserted/);
    assert.match(TYPES, /chapter_affiliations_upserted\?: number/);
  });
});

describe('w3a-iii — ADR-0104 amended', () => {
  it('ADR documents the 3a-iii worker delivery + the migration', () => {
    assert.ok(existsSync(ADR_PATH));
    const adr = readFileSync(ADR_PATH, 'utf8');
    assert.match(adr, /Amendment — Wave 3a-iii/);
    assert.match(adr, /20260805000193/);
  });
});
