/**
 * Contract test for issue #1098 — event guest certificates (persons-anchored).
 *
 * The 16/07 Aftershow promises participation certificates to EXTERNAL guests, but
 * certificates.member_id is NOT NULL by design (ADR-0006). The guest path is a
 * dedicated table (event_guest_certificates) + issuance RPC + a dual-path
 * verify_certificate, with its own LGPD retention lane (ROPA G.1: 1 year
 * post-event, OUTSIDE the members 5y anonymization cron).
 *
 * Layers (mirrors 991-verify-certificate-no-pii-leak.test.mjs):
 *   1. Static — migration 20260805000338 structure: table shape, RLS enabled,
 *      anon revoked, issuance gate (manage_event/manage_platform), retention RPC
 *      (dry-run default + audit log), autogen trigger mirror, and the guest
 *      branch of verify_certificate keeping the #991 oracle-free semantics.
 *      Plus the render-pipeline wiring: pdf.ts event_participation type ×3 langs,
 *      endpoint guest fallback + guests/ storage prefix, backfill --guests lane.
 *   2. Runtime DB-aware (skip offline): unauthenticated issuance refused,
 *      unknown CERT-EVT code collapses to exactly {valid:false}, retention
 *      dry-run returns shape without deleting.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const MIGRATION_FILE = join(MIGRATIONS_DIR, '20260805000338_1098_event_guest_certificates.sql');

const migrationSQL = readFileSync(MIGRATION_FILE, 'utf8');

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

// ── Layer 1a: table + RLS structure ─────────────────────────────────────────

test('#1098 static: table is persons-anchored with own retention column', () => {
  assert.ok(/CREATE TABLE IF NOT EXISTS public\.event_guest_certificates/.test(migrationSQL));
  assert.ok(/person_id uuid NOT NULL REFERENCES public\.persons\(id\)/.test(migrationSQL),
    'person_id FK → persons (NOT members — that is the whole point of #1098)');
  assert.ok(/event_id uuid NOT NULL REFERENCES public\.events\(id\)/.test(migrationSQL));
  assert.ok(/retention_until date NOT NULL/.test(migrationSQL),
    'retention_until drives the ROPA G.1 one-year deletion lane');
  assert.ok(/verification_code text NOT NULL UNIQUE/.test(migrationSQL));
  assert.ok(!/REFERENCES public\.members\(id\)[\s\S]{0,40}NOT NULL/.test(migrationSQL.match(/CREATE TABLE[\s\S]*?\);/)[0]),
    'no NOT NULL member FK — guests have no members row');
});

test('#1098 static: RLS enabled, anon fully revoked, one-issued-per-person-event', () => {
  assert.ok(/ALTER TABLE public\.event_guest_certificates ENABLE ROW LEVEL SECURITY/.test(migrationSQL));
  assert.ok(/REVOKE ALL ON public\.event_guest_certificates FROM anon/.test(migrationSQL),
    'anon gets NOTHING from the table (public surface is only the SECURITY DEFINER verify RPC)');
  assert.ok(/CREATE POLICY egc_admin_all[\s\S]*?rls_can\('manage_platform'\)/.test(migrationSQL));
  assert.ok(/CREATE POLICY egc_read[\s\S]*?auth_id = auth\.uid\(\)/.test(migrationSQL),
    'own-row read via persons.auth_id');
  assert.ok(/CREATE UNIQUE INDEX IF NOT EXISTS event_guest_certs_one_issued_per_person_event[\s\S]*?WHERE status = 'issued'/.test(migrationSQL));
});

// ── Layer 1b: issuance RPC gate + retention RPC ──────────────────────────────

test('#1098 static: issuance RPC gated by manage_event/manage_platform via can()', () => {
  const body = latestFunctionBody('issue_event_guest_certificate');
  assert.ok(body, 'issue_event_guest_certificate must be captured in a migration');
  assert.ok(/can\(v_caller_person, 'manage_event', 'organization'/.test(body));
  assert.ok(/can\(v_caller_person, 'manage_platform', 'organization'/.test(body));
  assert.ok(/persons p WHERE p\.auth_id = auth\.uid\(\)/.test(body), 'caller resolved via persons.auth_id (V4)');
  assert.ok(/lower\(p\.email\) = v_email/.test(body), 'person reuse by lower(email)');
  assert.ok(/CERT-EVT-/.test(body), 'guest codes carry the CERT-EVT namespace');
  assert.ok(/NOT EXISTS \(SELECT 1 FROM public\.certificates WHERE verification_code = v_code\)/.test(body),
    'code uniqueness checked across BOTH tables');
  assert.ok(/admin_audit_log/.test(body), 'issuance is audit-logged');
  assert.ok(/interval '1 year'/.test(body), 'retention_until = event date + 1 year');
  // Review fixes (2026-07-04): consent is never fabricated — creating a NEW person
  // requires naming the consent instrument (LGPD Art. 7 I), with the event-guest
  // prefix the retention orphan-guard keys on; and the concurrent-create race is
  // closed by a partial unique index + unique_violation re-select.
  assert.ok(/consent_version is required when creating a guest person/.test(body),
    'consent_version required (no silent consent fabrication)');
  assert.ok(/NOT LIKE 'event-guest%'/.test(body), 'event-guest prefix enforced');
  assert.ok(/WHEN unique_violation THEN/.test(body), 'concurrent person-create resolves via re-select');
  assert.ok(/CREATE UNIQUE INDEX IF NOT EXISTS persons_event_guest_email_unique[\s\S]*?WHERE consent_version LIKE 'event-guest%'/.test(migrationSQL),
    'partial unique index closes the guest-person create race');
  // Grants: authenticated only (gate inside), never anon/PUBLIC.
  assert.ok(/REVOKE ALL ON FUNCTION public\.issue_event_guest_certificate\(jsonb\) FROM PUBLIC/.test(migrationSQL));
  assert.ok(/REVOKE ALL ON FUNCTION public\.issue_event_guest_certificate\(jsonb\) FROM anon/.test(migrationSQL));
});

test('#1098 static: retention RPC is dry-run-default, gated, audit-logged, guard-railed', () => {
  const body = latestFunctionBody('delete_expired_event_guest_certificates');
  assert.ok(body, 'delete_expired_event_guest_certificates must be captured in a migration');
  assert.ok(/p_dry_run boolean DEFAULT true/.test(migrationSQL), 'dry-run by default');
  assert.ok(/service_role/.test(body) && /manage_platform/.test(body), 'gate: manage_platform or service_role');
  assert.ok(/retention_until < current_date/.test(body));
  assert.ok(/auth_id IS NULL/.test(body) && /legacy_member_id IS NULL/.test(body)
    && /consent_version LIKE 'event-guest%'/.test(body),
    'orphan persons deletion restricted to guest-only rows');
  assert.ok(/foreign_key_violation/.test(body), 'per-row FK-safe person deletion');
  assert.ok(/lgpd_event_guest_cert_retention_deletion/.test(body), 'writes the LGPD audit log entry');
  assert.ok(/storage_paths_to_purge/.test(body), 'returns storage paths for the DPO purge step');
});

// ── Layer 1c: verify_certificate dual path keeps #991 semantics ──────────────

test('#1098 static: verify_certificate guest branch is oracle-free and PII-safe', () => {
  const body = latestFunctionBody('verify_certificate');
  assert.ok(body);
  assert.ok(/FROM event_guest_certificates g/.test(body), 'guest table is resolved by the SAME public surface');
  assert.ok(/'audience', 'event_guest'/.test(body), 'guest payload is marked audience=event_guest');
  // #991 invariants survive the extension:
  assert.ok(/cert IS NULL/.test(body) && /IS DISTINCT FROM\s*'issued'/.test(body));
  assert.ok(/guest\.id IS NULL OR guest\.status IS DISTINCT FROM 'issued'/.test(body),
    'guest misses/non-issued collapse into the same {valid:false}');
  const nameSelects = body.match(/SELECT\s+name\s+INTO/gi) || [];
  assert.equal(nameSelects.length, 1, 'still exactly one bare name lookup (the member holder)');
  assert.ok(!/v_issuer_name/.test(body) && !/'issued_by'/.test(body),
    'no issuer name/key on either path');
});

// ── Layer 1d: render pipeline wiring (pdf.ts + endpoint + backfill) ──────────

const pdfTs = readFileSync(resolve(ROOT, 'src/lib/certificates/pdf.ts'), 'utf8');
const endpointTs = readFileSync(resolve(ROOT, 'src/pages/api/internal/cert-pdf-render/[id].ts'), 'utf8');
const backfillTs = readFileSync(resolve(ROOT, 'scripts/backfill-cert-pdfs.ts'), 'utf8');

test('#1098 static: pdf.ts renders event_participation via the recognition template, 3 langs', () => {
  assert.ok(/RECOGNITION_TYPES = new Set\(\[[^\]]*"event_participation"/.test(pdfTs),
    'event_participation must be a recognition (landscape dual-sign) type');
  const bodies = pdfTs.match(/bodyEventParticipation:/g) || [];
  assert.equal(bodies.length, 3, 'bodyEventParticipation present in pt-BR, en-US and es-LATAM');
  assert.ok(/\{event\}/.test(pdfTs), 'guest body copy interpolates the event title');
  assert.ok(!/PDU/i.test(pdfTs.match(/bodyEventParticipation:[^\n]*/g).join('\n')),
    'guest body copy carries NO PDU claim (gate #1008 Option A)');
  assert.ok(/counter_signed_by\?: string/.test(pdfTs),
    'CertificateData accepts a direct counter-signer (guest certs have no certificates row for hydrate)');
  assert.ok(/certRow\?\.counter_signed_by\s*\|\|\s*\(certData\.type === 'event_participation' \? certData\.counter_signed_by : undefined\)/.test(pdfTs),
    'hydrateCertData falls back to the directly-passed counter-signer ONLY for guest certs — member certs keep resolving from the DB row (review fix 2026-07-04)');
});

