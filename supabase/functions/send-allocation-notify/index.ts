import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
  const json = (d: Record<string, unknown>, s = 200) =>
    new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  let raw = ''
  try { raw = await req.text() } catch (_) { raw = '' }

  try {
    if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const srk = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const rkey = Deno.env.get('RESEND_API_KEY') ?? ''

    if (!rkey) return json({ error: 'No RESEND key' }, 500)

    const ah = req.headers.get('Authorization') ?? ''
    const tk = ah.replace(/^Bearer\s+/i, '').trim()
    if (!tk) return json({ error: 'No token' }, 401)

    const uc = createClient(url, anon, { global: { headers: { Authorization: 'Bearer ' + tk } } })
    const ur = await uc.auth.getUser()
    if (ur.error || !ur.data?.user) return json({ error: 'Bad token' }, 401)
    const uid = ur.data.user.id

    const sb = createClient(url, srk)

    const cr = await sb.from('members')
      .select('id, operational_role, is_superadmin, name, phone, linkedin_url')
      .eq('auth_id', uid).single()
    if (!cr.data) return json({ error: 'No member' }, 403)
    const caller = cr.data

    const adm = caller.is_superadmin === true ||
      caller.operational_role === 'manager' ||
      caller.operational_role === 'deputy_manager'
    if (!adm) return json({ error: 'Forbidden: superadmin/manager only' }, 403)

    let p: Record<string, unknown> = {}
    try { p = JSON.parse(raw) } catch (_) { return json({ error: 'Bad JSON' }, 400) }

    const dryRun = p.dry_run === true

    const { data: members, error: mErr } = await sb.from('members')
      .select('id, name, email, tribe_id, selected_tribe_id, fixed_tribe_id')
      .eq('current_cycle_active', true)
      .not('email', 'is', null)
    if (mErr) return json({ error: 'DB error', detail: mErr.message }, 500)

    const allocated = (members || []).filter((m: any) => {
      const tid = m.tribe_id || m.selected_tribe_id || m.fixed_tribe_id
      return tid && m.email && m.email.includes('@')
    })

    if (!allocated.length) return json({ error: 'No allocated members found' }, 400)

    const { data: tribes } = await sb.from('tribes').select('id, name, whatsapp_url')
    const tribeMap: Record<number, any> = {}
    ;(tribes || []).forEach((t: any) => { tribeMap[t.id] = t })

    const { data: initsByTribe } = await sb.from('initiatives')
      .select('id, legacy_tribe_id')
      .not('legacy_tribe_id', 'is', null)
    const initiativeByTribe: Record<number, string> = {}
    ;(initsByTribe || []).forEach((i: any) => { if (i.legacy_tribe_id) initiativeByTribe[i.legacy_tribe_id] = i.id })

    const { data: cycle } = await sb.from('cycles').select('cycle_label').eq('is_current', true).limit(1).single()
    const cycleName = cycle?.cycle_label || 'Ciclo 3'

    if (dryRun) {
      const summary = allocated.map((m: any) => {
        const tid = m.tribe_id || m.selected_tribe_id || m.fixed_tribe_id
        return { name: m.name, email: m.email, tribe_id: tid, tribe_name: tribeMap[tid]?.name || 'Tribo ' + tid }
      })
      return json({ success: true, dry_run: true, count: allocated.length, members: summary })
    }

    const byTribe: Record<number, any[]> = {}
    for (const m of allocated) {
      const tid = m.tribe_id || m.selected_tribe_id || m.fixed_tribe_id
      if (!byTribe[tid]) byTribe[tid] = []
      byTribe[tid].push(m)
    }

    const from = Deno.env.get('RESEND_FROM_ADDRESS') || 'onboarding@resend.dev'
    const sandbox = from.includes('onboarding@resend.dev')
    const portalUrl = 'https://nucleoia.vitormr.dev'
    let totalSent = 0
    const errors: string[] = []

    const callerName = caller.name || 'Gerente de Projeto'
    const callerPhone = caller.phone || '+1 267-874-8329'
    const callerLinkedin = caller.linkedin_url || 'https://www.linkedin.com/in/vitor-rodovalho-pmp/'

    for (const [tidStr, tribeMembers] of Object.entries(byTribe)) {
      const tid = Number(tidStr)
      const tribe = tribeMap[tid]
      const tribeName = tribe?.name || 'Tribo ' + tid
      const waUrl = tribe?.whatsapp_url || ''

      const waBlock = waUrl
        ? '<div style="margin:16px 0;text-align:center"><a href="' + waUrl + '" style="display:inline-block;background:#25D366;color:#fff;padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:bold;font-size:14px">&#x1F4F1; Entrar no Grupo do WhatsApp</a></div>'
        : ''

      const html = '<div style="font-family:sans-serif;max-width:600px;margin:0 auto;padding:20px">'
        + '<div style="background:#0F172A;color:#fff;padding:16px 20px;border-radius:12px 12px 0 0">'
        + '<strong>Nucleo IA e GP</strong> - ' + cycleName + '</div>'
        + '<div style="background:#fff;border:1px solid #E2E8F0;border-top:none;padding:24px 20px;border-radius:0 0 12px 12px">'
        + '<h2 style="color:#0F172A;font-size:18px;margin-bottom:8px">Sua Alocacao de Tribo foi Confirmada!</h2>'
        + '<p style="color:#334155;font-size:14px;line-height:1.7">Parabens! Voce foi alocado(a) na <strong style="color:#0F172A">' + tribeName + '</strong>.</p>'
        + '<p style="color:#334155;font-size:14px;line-height:1.7">Acesse o portal para ver os detalhes da sua tribo, conhecer seus colegas e acompanhar os entregaveis:</p>'
        + '<div style="margin:16px 0;text-align:center"><a href="' + portalUrl + '/tribe/' + tid + '" style="display:inline-block;background:#0F172A;color:#fff;padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:bold;font-size:14px">Acessar Minha Tribo</a></div>'
        + waBlock
        + '<hr style="border:none;border-top:1px solid #E2E8F0;margin:24px 0 16px">'
        + '<p style="color:#64748B;font-size:12px;line-height:1.6">Atenciosamente,<br><strong>' + callerName + '</strong>'
        + '<br>' + callerPhone
        + ' | <a href="' + callerLinkedin + '" style="color:#0D9488">LinkedIn</a>'
        + '<br>Gerente de Projeto - Nucleo IA &amp; GP (' + cycleName + ')</p>'
        + '</div></div>'

      const emails = tribeMembers.map((m: any) => m.email)
      const finalTo = sandbox ? ['vitor.rodovalho@outlook.com'] : [from]
      const finalBcc = sandbox ? [] : emails

      const rr = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer ' + rkey, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          from,
          to: finalTo,
          bcc: finalBcc.length ? finalBcc : undefined,
          subject: '[Nucleo IA] Alocacao Confirmada - ' + tribeName,
          html,
        }),
      })

      const rt = await rr.text()
      console.log('[allocation-notify] tribe:', tid, 'status:', rr.status, 'members:', emails.length)

      if (rr.ok) {
        totalSent += emails.length
      } else {
        errors.push('Tribe ' + tid + ': Resend ' + rr.status + ' - ' + rt)
      }

      const { error: logErr } = await sb.from('broadcast_log').insert([{
        initiative_id: initiativeByTribe[tid] ?? null,
        sender_id: caller.id,
        subject: 'Alocacao Confirmada - ' + tribeName,
        body: 'Notificacao automatica de alocacao',
        recipient_count: emails.length,
        status: rr.ok ? 'sent' : 'failed',
        error_detail: rr.ok ? null : rt,
      }])
      if (logErr) console.error('[allocation-notify] log err:', logErr.message)
    }

    return json({
      success: errors.length === 0,
      total_notified: totalSent,
      tribes_processed: Object.keys(byTribe).length,
      errors: errors.length ? errors : undefined,
      sandbox,
    })

  } catch (e) {
    const m = e instanceof Error ? e.message : String(e)
    console.error('[allocation-notify] FATAL:', m)
    return json({ success: false, error: 'Internal error', detail: m }, 500)
  }
})
