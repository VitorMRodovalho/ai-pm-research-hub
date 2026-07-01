/**
 * Contract test for issue #991 — verify_certificate must not leak third-party
 * member NAMES (issuer / counter-signer) and must not act as a status oracle on
 * the anonymous /verify surface.
 *
 * Two layers:
 *   1. Static analysis of the latest verify_certificate migration body — offline-safe,
 *      always runs, hard-fails without a DB. This is the structural guarantee: the
 *      function resolves NO issuer/counter-signer name, returns NO name-bearing keys,
 *      no revoked_reason, no status discriminant, and collapses non-issued codes to
 *      {valid:false}.
 *   2. Runtime DB-aware assertions (skip when SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
 *      are absent). verify_certificate is SECURITY DEFINER, so its response shape is
 *      identical regardless of caller; a service-role call proves the anon-visible
 *      projection carries no third-party name and that a bad code returns exactly
 *      {valid:false}.
 *
 * Pattern: static half mirrors certificate-signature-evidence.test.mjs (read-all
 * migrations, regex latest body). Ref: SPEC_308 §11 F-M-names / F-H5; ADR-0098.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => readFileSync(join(MIGRATIONS_DIR, f), 'utf8'));
}

const allSQL = loadAllMigrations().join('\n');

function latestFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][2] : null;
}

// ── Layer 1: static structural guarantees ────────────────────────────────────

test('#991 static: verify_certificate resolves no issuer/counter-signer NAME', () => {
  const body = latestFunctionBody('verify_certificate');
  assert.ok(body, 'verify_certificate must be defined in a migration');

  // No declaration/resolution of third-party names.
  assert.ok(!/v_issuer_name/.test(body), 'must not declare/resolve v_issuer_name');
  assert.ok(!/v_countersigner_name/.test(body), 'must not declare/resolve v_countersigner_name');
  // The only name resolved is the holder (member_name). Assert exactly one
  // "SELECT name INTO" (the holder), not the two name lookups the leak added.
  const nameSelects = body.match(/SELECT\s+name\s+INTO/gi) || [];
  assert.equal(nameSelects.length, 1, 'exactly one name lookup (the holder) — no issuer/counter-signer name resolution');
});

test('#991 static: returned jsonb carries no name-bearing / oracle keys', () => {
  const body = latestFunctionBody('verify_certificate');
  assert.ok(body);

  // Returned KEYS (single-quoted) that must be GONE.
  for (const key of ["'issued_by'", "'counter_signed_by'", "'revoked_reason'", "'revoked'", "'rejected'", "'superseded'"]) {
    assert.ok(!body.includes(key), `returned key ${key} must be removed`);
  }
  // No status-discriminant "error" marker at all (not-found is indistinguishable).
  assert.ok(!/'error'/.test(body), "no 'error' discriminant key");

  // Returned KEYS that must be PRESENT.
  for (const key of ["'valid'", "'authorized_by'", "'has_counter_signature'", "'counter_signed_at'", "'member_name'"]) {
    assert.ok(body.includes(key), `returned key ${key} must be present`);
  }
  // The org-attribution string replaces the issuer/counter-signer names.
  assert.ok(/Presidência, Núcleo IA e GP/.test(body), 'authorized_by uses the fixed org string');
});

test('#991 static: non-issued codes collapse to {valid:false} (no oracle)', () => {
  const body = latestFunctionBody('verify_certificate');
  assert.ok(body);
  // A single collapse branch returning only {valid:false}.
  assert.ok(
    /jsonb_build_object\(\s*'valid'\s*,\s*false\s*\)/.test(body),
    "must have a jsonb_build_object('valid', false) collapse branch"
  );
  // The guard covers both not-found AND any non-issued status (fail-closed on NULL
  // via IS DISTINCT FROM; the older <> form is also accepted for robustness).
  assert.ok(
    /cert IS NULL/.test(body) && /status[\s\S]*?(?:IS DISTINCT FROM|<>)\s*'issued'/.test(body),
    'collapse guard covers cert IS NULL OR status is-not issued'
  );
});

test('#991 static: verify_certificate stays SECURITY DEFINER', () => {
  // pg_get_functiondef body capture excludes the header, so scan the raw SQL:
  // the latest CREATE for verify_certificate must be SECURITY DEFINER (anon /verify).
  const idx = allSQL.lastIndexOf('FUNCTION public.verify_certificate');
  assert.ok(idx >= 0, 'verify_certificate CREATE present');
  const header = allSQL.slice(idx, idx + 400);
  assert.ok(/SECURITY DEFINER/.test(header), 'latest verify_certificate must be SECURITY DEFINER');
});

// ── Layer 2: runtime DB-aware assertions (skip offline) ───────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const ALLOWED_KEYS = new Set([
  'valid', 'type', 'title', 'member_name', 'issued_at', 'authorized_by',
  'has_counter_signature', 'counter_signed_at', 'cycle', 'period_start',
  'period_end', 'function_role', 'language', 'verification_code',
]);

test('#991 runtime: valid cert returns no third-party name, no leaking keys', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data: cert, error: cErr } = await sb
    .from('certificates')
    .select('verification_code, member_id, issued_by, counter_signed_by')
    .eq('status', 'issued')
    .not('issued_by', 'is', null)
    .not('counter_signed_by', 'is', null)
    .limit(1)
    .maybeSingle();
  assert.equal(cErr, null, cErr?.message);
  if (!cert) return; // no counter-signed issued cert to probe — nothing to assert

  const ids = [cert.member_id, cert.issued_by, cert.counter_signed_by].filter(Boolean);
  const { data: members } = await sb.from('members').select('id, name').in('id', ids);
  const nameOf = (id) => (members || []).find(m => m.id === id)?.name || null;
  const holderName = nameOf(cert.member_id);
  const issuerName = nameOf(cert.issued_by);
  const csName = nameOf(cert.counter_signed_by);

  const { data: resp, error: rErr } = await sb.rpc('verify_certificate', { p_code: cert.verification_code });
  assert.equal(rErr, null, rErr?.message);
  assert.equal(resp.valid, true, 'issued cert must verify as valid');

  // Key allowlist: no unexpected keys leaked in.
  for (const k of Object.keys(resp)) {
    assert.ok(ALLOWED_KEYS.has(k), `unexpected key in anon /verify response: ${k}`);
  }
  assert.ok(!('issued_by' in resp), 'issued_by name must not be returned');
  assert.ok(!('counter_signed_by' in resp), 'counter_signed_by name must not be returned');
  assert.ok(!('revoked_reason' in resp), 'revoked_reason must not be returned');
  assert.equal(resp.authorized_by, 'Presidência, Núcleo IA e GP');
  assert.equal(resp.has_counter_signature, true);

  // Third-party names must be ABSENT from the payload; holder name is intentionally kept.
  const blob = JSON.stringify(resp);
  if (issuerName && issuerName !== holderName) {
    assert.ok(!blob.includes(issuerName), 'issuer name leaked into anon /verify response');
  }
  if (csName && csName !== holderName) {
    assert.ok(!blob.includes(csName), 'counter-signer name leaked into anon /verify response');
  }
});

test('#991 runtime: unknown code returns exactly {valid:false} (no oracle)', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data: resp, error } = await sb.rpc('verify_certificate', { p_code: 'NOT-A-REAL-CODE-991-contract-test' });
  assert.equal(error, null, error?.message);
  assert.deepEqual(resp, { valid: false }, 'unknown code must be indistinguishable {valid:false}');
});
