/**
 * p221 #267 alpha — Backfill server-side PDF for existing certificates.
 *
 * Renders the same HTML template the browser uses (src/lib/certificates/pdf.ts)
 * via local headless Chromium (playwright) and uploads to the `certificates`
 * Supabase Storage bucket, then UPDATEs certificates.pdf_url with the storage path.
 *
 * Storage path convention: <member_id>/<verification_code>.pdf
 *
 * This is a ONE-SHOT backfill script. Forward auto-gen for new certs is a
 * separate ticket (Option C — pending architecture decision). After backfill
 * completes, this script remains in-tree for re-runs / future audits but is
 * not invoked by app code.
 *
 * Usage:
 *   # All certs WHERE pdf_url IS NULL
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
 *     node scripts/backfill-cert-pdfs.ts
 *
 *   # Dry-run (no upload, no DB write — only render + local file out)
 *   node scripts/backfill-cert-pdfs.ts --dry-run --out-dir /tmp/cert-pdfs-debug
 *
 *   # Single cert sanity check
 *   node scripts/backfill-cert-pdfs.ts --cert CERT-2026-10752E --out-dir /tmp/cert-pdfs-debug
 *
 *   # Limit count
 *   node scripts/backfill-cert-pdfs.ts --limit 3
 *
 *   # Force re-upload even if pdf_url already set
 *   node scripts/backfill-cert-pdfs.ts --force
 */
import { createClient } from '@supabase/supabase-js';
import { chromium, type Browser } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  buildCertificateHTML,
  hydrateCertData,
  type CertificateData,
} from '../src/lib/certificates/pdf.ts';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY env vars.');
  process.exit(1);
}

const args = process.argv.slice(2);
const arg = (name: string): string | undefined => {
  const idx = args.findIndex((a) => a === name || a.startsWith(name + '='));
  if (idx < 0) return undefined;
  const v = args[idx];
  if (v.includes('=')) return v.split('=').slice(1).join('=');
  return args[idx + 1];
};
const flag = (name: string): boolean => args.includes(name);

const LIMIT = arg('--limit') ? parseInt(arg('--limit')!, 10) : undefined;
const DRY_RUN = flag('--dry-run');
const FORCE = flag('--force');
const CERT_FILTER = arg('--cert');
const OUT_DIR = arg('--out-dir');

if (OUT_DIR) mkdirSync(OUT_DIR, { recursive: true });

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const BUCKET = 'certificates';

/**
 * Wrap inner cert HTML in a full print-ready document.
 * Same @page CSS as src/lib/certificates/pdf.ts buildPrintDocument(), minus the
 * screen-only "Dica para gerar PDF limpo" banner (we're not invoking a print dialog).
 */
function buildBackfillDocument(title: string, innerHtml: string): string {
  return `<!DOCTYPE html><html lang="pt-BR"><head>
    <meta charset="UTF-8">
    <title>${title}</title>
    <style>
      @page{size:A4 portrait;margin:15mm 12mm 18mm 12mm}
      html,body{margin:0 !important;padding:0 !important;background:#fff !important;-webkit-print-color-adjust:exact;print-color-adjust:exact}
      .cert-page{box-shadow:none !important;margin:0 !important;width:auto !important;min-height:auto !important;padding:0 !important;max-width:none !important}
      body{font-family:Georgia,serif}
    </style>
  </head><body>${innerHtml}</body></html>`;
}

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

async function fetchCerts(): Promise<CertRow[]> {
  let q = sb
    .from('certificates')
    .select('id, member_id, verification_code, type, pdf_url, issued_by, language, function_role, title, description, period_start, period_end, content_snapshot')
    .order('issued_at', { ascending: true });

  if (CERT_FILTER) {
    q = q.eq('verification_code', CERT_FILTER);
  } else if (!FORCE) {
    q = q.is('pdf_url', null);
  }

  const { data, error } = await q;
  if (error) throw error;
  let rows = (data ?? []) as CertRow[];
  if (LIMIT) rows = rows.slice(0, LIMIT);
  return rows;
}

