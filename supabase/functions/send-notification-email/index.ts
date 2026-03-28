/// <reference types="https://esm.sh/@supabase/functions-js/src/edge-runtime.d.ts" />
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CRITICAL_TYPES = [
  'governance_cr_approved',
  'governance_cr_vote',
  'governance_cr_new',
  'volunteer_agreement_signed',
  'certificate_ready',
  'attendance_detractor',
  'webinar_status_confirmed',
  'webinar_status_completed',
  'webinar_status_cancelled',
]

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
}

function buildHtml(notification: any): string {
  return `
    <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <div style="background: #003B5C; padding: 20px; text-align: center;">
        <h1 style="color: white; font-size: 18px; margin: 0;">Nucleo IA &amp; GP</h1>
      </div>
      <div style="padding: 24px; background: #f8f9fa; border: 1px solid #e9ecef;">
        <h2 style="color: #003B5C; font-size: 16px; margin: 0 0 12px 0;">${notification.title || ''}</h2>
        <p style="color: #495057; font-size: 14px; line-height: 1.6; margin: 0 0 16px 0;">${notification.body || ''}</p>
        ${notification.link ? `<a href="https://platform.ai-pm-research-hub.workers.dev${notification.link}" style="display: inline-block; background: #003B5C; color: white; padding: 10px 20px; text-decoration: none; border-radius: 8px; font-size: 14px; font-weight: 600;">Ver na plataforma</a>` : ''}
      </div>
      <div style="padding: 16px; text-align: center; font-size: 11px; color: #868e96;">
        <p>Nucleo de Estudos e Pesquisa em IA &amp; GP</p>
        <p>Enviado automaticamente pela plataforma. <a href="https://platform.ai-pm-research-hub.workers.dev/profile" style="color: #003B5C;">Gerir preferencias</a></p>
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

    // Get unprocessed critical notifications (last 10 minutes)
    const { data: notifications, error: fetchErr } = await sb
      .from('notifications')
      .select('id, recipient_id, type, title, body, link, created_at')
      .in('type', CRITICAL_TYPES)
      .gte('created_at', new Date(Date.now() - 10 * 60 * 1000).toISOString())
      .is('email_sent_at', null)
      .order('created_at', { ascending: true })
      .limit(20)

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

      // Send email
      const subject = `${TYPE_SUBJECTS[notif.type] || notif.title} — Nucleo IA & GP`
      try {
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${rkey}`, 'Content-Type': 'application/json' },
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
