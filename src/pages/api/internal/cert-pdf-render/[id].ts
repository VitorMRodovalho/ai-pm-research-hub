// p225 #281 — Forward auto-gen of certificate PDFs via CF Browser Rendering
//
// Internal endpoint invoked by DB trigger trg_certificate_pdf_autogen via pg_net.
// Reuses the same buildCertificateHTML + hydrateCertData pipeline as the p221
// backfill script (scripts/backfill-cert-pdfs.ts) → zero visual drift between
// the stored PDF and the member-print PDF.
//
// Auth: Bearer shared secret CERT_PDF_INTERNAL_SECRET (wrangler secret).
// Must match the value in DB GUC app.cert_pdf_internal_secret. Missing/empty
// secret = trigger silently skips upstream; this endpoint rejects 401 if reached.
//
// CSRF: /api/internal/ is on the CSRF bypass allowlist (src/middleware.ts).
//
// Idempotency: cert is fetched first; if pdf_url IS NOT NULL, returns 200 with
// skip=true. Storage upload uses upsert=true (re-renders overwrite, same path).
//
// Best-effort: the DB trigger does NOT await this endpoint. Failures here only
// leave cert.pdf_url IS NULL — recoverable via scripts/backfill-cert-pdfs.ts.
//
// Cross-ref: ADR-0098, migration 20260805000005, src/lib/certificates/pdf.ts.

import type { APIRoute } from 'astro';
import { env as cfEnv } from 'cloudflare:workers';
import { createClient } from '@supabase/supabase-js';
import puppeteer from '@cloudflare/puppeteer';
import {
  buildCertificateHTML,
  hydrateCertData,
  type CertificateData,
} from '../../../../lib/certificates/pdf';

export const prerender = false;

const BUCKET = 'certificates';

interface CertRow {
  id: string;
  member_id: string;
  verification_code: string | null;
  type: string;
  pdf_url: string | null;
  issued_by: string | null;
  language: string | null;
  function_role: string | null;
  title: string | null;
  description: string | null;
  period_start: string | null;
  period_end: string | null;
  content_snapshot: Record<string, any> | null;
}

function buildPrintDocument(title: string, innerHtml: string, lang: string): string {
  return `<!DOCTYPE html><html lang="${lang}"><head>
    <meta charset="UTF-8">
    <title>${title.replace(/</g, '&lt;')}</title>
    <style>
      @page{size:A4 portrait;margin:15mm 12mm 18mm 12mm}
      html,body{margin:0 !important;padding:0 !important;background:#fff !important;-webkit-print-color-adjust:exact;print-color-adjust:exact}
      .cert-page{box-shadow:none !important;margin:0 !important;width:auto !important;min-height:auto !important;padding:0 !important;max-width:none !important}
      body{font-family:Georgia,serif}
    </style>
  </head><body>${innerHtml}</body></html>`;
}

async function buildCertData(cert: CertRow, sb: any): Promise<CertificateData> {
  // Mirrors scripts/backfill-cert-pdfs.ts buildCertData; intentionally kept in
  // sync (drift surfaces via tests/contracts/certificate-pdf-autogen.test.mjs).
  if (cert.type === 'volunteer_agreement') {
    const snap = cert.content_snapshot ?? {};
    const certData: CertificateData = {
      member_name: snap.member_name || '',
      type: 'volunteer_agreement',
      verification_code: cert.verification_code || undefined,
      issued_by: cert.issued_by || undefined,
      function_role: cert.function_role || snap.member_role || undefined,
      period_start: cert.period_start || snap.period_start || undefined,
      period_end: cert.period_end || snap.period_end || undefined,
      language: cert.language || snap.language || 'pt-BR',
    };
    await hydrateCertData(certData, sb);
    if (!certData.member_name) {
      const { data: m } = await sb
        .from('members')
        .select('name')
        .eq('id', cert.member_id)
        .maybeSingle();
      certData.member_name = m?.name ?? '(nome indisponível)';
    }
    return certData;
  }

  const { data: m } = await sb
    .from('members')
    .select('name')
    .eq('id', cert.member_id)
    .maybeSingle();
  const certData: CertificateData = {
    member_name: m?.name ?? '(nome indisponível)',
    type: cert.type,
    title: cert.title || undefined,
    verification_code: cert.verification_code || undefined,
    issued_by: cert.issued_by || undefined,
    function_role: cert.function_role || undefined,
    description: cert.description || undefined,
    period_start: cert.period_start || undefined,
    period_end: cert.period_end || undefined,
    language: cert.language || 'pt-BR',
  };
  await hydrateCertData(certData, sb);
  return certData;
}

