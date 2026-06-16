/**
 * Contract: Wave 3a-ii (C3) #740 — explicit contracting party + signatory in
 * sign_volunteer_agreement (per legal-counsel parecer 2026-06-16, ADR-0104).
 *
 *  - Contracting party is ALWAYS the contracting chapter (is_contracting_chapter),
 *    never derived from the member's affiliation chapter (the format-accident is gone).
 *  - The issuer (issued_by) is a board member of the CONTRACTING chapter (PMI-GO),
 *    falling back to a manager — so contractant and signatory representative match.
 *  - content_snapshot records contracting_chapter / issuer_chapter / issuer_authority_basis;
 *    the volunteer's own chapter stays as member_chapter (indicator only).
 *  - admin_audit_log records chapter_cnpj_source (observability of the emergency fallback).
 *  - counter_sign_certificate is UNCHANGED: it already gates a chapter_board counter-signer
 *    by content_snapshot->>'contracting_chapter', so writing it = PMI-GO board gating.
 *
 * Static-only (reads source) → runs without DB env. Live md5 of the function body was
 * confirmed == this file's body at apply time (Phase C drift guard).
 *
 * Cross-ref: #740 Wave 3, ADR-0104, legal-counsel parecer (CC/2002 arts. 115-120 representação).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIG_PATH = 'supabase/migrations/20260805000191_w3a_c3_explicit_contracting_chapter_signatory.sql';
const ADR_PATH = 'docs/adr/ADR-0104-chapter-affiliations-ssot.md';
const MIG = readFileSync(MIG_PATH, 'utf8');

describe('w3a-c3 — contracting party always the contracting chapter (R1)', () => {
  it('migration exists and uses DROP+CREATE (drift history)', () => {
    assert.ok(existsSync(MIG_PATH));
    assert.match(MIG, /DROP FUNCTION IF EXISTS public\.sign_volunteer_agreement\(text, text, text\)/);
    assert.match(MIG, /CREATE FUNCTION public\.sign_volunteer_agreement/);
  });

  it('selects the contracting chapter directly (no member-chapter join)', () => {
    assert.match(MIG, /WHERE cr\.is_contracting_chapter = true AND cr\.is_active = true/);
    // the old brittle lookup by the member's chapter must be gone
    assert.doesNotMatch(MIG, /WHERE cr\.chapter_code = v_member\.chapter/);
  });

  it('keeps an emergency hardcoded fallback flagged in audit', () => {
    assert.match(MIG, /v_chapter_cnpj_source\s*:?=\s*'hardcoded_emergency_fallback'/);
    assert.match(MIG, /'06\.065\.645\/0001-99'/);
  });
});

describe('w3a-c3 — issuer represents the contracting chapter (R2)', () => {
  it('picks the issuer from the contracting-chapter board (PMI- prefixed), else manager', () => {
    assert.match(MIG, /WHERE chapter = 'PMI-' \|\| v_contracting_code AND 'chapter_board' = ANY\(designations\)/);
    assert.match(MIG, /v_issuer_basis\s*:?=\s*'manager_fallback'/);
  });

  it('snapshot records contracting_chapter + issuer fields; member chapter stays an indicator', () => {
    assert.match(MIG, /'contracting_chapter', 'PMI-' \|\| v_contracting_code/);
    assert.match(MIG, /'issuer_chapter', 'PMI-' \|\| v_contracting_code/);
    assert.match(MIG, /'issuer_authority_basis', v_issuer_basis/);
    assert.match(MIG, /'member_chapter', v_member\.chapter/);
  });
});

describe('w3a-c3 — audit observability (R3)', () => {
  it('audit log carries chapter_cnpj_source + contracting_chapter', () => {
    assert.match(MIG, /'chapter_cnpj_source', v_chapter_cnpj_source/);
    assert.match(MIG, /'contracting_chapter', 'PMI-' \|\| v_contracting_code/);
  });
});

describe('w3a-c3 — ADR-0104 amended', () => {
  it('ADR documents the C3 delivery', () => {
    assert.ok(existsSync(ADR_PATH));
    const adr = readFileSync(ADR_PATH, 'utf8');
    assert.match(adr, /C3.*shipped|Wave 3a-ii \(C3\)/);
    assert.match(adr, /20260805000191/);
  });
});