async function buildCertData(cert: CertRow): Promise<CertificateData> {
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

async function renderPdf(browser: Browser, html: string, title: string): Promise<Buffer> {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  await page.setContent(html, { waitUntil: 'networkidle', timeout: 30000 });
  const pdfBuffer = await page.pdf({
    format: 'A4',
    margin: { top: '15mm', right: '12mm', bottom: '18mm', left: '12mm' },
    printBackground: true,
    preferCSSPageSize: false,
  });
  await ctx.close();
  return Buffer.from(pdfBuffer);
}

async function uploadPdf(storagePath: string, pdfBuffer: Buffer): Promise<void> {
  const { error } = await sb.storage
    .from(BUCKET)
    .upload(storagePath, pdfBuffer, {
      contentType: 'application/pdf',
      upsert: true,
      cacheControl: '31536000',
    });
  if (error) throw new Error(`storage upload failed: ${error.message}`);
}

async function main() {
  console.log('[backfill-cert-pdfs] start');
  console.log(`  dry_run=${DRY_RUN}  force=${FORCE}  limit=${LIMIT ?? 'all'}  cert=${CERT_FILTER ?? '<all-null-pdf_url>'}  out_dir=${OUT_DIR ?? '<none>'}`);

  const certs = await fetchCerts();
  console.log(`[backfill-cert-pdfs] fetched ${certs.length} cert(s) to process`);

  if (!certs.length) {
    console.log('[backfill-cert-pdfs] nothing to do');
    return;
  }

  const browser = await chromium.launch({ headless: true });
  let okCount = 0;
  let skipCount = 0;
  const errors: { cert_id: string; verification_code: string | null; error: string }[] = [];

  try {
    for (const cert of certs) {
      const vc = cert.verification_code || `id-${cert.id.slice(0, 8)}`;
      if (!FORCE && cert.pdf_url && !CERT_FILTER) {
        console.log(`  [skip] ${vc} — pdf_url already set`);
        skipCount += 1;
        continue;
      }
      try {
        const certData = await buildCertData(cert);
        const innerHtml = buildCertificateHTML(certData);
        const title = `${vc} — ${certData.member_name}`;
        const fullDoc = buildBackfillDocument(title, innerHtml);
        const pdfBuffer = await renderPdf(browser, fullDoc, title);

        const storagePath = `${cert.member_id}/${vc}.pdf`;

        if (OUT_DIR) {
          const localPath = resolve(OUT_DIR, `${vc}.pdf`);
          writeFileSync(localPath, pdfBuffer);
          console.log(`  [debug] wrote ${localPath} (${pdfBuffer.length} bytes)`);
        }

        if (DRY_RUN) {
          console.log(`  [dry] ${vc} — would upload ${pdfBuffer.length} bytes to ${storagePath}`);
        } else {
          await uploadPdf(storagePath, pdfBuffer);
          const { error: updErr } = await sb
            .from('certificates')
            .update({ pdf_url: storagePath })
            .eq('id', cert.id);
          if (updErr) throw new Error(`UPDATE pdf_url failed: ${updErr.message}`);
          console.log(`  [ok]   ${vc} — uploaded ${pdfBuffer.length} bytes → ${storagePath}`);
        }
        okCount += 1;
      } catch (e: any) {
        const msg = e?.message || String(e);
        console.error(`  [err]  ${vc} — ${msg}`);
        errors.push({ cert_id: cert.id, verification_code: cert.verification_code, error: msg });
      }
    }
  } finally {
    await browser.close();
  }

  console.log('[backfill-cert-pdfs] done');
  console.log(`  processed=${certs.length}  ok=${okCount}  skip=${skipCount}  err=${errors.length}`);
  if (errors.length) {
    console.log('[backfill-cert-pdfs] errors:');
    for (const e of errors) console.log(`  - ${e.verification_code ?? e.cert_id}: ${e.error}`);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error('[backfill-cert-pdfs] fatal:', e);
  process.exit(1);
});
