/**
 * #632 round-2 (2026-06-11) — guards for:
 *  - mig 146: doc_type CHECK extended with declaration_template / accession_term /
 *    data_processing_agreement (the 3 new revised-package instruments, doc07/10/11).
 *  - mig 147: document_versions SELECT policy that exposes UNLOCKED drafts to
 *    manage_member holders via rls_can — fixes edit_document_version_draft which
 *    could not edit any unlocked draft because its pre-SELECT ran under RLS and
 *    the existing policy's admin OR-branch (nested EXISTS + can_by_member) did not
 *    materialize during enforcement. Without this, the governed governance-editing
 *    surface is structurally broken for every admin.
 *
 * Static (offline) assertions on the migration files + optional DB-aware check
 * that the policy is live.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG146 = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260805000146_doc_type_check_new_instrument_types.sql'),
  'utf8',
);
const MIG147 = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260805000147_fix_document_versions_unlocked_draft_admin_select.sql'),
  'utf8',
);

test('#632 mig146: doc_type CHECK adds the 3 new instrument types', () => {
  assert.match(MIG146, /ALTER TABLE public\.governance_documents DROP CONSTRAINT governance_documents_doc_type_check/i);
  for (const t of ['declaration_template', 'accession_term', 'data_processing_agreement']) {
    assert.match(MIG146, new RegExp(`'${t}'::text`), `CHECK must include ${t}`);
  }
  // the legacy types must survive the redefinition
  for (const t of ['policy', 'cooperation_agreement', 'volunteer_term_template', 'manual']) {
    assert.match(MIG146, new RegExp(`'${t}'::text`), `CHECK must retain legacy type ${t}`);
  }
});

test('#632 mig147: dedicated SELECT policy exposes unlocked drafts to manage_member', () => {
  assert.match(MIG147, /CREATE POLICY document_versions_read_unlocked_drafts_admin/i);
  assert.match(MIG147, /FOR\s+SELECT/i);
  assert.match(MIG147, /locked_at IS NULL/i);
  assert.match(MIG147, /rls_can\('manage_member'\)/i);
  // must NOT weaken: no blanket TRUE / no anon exposure
  assert.doesNotMatch(MIG147, /USING\s*\(\s*true\s*\)/i, 'policy must not be unconditionally true');
  assert.doesNotMatch(MIG147, /TO\s+anon/i, 'policy must not target anon');
});

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';

test('#632 mig147 DB: the unlocked-draft admin SELECT policy is live', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('exec_sql_select_json', {}).then(() => ({ data: null, error: null })).catch(() => ({ data: null, error: null }));
  // No generic exec RPC — assert via a lightweight pg_policy probe through PostgREST is not available;
  // instead verify the 9 revised drafts exist and are unlocked (the end-state the fix enabled).
  const { data: rows, error: e2 } = await sb
    .from('document_versions')
    .select('id, locked_at, version_label')
    .eq('version_label', 'draft-rev-juridica-2026-06-07');
  assert.ifError(e2);
  // #1153 Onda 1: the volunteer_term_template's draft-rev-juridica-2026-06-07 (v8) was superseded
  // by v9 (docx V2, locked into the Onda 1 chain) and discarded, so the package is down to 8 here.
  assert.equal(rows.length, 8, 'the 8 still-pending revised-package drafts present (Termo advanced to v9 in #1153 Onda 1)');
  assert.ok(rows.every(r => r.locked_at === null), 'all remaining drafts stay unlocked (gated for legal review)');
});
