import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Retry with exponential backoff for external API calls
async function fetchWithRetry(url: string, options: RequestInit, maxRetries = 3): Promise<Response> {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      const response = await fetch(url, options);
      if (response.ok || response.status < 500) return response;
    } catch (error) {
      if (attempt === maxRetries - 1) throw error;
    }
    await new Promise(resolve => setTimeout(resolve, Math.pow(2, attempt) * 1000));
  }
  throw new Error(`Failed after ${maxRetries} retries: ${url}`);
}

function buildDynamicSignature(sender: Record<string, any>, cycleName: string): string {
  const name = sender.name || 'Gerencia do Projeto'
  const phone = sender.phone || ''
  const linkedin = sender.linkedin_url || ''
  const role = sender.operational_role === 'manager' ? 'Gerente de Projeto'
    : sender.operational_role === 'deputy_manager' ? 'Vice-Gerente de Projeto'
    : sender.is_superadmin ? 'Superadmin' : 'Gerencia do Projeto'

  let sig = 'Atenciosamente,\n' + name
  if (phone) sig += '\n' + phone
  if (linkedin) sig += ' | ' + linkedin
  sig += '\n' + role + ' do Nucleo IA & GP'
  if (cycleName) sig += ' (' + cycleName + ')'
  return sig
}

function buildSignatureHtml(sender: Record<string, any>, cycleName: string): string {
  const name = sender.name || 'Gerencia do Projeto'
  const phone = sender.phone || ''
  const linkedin = sender.linkedin_url || ''
  const role = sender.operational_role === 'manager' ? 'Gerente de Projeto'
    : sender.operational_role === 'deputy_manager' ? 'Vice-Gerente de Projeto'
    : sender.is_superadmin ? 'Superadmin' : 'Gerencia do Projeto'

  let sig = '<p style="color:#64748B;font-size:12px;line-height:1.6">Atenciosamente,<br><strong>' + name + '</strong>'
  if (phone) sig += '<br>' + phone
  if (linkedin) sig += ' | <a href="' + linkedin + '" style="color:#0D9488">LinkedIn</a>'
  sig += '<br>' + role + ' - Nucleo IA &amp; GP'
  if (cycleName) sig += ' (' + cycleName + ')'
  sig += '</p>'
  return sig
}

const HELP_URL = 'https://nucleoia.vitormr.dev/admin/help'
const HUB_URL = 'https://nucleoia.vitormr.dev'

function buildOnboardingHtml(tribeName: string, memberNames: string[], signatureHtml: string): string {
  const greeting = memberNames.length > 3
    ? 'Prezados pesquisadores da Tribo ' + tribeName
    : 'Prezados ' + memberNames.join(', ')

  return '<div style="font-family:sans-serif;max-width:640px;margin:0 auto;padding:0">'
    + '<div style="background:#0F172A;color:#fff;padding:18px 24px;border-radius:14px 14px 0 0">'
    + '<strong style="font-size:16px">Nucleo de Pesquisa em IA &amp; Gestao de Projetos</strong>'
    + '<br><span style="font-size:12px;color:#94A3B8">PMI Goias | Ciclo 3 (2026)</span></div>'
    + '<div style="background:#fff;border:1px solid #E2E8F0;border-top:none;padding:28px 24px;border-radius:0 0 14px 14px">'
    + '<p style="color:#334155;font-size:15px;line-height:1.8">' + greeting + ',</p>'
    + '<p style="color:#334155;font-size:14px;line-height:1.8">'
    + 'Seja muito bem-vindo(a) ao <strong>Ciclo 3</strong> do Nucleo de Pesquisa! '
    + 'Estamos felizes em ter voce conosco nesta jornada de pesquisa aplicada em <strong>Inteligencia Artificial e Gestao de Projetos</strong>.</p>'

    + '<h3 style="color:#0F172A;font-size:15px;margin-top:24px">Proximos Passos</h3>'
    + '<ol style="color:#334155;font-size:14px;line-height:2;padding-left:20px">'
    + '<li><strong>Acesse a plataforma:</strong> <a href="' + HUB_URL + '" style="color:#0D9488">' + HUB_URL + '</a></li>'
    + '<li><strong>Faca login</strong> com sua conta Google (a mesma do cadastro).</li>'
    + '<li><strong>Preencha seu perfil:</strong> Nome completo, telefone, LinkedIn e URL do Credly.</li>'
    + '<li><strong>Sincronize o Credly:</strong> Acesse <a href="https://www.credly.com" style="color:#0D9488">credly.com</a>, '
    + 'va em seu perfil, copie a URL publica (ex: credly.com/users/seu-nome) e cole no campo "Credly URL" do seu perfil na plataforma.</li>'
    + '<li><strong>Participe da reuniao semanal</strong> da sua tribo e registre presenca na plataforma.</li>'
    + '</ol>'

    + '<div style="background:#F0FDFA;border:1px solid #99F6E4;border-radius:10px;padding:16px;margin:20px 0">'
    + '<p style="color:#0F766E;font-size:13px;margin:0"><strong>Conflito de horario?</strong> '
    + 'A <strong>Tribo 3 (TMO/PMO)</strong> oferece horarios alternativos. '
    + 'Converse com a gerencia do projeto para avaliar a possibilidade de realocacao.</p></div>'

    + '<div style="background:#F8FAFC;border:1px solid #E2E8F0;border-radius:10px;padding:16px;margin:20px 0">'
    + '<p style="color:#475569;font-size:13px;margin:0"><strong>Duvidas?</strong> '
    + 'Acesse nosso <a href="' + HELP_URL + '" style="color:#0D9488">Guia do Lider e Pesquisador</a> '
    + 'para tutoriais sobre LGPD, comunicados, WhatsApp e mais.</p></div>'

    + '<hr style="border:none;border-top:1px solid #E2E8F0;margin:24px 0 16px">'
    + signatureHtml
    + '</div></div>'
}

