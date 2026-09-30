/// <reference types="https://esm.sh/@supabase/functions-js@2.116.0/src/edge-runtime.d.ts" />
import { COMMS_ORIGIN } from '../_shared/comms-host.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { isServiceRoleToken } from '../_shared/service-auth.ts'
import { isSandboxMode } from '../_shared/email-utils.ts'

// #2529 / ADR-0133 — send-competition-email
// Dispatched by competition.dispatch_email via pg_net.http_post with {registration_id, token, kind}.
// The token is the link credential; the database keeps only its sha256, and
// _competition_email_payload returns content only for a valid, unexpired link OF THAT
// registration, so a service-role caller cannot mail a registration it does not hold a link for.
// kind: 'confirm' (a registration waiting for the owner of the address to confirm it; nothing
// counts until then) or 'link_resent' (the address was already confirmed; a new access link,
// and the earlier ones keep working). The link carries the token in the URL fragment, which
// the browser never sends to the server or in the Referer header.

const escapeHtml = (s: string | null | undefined) =>
  !s ? '' : String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } })

type Payload = {
  to: string; name: string; edition_slug: string; edition_title: string;
  pending: boolean; confirm_by: string | null;
  team_name: string | null; is_leader: boolean | null; leader_email: string | null;
  closes_at: string | null; timezone: string; confirmation_note: string | null;
  rules_url: string | null; privacy_notice_url: string | null;
}

function fmtClose(iso: string | null, tz: string): string {
  if (!iso) return ''
  return new Date(iso).toLocaleString('pt-BR', { timeZone: tz || 'America/Sao_Paulo', dateStyle: 'short', timeStyle: 'short' })
}

function buildHtml(p: Payload, kind: string, link: string): string {
  const pending = kind === 'confirm' && p.pending
  const intro = pending
    ? `Recebemos a sua inscrição. <strong>Ela só vale depois que você confirmar o seu e-mail</strong>, no botão abaixo, até ${escapeHtml(fmtClose(p.confirm_by, p.timezone))} (horário de Brasília). Sem a confirmação, a inscrição é descartada.`
    : 'Recebemos um novo envio com o seu e-mail, que já estava inscrito. Nada foi alterado na sua inscrição. Este é um link de acesso a ela; os links anteriores continuam valendo.'
  const team = p.team_name
    ? `<li>Equipe: <strong>${escapeHtml(p.team_name)}</strong></li>
       <li>${p.is_leader ? 'Você lidera a equipe.' : `Quem lidera: ${escapeHtml(p.leader_email)}`}</li>`
    : ''
  const closes = p.closes_at ? `até <strong>${escapeHtml(fmtClose(p.closes_at, p.timezone))} (horário de Brasília)</strong>` : 'enquanto as inscrições estiverem abertas'
  const links = [
    p.rules_url ? `<a href="${escapeHtml(p.rules_url)}" style="color:#003B5C;">Edital</a>` : '',
    p.privacy_notice_url ? `<a href="${escapeHtml(p.privacy_notice_url)}" style="color:#003B5C;">Aviso de privacidade</a>` : '',
  ].filter(Boolean).join(' · ')
  const note = p.confirmation_note
    ? `<div style="background:#fff8e1;border-left:4px solid #ffc107;padding:10px 14px;margin:16px 0 0 0;border-radius:4px;">
         <p style="color:#6b4e00;font-size:13px;margin:0;line-height:1.5;">${escapeHtml(p.confirmation_note)}</p></div>`
    : ''
  return `
    <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <div style="background: #003B5C; padding: 20px; text-align: center;">
        <h1 style="color: white; font-size: 18px; margin: 0;">${escapeHtml(p.edition_title)}</h1>
      </div>
      <div style="padding: 24px; background: #f8f9fa; border: 1px solid #e9ecef;">
        <p style="color: #495057; font-size: 14px; line-height: 1.6; margin: 0 0 12px 0;">
          Olá, <strong>${escapeHtml(p.name)}</strong>. ${intro}
        </p>
        <ul style="color: #495057; font-size: 14px; line-height: 1.6; margin: 0 0 12px 0; padding-left: 18px;">${team}</ul>
        <p style="color: #495057; font-size: 14px; line-height: 1.6; margin: 0 0 16px 0;">
          ${pending ? 'Depois de confirmar, o mesmo link serve para ver e corrigir a inscrição' : 'Pelo link você vê a inscrição e pode corrigi-la'} ${closes}.
        </p>
        <p style="margin: 0 0 16px 0;">
          <a href="${escapeHtml(link)}" style="display: inline-block; background: #003B5C; color: white; padding: 12px 24px; text-decoration: none; border-radius: 8px; font-size: 14px; font-weight: 600;">
            ${pending ? 'Confirmar a inscrição' : 'Ver ou corrigir a inscrição'}
          </a>
        </p>
        ${note}
        ${links ? `<p style="color:#495057;font-size:13px;margin:16px 0 0 0;">${links}</p>` : ''}
        <p style="color: #adb5bd; font-size: 11px; margin: 16px 0 0 0; line-height: 1.4; word-break: break-all;">
          Este link é pessoal: quem o tiver pode ver, corrigir ou retirar a sua inscrição. Se o botão não funcionar, copie esta URL:<br>${escapeHtml(link)}
        </p>
      </div>
      <div style="padding: 16px; text-align: center; font-size: 11px; color: #868e96;">
        <p>Núcleo de Estudos e Pesquisa em IA &amp; GP · e-mail enviado automaticamente.</p>
        <p>Se você não fez esta inscrição, ignore este e-mail.</p>
      </div>
    </div>`
}

