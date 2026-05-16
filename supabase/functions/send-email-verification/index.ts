/// <reference types="https://esm.sh/@supabase/functions-js/src/edge-runtime.d.ts" />
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { isSandboxMode } from '../_shared/email-utils.ts'

// P168 R4 — send-email-verification
// Dispatched by request_secondary_email_verification RPC via pg_net.http_post.
// Receives {token} body; looks up email_verification_pending row, sends Resend
// transactional with verification link, marks dispatched_at on success.

const escapeHtml = (s: string | null | undefined) =>
  !s ? '' : String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } })

function buildHtml(targetEmail: string, requestingName: string, link: string, expiresAt: string): string {
  const expDate = new Date(expiresAt)
  const expHuman = expDate.toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', dateStyle: 'short', timeStyle: 'short' })
  return `
    <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <div style="background: #003B5C; padding: 20px; text-align: center;">
        <h1 style="color: white; font-size: 18px; margin: 0;">Núcleo IA &amp; GP</h1>
      </div>
      <div style="padding: 24px; background: #f8f9fa; border: 1px solid #e9ecef;">
        <h2 style="color: #003B5C; font-size: 16px; margin: 0 0 12px 0;">Confirmação de email secundário</h2>
        <p style="color: #495057; font-size: 14px; line-height: 1.6; margin: 0 0 12px 0;">
          <strong>${escapeHtml(requestingName)}</strong> adicionou <strong>${escapeHtml(targetEmail)}</strong>
          como email secundário na plataforma Núcleo IA &amp; GP.
        </p>
        <p style="color: #495057; font-size: 14px; line-height: 1.6; margin: 0 0 16px 0;">
          Se foi você, confirme clicando no botão abaixo. O link expira em <strong>${escapeHtml(expHuman)} (Brasília)</strong>.
        </p>
        <p style="margin: 0 0 16px 0;">
          <a href="${escapeHtml(link)}" style="display: inline-block; background: #003B5C; color: white; padding: 12px 24px; text-decoration: none; border-radius: 8px; font-size: 14px; font-weight: 600;">
            Confirmar email
          </a>
        </p>
        <div style="background: #fff8e1; border-left: 4px solid #ffc107; padding: 10px 14px; margin: 16px 0 0 0; border-radius: 4px;">
          <p style="color: #6b4e00; font-size: 12px; margin: 0; line-height: 1.5;">
            <strong>Não foi você?</strong> Ignore este email. Nenhuma alteração será feita sem o clique no link.
          </p>
        </div>
        <p style="color: #adb5bd; font-size: 11px; margin: 16px 0 0 0; line-height: 1.4; word-break: break-all;">
          Se o botão não funcionar, copie e cole esta URL no seu navegador:<br>${escapeHtml(link)}
        </p>
      </div>
      <div style="padding: 16px; text-align: center; font-size: 11px; color: #868e96;">
        <p>Núcleo de Estudos e Pesquisa em IA &amp; GP</p>
        <p>Email enviado automaticamente. <a href="https://nucleoia.vitormr.dev/profile" style="color: #003B5C;">Acessar perfil</a></p>
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

    // Service-role auth: literal compare → fallback JWT role decode
    const ah = req.headers.get('Authorization') ?? ''
    const tk = ah.replace(/^Bearer\s+/i, '').trim()
    if (!tk) return json({ error: 'No token' }, 401)

    let isServiceRole = tk === srk
    if (!isServiceRole) {
      try {
        const parts = tk.split('.')
        if (parts.length === 3) {
          const payloadJson = atob(parts[1].replace(/-/g, '+').replace(/_/g, '/'))
          const payload = JSON.parse(payloadJson)
          if (payload.role === 'service_role') isServiceRole = true
        }
      } catch { /* not JWT */ }
    }
    if (!isServiceRole) return json({ error: 'Forbidden: service_role required' }, 403)

    const body = await req.json().catch(() => ({}))
    const token = (body?.token ?? '').toString()
    if (!token || token.length < 16) return json({ error: 'Missing or short token' }, 400)

    const sb = createClient(url, srk, { auth: { autoRefreshToken: false, persistSession: false } })

    // Pull pending row
    const { data: pending, error: pErr } = await sb
      .from('email_verification_pending')
      .select('id, target_email, requesting_member_id, expires_at, consumed_at, dispatched_at')
      .eq('token', token)
      .maybeSingle()

    if (pErr) return json({ error: 'Lookup failed', detail: pErr.message }, 500)
    if (!pending) return json({ error: 'Token not found' }, 404)
    if (pending.consumed_at) return json({ error: 'Token already consumed', skipped: true }, 200)
    if (new Date(pending.expires_at).getTime() < Date.now()) {
      return json({ error: 'Token expired', skipped: true }, 200)
    }
    if (pending.dispatched_at) {
      // Idempotency — token-based pg_net retries don't re-dispatch
      return json({ ok: true, already_dispatched: true }, 200)
    }

    // Pull requesting member name for salutation
    const { data: member } = await sb
      .from('members')
      .select('name')
      .eq('id', pending.requesting_member_id)
      .maybeSingle()
    const requestingName = member?.name ?? 'Um membro da plataforma'

    const link = `https://nucleoia.vitormr.dev/profile/verify-secondary?token=${encodeURIComponent(token)}`

    const sandbox = isSandboxMode(from)
    if (sandbox) console.log('[send-email-verification] sandbox mode — restricted recipients')

    // Resend send (Idempotency-Key keyed on pending row id)
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${rkey}`,
        'Content-Type': 'application/json',
        'Idempotency-Key': `email-verification/${pending.id}`,
      },
      body: JSON.stringify({
        from: `Nucleo IA e GP <${from}>`,
        to: [pending.target_email],
        subject: 'Confirme seu email secundario — Nucleo IA & GP',
        html: buildHtml(pending.target_email, requestingName, link, pending.expires_at),
      }),
    })

    if (!res.ok) {
      const errText = await res.text().catch(() => '(no body)')
      return json({ error: 'Resend dispatch failed', status: res.status, detail: errText }, 502)
    }

    // Mark dispatched
    const { error: updErr } = await sb
      .from('email_verification_pending')
      .update({ dispatched_at: new Date().toISOString() })
      .eq('id', pending.id)
    if (updErr) console.warn('[send-email-verification] failed to mark dispatched_at:', updErr.message)

    return json({ ok: true, dispatched_to: pending.target_email })
  } catch (err) {
    return json({ error: 'Unhandled', detail: String(err) }, 500)
  }
})
