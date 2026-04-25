/// <reference types="https://esm.sh/@supabase/functions-js/src/edge-runtime.d.ts" />
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ADR-0022 W1 (2026-04-26): filter migrated from hardcoded CRITICAL_TYPES list to
// notifications.delivery_mode. The catalog at docs/adr/ADR-0022-notification-types-catalog.json
// is the single source of truth for type → delivery_mode mapping; producers set
// delivery_mode explicitly via public._delivery_mode_for(p_type) at INSERT time.
// Catalog says `transactional_immediate` ⇒ this EF; `digest_weekly` ⇒ send-weekly-member-digest;
// `suppress` ⇒ never emailed (in-app only).
const TRANSACTIONAL_DELIVERY_MODE = 'transactional_immediate'

const TYPE_SUBJECTS: Record<string, string> = {
  governance_cr_approved: 'CR aprovado por quorum',
  governance_cr_vote: 'Novo voto em Change Request',
  governance_cr_new: 'Novo Change Request',
  volunteer_agreement_signed: 'Termo de Voluntariado assinado',
  certificate_ready: 'Certificado disponivel',
  attendance_detractor: 'Alerta de presenca',
  webinar_status_confirmed: 'Webinar confirmado',
  webinar_status_completed: 'Webinar realizado',
  webinar_status_cancelled: 'Webinar cancelado',
  ip_ratification_gate_pending: 'Acao necessaria — ratificacao de documento',
  ip_ratification_gate_advanced: 'Gate satisfeito — cadeia avancou',
  ip_ratification_chain_approved: 'Cadeia de aprovacao concluida',
  ip_ratification_awaiting_members: 'Aguardando sua ratificacao',
  weekly_card_digest_member: 'Seu resumo semanal de atividades',
}

// Digest types render body as multi-line text (preserve \n as <br>) without CTA deadline block.
const DIGEST_TYPES = new Set([
  'weekly_card_digest_member',
])

