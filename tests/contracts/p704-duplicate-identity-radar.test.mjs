/**
 * #704 — Duplicate PMI identity radar.
 *
 * selection_applications dedups by (vep_application_id, vep_opportunity_id) — per VEP
 * ACCOUNT, never per PERSON. One human with two PMI registrations (distinct pmi_id +
 * email + name) appears as independent candidates. The anchor case (Ana) has DIFFERENT
 * names per account ("Ana Pacheco" vs "Ana Sofia Pires Pacheco"), so group-by-name finds
 * nothing — detection needs multi-signal fuzzy matching.
 *
 * get_duplicate_identity_candidates() (migration 20260805000175) is the standing radar:
 * read-only, manage_member-gated, surfaces candidate pairs by exact corroborators
 * (email/phone/linkedin/resume across distinct pmi_id) + fuzzy name (same normalized
 * first+last token, or trigram >= 0.55). It does NOT merge or mutate data.
 *
 * This test locks: (1) migration shape + gate, (2) the normalization/strong-token
 * algorithm (pure JS mirror of the SQL — deterministic, no DB), (3) the live gate is
 * closed to non-authenticated callers (service_role → Forbidden).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000175_704_duplicate_identity_radar.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── pure-JS mirror of the SQL normalization (must stay byte-equivalent to the migration) ──
const ACC_FROM = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
const ACC_TO   = 'aaaaaeeeeiiiiooooouuuucn';
function unaccent(s) {
  return s.replace(/./g, ch => { const i = ACC_FROM.indexOf(ch); return i === -1 ? ch : ACC_TO[i]; });
}
function normName(raw) {
  return unaccent((raw || '').toLowerCase().trim()).replace(/[^a-z ]+/g, ' ').trim();
}
function tokens(raw) {
  const t = normName(raw).split(/\s+/).filter(Boolean);
  return { first: t[0] || '', last: t[t.length - 1] || '' };
}
// strong = same first AND same last normalized token, last length > 2 (the SQL 'fuzzy_name_strong')
function isStrongPair(nameA, nameB) {
  const a = tokens(nameA), b = tokens(nameB);
  return a.first === b.first && a.last === b.last && a.last.length > 2;
}

// ── STATIC ────────────────────────────────────────────────────────────────────
test('#704 static: migration 20260805000175 exists and defines the gated radar', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000175 present');
  const src = readFileSync(MIG, 'utf8');
  assert.match(src, /CREATE OR REPLACE FUNCTION public\.get_duplicate_identity_candidates\(/,
    'get_duplicate_identity_candidates defined');
  assert.match(src, /SECURITY DEFINER/, 'SECURITY DEFINER');
  assert.match(src, /can_by_member\(\s*v_caller_id\s*,\s*'manage_member'\s*\)/,
    'gated on can_by_member(..., manage_member)');
  assert.match(src, /REVOKE ALL ON FUNCTION public\.get_duplicate_identity_candidates[\s\S]*?FROM PUBLIC, anon/,
    'anon must be revoked');
});

// ── ALGORITHM (deterministic, no DB) ────────────────────────────────────────────
test('#704 algorithm: anchor case (Ana) is a strong cross-account match', () => {
  // The two accounts: distinct name/email/pmi_id, same person.
  assert.equal(isStrongPair('Ana Pacheco', 'Ana Sofia Pires Pacheco'), true,
    'Ana Pacheco ⇄ Ana Sofia Pires Pacheco must match on first+last token');
});

test('#704 algorithm: coincidental BR surnames are NOT strong matches (no false positives)', () => {
  // Same first token, different last token → not a duplicate identity.
  assert.equal(isStrongPair('Marcio Pimenta', 'Marcio Vidal'), false, 'diff last token');
  assert.equal(isStrongPair('Erick Oliveira', 'Flavio Oliveira'), false, 'diff first token');
  // accent-insensitivity must not collapse distinct names
  assert.equal(isStrongPair('Bruna Soares', 'Edinan Soares'), false, 'diff first token (shared surname)');
});

test('#704 algorithm: normalization is accent + case insensitive', () => {
  assert.equal(normName('José da SILVA'), 'jose da silva');
  assert.equal(isStrongPair('João Conceição', 'joao  conceicao'), true, 'accents/case/spacing normalized');
});

// ── DB-AWARE: gate is closed to non-authenticated callers ───────────────────────
test('#704 gate: service_role (no auth.uid) must be Forbidden', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_duplicate_identity_candidates');
  // No JWT context → auth.uid() is null → the RPC RAISEs 'authentication required'.
  assert.ok(error, `expected a Forbidden error, got data: ${JSON.stringify(data)}`);
  assert.match(String(error.message), /Forbidden|authentication required/i,
    `unexpected error: ${error.message}`);
});
