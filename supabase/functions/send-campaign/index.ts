import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { isSandboxMode } from '../_shared/email-utils.ts'

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
    const rkey = Deno.env.get('RESEND_API_KEY') ?? ''
    const from = Deno.env.get('RESEND_FROM_ADDRESS') || 'onboarding@resend.dev'

    if (!rkey) return json({ error: 'No RESEND key' }, 500)

    // Sandbox mode: onboarding@resend.dev can only send to account owner
    const sandbox = isSandboxMode(from)
    console.log('[campaign] from:', from, 'sandbox:', sandbox)

    // Auth: verify caller (accepts both user JWT and service_role key)
    const ah = req.headers.get('Authorization') ?? ''
    const tk = ah.replace(/^Bearer\s+/i, '').trim()
    if (!tk) return json({ error: 'No token' }, 401)

    const sb = createClient(url, srk)
    const isServiceRole = tk === srk

    if (!isServiceRole) {
      const { data: { user }, error: userError } = await sb.auth.getUser(tk)
      if (userError || !user) return json({ error: `Auth failed: ${userError?.message || 'token invalid'}` }, 401)

      const { data: caller } = await sb.from('members')
        .select('id, is_superadmin, operational_role')
        .eq('auth_id', user.id).single()
      if (!caller) return json({ error: 'No member' }, 403)
      const isAdmin = caller.is_superadmin || ['manager', 'deputy_manager'].includes(caller.operational_role)
      if (!isAdmin) return json({ error: 'Forbidden: GP/DM only' }, 403)
    }

    // Parse payload
    const body = await req.json()
    const sendId: string = body.send_id
    if (!sendId) return json({ error: 'Missing send_id' }, 400)

    // Load send record
    const { data: send, error: sendErr } = await sb.from('campaign_sends')
      .select('*, campaign_templates(*)')
      .eq('id', sendId).single()
    if (!send) return json({ error: 'Send not found', detail: sendErr?.message }, 404)
    if (send.status === 'sent') return json({ error: 'Already sent' }, 400)

    const tmpl = send.campaign_templates
    if (!tmpl) return json({ error: 'Template not found' }, 404)

    // Mark as sending
    await sb.from('campaign_sends').update({ status: 'sending' }).eq('id', sendId)

    // Load recipients
    const { data: recipients, error: recipErr } = await sb.from('campaign_recipients')
      .select('id, member_id, external_email, external_name, language, unsubscribed, unsubscribe_token')
      .eq('send_id', sendId)
    if (!recipients || recipients.length === 0) {
      await sb.from('campaign_sends').update({ status: 'failed', error_log: `No recipients: ${recipErr?.message || 'empty'}` }).eq('id', sendId)
      return json({ error: 'No recipients' }, 400)
    }
    console.log('[campaign] recipients:', recipients.length)

    // Load member emails
    const memberIds = recipients.filter(r => r.member_id).map(r => r.member_id)
    let memberMap: Record<string, { email: string; name: string; tribe_name: string; chapter: string }> = {}
    if (memberIds.length > 0) {
      const { data: members, error: memErr } = await sb.from('members')
        .select('id, email, name, tribe_id')
        .in('id', memberIds)
      if (memErr) console.error('[campaign] members query error:', memErr.message)
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
      console.log('[campaign] memberMap entries:', Object.keys(memberMap).length)
    }

    const platformUrl = 'https://nucleoiagp.pages.dev'
    let delivered = 0
    let errors: string[] = []

    for (const r of recipients) {
      if (r.unsubscribed) continue

      const lang = r.language || 'pt'
      const langKey = lang === 'en' ? 'en' : lang === 'es' ? 'es' : 'pt'

      let toEmail = ''
      let memberName = ''
      let tribeName = ''
      let chapterName = ''

      if (r.member_id && memberMap[r.member_id]) {
        const m = memberMap[r.member_id]
        toEmail = m.email
        memberName = m.name
        tribeName = m.tribe_name
        chapterName = m.chapter
      } else if (r.external_email) {
        toEmail = r.external_email
        memberName = r.external_name || ''
      }

      if (!toEmail) {
        console.log('[campaign] skip: no email for recipient', r.id)
        continue
      }

      // Sandbox: override recipient to test address (Resend free tier only sends to account owner)
      const sandboxTo = Deno.env.get('RESEND_TEST_TO') || 'nucleoia@pmigo.org.br'
      const finalTo = sandbox ? [sandboxTo] : [toEmail]

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
        const payload = {
          from,
          to: finalTo,
          subject: sandbox ? `[SANDBOX] ${subject}` : subject,
          html,
          text,
          headers: { 'List-Unsubscribe': `<${unsubUrl}>` },
        }
        console.log('[campaign] sending to:', finalTo[0], 'from:', from)

        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { 'Authorization': 'Bearer ' + rkey, 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        })

        const rt = await res.text()
        console.log('[campaign] resend:', res.status, rt)

        if (res.ok) {
          // Parse resend_id for webhook correlation
          let resendId: string | undefined
          try { resendId = JSON.parse(rt)?.id } catch { /* ignore */ }
          await sb.from('campaign_recipients').update({
            delivered: true,
            ...(resendId ? { resend_id: resendId } : {}),
          }).eq('id', r.id)
          delivered++
        } else {
          errors.push(`${toEmail}: ${rt}`)
        }
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : String(e)
        errors.push(`${toEmail}: ${msg}`)
      }

      // Small delay between sends to avoid rate limits
      await new Promise(resolve => setTimeout(resolve, 100))
    }

    // Update send status
    const finalStatus = delivered > 0 ? 'sent' : 'failed'
    await sb.from('campaign_sends').update({
      status: finalStatus,
      sent_at: new Date().toISOString(),
      error_log: errors.length > 0 ? errors.join('\n') : (sandbox ? 'sandbox: sent to account owner only' : null),
    }).eq('id', sendId)

    console.log('[campaign] done:', { delivered, errors: errors.length, total: recipients.length, status: finalStatus, sandbox })
    return json({ delivered, errors: errors.length, total: recipients.length, status: finalStatus, sandbox })
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e)
    console.error('[campaign] FATAL:', msg)
    return json({ error: msg }, 500)
  }
})
