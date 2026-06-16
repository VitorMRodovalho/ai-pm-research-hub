/**
 * Contract: Wave 3b-ii (#740 / ADR-0104) — members.chapter becomes a derived/compat value.
 *
 * members.chapter is now maintained by two event-specific triggers from the canonical sources:
 *   COALESCE('PMI-' || entry_chapter_code, 'PMI-' || primary affiliation code, legacy chapter)
 *   - T1 derive_member_chapter_before          BEFORE UPDATE OF entry_chapter_code ON members
 *   - T2 recompute_member_chapter_from_affiliation AFTER INS/DEL/UPD OF is_primary ON member_chapter_affiliations
 * They are event-specific (NOT a blanket BEFORE override) so the admin free-text edit path
 * (admin_update_member: chapter = COALESCE(p_chapter, chapter)) is NOT silently overridden.
 * Invariant U_active_person_has_primary_chapter_affiliation is added to check_schema_invariants().
 *
 * Live behavior (primary change → chapter follows; entry choice → chapter follows; admin
 * chapter-only edit → passthrough; backfill 0 rows; invariant U = 0) was validated at apply
 * time via a rolled-back probe; this static test guards the DDL.
 *
 * Static-only (reads migration source + ADR) → runs without DB env.
 *
 * Cross-ref: #740 Wave 3, ADR-0104, ADR-0006 (person_id).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIG_PATH = 'supabase/migrations/20260805000195_w3b_ii_members_chapter_derivation.sql';
const ADR_PATH = 'docs/adr/ADR-0104-chapter-affiliations-ssot.md';

const MIG = readFileSync(MIG_PATH, 'utf8');

describe('w3b-ii — T1: entry-chapter choice drives members.chapter', () => {
  it('defines derive_member_chapter_before() as a SECDEF trigger fn with the COALESCE derivation', () => {
    assert.ok(existsSync(MIG_PATH));
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.derive_member_chapter_before\(\)\s*\n\s*RETURNS trigger/);
    assert.match(MIG, /SECURITY DEFINER/);
    assert.match(MIG, /SET search_path TO 'public', 'pg_temp'/);
    // COALESCE('PMI-'||entry, 'PMI-'||primary, NEW.chapter)
    assert.match(MIG, /NEW\.chapter := COALESCE\(/);
    assert.match(MIG, /'PMI-' \|\| NEW\.entry_chapter_code/);
    assert.match(MIG, /WHERE a\.person_id = NEW\.person_id AND a\.is_primary/);
  });

  it('fires only on UPDATE OF entry_chapter_code (so an admin chapter-only edit passes through)', () => {
    assert.match(MIG, /CREATE TRIGGER trg_z_derive_member_chapter\s*\n\s*BEFORE UPDATE OF entry_chapter_code ON public\.members/);
    // documents the admin passthrough rationale
    assert.match(MIG, /admin_update_member/);
    assert.match(MIG, /NOT silently overridden/);
  });
});

describe('w3b-ii — T2: primary affiliation change drives members.chapter', () => {
  it('defines recompute_member_chapter_from_affiliation() guarded by IS DISTINCT FROM', () => {
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.recompute_member_chapter_from_affiliation\(\)\s*\n\s*RETURNS trigger/);
    assert.match(MIG, /v_pid uuid := COALESCE\(NEW\.person_id, OLD\.person_id\)/);
    assert.match(MIG, /WHERE m\.person_id = v_pid\s*\n\s*AND m\.chapter IS DISTINCT FROM COALESCE\(/);
  });

  it('fires AFTER INS/DEL/UPD OF is_primary on member_chapter_affiliations', () => {
    assert.match(MIG, /CREATE TRIGGER trg_recompute_member_chapter_on_affiliation\s*\n\s*AFTER INSERT OR DELETE OR UPDATE OF is_primary ON public\.member_chapter_affiliations/);
  });
});

describe('w3b-ii — one-time backfill recompute', () => {
  it('recomputes members.chapter once, guarded so it is a no-op for already-aligned data', () => {
    assert.match(MIG, /-- ── One-time backfill recompute/);
    assert.match(MIG, /UPDATE public\.members m\s*\n\s*SET chapter = COALESCE\(/);
    assert.match(MIG, /WHERE m\.person_id IS NOT NULL\s*\n\s*AND m\.chapter IS DISTINCT FROM COALESCE\(/);
  });
});

describe('w3b-ii — invariant U in check_schema_invariants()', () => {
  it('adds U_active_person_has_primary_chapter_affiliation, registry-scoped (Outro/Externo excluded)', () => {
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.check_schema_invariants\(\)/);
    assert.match(MIG, /'U_active_person_has_primary_chapter_affiliation'::text/);
    assert.match(MIG, /replace\(m\.chapter, 'PMI-', ''\) IN \(SELECT chapter_code FROM public\.chapter_registry\)/);
    assert.match(MIG, /WHERE a\.person_id = m\.person_id AND a\.is_primary\) <> 1/);
    // does not drop any pre-existing invariant (spot-check the last one before U)
    assert.match(MIG, /'B2_current_cycle_active_terminal_status'::text/);
  });

  it('reloads PostgREST', () => {
    assert.match(MIG, /NOTIFY pgrst, 'reload schema'/);
  });
});

describe('w3b-ii — ADR-0104 amended', () => {
  it('ADR documents the 3b-ii delivery + the migration', () => {
    assert.ok(existsSync(ADR_PATH));
    const adr = readFileSync(ADR_PATH, 'utf8');
    assert.match(adr, /Amendment — Wave 3b-ii/);
    assert.match(adr, /20260805000195/);
    assert.match(adr, /event-specific triggers/i);
  });
});
