import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (d: Record<string, unknown>, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const srk = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const rkey = Deno.env.get('RESEND_API_KEY') ?? ''

    if (!rkey) return json({ error: 'No RESEND key' }, 500)

    // Auth: verify caller
    const ah = req.headers.get('Authorization') ?? ''
    const tk = ah.replace(/^Bearer\s+/i, '').trim()
    if (!tk) return json({ error: 'No token' }, 401)

    const uc = createClient(url, anon, { global: { headers: { Authorization: 'Bearer ' + tk } } })
    const ur = await uc.auth.getUser()
    if (ur.error || !ur.data?.user) return json({ error: 'Bad token' }, 401)
    const uid = ur.data.user.id

    const sb = createClient(url, srk)

    // Verify caller is GP/DM
    const { data: caller } = await sb.from('members')
      .select('id, is_superadmin, operational_role')
      .eq('auth_id', uid).single()
    if (!caller) return json({ error: 'No member' }, 403)
    const isAdmin = caller.is_superadmin || ['manager', 'deputy_manager'].includes(caller.operational_role)
    if (!isAdmin) return json({ error: 'Forbidden: GP/DM only' }, 403)

    // Parse payload
    const body = await req.json()
    const sendId: string = body.send_id
    if (!sendId) return json({ error: 'Missing send_id' }, 400)

    // Load send record
    const { data: send } = await sb.from('campaign_sends')
      .select('*, campaign_templates(*)')
      .eq('id', sendId).single()
    if (!send) return json({ error: 'Send not found' }, 404)
    if (send.status === 'sent') return json({ error: 'Already sent' }, 400)

    const tmpl = send.campaign_templates
    if (!tmpl) return json({ error: 'Template not found' }, 404)

    // Mark as sending
    await sb.from('campaign_sends').update({ status: 'sending' }).eq('id', sendId)

    // Load recipients
    const { data: recipients } = await sb.from('campaign_recipients')
      .select('id, member_id, external_email, external_name, language, unsubscribed, unsubscribe_token')
      .eq('send_id', sendId)
    if (!recipients || recipients.length === 0) {
      await sb.from('campaign_sends').update({ status: 'failed', error_log: 'No recipients' }).eq('id', sendId)
      return json({ error: 'No recipients' }, 400)
    }

    // Load member emails for member recipients
    const memberIds = recipients.filter(r => r.member_id).map(r => r.member_id)
    let memberMap: Record<string, { email: string; name: string; tribe_name: string; chapter: string }> = {}
    if (memberIds.length > 0) {
      const { data: members } = await sb.from('members')
        .select('id, email, name, tribe_id, preferred_language')
        .in('id', memberIds)
      const tribeIds = [...new Set((members || []).filter(m => m.tribe_id).map(m => m.tribe_id))]
      let tribeMap: Record<number, { name: string; chapter: string }> = {}
      if (tribeIds.length > 0) {
        const { data: tribes } = await sb.from('tribes').select('id, name, chapter').in('id', tribeIds)
        for (const t of (tribes || [])) tribeMap[t.id] = { name: t.name, chapter: t.chapter || '' }
      }
      for (const m of (members || [])) {
        const tribe = m.tribe_id ? tribeMap[m.tribe_id] : null
        memberMap[m.id] = {
          email: m.email,
          name: m.name || 'Membro',
          tribe_name: tribe?.name || '',
          chapter: tribe?.chapter || '',
        }
      }
    }

    const platformUrl = 'https://nucleoiagp.pages.dev'
    let delivered = 0
    let errors: string[] = []

    for (const r of recipients) {
      // Skip unsubscribed
      if (r.unsubscribed) continue

      const lang = r.language || 'pt'
      const langKey = lang === 'en' ? 'en' : lang === 'es' ? 'es' : 'pt'

      let toEmail = ''
      let toName = ''
      let memberName = ''
      let tribeName = ''
      let chapterName = ''

      if (r.member_id && memberMap[r.member_id]) {
        const m = memberMap[r.member_id]
        toEmail = m.email
        toName = m.name
        memberName = m.name
        tribeName = m.tribe_name
        chapterName = m.chapter
      } else if (r.external_email) {
        toEmail = r.external_email
        toName = r.external_name || ''
        memberName = r.external_name || ''
      }

      if (!toEmail) continue

      // Render template
      const subject = (tmpl.subject[langKey] || tmpl.subject['pt'] || '').replace('{member.name}', memberName)
      let html = tmpl.body_html[langKey] || tmpl.body_html['pt'] || ''
      let text = tmpl.body_text[langKey] || tmpl.body_text['pt'] || ''

      const unsubUrl = `${platformUrl}/unsubscribe?token=${r.unsubscribe_token}`

      const vars: [string, string][] = [
        ['{member.name}', memberName],
        ['{member.tribe}', tribeName],
        ['{member.chapter}', chapterName],
        ['{platform.url}', platformUrl],
        ['{unsubscribe_url}', unsubUrl],
      ]
      for (const [k, v] of vars) {
        html = html.split(k).join(v)
        text = text.split(k).join(v)
      }

      // Send via Resend
      try {
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${rkey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            from: 'Nucleo IA & GP <nucleoia@pmigo.org.br>',
            to: [toEmail],
            subject,
            html,
            text,
            headers: { 'List-Unsubscribe': `<${unsubUrl}>` },
          }),
        })
        if (res.ok) {
          await sb.from('campaign_recipients').update({ delivered: true }).eq('id', r.id)
          delivered++
        } else {
          const err = await res.text()
          errors.push(`${toEmail}: ${err}`)
        }
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : String(e)
        errors.push(`${toEmail}: ${msg}`)
      }

      // Small delay between sends to avoid rate limits
      await new Promise(resolve => setTimeout(resolve, 100))
    }

    // Update send status
    const finalStatus = errors.length === 0 ? 'sent' : (delivered > 0 ? 'sent' : 'failed')
    await sb.from('campaign_sends').update({
      status: finalStatus,
      sent_at: new Date().toISOString(),
      error_log: errors.length > 0 ? errors.join('\n') : null,
    }).eq('id', sendId)

    return json({ delivered, errors: errors.length, total: recipients.length, status: finalStatus })
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e)
    return json({ error: msg }, 500)
  }
})