// Escape HTML-significant characters. Applied to title/body on all notification types
// to prevent XSS via user-influenced content (doc names, submitter names, card titles).
function escapeHtml(s: string | null | undefined): string {
  if (!s) return ''
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

// Convert plain-text body (with \n linebreaks) to HTML preserving paragraph/line structure.
// Used for digest-style notifications where body is markdown-like output from the RPC.
function formatDigestBody(body: string): string {
  if (!body) return ''
  const escaped = escapeHtml(body)
  // \n\n → paragraph break, \n → line break
  return escaped.split(/\n\n+/).map(p => p.replace(/\n/g, '<br>')).map(p => `<p style="color: #495057; font-size: 14px; line-height: 1.6; margin: 0 0 12px 0;">${p}</p>`).join('')
}

// Governance types get a gentle deadline nudge inline (15 dias suggested)
const GOVERNANCE_TYPES = new Set([
  'ip_ratification_gate_pending',
  'ip_ratification_awaiting_members',
])

function buildHtml(notification: any): string {
  const isGovernance = GOVERNANCE_TYPES.has(notification.type)
  const isDigest = DIGEST_TYPES.has(notification.type)
  const ctaLabel = isDigest ? 'Abrir meu workspace' : isGovernance ? 'Revisar e assinar' : 'Ver na plataforma'
  const deadlineBlock = isGovernance
    ? `<div style="background: #fff8e1; border-left: 4px solid #ffc107; padding: 10px 14px; margin: 0 0 16px 0; border-radius: 4px;">
         <p style="color: #6b4e00; font-size: 12px; margin: 0; line-height: 1.5;">
           <strong>Prazo sugerido:</strong> 15 dias corridos. Este e um processo de governanca com peso legal; sua assinatura confirma ciencia ou aprovacao conforme o gate.
         </p>
       </div>`
    : ''
  const bodyHtml = isDigest
    ? formatDigestBody(notification.body || '')
    : `<p style="color: #495057; font-size: 14px; line-height: 1.6; margin: 0 0 16px 0;">${escapeHtml(notification.body)}</p>`
  const optOutBlock = isDigest
    ? `<p style="color: #adb5bd; font-size: 11px; margin: 16px 0 0 0; line-height: 1.4;">
         Deseja parar de receber este resumo? Ajuste em <a href="https://nucleoia.vitormr.dev/profile" style="color: #6c757d;">preferencias de notificacao</a>.
       </p>`
    : ''

  return `
    <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <div style="background: #003B5C; padding: 20px; text-align: center;">
        <h1 style="color: white; font-size: 18px; margin: 0;">Nucleo IA &amp; GP</h1>
      </div>
      <div style="padding: 24px; background: #f8f9fa; border: 1px solid #e9ecef;">
        <h2 style="color: #003B5C; font-size: 16px; margin: 0 0 12px 0;">${escapeHtml(notification.title)}</h2>
        ${bodyHtml}
        ${deadlineBlock}
        ${notification.link ? `<a href="https://nucleoia.vitormr.dev${notification.link}" style="display: inline-block; background: #003B5C; color: white; padding: 10px 20px; text-decoration: none; border-radius: 8px; font-size: 14px; font-weight: 600;">${ctaLabel}</a>` : ''}
        ${optOutBlock}
      </div>
      <div style="padding: 16px; text-align: center; font-size: 11px; color: #868e96;">
        <p>Nucleo de Estudos e Pesquisa em IA &amp; GP</p>
        <p>Enviado automaticamente pela plataforma. <a href="https://nucleoia.vitormr.dev/profile" style="color: #003B5C;">Gerir preferencias</a></p>
      </div>
    </div>`
}

Deno.serve(async (req) => {
  try {
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const srk = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const rkey = Deno.env.get('RESEND_API_KEY') ?? ''
    const from = Deno.env.get('RESEND_FROM_ADDRESS') || 'nucleoia@pmigo.org.br'

    if (!rkey) return new Response(JSON.stringify({ error: 'No RESEND_API_KEY' }), { status: 500 })

    const sb = createClient(url, srk, { auth: { autoRefreshToken: false, persistSession: false } })

    // ADR-0022 W1: filter by delivery_mode = 'transactional_immediate' instead of
    // type IN CRITICAL_TYPES. Catalog drives routing; EF stays type-agnostic.
    // Fix p34 (ai-engineer audit): no time window — email_sent_at IS NULL is guard.
    // Limit 50 accommodates CR-050 pico (~75 notifs in lock onda).
    const { data: notifications, error: fetchErr } = await sb
      .from('notifications')
      .select('id, recipient_id, type, title, body, link, created_at')
      .eq('delivery_mode', TRANSACTIONAL_DELIVERY_MODE)
      .is('email_sent_at', null)
      .order('created_at', { ascending: true })
      .limit(50)

    if (fetchErr) throw fetchErr
    if (!notifications?.length) {
      return new Response(JSON.stringify({ sent: 0, message: 'No pending notifications' }))
    }

    let sent = 0
    const errors: string[] = []

    for (const notif of notifications) {
      // Get recipient email + preferences
      const { data: member } = await sb
        .from('members')
        .select('email, name')
        .eq('id', notif.recipient_id)
        .single()

      if (!member?.email) continue

      // Check preferences (opt-out)
      const { data: prefs } = await sb
        .from('notification_preferences')
        .select('email_digest, muted_types')
        .eq('member_id', notif.recipient_id)
        .single()

      if (prefs?.muted_types?.includes(notif.type)) continue

      // Send email — IP ratification types carry specific title (doc + version + action + submitter)
      // so we use notif.title directly. Other types fall back to TYPE_SUBJECTS generic.
      const isIpRatif = notif.type?.startsWith('ip_ratification_')
      const subject = isIpRatif
        ? `${notif.title} — Nucleo IA & GP`
        : `${TYPE_SUBJECTS[notif.type] || notif.title} — Nucleo IA & GP`
      try {
        // Resend: Idempotency-Key prevents duplicate sends if this EF is retried after a successful API call.
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${rkey}`,
            'Content-Type': 'application/json',
            'Idempotency-Key': `critical-notification/${notif.id}`,
          },
          body: JSON.stringify({
            from: `Nucleo IA e GP <${from}>`,
            to: [member.email],
            subject,
            html: buildHtml(notif),
          }),
        })

        if (res.ok) {
          sent++
          // Mark as sent
          await sb.from('notifications').update({ email_sent_at: new Date().toISOString() }).eq('id', notif.id)
        } else {
          const err = await res.json()
          errors.push(`${member.email}: ${err.message || res.status}`)
        }
      } catch (e) {
        errors.push(`${member.email}: ${String(e)}`)
      }
    }

    return new Response(JSON.stringify({ sent, total: notifications.length, errors }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 })
  }
})