Deno.serve(async (req) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cli-secret',
  }
  const json = (d: Record<string, unknown>, s = 200) =>
    new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  let raw = ''
  try { raw = await req.text() } catch { raw = '' }

  try {
    if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const srk = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const rkey = Deno.env.get('RESEND_API_KEY') ?? ''

    if (!rkey) return json({ error: 'No RESEND key' }, 500)

    const sb = createClient(url, srk)

    // CLI/automated invocation via dedicated secret in x-cli-secret header
    const cliSecret = req.headers.get('x-cli-secret') ?? ''
    const expectedCliSecret = Deno.env.get('ONBOARDING_CLI_SECRET') ?? ''
    let callerId: string | null = null
    let callerName = 'Sistema (Automated)'

    let senderData: Record<string, any> = {}

    if (cliSecret && expectedCliSecret && cliSecret === expectedCliSecret) {
      const gp = await sb.from('members').select('id, name, phone, linkedin_url, operational_role, is_superadmin')
        .eq('is_superadmin', true).limit(1).single()
      callerId = gp.data?.id ?? null
      callerName = gp.data?.name ?? 'GP Automatico'
      senderData = gp.data || {}
    } else {
      const ah = req.headers.get('Authorization') ?? ''
      const tk = ah.replace(/^Bearer\s+/i, '').trim()
      if (!tk) return json({ error: 'No token' }, 401)

      const uc = createClient(url, anon, { global: { headers: { Authorization: 'Bearer ' + tk } } })
      const ur = await uc.auth.getUser()
      if (ur.error || !ur.data?.user) return json({ error: 'Bad token' }, 401)

      const cr = await sb.from('members').select('id, is_superadmin, operational_role, name, phone, linkedin_url')
        .eq('auth_id', ur.data.user.id).single()
      if (!cr.data) return json({ error: 'No member' }, 403)

      const isAdmin = cr.data.is_superadmin === true
        || cr.data.operational_role === 'manager'
        || cr.data.operational_role === 'deputy_manager'
      if (!isAdmin) return json({ error: 'Admin access required' }, 403)

      callerId = cr.data.id
      callerName = cr.data.name || 'Admin'
      senderData = cr.data
    }

    let opts: { dry_run?: boolean; subject_override?: string } = {}
    try { opts = JSON.parse(raw) } catch { opts = {} }

    const { data: tribes } = await sb.from('tribes').select('id, name')
    if (!tribes?.length) return json({ error: 'No tribes found' }, 400)

    const { data: initsByTribe } = await sb.from('initiatives')
      .select('id, legacy_tribe_id')
      .not('legacy_tribe_id', 'is', null)
    const initiativeByTribe: Record<number, string> = {}
    ;(initsByTribe || []).forEach((i: any) => { if (i.legacy_tribe_id) initiativeByTribe[i.legacy_tribe_id] = i.id })

    const { data: allMembers } = await sb.from('members')
      .select('id, name, email, tribe_id')
      .eq('current_cycle_active', true)
      .not('tribe_id', 'is', null)
      .not('email', 'is', null)

    if (!allMembers?.length) return json({ error: 'No active members with tribes' }, 400)

    const { data: mgmt } = await sb.from('members')
      .select('email')
      .or('is_superadmin.eq.true,operational_role.in.(manager,deputy_manager)')
      .not('email', 'is', null)

    const mgmtEmails = (mgmt || []).map((m: any) => m.email).filter((e: string) => e && e.includes('@'))

    const tribeMap = Object.fromEntries((tribes || []).map((t: any) => [t.id, t.name]))
    const grouped: Record<number, { name: string; emails: string[]; names: string[] }> = {}

    for (const m of allMembers) {
      if (!m.email || !m.email.includes('@') || !m.tribe_id) continue
      if (!grouped[m.tribe_id]) {
        grouped[m.tribe_id] = { name: tribeMap[m.tribe_id] || 'Tribo ' + m.tribe_id, emails: [], names: [] }
      }
      grouped[m.tribe_id].emails.push(m.email)
      grouped[m.tribe_id].names.push(m.name || 'Pesquisador')
    }

    const from = Deno.env.get('RESEND_FROM_ADDRESS') || 'onboarding@resend.dev'
    const sandbox = from.includes('onboarding@resend.dev')
    const subject = opts.subject_override || 'Bem-vindo ao Ciclo 3 do Nucleo de Pesquisa em IA & GP!'
    const results: any[] = []
    let totalSent = 0

    const { data: cycle } = await sb.from('cycles').select('cycle_label').eq('is_current', true).limit(1).single()
    const cycleName = cycle?.cycle_label || 'Ciclo 3'
    const signatureHtml = buildSignatureHtml(senderData, cycleName)

    for (const [tribeIdStr, group] of Object.entries(grouped)) {
      const html = buildOnboardingHtml(group.name, group.names, signatureHtml)
      const allBcc = [...new Set([...group.emails, ...mgmtEmails])]

      const finalTo = sandbox ? ['vitor.rodovalho@outlook.com'] : [from]
      const finalBcc = sandbox ? [] : allBcc

      if (opts.dry_run) {
        results.push({
          tribe: group.name,
          recipients: allBcc.length,
          emails_sample: allBcc.slice(0, 3),
          sandbox: sandbox,
        })
        continue
      }

      const resendPayload = {
        from: from,
        to: finalTo,
        bcc: finalBcc.length > 0 ? finalBcc : undefined,
        subject: '[' + group.name + '] ' + subject,
        html: html,
      }

      // Rate-limit safeguard: 1s delay between sends (Resend free tier = 2 req/sec)
      await new Promise(r => setTimeout(r, 1000))

      const rr = await fetchWithRetry('https://api.resend.com/emails', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + rkey },
        body: JSON.stringify(resendPayload),
      })

      const rb = await rr.text()
      let rj: any = {}
      try { rj = JSON.parse(rb) } catch { rj = { raw: rb } }

      if (rr.ok) {
        totalSent += allBcc.length
        results.push({ tribe: group.name, status: 'sent', recipients: allBcc.length, resend_id: rj.id })
      } else {
        results.push({ tribe: group.name, status: 'failed', error: rj })
      }

      const { error: logErr } = await sb.from('broadcast_log').insert([{
        initiative_id: initiativeByTribe[Number(tribeIdStr)] ?? null,
        sender_id: callerId,
        subject: '[' + group.name + '] ' + subject,
        body: 'Global Onboarding Email (HTML template)',
        recipient_count: allBcc.length,
        status: rr.ok ? 'sent' : 'failed',
        error_detail: rr.ok ? null : JSON.stringify(rj),
      }])
      if (logErr) console.error('Log error:', logErr.message)
    }

    return json({
      success: true,
      dry_run: opts.dry_run ?? false,
      tribes_processed: Object.keys(grouped).length,
      total_recipients: totalSent,
      details: results,
    })

  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err)
    return json({ error: 'Internal error', detail: msg }, 500)
  }
})