test('#1098 static: render endpoint resolves guest certs and segregates storage', () => {
  assert.ok(/from\('event_guest_certificates'\)/.test(endpointTs), 'guest fallback lookup');
  assert.ok(/guests\/\$\{/.test(endpointTs), 'guest PDFs under guests/<person_id>/ (ROPA G.1 purge prefix)');
  assert.ok(/buildGuestCertData/.test(endpointTs));
  assert.ok(/cert \? 'certificates' : 'event_guest_certificates'/.test(endpointTs),
    'pdf_url UPDATE targets the right table');
});

test('#1098 static: backfill script has the --guests recovery lane', () => {
  assert.ok(/--guests/.test(backfillTs), '429-recovery lane for post-event batches (C3 lesson)');
  assert.ok(/fetchGuestCerts/.test(backfillTs) && /buildGuestCertData/.test(backfillTs));
  assert.ok(/guests\/\$\{/.test(backfillTs), 'same guests/ storage prefix as the endpoint');
});

// ── Layer 2: runtime DB-aware assertions (skip offline) ──────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1098 runtime: unauthenticated issuance is refused', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // service_role has no auth.uid() → the RPC must refuse before touching anything.
  const { data, error } = await sb.rpc('issue_event_guest_certificate', {
    p_data: { event_id: '00000000-0000-0000-0000-000000000000', guest_name: 'X', guest_email: 'x@x.com' },
  });
  assert.equal(error, null, error?.message);
  assert.equal(data?.error, 'Not authenticated');
});

test('#1098 runtime: unknown CERT-EVT code is exactly {valid:false} (no oracle)', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('verify_certificate', { p_code: 'CERT-EVT-2026-CONTRACT-TEST-MISS' });
  assert.equal(error, null, error?.message);
  assert.deepEqual(data, { valid: false });
});

test('#1098 runtime: retention dry-run returns shape without deleting', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('delete_expired_event_guest_certificates', { p_dry_run: true });
  assert.equal(error, null, error?.message);
  assert.equal(data?.ok, true);
  assert.equal(data?.dry_run, true);
  assert.ok(Array.isArray(data?.candidates));
});
