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

    // Auth
    const ah = req.headers.get('Authorization') ?? ''
    const tk = ah.replace(/^Bearer\s+/i, '').trim()
    if (!tk) return json({ error: 'No token' }, 401)

    const uc = createClient(url, anon, { global: { headers: { Authorization: 'Bearer ' + tk } } })
    const ur = await uc.auth.getUser()
    if (ur.error || !ur.data?.user) return json({ error: 'Bad token', d: ur.error?.message }, 401)
    const uid = ur.data.user.id

    // Service client
    const sb = createClient(url, srk)

    // Caller
    const cr = await sb.from('members').select('id,tribe_id,operational_role,is_superadmin,name').eq('auth_id', uid).single()
    if (!cr.data) return json({ error: 'No member', d: cr.error?.message }, 403)
    const c = cr.data

    // Payload
    let p: Record<string, unknown> = {}
    try { p = JSON.parse(raw) } catch (_) { return json({ error: 'Bad JSON', raw_len: raw.length }, 400) }

    const tid = Number(p.tribe_id) || 0
    const subj = String(p.subject || '').trim()
    const bd = String(p.body || '').trim()
    if (!tid || !subj || !bd) return json({ error: 'Missing fields', tid: tid, subj_len: subj.length, bd_len: bd.length }, 400)

    // Authz
    const adm = c.is_superadmin === true || c.operational_role === 'manager' || c.operational_role === 'deputy_manager'
    const tl = c.operational_role === 'tribe_leader' && c.tribe_id === tid
    if (!adm && !tl) return json({ error: 'Forbidden' }, 403)

    // Emails
    const mr = await sb.from('members').select('email').eq('tribe_id', tid).eq('current_cycle_active', true).not('email', 'is', null)
    const emails = (mr.data || []).map((m: Record<string, string>) => m.email).filter((e: string) => e && e.includes('@'))
    if (!emails.length) return json({ error: 'No emails found' }, 400)

    // Tribe
    const tr = await sb.from('tribes').select('name').eq('id', tid).single()
    const tn = tr.data?.name || 'Tribo ' + tid

    // Send
    const from = Deno.env.get('RESEND_FROM_ADDRESS') || 'onboarding@resend.dev'
    const html = '<div style="font-family:sans-serif;max-width:600px;margin:0 auto;padding:20px">'
      + '<div style="background:#0F172A;color:#fff;padding:16px 20px;border-radius:12px 12px 0 0"><strong>Nucleo IA e GP</strong> - ' + tn + '</div>'
      + '<div style="background:#fff;border:1px solid #E2E8F0;border-top:none;padding:24px 20px;border-radius:0 0 12px 12px">'
      + '<p style="color:#64748B;font-size:13px">De: <strong>' + (c.name || 'Lider') + '</strong></p>'
      + '<h2 style="color:#0F172A;font-size:18px">' + subj + '</h2>'
      + '<div style="color:#334155;font-size:14px;line-height:1.7;white-space:pre-wrap">' + bd + '</div>'
      + '<hr style="border:none;border-top:1px solid #E2E8F0;margin:24px 0 16px">'
      + '<p style="color:#94A3B8;font-size:11px">Enviado pelo Nucleo IA e GP.</p></div></div>'

    // Sandbox mode: when using Resend test domain, only send to the verified test email
    const sandbox = from.includes('onboarding@resend.dev')
    const finalTo = sandbox ? ['vitor.rodovalho@outlook.com'] : [from]
    const finalBcc = sandbox ? [] : emails
    console.log('[broadcast] sandbox:', sandbox, 'to:', finalTo.length, 'bcc:', finalBcc.length)

    const rr = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + rkey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: from, to: finalTo, bcc: finalBcc.length ? finalBcc : undefined, subject: '[' + tn + '] ' + subj, html: html }),
    })

    const rt = await rr.text()
    console.log('[broadcast] resend:', rr.status, rt)

    if (!rr.ok) {
      const { error: logErr1 } = await sb.from('broadcast_log').insert([{ tribe_id: tid, sender_id: c.id, subject: subj, body: bd, recipient_count: emails.length, status: 'failed', error_detail: 'Resend ' + rr.status + ': ' + rt }])
      if (logErr1) console.error('[broadcast] log insert err:', logErr1.message)
      return json({ success: false, error: 'Resend failed', status: rr.status, detail: rt }, 502)
    }

    const { error: logErr2 } = await sb.from('broadcast_log').insert([{ tribe_id: tid, sender_id: c.id, subject: subj, body: bd, recipient_count: emails.length, status: 'sent', error_detail: null }])
    if (logErr2) console.error('[broadcast] log insert err:', logErr2.message)

    return json({ success: true, recipient_count: emails.length, tribe: tn })

  } catch (e) {
    const m = e instanceof Error ? e.message : String(e)
    console.error('[broadcast] FATAL:', m)
    return json({ success: false, error: 'Internal error', detail: m }, 500)
  }
})
