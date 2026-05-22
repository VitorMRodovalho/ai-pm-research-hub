/**
 * Forward-defense for p221 #267 alpha — server-side cert PDF backfill scope.
 *
 * Locks the invariants that the alpha scope deliberately ships:
 *   1. Migration creates `certificates` storage bucket (private, 10MB, PDF only)
 *   2. Migration deliberately omits storage.objects RLS policies — service_role
 *      bypasses RLS for backfill; member-owned access waits for Option C
 *      (verify-route binding + Studio UI policy step). Drift here means a future
 *      session may silently expose private cert content via authenticated SELECT
 *      without going through the controlled signed-URL pipeline.
 *   3. Backfill script imports the canonical HTML template (pdf.ts) — porting
 *      drift between client and server-side renderers would mean visual divergence
 *      between member-print and stored-PDF artifacts.
 *   4. Storage path convention is <member_id>/<verification_code>.pdf — required
 *      for future member-owned RLS policy in Option C (path[0] = member_id).
 *   5. Script is idempotent: default mode (no --force) only fetches certs WHERE
 *      pdf_url IS NULL. Re-runs MUST NOT double-upload after the 42-cert backfill.
 *
 * Cross-ref:
 *   - supabase/migrations/20260805000000_p221_267_create_certificates_bucket.sql
 *   - scripts/backfill-cert-pdfs.ts
 *   - src/lib/certificates/pdf.ts (canonical HTML template)
 *   - Issue #267 (WATCH-258.A)
 *   - P162 RESOLVED-267 (to be added at session close)
 *
 * Scope: static analysis. No DB env required.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATION = resolve(ROOT, 'supabase/migrations/20260805000000_p221_267_create_certificates_bucket.sql');
const SCRIPT = resolve(ROOT, 'scripts/backfill-cert-pdfs.ts');

test('migration 20260805000000 exists', () => {
  assert.ok(existsSync(MIGRATION),
    'supabase/migrations/20260805000000_p221_267_create_certificates_bucket.sql must exist — alpha scope creates the certificates bucket');
});

test('migration creates certificates bucket as private with PDF mime + 10MB cap', () => {
  const body = readFileSync(MIGRATION, 'utf8');
  assert.match(body, /INSERT\s+INTO\s+storage\.buckets\b/i,
    'migration must INSERT into storage.buckets');
  assert.match(body, /'certificates'/,
    'bucket id must be "certificates"');
  assert.match(body, /\bfalse\b/i,
    'public must be false (bucket is private; cert content_snapshot is PII-heavy)');
  assert.match(body, /\b10485760\b/,
    'file_size_limit must be 10485760 (10MB) — certs typically 130-150KB, generous headroom');
  assert.match(body, /'application\/pdf'/,
    'allowed_mime_types must include application/pdf');
  assert.match(body, /ON\s+CONFLICT\s*\(\s*id\s*\)\s+DO\s+UPDATE/i,
    'migration must be idempotent via ON CONFLICT DO UPDATE — re-applying must not error');
});

test('migration deliberately omits storage.objects RLS policies (alpha scope)', () => {
  // RLS policies on storage.objects require Studio UI (owner chain blocks MCP/SQL editor).
  // Alpha scope is service_role-only (backfill); member-owned SELECT path is Option C.
  // Drift here would mean a future session re-introduced a policy via MCP that will fail to apply,
  // OR accidentally added a policy that exposes private cert content via direct storage SELECT.
  const body = readFileSync(MIGRATION, 'utf8');
  assert.doesNotMatch(body, /CREATE\s+POLICY/i,
    'migration must NOT CREATE POLICY on storage.objects — alpha is service_role-only. ' +
    'Member-owned + GP/admin RLS lives in Option C (Studio UI Storage > Policies tab per sediment p210).');
});

test('backfill script exists at scripts/backfill-cert-pdfs.ts', () => {
  assert.ok(existsSync(SCRIPT),
    'scripts/backfill-cert-pdfs.ts must exist — alpha backfill runner');
});

test('backfill script imports canonical pdf.ts template (no rendering drift)', () => {
  const body = readFileSync(SCRIPT, 'utf8');
  const importPattern = /import\s*\{[^}]*\b(buildCertificateHTML|hydrateCertData)\b[^}]*\}\s*from\s*['"]\.\.\/src\/lib\/certificates\/pdf\.ts['"]/;
  assert.match(body, importPattern,
    'backfill script must import buildCertificateHTML + hydrateCertData from ../src/lib/certificates/pdf.ts ' +
    '— preserves visual 1:1 with browser-print pipeline; porting drift would mean stored PDFs diverge from member downloads');
});

test('backfill script uses <member_id>/<verification_code>.pdf storage path convention', () => {
  // Convention is required so future member-owned RLS policy (Option C) can extract member_id
  // via storage.foldername(name)[1] and compare to auth.uid() → members.id.
  const body = readFileSync(SCRIPT, 'utf8');
  const pathPattern = /\$\{\s*cert\.member_id\s*\}\s*\/\s*\$\{[^}]*\}\s*\.pdf/;
  assert.match(body, pathPattern,
    'backfill script must build storage path as <member_id>/<verification_code>.pdf ' +
    '— required for future member-owned RLS in Option C (path[0] = member_id)');
});

test('backfill script is idempotent (default mode skips certs with pdf_url already set)', () => {
  const body = readFileSync(SCRIPT, 'utf8');
  // The fetch loop must filter pdf_url IS NULL by default. The --force flag may override.
  const idempotentFilter = /\.is\(\s*['"]pdf_url['"]\s*,\s*null\s*\)/;
  assert.match(body, idempotentFilter,
    'backfill script default mode must filter pdf_url IS NULL — re-runs after the 42-cert backfill MUST NOT double-upload');
  // Belt-and-suspenders: there's also a row-level skip if pdf_url is set
  assert.match(body, /cert\.pdf_url/,
    'backfill script must additionally row-level skip when cert.pdf_url is set (defense in depth)');
});

test('backfill script uses application/pdf content type on upload (matches bucket allowed_mime_types)', () => {
  const body = readFileSync(SCRIPT, 'utf8');
  assert.match(body, /contentType:\s*['"]application\/pdf['"]/,
    'backfill script must upload with contentType: "application/pdf" — bucket allowed_mime_types only accepts this');
});

test('backfill script renders A4 with margins matching the existing print template', () => {
  // pdf.ts buildPrintDocument uses @page{size:A4 portrait;margin:15mm 12mm 18mm 12mm}.
  // The backfill renderer MUST mirror these margins exactly so stored PDFs match what a member
  // would get from window.print() — otherwise visual divergence (e.g., text reflow, page break shifts).
  const body = readFileSync(SCRIPT, 'utf8');
  assert.match(body, /format:\s*['"]A4['"]/,
    'backfill must render A4');
  assert.match(body, /top:\s*['"]15mm['"]/,
    'top margin must be 15mm (matches pdf.ts @page)');
  assert.match(body, /bottom:\s*['"]18mm['"]/,
    'bottom margin must be 18mm (matches pdf.ts @page)');
  assert.match(body, /left:\s*['"]12mm['"]/,
    'left margin must be 12mm (matches pdf.ts @page)');
  assert.match(body, /right:\s*['"]12mm['"]/,
    'right margin must be 12mm (matches pdf.ts @page)');
});