export const POST: APIRoute = async ({ params, request }) => {
  // 1. Auth: Bearer shared secret
  const expectedSecret = (cfEnv as any)?.CERT_PDF_INTERNAL_SECRET as string | undefined;
  if (!expectedSecret) {
    return new Response(
      JSON.stringify({ error: 'server_misconfig', detail: 'CERT_PDF_INTERNAL_SECRET not set' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const auth = request.headers.get('Authorization') ?? '';
  if (auth !== `Bearer ${expectedSecret}`) {
    return new Response(
      JSON.stringify({ error: 'unauthorized' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const certId = params.id;
  if (!certId || typeof certId !== 'string') {
    return new Response(
      JSON.stringify({ error: 'cert_id_required' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // 2. Service-role Supabase client (bypass RLS for cert + members read + storage upload)
  // Pattern matches src/pages/api/calendar-webhook.ts + src/pages/api/admin/import-pmi-vep-json.ts:
  // SUPABASE_URL falls back to import.meta.env.PUBLIC_SUPABASE_URL (build-time from .env);
  // SUPABASE_SERVICE_ROLE_KEY is runtime only (wrangler secret).
  const supabaseUrl = (cfEnv as any)?.SUPABASE_URL || import.meta.env.PUBLIC_SUPABASE_URL;
  const serviceRoleKey = (cfEnv as any)?.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(
      JSON.stringify({ error: 'server_misconfig', detail: 'SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const sb = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // 3. Fetch cert + idempotency guard
  const { data: cert, error: certErr } = await sb
    .from('certificates')
    .select('id, member_id, verification_code, type, pdf_url, issued_by, language, function_role, title, description, period_start, period_end, content_snapshot')
    .eq('id', certId)
    .maybeSingle();

  if (certErr) {
    return new Response(
      JSON.stringify({ error: 'cert_lookup_failed', detail: certErr.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }
  if (!cert) {
    return new Response(
      JSON.stringify({ error: 'cert_not_found', cert_id: certId }),
      { status: 404, headers: { 'Content-Type': 'application/json' } },
    );
  }
  if (cert.pdf_url) {
    return new Response(
      JSON.stringify({ ok: true, skip: 'pdf_already_set', cert_id: cert.id, pdf_url: cert.pdf_url }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }
  if (!cert.verification_code) {
    return new Response(
      JSON.stringify({ error: 'verification_code_missing', cert_id: cert.id }),
      { status: 422, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // 4. Build certData + HTML (mirrors backfill script + browser-print pipeline)
  let certData: CertificateData;
  try {
    certData = await buildCertData(cert as CertRow, sb);
  } catch (e: any) {
    return new Response(
      JSON.stringify({ error: 'hydrate_failed', detail: e?.message ?? String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const innerHtml = buildCertificateHTML(certData);
  const title = `${cert.verification_code} — ${certData.member_name}`;
  const fullDoc = buildPrintDocument(title, innerHtml, certData.language ?? 'pt-BR');

  // 5. Render PDF via CF Browser Rendering binding
  const browserBinding = (cfEnv as any)?.BROWSER;
  if (!browserBinding) {
    return new Response(
      JSON.stringify({ error: 'server_misconfig', detail: 'BROWSER binding not available' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  let pdfBytes: Uint8Array;
  let browser: any = null;
  try {
    browser = await puppeteer.launch(browserBinding);
    const page = await browser.newPage();
    await page.setContent(fullDoc, { waitUntil: 'networkidle0', timeout: 30000 });
    pdfBytes = await page.pdf({
      format: 'A4',
      margin: { top: '15mm', right: '12mm', bottom: '18mm', left: '12mm' },
      printBackground: true,
      preferCSSPageSize: false,
    });
  } catch (e: any) {
    return new Response(
      JSON.stringify({ error: 'render_failed', detail: e?.message ?? String(e), cert_id: cert.id }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  } finally {
    if (browser) {
      try { await browser.close(); } catch { /* ignore */ }
    }
  }

  // 6. Upload to storage
  const storagePath = `${cert.member_id}/${cert.verification_code}.pdf`;
  const { error: upErr } = await sb.storage
    .from(BUCKET)
    .upload(storagePath, pdfBytes, {
      contentType: 'application/pdf',
      upsert: true,
      cacheControl: '31536000',
    });
  if (upErr) {
    return new Response(
      JSON.stringify({ error: 'upload_failed', detail: upErr.message, cert_id: cert.id }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // 7. UPDATE pdf_url — only if still NULL (race-safe; concurrent renders would
  // both succeed at upload step due to upsert, but only first UPDATE flips).
  const { error: updErr, data: updData } = await sb
    .from('certificates')
    .update({ pdf_url: storagePath })
    .eq('id', cert.id)
    .is('pdf_url', null)
    .select('id, pdf_url');
  if (updErr) {
    return new Response(
      JSON.stringify({ error: 'pdf_url_update_failed', detail: updErr.message, cert_id: cert.id }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const wasRaceWinner = Array.isArray(updData) && updData.length > 0;

  return new Response(
    JSON.stringify({
      ok: true,
      cert_id: cert.id,
      verification_code: cert.verification_code,
      pdf_url: storagePath,
      bytes: pdfBytes.byteLength,
      race_winner: wasRaceWinner,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
};

// GET: probe/health endpoint (returns 405 for security; only POST allowed).
export const GET: APIRoute = () => {
  return new Response(
    JSON.stringify({ error: 'method_not_allowed', allowed: ['POST'] }),
    { status: 405, headers: { 'Content-Type': 'application/json', Allow: 'POST' } },
  );
};
