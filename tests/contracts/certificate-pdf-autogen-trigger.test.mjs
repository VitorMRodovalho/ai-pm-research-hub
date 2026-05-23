// p225 #281 — Forward auto-gen of certificate PDFs via DB trigger + CF Browser Rendering
//
// Static-analysis assertions on the artifacts that constitute the pipeline:
//   1. Migration 20260805000005 exists + contains the trigger fn + trigger + sanity DO
//   2. Endpoint src/pages/api/internal/cert-pdf-render/[id].ts exists with auth + render + upload
//   3. wrangler.toml has [browser] binding = "BROWSER"
//   4. middleware.ts CSRF_BYPASS_PREFIXES includes /api/internal/
//   5. ADR-0098 exists + README entry references it
//   6. package.json has @cloudflare/puppeteer dep
//
// Why static-only (no DB-gated runtime tests):
//   - The trigger fires net.http_post which is async fire-and-forget; testing it
//     end-to-end requires the Worker endpoint deployed + secret configured (deploy ops).
//   - Pre-deploy unit/contract assertions catch surface drift (e.g. someone
//     refactors out the trigger, removes the binding, drops the ADR).

import { strict as assert } from 'node:assert';
import { readFileSync, existsSync } from 'node:fs';
import { test, describe } from 'node:test';

const MIGRATION_PATH = 'supabase/migrations/20260805000005_p225_281_certificate_pdf_autogen_trigger.sql';
const ENDPOINT_PATH = 'src/pages/api/internal/cert-pdf-render/[id].ts';
const WRANGLER_PATH = 'wrangler.toml';
const MIDDLEWARE_PATH = 'src/middleware.ts';
const ADR_PATH = 'docs/adr/ADR-0098-server-side-certificate-pdf-autogen.md';
const ADR_README_PATH = 'docs/adr/README.md';
const PACKAGE_JSON_PATH = 'package.json';

