import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/**
 * Edge Function: send-notification-digest
 * Cron: weekly (Monday 8h BRT = 11:00 UTC)
 * For each member with email_digest=true in notification_preferences,
 * fetches unread notifications from the past 7 days and sends a summary email via Resend.
 */
Deno.serve(async (req) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
  const json = (d: Record<string, unknown>, s = 200) =>
    new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const srk = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const rkey = Deno.env.get('RESEND_API_KEY') ?? ''
    const fromAddr = Deno.env.get('RESEND_FROM_ADDRESS') || 'nucleo@resend.dev'

    if (!rkey) return json({ error: 'No RESEND key' }, 500)

    const sb = createClient(url, srk)

    // Get members who want email digest
    const { data: prefs, error: prefsErr } = await sb
      .from('notification_preferences')
      .select('member_id, digest_frequency')
      .eq('email_digest', true)
      .neq('digest_frequency', 'never')

    if (prefsErr) return json({ error: 'DB error', detail: prefsErr.message }, 500)
    if (!prefs || prefs.length === 0) return json({ sent: 0, message: 'No members opted in' })

    const memberIds = prefs.map((p: any) => p.member_id)

    // Get member emails
    const { data: members } = await sb
      .from('members')
      .select('id, name, email')
      .in('id', memberIds)
      .not('email', 'is', null)

    if (!members || members.length === 0) return json({ sent: 0, message: 'No valid emails' })

    const memberMap = new Map(members.map((m: any) => [m.id, m]))

    // Fetch unread notifications per member from last 7 days
    const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()
    let sent = 0
    const errors: string[] = []

    for (const pref of prefs) {
      const member = memberMap.get(pref.member_id)
      if (!member || !member.email) continue

      const { data: notifs } = await sb
        .from('notifications')
        .select('type, title, body, link, created_at')
        .eq('recipient_id', pref.member_id)
        .eq('is_read', false)
        .gte('created_at', weekAgo)
        .order('created_at', { ascending: false })
        .limit(50)

      if (!notifs || notifs.length === 0) continue

      // Group by type
      const grouped: Record<string, any[]> = {}
      for (const n of notifs) {
        const t = n.type || 'system'
        if (!grouped[t]) grouped[t] = []
        grouped[t].push(n)
      }

      const typeLabels: Record<string, string> = {
        assignment: 'Atribuições',
        curation_status: 'Curadoria',
        publication: 'Publicações',
        system: 'Sistema',
        mention: 'Menções',
      }

      const sectionsHtml = Object.entries(grouped).map(([type, items]) => {
        const label = typeLabels[type] || type
        const itemsHtml = items.map((n: any) => {
          const date = new Date(n.created_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' })
          return `<tr>
            <td style="padding:6px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;color:#334155">${n.title}</td>
            <td style="padding:6px 12px;border-bottom:1px solid #f1f5f9;font-size:12px;color:#94a3b8;white-space:nowrap">${date}</td>
          </tr>`
        }).join('')
        return `
          <h3 style="font-size:14px;color:#0f172a;margin:16px 0 8px;padding-bottom:4px;border-bottom:2px solid #14b8a6">${label} (${items.length})</h3>
          <table style="width:100%;border-collapse:collapse">${itemsHtml}</table>
        `
      }).join('')

      const firstName = (member.name || 'Membro').split(' ')[0]
      const html = `
        <div style="max-width:560px;margin:0 auto;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">
          <div style="background:#0f172a;padding:20px 24px;border-radius:12px 12px 0 0">
            <h1 style="color:#fff;font-size:18px;margin:0">Núcleo IA & GP</h1>
            <p style="color:#94a3b8;font-size:13px;margin:4px 0 0">Resumo semanal de notificações</p>
          </div>
          <div style="background:#fff;padding:24px;border:1px solid #e2e8f0;border-top:none;border-radius:0 0 12px 12px">
            <p style="font-size:14px;color:#334155">Olá <strong>${firstName}</strong>, você tem <strong>${notifs.length}</strong> notificação(ões) não lida(s) esta semana:</p>
            ${sectionsHtml}
            <div style="margin-top:24px;text-align:center">
              <a href="https://nucleoiagp.com/notifications" style="display:inline-block;padding:10px 28px;background:#14b8a6;color:#fff;text-decoration:none;border-radius:8px;font-weight:600;font-size:14px">Ver notificações</a>
            </div>
            <p style="font-size:11px;color:#94a3b8;margin-top:20px;text-align:center">
              Para desativar o resumo semanal, acesse seu Perfil → Preferências de Notificação.
            </p>
          </div>
        </div>
      `

      try {
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${rkey}` },
          body: JSON.stringify({
            from: fromAddr,
            to: [member.email],
            subject: `Núcleo IA & GP — Resumo da semana: ${notifs.length} novidade(s)`,
            html,
          }),
        })
        if (res.ok) sent++
        else {
          const body = await res.text()
          errors.push(`${member.email}: ${res.status} ${body}`)
        }
      } catch (e: any) {
        errors.push(`${member.email}: ${e.message}`)
      }

      // Rate limit: 1 email per second
      await new Promise(r => setTimeout(r, 1000))
    }

    return json({ sent, total_eligible: prefs.length, errors: errors.length > 0 ? errors : undefined })
  } catch (e: any) {
    return json({ error: e.message || 'Unknown error' }, 500)
  }
})
