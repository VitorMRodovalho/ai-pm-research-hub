/**
 * #403 (BUG-268.B) contract test — Tier-2 governance INSERT RPCs restored.
 *
 * Same bug class as SEDIMENT-268.A (p269, migration 20260805000048) but on the
 * Tier-2 writers that ALSO omit visibility_class + acknowledgement_mode:
 *
 *   1. confirm_manual_version        → INSERT INTO public.governance_documents (doc_type='manual')
 *   2. link_attachment_to_governance → INSERT INTO public.governance_documents (doc_type='cooperation_agreement')
 *
 * Both INSERTs omitted the three columns made NOT NULL (no default) by the W1a M2
 * taxonomy migration (#315): organization_id, visibility_class, acknowledgement_mode.
 * Latent (no caller hit them since W1a M2). Migration 20260805000109 patches both:
 *   - organization_id      := caller's members.organization_id (single-tenant; caller-derived,
 *                             matches create_governance_document_intake).
 *   - visibility_class     := 'active_members' (100% uniform across existing rows; verified live).
 *   - acknowledgement_mode := per doc_type, mirroring existing rows
 *                             (manual → 'informational'; cooperation_agreement → 'legal_signature').
 * Body-only CREATE OR REPLACE (same signatures). #315 may later centralize the defaults.
 *
 * Cross-ref: BUG-268.A (mig 047), SEDIMENT-268.A (mig 048),
 *   parent constraint 20260805000035_p256_wave1a_315_m1_governance_org_id_backfill + W1a M2.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const MIGRATION_FILE = join(MIGRATIONS_DIR, '20260805000109_p403_governance_insert_rpcs_required_columns.sql');
const REQUIRED = ['organization_id', 'visibility_class', 'acknowledgement_mode'];

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const readMigration = () => readFileSync(MIGRATION_FILE, 'utf8');
const codeOnly = (body) => body.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
function extractFunctionBody(body, name) {
  const startRegex = new RegExp(`CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${name}\\s*\\(`, 'i');
  const startMatch = body.match(startRegex);
  if (!startMatch) return null;
  const endIdx = body.indexOf('$function$;', startMatch.index);
  if (endIdx === -1) return null;
  return body.slice(startMatch.index, endIdx + '$function$;'.length);
}
// the governance_documents INSERT column list inside a function body
function insertCols(fnCode) {
  const m = fnCode.match(/INSERT INTO (?:public\.)?governance_documents\s*\(([^)]+)\)/i);
  return m ? m[1].split(',').map((s) => s.trim()) : null;
}
// the full INSERT INTO governance_documents ... RETURNING id INTO v_doc_id; statement
// (terminate on RETURNING, NOT the first `;` — the manual description string contains a literal ';').
function insertStmt(fnCode) {
  const m = codeOnly(fnCode).match(/INSERT INTO (?:public\.)?governance_documents[\s\S]+?RETURNING id INTO v_doc_id;/i);
  return m ? m[0] : null;
}

const WRITERS = [
  { name: 'confirm_manual_version', ack: 'informational', selectOrg: /SELECT id, name, organization_id INTO v_signer_id, v_signer_name, v_org_id/i },
  { name: 'link_attachment_to_governance', ack: 'legal_signature', selectOrg: /SELECT id, organization_id INTO v_member_id, v_org_id/i },
];

// ── static ──────────────────────────────────────────────────────────────────────
test('#403: migration file present at canonical path', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.startsWith('20260805000109_'));
  assert.equal(files.length, 1, 'exactly one 20260805000109_ migration');
  assert.match(files[0], /^20260805000109_p403_governance_insert_rpcs_required_columns\.sql$/);
});

test('#403: two CREATE OR REPLACE FUNCTIONs, no DROP (consumer-safe)', () => {
  const body = readMigration();
  for (const { name } of WRITERS) {
    assert.match(body, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\(`, 'i'), `${name} present`);
    assert.doesNotMatch(body, new RegExp(`DROP\\s+FUNCTION[^;]*${name}`, 'i'), `${name} must not be DROPped`);
  }
});

test('#403: SECURITY DEFINER + pinned search_path + RETURNS jsonb preserved (both)', () => {
  const body = readMigration();
  for (const { name } of WRITERS) {
    const fn = extractFunctionBody(body, name);
    assert.ok(fn, `${name} extractable`);
    assert.match(fn, /SECURITY DEFINER/i, `${name}: SECURITY DEFINER`);
    assert.match(fn, /SET search_path TO 'public', 'pg_temp'/i, `${name}: pinned search_path`);
    assert.match(fn, /RETURNS jsonb/i, `${name}: RETURNS jsonb`);
  }
});

test('#403: signatures preserved (no DROP+CREATE / DEFAULT changes)', () => {
  const body = readMigration();
  assert.match(body, /FUNCTION public\.confirm_manual_version\(p_proposal_id uuid\)/i,
    'confirm_manual_version 1-arg signature verbatim');
  assert.match(body,
    /FUNCTION public\.link_attachment_to_governance\(p_attachment_id uuid, p_title text, p_signed_at timestamp with time zone DEFAULT now\(\), p_parties text\[\] DEFAULT '\{\}'::text\[\]\)/i,
    'link_attachment_to_governance 4-arg signature + 2 DEFAULTs verbatim');
});

test('#403: each writer SELECTs the caller organization_id into v_org_id', () => {
  const body = readMigration();
  for (const { name, selectOrg } of WRITERS) {
    const fn = extractFunctionBody(body, name);
    assert.match(codeOnly(fn), selectOrg, `${name}: SELECT must load caller organization_id into v_org_id`);
  }
});

test('#403: both INSERT INTO governance_documents column lists include all 3 required columns', () => {
  const body = readMigration();
  for (const { name } of WRITERS) {
    const cols = insertCols(extractFunctionBody(body, name));
    assert.ok(cols, `${name}: INSERT INTO governance_documents column list present`);
    for (const c of REQUIRED) assert.ok(cols.includes(c), `${name}: column list must include ${c}`);
  }
});

test('#403: INSERT VALUES source org from v_org_id + correct per-doc_type ack/visibility', () => {
  const body = readMigration();
  for (const { name, ack } of WRITERS) {
    const stmt = insertStmt(extractFunctionBody(body, name));
    assert.ok(stmt, `${name}: INSERT statement present`);
    assert.ok(stmt.includes('v_org_id'), `${name}: organization_id sourced from v_org_id (caller-derived, not NULL/hardcoded)`);
    assert.ok(stmt.includes("'active_members'"), `${name}: visibility_class = 'active_members'`);
    assert.ok(stmt.includes(`'${ack}'`), `${name}: acknowledgement_mode = '${ack}'`);
  }
});

test('#403: sanity DO block + NOTIFY pgrst present', () => {
  const body = readMigration();
  assert.match(body, /DO \$sanity\$[\s\S]+acknowledgement_mode[\s\S]+\$sanity\$/i, 'post-apply sanity DO');
  assert.match(body, /NOTIFY\s+pgrst\s*,\s*'reload schema'/i, 'PostgREST cache reload');
});

// ── forward-defense (lock the regression class) ──────────────────────────────────
test('#403: FD — neither writer may drop the 3 columns or NULL/hardcode org', () => {
  const body = readMigration();
  for (const { name } of WRITERS) {
    const code = codeOnly(extractFunctionBody(body, name));
    const stmt = insertStmt(extractFunctionBody(body, name));
    for (const c of REQUIRED) assert.ok(stmt.includes(c), `FD: ${name} INSERT must keep ${c}`);
    assert.doesNotMatch(code, /organization_id\s*[:=]\s*NULL/i, `FD: ${name} must never NULL organization_id`);
    assert.doesNotMatch(stmt, /,\s*NULL\s*,\s*'active_members'/i, `FD: ${name} must not pass NULL org positionally`);
  }
});

test('#403: forward-defense — latest migration declaring each writer keeps all 3 columns', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  for (const { name } of WRITERS) {
    const declarers = files.filter((f) =>
      new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\b`, 'i').test(readFileSync(join(MIGRATIONS_DIR, f), 'utf8'))
    );
    assert.ok(declarers.length >= 1, `${name}: at least one declarer`);
    // Guard the regression CLASS, not a filename: whichever migration last declares this writer must
    // still carry all 3 required columns. (No strict filename pin — that would self-block the next
    // legitimate body patch; the column-presence check below is the substantive forward-defense.)
    const latest = declarers[declarers.length - 1];
    const cols = insertCols(extractFunctionBody(readFileSync(join(MIGRATIONS_DIR, latest), 'utf8'), name));
    assert.ok(cols, `${name}: latest declarer (${latest}) must have an extractable governance_documents INSERT`);
    for (const c of REQUIRED) assert.ok(cols.includes(c),
      `${name}: the latest migration declaring it (${latest}) dropped ${c} — re-introduces #403`);
  }
});

// ── DB-gated ─────────────────────────────────────────────────────────────────────
test('DB: live bodies of both writers reference all 3 required columns', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_list_public_function_bodies', {
    p_names: ['confirm_manual_version', 'link_attachment_to_governance'],
  });
  assert.ok(!error, error?.message);
  assert.ok(Array.isArray(data), 'helper returns rows');
  for (const { name } of WRITERS) {
    const fn = data.find((r) => r.proname === name);
    assert.ok(fn?.prosrc, `${name}: live body present`);
    const cols = insertCols(fn.prosrc);
    assert.ok(cols, `${name}: live INSERT INTO governance_documents column list present`);
    for (const c of REQUIRED) assert.ok(cols.includes(c), `${name}: live body INSERT must list ${c}`);
  }
});

test('DB: governance_documents has the 3 columns NOT NULL (the constraint that broke the RPCs)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // service-role exercise: a row missing any of the 3 must be rejected — proves the columns are required.
  const { error } = await sb.from('governance_documents').insert({ title: '__p403_probe__', doc_type: 'manual' });
  assert.ok(error, 'INSERT omitting organization_id/visibility_class/acknowledgement_mode must be rejected (NOT NULL)');
  // pin the rejection to one of the 3 required columns, so a future NOT-NULL on an unrelated column
  // (e.g. version) can't produce a false green here.
  assert.match(error.message, /organization_id|visibility_class|acknowledgement_mode|null value/i,
    `rejection must be a NOT NULL violation on a required taxonomy column, got: ${error.message}`);
});
