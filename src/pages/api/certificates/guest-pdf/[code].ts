// Download of an EVENT GUEST certificate PDF by its public verification code.
//
// Why: event_guest_certificates (#1098) are issued to people with no platform login, and the
// PDF lives in the PRIVATE `certificates` bucket. /verify/<code> proved the certificate but gave
// the guest no way to get the file, so nothing could deliver it. This route closes that gap:
// the e-mail carries a permanent /verify link, and the page links here.
//
// Contract:
// - Only guest codes (CERT-EVT-YYYY-XXXXXX). Member certificates keep their authenticated path.
// - Oracle-free like verify_certificate (#991): not found, not issued, no PDF yet, a malformed
//   code and a throttled caller all get the SAME 404, so the route cannot be used to learn more
//   than /verify already says.
// - The redirect target is a signed URL that expires in SIGNED_URL_TTL_S; the e-mail never
//   carries a storage URL, so nothing in a mailbox goes stale.
// - Per-IP throttle (KV, fail-open like the other anon routes, #1050). The authority is the
//   status check below, not the throttle.
// - Read-only. The service-role client only SELECTs one row and signs one object path.

import type { APIRoute } from 'astro';
import { env as cfEnv } from 'cloudflare:workers';
import { createClient } from '@supabase/supabase-js';
import { checkIpRateLimit, clientIpFrom } from '../../../../lib/ip-rate-limit';

export const prerender = false;

const BUCKET = 'certificates';
const GUEST_CODE_RE = /^CERT-EVT-\d{4}-[A-F0-9]{6}$/;
const SIGNED_URL_TTL_S = 120;
const RATE_LIMIT_PER_MIN = 10;

const NO_STORE = {
  'Cache-Control': 'no-store',
  'Referrer-Policy': 'no-referrer',
  'X-Robots-Tag': 'noindex',
};

function notFound(): Response {
  return new Response('Not found', {
    status: 404,
    headers: { 'Content-Type': 'text/plain; charset=utf-8', ...NO_STORE },
  });
}

export const GET: APIRoute = async ({ params, request }) => {
  const code = String(params.code || '').trim().toUpperCase();
  if (!GUEST_CODE_RE.test(code)) return notFound();

  const rl = await checkIpRateLimit((cfEnv as any)?.SESSION, clientIpFrom(request), 'guest-cert-pdf', RATE_LIMIT_PER_MIN);
  if (!rl.allowed) return notFound();

  const supabaseUrl = (cfEnv as any)?.SUPABASE_URL || import.meta.env.PUBLIC_SUPABASE_URL;
  const serviceRoleKey = (cfEnv as any)?.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response('Unavailable', { status: 503, headers: { 'Content-Type': 'text/plain; charset=utf-8', ...NO_STORE } });
  }
  const sb = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

  const { data: row, error } = await sb
    .from('event_guest_certificates')
    .select('status, pdf_url')
    .eq('verification_code', code)
    .maybeSingle();
  if (error) {
    return new Response('Unavailable', { status: 503, headers: { 'Content-Type': 'text/plain; charset=utf-8', ...NO_STORE } });
  }
  if (!row || row.status !== 'issued' || !row.pdf_url || !String(row.pdf_url).startsWith('guests/')) {
    return notFound();
  }

  const { data: signed, error: signErr } = await sb.storage
    .from(BUCKET)
    .createSignedUrl(row.pdf_url, SIGNED_URL_TTL_S, { download: `${code}.pdf` });
  if (signErr || !signed?.signedUrl) {
    return new Response('Unavailable', { status: 503, headers: { 'Content-Type': 'text/plain; charset=utf-8', ...NO_STORE } });
  }

  return new Response(null, { status: 302, headers: { Location: signed.signedUrl, ...NO_STORE } });
};
