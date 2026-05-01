/**
 * Wave 5b-1 (p84) — AI-augmented self-improvement loop schema contract.
 *
 * Spec-grep style: walks the migration file and asserts the foundation
 * invariants for the enrichment loop are present.
 *
 * Migration: supabase/migrations/20260430232714_p84_wave5b1_enrichment_loop_schema.sql
 *
 * Invariants asserted:
 *   - Schema additions on selection_applications (3 columns)
 *   - selection_topic_views table + RLS audit-immutable policies
 *   - Cap = 2 + cooldown = 5 minutes (PM-approved)
 *   - MD5 content_hash dedup (council ai-engineer)
 *   - SECDEF + search_path pinned on all token RPCs
 *   - Whitelist of 12 enrichable fields enforced via per-column COALESCE
 *   - Token validation requires profile_completion scope + pmi_application source_type
 *   - net.http_post dispatch to pmi-ai-analyze EF (re-analysis trigger)
 *   - GRANT EXECUTE to anon/authenticated/service_role (token-auth pattern)
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIG_PATH = resolve(
  ROOT,
  'supabase/migrations/20260430232714_p84_wave5b1_enrichment_loop_schema.sql'
);
const sql = readFileSync(MIG_PATH, 'utf8');

test('Wave 5b-1: selection_applications gains 3 enrichment columns', () => {
  assert.match(sql, /ADD COLUMN IF NOT EXISTS enrichment_count integer NOT NULL DEFAULT 0/i);
  assert.match(sql, /ADD COLUMN IF NOT EXISTS last_enrichment_at timestamptz/i);
  assert.match(sql, /ADD COLUMN IF NOT EXISTS last_enrichment_content_hash text/i);
});

test('Wave 5b-1: selection_topic_views table is audit-immutable', () => {
  assert.match(sql, /CREATE TABLE IF NOT EXISTS selection_topic_views/i);
  assert.match(sql, /application_id uuid NOT NULL REFERENCES selection_applications\(id\) ON DELETE CASCADE/i);
  assert.match(sql, /ALTER TABLE selection_topic_views ENABLE ROW LEVEL SECURITY/i);
  // No direct insert
  assert.match(sql, /CREATE POLICY "selection_topic_views_no_direct_insert"[\s\S]*?WITH CHECK \(false\)/i);
  // No update
  assert.match(sql, /CREATE POLICY "selection_topic_views_no_update"[\s\S]*?USING \(false\)/i);
  // No delete
  assert.match(sql, /CREATE POLICY "selection_topic_views_no_delete"[\s\S]*?USING \(false\)/i);
  // Committee read
  assert.match(sql, /CREATE POLICY "selection_topic_views_committee_read"[\s\S]*?rls_can\('manage_member'\)\s*OR\s*rls_can\('view_internal_analytics'\)/i);
});

test('Wave 5b-1: cap = 2 re-analyses + cooldown = 5 minutes (PM-approved)', () => {
  assert.match(sql, /v_max_attempts CONSTANT integer\s*:=\s*2;/i,
    'Cap must be exactly 2 attempts (PM 2026-04-30).');
  assert.match(sql, /v_cooldown CONSTANT interval\s*:=\s*interval '5 minutes';/i,
    'Cooldown must be exactly 5 minutes (PM 2026-04-30).');
});

test('Wave 5b-1: MD5 content_hash dedup (council ai-engineer)', () => {
  assert.match(sql, /v_content_hash\s*:=\s*md5\(v_normalized_content\);/i,
    'Content hash must use MD5 of normalized content.');
  assert.match(sql, /lower\(trim\(coalesce\(v_field_value, ''\)\)\)/i,
    'Normalization must be lowercase + trim + null-coalesce.');
  // Dedup short-circuit branch (early-return when hash matches)
  assert.match(sql, /v_app\.last_enrichment_content_hash\s*=\s*v_content_hash/i,
    'Dedup branch must compare incoming hash to last persisted hash.');
  assert.match(sql, /'reason',\s*'no_change_detected'/i,
    'Dedup must surface no_change_detected reason for portal copy.');
});

test('Wave 5b-1: token RPCs are SECDEF + search_path-pinned', () => {
  for (const fn of ['request_application_enrichment', 'log_topic_view', 'get_application_enrichment_status']) {
    const rxSecdef = new RegExp(`CREATE OR REPLACE FUNCTION ${fn}\\b[\\s\\S]*?SECURITY DEFINER`, 'i');
    const rxPath = new RegExp(`CREATE OR REPLACE FUNCTION ${fn}\\b[\\s\\S]*?SET search_path TO 'public', 'pg_temp'`, 'i');
    assert.match(sql, rxSecdef, `${fn} must be SECURITY DEFINER`);
    assert.match(sql, rxPath, `${fn} must SET search_path to 'public', 'pg_temp'`);
  }
});

test('Wave 5b-1: enrichment whitelist is exactly the 12 PM-approved fields', () => {
  const expected = [
    'academic_background', 'motivation_letter', 'non_pmi_experience',
    'leadership_experience', 'proposed_theme', 'reason_for_applying',
    'areas_of_interest', 'availability_declared', 'certifications',
    'linkedin_url', 'credly_url', 'resume_url'
  ];
  for (const field of expected) {
    assert.match(sql, new RegExp(`'${field}'`),
      `Whitelist must include ${field}`);
    // Each whitelisted field must be threaded through UPDATE via COALESCE+NULLIF
    assert.match(
      sql,
      new RegExp(`${field}\\s*=\\s*COALESCE\\(NULLIF\\(p_field_updates->>'${field}',''\\),\\s*${field}\\)`),
      `${field} must be threaded through COALESCE+NULLIF in UPDATE`
    );
  }
});

test('Wave 5b-1: token validation requires profile_completion scope + pmi_application source', () => {
  // All 3 token RPCs must check the scope
  const scopeMatches = sql.match(/'profile_completion'\s*=\s*ANY\(scopes\)/g) ?? [];
  assert.ok(scopeMatches.length >= 3, `Expected 3+ profile_completion scope checks, got ${scopeMatches.length}`);
  const sourceMatches = sql.match(/source_type\s*<>\s*'pmi_application'/g) ?? [];
  assert.ok(sourceMatches.length >= 3, `Expected 3+ source_type guards, got ${sourceMatches.length}`);
});

test('Wave 5b-1: re-analysis fires net.http_post to pmi-ai-analyze EF', () => {
  assert.match(sql, /SELECT net\.http_post\(/i,
    'Re-analysis must dispatch via net.http_post.');
  assert.match(sql, /\/functions\/v1\/pmi-ai-analyze/i,
    'Dispatch URL must point to pmi-ai-analyze EF.');
  assert.match(sql, /jsonb_build_object\('application_id', v_application_id\)/i,
    'Dispatch body must include application_id only (matches EF contract).');
  assert.match(sql, /'service_role_key'/i,
    'Dispatch must lookup service_role_key from vault.');
});

test('Wave 5b-1: GRANT EXECUTE to anon/authenticated/service_role on all 4 fns', () => {
  const grants = [
    'GRANT EXECUTE ON FUNCTION _should_offer_enrichment(jsonb)',
    'GRANT EXECUTE ON FUNCTION request_application_enrichment(text, jsonb)',
    'GRANT EXECUTE ON FUNCTION log_topic_view(text, inet, text)',
    'GRANT EXECUTE ON FUNCTION get_application_enrichment_status(text)'
  ];
  for (const g of grants) {
    const rx = new RegExp(g.replace(/[()]/g, m => '\\' + m) + '\\s+TO\\s+anon,\\s*authenticated,\\s*service_role', 'i');
    assert.match(sql, rx, `Missing or malformed grant: ${g}`);
  }
});

test('Wave 5b-1: rollback documented in header', () => {
  assert.match(sql, /Rollback:[\s\S]*?DROP FUNCTION request_application_enrichment/i);
  assert.match(sql, /DROP TABLE selection_topic_views/i);
  assert.match(sql, /DROP COLUMN enrichment_count/i);
});

test('Wave 5b-1: _should_offer_enrichment helper is IMMUTABLE pure', () => {
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION _should_offer_enrichment\(p_ai_analysis jsonb\)[\s\S]*?IMMUTABLE/i,
    'Helper must be IMMUTABLE (no side-effects, cacheable per-input).'
  );
  // Threshold is score < 3 OR red_flags >= 2
  assert.match(sql, /v_score\s*<\s*3/i);
  assert.match(sql, /v_red_count\s*>=\s*2/i);
});