Deno.serve(async (req) => {
  try {
    const url  = Deno.env.get('SUPABASE_URL') ?? ''
    const srk  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const rkey = Deno.env.get('RESEND_API_KEY') ?? ''
    const from = Deno.env.get('RESEND_FROM_ADDRESS') || 'nucleoia@pmigo.org.br'
    if (!rkey) return json({ error: 'No RESEND_API_KEY' }, 500)
    if (!url || !srk) return json({ error: 'Missing supabase env' }, 500)

    const tk = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
    if (!tk) return json({ error: 'No token' }, 401)
    if (!(await isServiceRoleToken(url, tk))) return json({ error: 'Forbidden: service_role required' }, 403)

    const body = await req.json().catch(() => ({}))
    const registrationId = (body?.registration_id ?? '').toString()
    const token = (body?.token ?? '').toString()
    const kind = (body?.kind ?? '').toString()
    if (!/^[0-9a-f-]{36}$/i.test(registrationId)) return json({ error: 'Bad registration_id' }, 400)
    if (kind !== 'confirm' && kind !== 'link_resent') return json({ error: 'Bad kind' }, 400)
    if (!/^[0-9a-f]{64}$/.test(token)) return json({ error: 'Bad token' }, 400)

    const sb = createClient<any, 'public', any>(url, srk, { auth: { autoRefreshToken: false, persistSession: false } })
    const { data, error } = await sb.rpc('_competition_email_payload', { p_registration_id: registrationId, p_token: token })
    if (error) return json({ error: 'Lookup failed' }, 500)
    const p = data as Payload | null
    if (!p || !p.to) return json({ error: 'Not found or token mismatch', skipped: true }, 200)

    const link = `${COMMS_ORIGIN}/competicoes/${encodeURIComponent(p.edition_slug)}/minha-inscricao#t=${encodeURIComponent(token)}`
    if (isSandboxMode(from)) console.log('[send-competition-email] sandbox mode — restricted recipients')

    // Idempotency per link, without sending any part of the token itself to the mail provider.
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token))
    const tokenTag = Array.from(new Uint8Array(digest)).slice(0, 6).map((b) => b.toString(16).padStart(2, '0')).join('')
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${rkey}`,
        'Content-Type': 'application/json',
        'Idempotency-Key': `competition/${registrationId}/${kind}/${tokenTag}`,
      },
      body: JSON.stringify({
        from: `Nucleo IA e GP <${from}>`,
        to: [p.to],
        subject: kind === 'confirm' && p.pending ? `Confirme a sua inscrição: ${p.edition_title}` : `Link da sua inscrição: ${p.edition_title}`,
        html: buildHtml(p, kind, link),
      }),
    })
    if (!res.ok) return json({ error: 'Resend dispatch failed', status: res.status }, 502)

    // Never echo the address or the token back: pg_net keeps responses in net._http_response.
    return json({ ok: true })
  } catch (_err) {
    return json({ error: 'Unhandled' }, 500)
  }
})
