/**
 * Contract: #1187 — the volunteer-term version label must read through the ratified
 * version, and activation must not leave "Em revisão" zombie chains behind.
 *
 * Grounded 2026-07-08: after the Onda 1 activation (v9, chain c72ceca4),
 * /admin/certificates "Ver Template" still showed the v2.7 label because
 * governance_documents.version (text) was never stamped, and /admin/governance/documents
 * rendered chain d72916d7 (v2.7, status='review', opened 2026-05-12) as
 * "Em revisão · Aberto há 57 dias" with "Bola em: Aceite do GP" — an obsolete chain
 * inviting signatures. Fixed by migration 20260805000370 + one-time data correction.
 *
 * Layers:
 *   (A) offline static guards on migration 370 — the stamp, the chain promotion and
 *       the sibling-supersede must not regress out of activate_volunteer_term_version,
 *       and get_volunteer_agreement_status must read the label through document_versions;
 *   (B) DB-aware (skipped without SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY) — live
 *       invariants: active template label coherence + no zombie chains left open
 *       behind an activated one for the same document.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const MIG = resolve(
  process.cwd(),
  'supabase/migrations/20260805000370_1187_term_version_label_readthrough_and_zombie_chain_close.sql'
);
const migSrc = readFileSync(MIG, 'utf8');

// ── Layer A: migration 370 static guards ───────────────────────────────────────

test('#1187: activation stamps governance_documents.version with the activated version_label', () => {
  assert.match(migSrc, /version = COALESCE\(v_version_label, version\)/,
    'activate_volunteer_term_version must stamp gd.version from the activated version_label');
  assert.match(migSrc, /SELECT dv\.content_html, dv\.version_label INTO v_html, v_version_label/,
    'the locked-body lookup must also fetch version_label');
});

test('#1187: activation promotes the winning chain to status active', () => {
  assert.match(migSrc, /SET status = 'active', activated_at = COALESCE\(activated_at, now\(\)\)/,
    'the ratified chain must be promoted to status=active (historic convention), not left approved');
});

test('#1187: activation supersedes sibling chains still open for older versions', () => {
  assert.match(migSrc, /SET status = 'superseded', closed_at = COALESCE\(closed_at, now\(\)\)/,
    'sibling open chains must be closed as superseded');
  assert.match(migSrc, /AND status IN \('draft', 'review', 'approved'\)\s*\n\s*AND opened_at <= v_chain_opened/,
    'only chains opened up to the activated chain stay eligible (newer drafts survive)');
});

test('#1187: get_volunteer_agreement_status template.version reads through current_version_id', () => {
  assert.match(migSrc, /'version', COALESCE\(dv\.version_label, gd\.version\)/,
    'template.version must be the ratified version_label, falling back to the text cache');
  assert.match(migSrc, /LEFT JOIN public\.document_versions dv ON dv\.id = gd\.current_version_id/,
    'the read-through join must target current_version_id');
});

// ── Layer B: live invariants (skip offline) ────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1187: active volunteer_term_template docs have version == current version_label', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data: docs, error } = await sb
    .from('governance_documents')
    .select('id, title, status, version, current_version_id')
    .eq('doc_type', 'volunteer_term_template')
    .eq('status', 'active');
  assert.ifError(error);
  assert.ok((docs ?? []).length >= 1, 'there must be exactly one active volunteer term template');

  for (const doc of docs) {
    assert.ok(doc.current_version_id, `${doc.title}: active template must have current_version_id`);
    const { data: dv, error: e2 } = await sb
      .from('document_versions')
      .select('version_label')
      .eq('id', doc.current_version_id)
      .single();
    assert.ifError(e2);
    assert.equal(doc.version, dv.version_label,
      `${doc.title}: governance_documents.version ("${doc.version}") drifted from the ratified ` +
      `version_label ("${dv.version_label}") — activation stamp regressed or manual edit bypassed it`);
  }
});

test('#1187: no zombie chains — nothing open behind an activated chain of the same doc', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data: docs, error } = await sb
    .from('governance_documents')
    .select('id, title')
    .eq('doc_type', 'volunteer_term_template');
  assert.ifError(error);

  for (const doc of docs ?? []) {
    const { data: chains, error: e2 } = await sb
      .from('approval_chains')
      .select('id, status, opened_at, activated_at')
      .eq('document_id', doc.id);
    assert.ifError(e2);
    const activated = (chains ?? []).filter((c) => c.activated_at);
    if (activated.length === 0) continue;
    const latestActivatedOpen = activated
      .map((c) => c.opened_at)
      .sort()
      .at(-1);
    const zombies = (chains ?? []).filter(
      (c) => ['draft', 'review', 'approved'].includes(c.status)
        && !c.activated_at
        && c.opened_at <= latestActivatedOpen
    );
    assert.deepEqual(
      zombies.map((z) => z.id),
      [],
      `${doc.title}: chains ${zombies.map((z) => z.id).join(', ')} are still open behind an ` +
      'activated chain — they render as "Em revisão" zombies in /admin/governance/documents'
    );
  }
});
