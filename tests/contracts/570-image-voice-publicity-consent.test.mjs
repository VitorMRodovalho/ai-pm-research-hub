/**
 * Contract: #570 — Autonomous image/voice publicity consent opt-in/revoke MECHANISM.
 *
 * Origin: Parecer 01/2026 rec (e); Adendo Retificativo "Art. 8-A" (net-new clause, gated); Termo
 * Cláusula 11 + Parágrafo único (current image-consent basis + revocation rule). The consent moves
 * from "implicit on Term adhesion (Cláusula 11)" → an AUTONOMOUS, dissociated, revocable-anytime
 * opt-in recorded in the immutable consent_records ledger. This migration (20260805000298) is the
 * FIRST writer to consent_records (read RPCs landed in #568; table armed RPC-only in p107).
 *
 *   1. consent_records policy_type CHECK extended with 'image_voice_publicity' (sole definition: p107).
 *   2. grant_image_voice_consent(jsonb) — member self-service active opt-in. SECDEF, auth.uid()→member,
 *      idempotent on the active row, inserts a single-member row (channel='platform_action').
 *   3. revoke_image_voice_consent(text) — sets revoked_at + reason on the active row. NO retroactive
 *      effect (mirrors Cláusula 11 Parágrafo único / LGPD Art. 8º §5º); the row is never deleted.
 *
 * RETROFIT INVARIANT (legal, AC): NO backfill — a Term/Cláusula-11 signature does NOT presume this
 * consent. The migration must not bulk-insert from members/auth_engagements/signatures.
 *
 * Grant posture: REVOKE FROM PUBLIC, anon + GRANT authenticated, service_role (anti-open-relay, cf.
 * #568/#963). Surfaced in export_my_data for free (member_id-keyed; #568 added the consent_records key).
 *
 * Go-live (the public Art. 8-A clause text + member UI) is gated on legal G12 (LGPD Art. 11) per
 * council decision 2026-06-08 — the RPCs ship dormant. Cross-ref: #570, #568, Parecer 01/2026 rec e.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000298_570_image_voice_publicity_consent_mechanism.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const svcGated = !!(SUPABASE_URL && SERVICE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);

// ── STATIC: policy_type CHECK extended (new value added, original set preserved) ─────────
test('#570 static: consent_records policy_type CHECK gains image_voice_publicity, keeps the rest', () => {
  assert.ok(existsSync(MIG), 'migration 298 exists');
  assert.match(body, /DROP CONSTRAINT consent_records_policy_type_check/);
  assert.match(body, /ADD CONSTRAINT consent_records_policy_type_check/);
  // the new autonomous type
  assert.match(body, /'image_voice_publicity'/, 'new policy_type literal present');
  // the original p107 set must NOT be dropped by the rewrite (regression guard)
  for (const t of ['privacy_policy', 'volunteer_term', 'ai_analysis', 'communication_preferences', 'cookies', 'other']) {
    assert.match(body, new RegExp(`'${t}'`), `policy_type '${t}' retained`);
  }
});

// ── STATIC: grant_image_voice_consent — SECDEF, member-scoped, idempotent ────────────────
test('#570 static: grant_image_voice_consent is SECDEF, member-scoped, idempotent, channel=platform_action', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.grant_image_voice_consent\(p_evidence jsonb DEFAULT NULL\)/);
  const block = body.slice(
    body.indexOf('CREATE OR REPLACE FUNCTION public.grant_image_voice_consent'),
    body.indexOf('CREATE OR REPLACE FUNCTION public.revoke_image_voice_consent'));
  assert.match(block, /SECURITY DEFINER/, 'grant is SECURITY DEFINER');
  assert.match(block, /SET search_path TO 'public', 'pg_temp'/, 'pinned search_path');
  assert.match(block, /FROM public\.members WHERE auth_id = auth\.uid\(\)/, 'resolves the authenticated member');
  assert.match(block, /Not authenticated/, 'fail-closes for null uid');
  // idempotency: an active consent is returned, not duplicated
  assert.match(block, /revoked_at IS NULL[\s\S]*?'already_active', true/, 'returns already_active on an existing active consent');
  assert.match(block, /INSERT INTO public\.consent_records[\s\S]*?'image_voice_publicity'/, 'writes the new policy_type');
  assert.match(block, /'platform_action'/, 'records a valid platform_action channel');
});

// ── STATIC: revoke_image_voice_consent — sets revoked_at, NO retroactive effect, no delete ──
test('#570 static: revoke sets revoked_at on the active row with no retroactive effect (no delete)', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.revoke_image_voice_consent\(p_reason text DEFAULT NULL\)/);
  const block = body.slice(body.indexOf('CREATE OR REPLACE FUNCTION public.revoke_image_voice_consent'));
  assert.match(block, /SECURITY DEFINER/);
  assert.match(block, /UPDATE public\.consent_records[\s\S]*?SET revoked_at = now\(\)/, 'revocation stamps revoked_at');
  assert.match(block, /revoked_at IS NULL/, 'only the active row is revoked');
  assert.match(block, /'no_active_consent', true/, 'no-op path when nothing is active');
  // no retroactive effect: revocation must not DELETE consent rows (immutable ledger; preserves history)
  assert.doesNotMatch(block, /DELETE\s+FROM\s+public\.consent_records/i, 'revoke must not delete the ledger row');
});

// ── STATIC: RETROFIT INVARIANT — no backfill from existing signers (legal AC) ────────────
test('#570 static: NO backfill — consent is never presumed from Term/Cláusula-11 signatures', () => {
  // exactly one writer to consent_records (the per-member grant), keyed by a resolved member id
  const inserts = body.match(/INSERT INTO public\.consent_records/g) || [];
  assert.equal(inserts.length, 1, 'exactly one INSERT INTO consent_records (the single-member grant)');
  // the writer is a single-row VALUES insert …
  assert.match(body, /INSERT INTO public\.consent_records\s*\([\s\S]*?\)\s*VALUES\s*\(/,
    'the consent writer is a single-row VALUES insert');
  // … and NEVER an INSERT … SELECT bulk backfill. Bound the scan to ONE statement ([^;]* cannot cross
  // a semicolon) so the member-resolution SELECT in a later function is not mistaken for a backfill.
  assert.doesNotMatch(body, /INSERT INTO public\.consent_records[^;]*\bSELECT\b/i,
    'must NOT bulk-backfill image/voice consent via INSERT … SELECT from existing signers');
});

// ── STATIC: grant posture (anti-open-relay) + accountability ─────────────────────────────
test('#570 static: both RPCs revoke PUBLIC/anon, grant authenticated, and log to admin_audit_log', () => {
  for (const fn of ['grant_image_voice_consent\\(jsonb\\)', 'revoke_image_voice_consent\\(text\\)']) {
    assert.match(body, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn} FROM PUBLIC;`));
    assert.match(body, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn} FROM anon;`));
    assert.match(body, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn} TO authenticated, service_role;`));
  }
  assert.match(body, /INSERT INTO public\.admin_audit_log[\s\S]*?'image_voice_consent_granted'/, 'grant is audited');
  assert.match(body, /INSERT INTO public\.admin_audit_log[\s\S]*?'image_voice_consent_revoked'/, 'revoke is audited');
});

// ── DB (gated): anon is revoked; service_role (no auth.uid) fail-closes ───────────────────
test('#570 DB: anon CANNOT execute grant/revoke (revoke effective)', { skip: anonGated ? false : 'anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const g = await anon.rpc('grant_image_voice_consent', { p_evidence: null });
  assert.ok(g.error, 'anon rejected from grant_image_voice_consent');
  const r = await anon.rpc('revoke_image_voice_consent', { p_reason: null });
  assert.ok(r.error, 'anon rejected from revoke_image_voice_consent');
});

test('#570 DB: service_role (no auth.uid) fail-closes on grant + revoke (no write)', { skip: svcGated ? false : 'service key required' }, async () => {
  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const g = await svc.rpc('grant_image_voice_consent', { p_evidence: null });
  assert.ok(g.error, 'grant fail-closes for null uid (Not authenticated)');
  const r = await svc.rpc('revoke_image_voice_consent', { p_reason: null });
  assert.ok(r.error, 'revoke fail-closes for null uid (Not authenticated)');
});
