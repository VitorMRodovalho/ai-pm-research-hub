/**
 * Contract: #315 Wave-1b foundation — governance_documents.metadata jsonb column.
 *
 * RATIFIED 2026-05-24 (SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md §19.2):
 *   P1-Q1: ip_policy / privacy_policy = doc_type 'policy' + metadata.subtype (NOT new doc_types).
 *   P1-Q3: template_role = 'instance' | 'template' in metadata (avoids a 'template' doc_type that
 *          would collide with volunteer_term_template).
 * Neither was storable: governance_documents had no metadata column. This migration adds the
 * foundation column + a CHECK that value-guards ONLY those two ratified keys when present (the bag
 * stays free for other keys), with NOT NULL DEFAULT '{}' so consumers never null-check.
 *
 * Scope: foundation only. Wiring the intake RPC to persist subtype/template_role and the readers to
 * surface them is a follow-up leaf, not this PR. Taxonomy was NOT re-decided here (already ratified).
 *
 * Static checks lock the migration body; the DB-gated check confirms no invariant regression.
 * (Live column shape + CHECK behaviour were verified during apply: jsonb NOT NULL DEFAULT '{}',
 * 16 rows all '{}', predicate accepts instance/template/ip_policy/privacy_policy + arbitrary other
 * keys, rejects bogus template_role/subtype.)
 *
 * Cross-ref: PM_DECISION_BRIEF_2026-06-04.md D3; issue #315.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000102_p278_315_w1b_governance_documents_metadata_column.sql');
const sql = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const sqlExec = sql.replace(/^\s*--.*$/gm, ''); // executable SQL only (strip line-comments incl. the ROLLBACK note)

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC ───────────────────────────────────────────────────────────────────
test('W1b static: migration file exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000102 exists');
});

test('W1b static: adds metadata jsonb NOT NULL DEFAULT \'{}\'', () => {
  assert.match(
    sql,
    /ALTER TABLE public\.governance_documents\s+ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '\{\}'::jsonb/i,
    'metadata column is jsonb NOT NULL DEFAULT {}'
  );
  assert.doesNotMatch(sqlExec, /DROP COLUMN metadata/i, 'must not drop the column in the same migration (rollback note in comments is fine)');
});

test('W1b static: CHECK value-guards template_role to the ratified enum when present', () => {
  assert.match(sql, /ADD CONSTRAINT governance_documents_metadata_ratified_keys_check/i, 'named CHECK constraint');
  assert.match(
    sql,
    /NOT \(metadata \? 'template_role'\)\s+OR metadata->>'template_role' IN \('instance',\s*'template'\)/i,
    "template_role guarded to instance|template only when the key is present"
  );
});

test('W1b static: CHECK value-guards subtype to the ratified enum when present', () => {
  assert.match(
    sql,
    /NOT \(metadata \? 'subtype'\)\s+OR metadata->>'subtype' IN \('ip_policy',\s*'privacy_policy'\)/i,
    "subtype guarded to ip_policy|privacy_policy only when the key is present"
  );
});

test('W1b static: column is documented + PostgREST reloaded', () => {
  assert.match(sql, /COMMENT ON COLUMN public\.governance_documents\.metadata IS/i, 'metadata column has a COMMENT');
  assert.match(sql, /NOTIFY pgrst, 'reload schema'/i, 'PostgREST schema reload notified');
});

// ── BEHAVIOURAL (DB-gated): no invariant regression ────────────────────────────
test('W1b behavioural: schema invariants still clean after the column add', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('check_schema_invariants');
  assert.ifError(error);
  assert.ok(Array.isArray(data), 'check_schema_invariants returns an array');
  const violations = data.filter((r) => Number(r.violation_count) > 0);
  assert.equal(violations.length, 0, `expected 0 invariant violations, got: ${violations.map((v) => v.invariant_name).join(', ')}`);
});