describe('p225 #281 — certificate PDF autogen trigger pipeline', () => {
  test('migration 20260805000005 exists', () => {
    assert.ok(existsSync(MIGRATION_PATH), `migration file missing: ${MIGRATION_PATH}`);
  });

  test('migration creates trigger fn _trg_certificate_pdf_autogen with SECURITY DEFINER', () => {
    const sql = readFileSync(MIGRATION_PATH, 'utf8');
    assert.match(sql, /CREATE OR REPLACE FUNCTION public\._trg_certificate_pdf_autogen\(\)/, 'fn name missing');
    assert.match(sql, /SECURITY DEFINER/, 'must be SECURITY DEFINER');
    assert.match(sql, /SET search_path = public, extensions/, 'must SET search_path for SECDEF safety');
  });

  test('migration reads shared secret from app.cert_pdf_internal_secret GUC', () => {
    const sql = readFileSync(MIGRATION_PATH, 'utf8');
    assert.match(sql, /current_setting\('app\.cert_pdf_internal_secret', true\)/, 'must read GUC with missing_ok=true');
    assert.match(
      sql,
      /v_secret = ''/,
      'must check for empty secret (not just NULL)',
    );
  });

  test('migration uses pg_net for fire-and-forget HTTP POST', () => {
    const sql = readFileSync(MIGRATION_PATH, 'utf8');
    assert.match(sql, /PERFORM net\.http_post\(/, 'must use net.http_post');
    assert.match(sql, /timeout_milliseconds := 30000/, 'must set timeout');
    assert.match(sql, /'Authorization', 'Bearer ' \|\| v_secret/, 'must send Bearer secret');
  });

  test('migration creates AFTER INSERT trigger with WHEN(NEW.pdf_url IS NULL) gate', () => {
    const sql = readFileSync(MIGRATION_PATH, 'utf8');
    assert.match(
      sql,
      /CREATE TRIGGER trg_certificate_pdf_autogen\s+AFTER INSERT ON public\.certificates\s+FOR EACH ROW WHEN \(NEW\.pdf_url IS NULL\)/,
      'trigger must be AFTER INSERT + WHEN(NEW.pdf_url IS NULL) for idempotency',
    );
    assert.match(sql, /EXECUTE FUNCTION public\._trg_certificate_pdf_autogen\(\)/, 'trigger must call the autogen fn');
  });

  test('migration has exception handler for best-effort semantics', () => {
    const sql = readFileSync(MIGRATION_PATH, 'utf8');
    assert.match(sql, /EXCEPTION\s+WHEN OTHERS THEN/, 'must catch any exception');
    assert.match(sql, /RAISE WARNING/, 'must log WARNING (not fail insert)');
    assert.match(sql, /RETURN NEW;[\s\S]+RETURN NEW;[\s\S]+RETURN NEW;/, 'must RETURN NEW in all paths (defense + skip + exception)');
  });

  test('migration has sanity DO block verifying trigger + function exist', () => {
    const sql = readFileSync(MIGRATION_PATH, 'utf8');
    assert.match(sql, /DO \$\$[\s\S]+pg_trigger[\s\S]+pg_proc[\s\S]+END \$\$;/m, 'must include sanity DO block');
    assert.match(sql, /RAISE EXCEPTION 'p225 #281 sanity/, 'sanity failure must RAISE EXCEPTION (block migration apply if invariant breaks)');
  });

  test('migration REVOKEs EXECUTE FROM PUBLIC + GRANTs to postgres', () => {
    const sql = readFileSync(MIGRATION_PATH, 'utf8');
    assert.match(sql, /REVOKE EXECUTE ON FUNCTION public\._trg_certificate_pdf_autogen\(\) FROM PUBLIC/);
    assert.match(sql, /GRANT EXECUTE ON FUNCTION public\._trg_certificate_pdf_autogen\(\) TO postgres/);
  });

  test('endpoint /api/internal/cert-pdf-render/[id].ts exists', () => {
    assert.ok(existsSync(ENDPOINT_PATH), `endpoint missing: ${ENDPOINT_PATH}`);
  });

  test('endpoint validates Bearer CERT_PDF_INTERNAL_SECRET', () => {
    const ts = readFileSync(ENDPOINT_PATH, 'utf8');
    assert.match(ts, /CERT_PDF_INTERNAL_SECRET/, 'must reference secret env var');
    assert.match(ts, /Authorization/, 'must read Authorization header');
    assert.match(ts, /Bearer \$\{expectedSecret\}/, 'must compare to Bearer <secret>');
    assert.match(ts, /status: 401/, 'must return 401 on auth failure');
  });

  test('endpoint uses service-role Supabase client', () => {
    const ts = readFileSync(ENDPOINT_PATH, 'utf8');
    assert.match(ts, /SUPABASE_SERVICE_ROLE_KEY/, 'must use service-role key');
    assert.match(ts, /persistSession: false/, 'must not persist session');
  });

  test('endpoint reuses buildCertificateHTML + hydrateCertData from pdf.ts (zero render drift)', () => {
    const ts = readFileSync(ENDPOINT_PATH, 'utf8');
    assert.match(
      ts,
      /from ['"](\.\.\/){1,4}lib\/certificates\/pdf['"]/,
      'must import from lib/certificates/pdf for visual parity with backfill + browser-print',
    );
    assert.match(ts, /buildCertificateHTML/, 'must call buildCertificateHTML');
    assert.match(ts, /hydrateCertData/, 'must call hydrateCertData');
  });

  test('endpoint uses CF Browser Rendering via @cloudflare/puppeteer', () => {
    const ts = readFileSync(ENDPOINT_PATH, 'utf8');
    assert.match(ts, /from ['"]@cloudflare\/puppeteer['"]/, 'must import @cloudflare/puppeteer');
    // BROWSER binding must be read from env
    assert.match(ts, /\.BROWSER\b/, 'must reference env.BROWSER binding (read from cloudflare:workers env)');
    // puppeteer.launch must be called (binding flows from variable above)
    assert.match(ts, /puppeteer\.launch\(/, 'must call puppeteer.launch()');
    assert.match(ts, /page\.pdf\(\{/, 'must call page.pdf');
    assert.match(ts, /format: 'A4'/, 'PDF format must be A4');
    assert.match(
      ts,
      /margin: \{\s*top: '15mm'.*right: '12mm'.*bottom: '18mm'.*left: '12mm'/s,
      'PDF margins must match backfill script + @page CSS',
    );
  });

  test('endpoint guards idempotency (skip when pdf_url already set)', () => {
    const ts = readFileSync(ENDPOINT_PATH, 'utf8');
    assert.match(ts, /if \(cert\.pdf_url\) \{/, 'must check cert.pdf_url before render');
    assert.match(ts, /pdf_already_set/, 'must return skip marker for already-set pdf_url');
    assert.match(ts, /\.is\('pdf_url', null\)/, 'UPDATE must filter WHERE pdf_url IS NULL (race-safe)');
  });

  test('endpoint uploads to certificates bucket via service-role + upsert true', () => {
    const ts = readFileSync(ENDPOINT_PATH, 'utf8');
    assert.match(ts, /from\(['"]certificates['"]\)/, 'must use certificates bucket');
    assert.match(ts, /upsert: true/, 'must use upsert=true for re-renders');
    assert.match(ts, /contentType: 'application\/pdf'/, 'contentType must match bucket allowed_mime');
    assert.match(
      ts,
      /\$\{cert\.member_id\}\/\$\{cert\.verification_code\}\.pdf/,
      'storage path must follow <member_id>/<verification_code>.pdf convention from backfill',
    );
  });

  test('endpoint only accepts POST (405 on GET)', () => {
    const ts = readFileSync(ENDPOINT_PATH, 'utf8');
    assert.match(ts, /export const POST: APIRoute/, 'must export POST handler');
    assert.match(ts, /export const GET: APIRoute/, 'must export GET handler (returning 405)');
    assert.match(ts, /status: 405/, 'GET must return 405 method_not_allowed');
  });

  test('wrangler.toml has [browser] binding = "BROWSER"', () => {
    const toml = readFileSync(WRANGLER_PATH, 'utf8');
    assert.match(
      toml,
      /\[browser\]\s*binding = "BROWSER"/,
      'wrangler.toml must declare [browser] binding for CF Browser Rendering',
    );
  });

  test('middleware.ts adds /api/internal/ to CSRF_BYPASS_PREFIXES', () => {
    const ts = readFileSync(MIDDLEWARE_PATH, 'utf8');
    assert.match(
      ts,
      /CSRF_BYPASS_PREFIXES = \[[^\]]*"\/api\/internal\/"[^\]]*\]/s,
      'middleware must allow cross-origin POST on /api/internal/ for DB-trigger callbacks',
    );
  });

  test('ADR-0098 exists + is Accepted status', () => {
    assert.ok(existsSync(ADR_PATH), `ADR-0098 missing: ${ADR_PATH}`);
    const adr = readFileSync(ADR_PATH, 'utf8');
    assert.match(adr, /\*\*Status:\*\*\s*Accepted/, 'ADR must be Accepted');
    assert.match(adr, /p225/, 'ADR must reference p225 session');
    assert.match(adr, /#281/, 'ADR must reference issue #281');
    assert.match(adr, /20260805000005/, 'ADR must reference the migration version');
  });

  test('ADR-0098 entry present in docs/adr/README.md', () => {
    const readme = readFileSync(ADR_README_PATH, 'utf8');
    assert.match(readme, /ADR-0098-server-side-certificate-pdf-autogen\.md/, 'README must link ADR-0098 file');
    assert.match(readme, /Accepted \(2026-05-23 p225 #281 close\)/, 'README entry must mark Accepted with session ref');
  });

  test('@cloudflare/puppeteer dep added to package.json', () => {
    const pkg = JSON.parse(readFileSync(PACKAGE_JSON_PATH, 'utf8'));
    const deps = { ...(pkg.dependencies ?? {}), ...(pkg.devDependencies ?? {}) };
    assert.ok(
      Object.prototype.hasOwnProperty.call(deps, '@cloudflare/puppeteer'),
      '@cloudflare/puppeteer must be declared in package.json dependencies (Workers Paid plan binding)',
    );
  });

  test('endpoint matches buildPrintDocument pattern (zero render drift vs backfill script)', () => {
    const ts = readFileSync(ENDPOINT_PATH, 'utf8');
    // The @page CSS pattern must match scripts/backfill-cert-pdfs.ts buildBackfillDocument()
    assert.match(ts, /@page\{size:A4 portrait;margin:15mm 12mm 18mm 12mm\}/, 'must match @page A4 margins from backfill');
    assert.match(ts, /font-family:Georgia,serif/, 'must use same font family as backfill');
  });
});
