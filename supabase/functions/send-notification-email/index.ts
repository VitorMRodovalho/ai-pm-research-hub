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
  weekly_member_digest: 'Seu resumo semanal — Núcleo IA',
  weekly_tribe_digest_leader: 'Resumo da sua tribo — Núcleo IA',
}

// Digest types render body as multi-line text (preserve \n as <br>) without CTA deadline block.
const DIGEST_TYPES = new Set([
  'weekly_card_digest_member',
])

// ADR-0022 W2/W3: digest types with JSON body (from RPC). Rendered via
// dedicated builders — separate from buildHtml dispatch.
const WEEKLY_MEMBER_DIGEST_TYPE = 'weekly_member_digest'
const WEEKLY_TRIBE_DIGEST_LEADER_TYPE = 'weekly_tribe_digest_leader'

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

// ADR-0022 W2: rich rendering for weekly_member_digest. Body is JSON text from
// get_weekly_member_digest RPC with 7 sections. Renders responsive HTML with
// collapsible-style headers (no <details> — Gmail strips it; uses bordered
// section blocks for clarity).
function buildWeeklyMemberDigestHtml(notification: any): string {
  let payload: any = {}
  try {
    payload = JSON.parse(notification.body || '{}')
  } catch {
    payload = {}
  }
  const sections = payload.sections || {}
  const cards = sections.cards || {}
  const events = sections.events_upcoming || []
  const pubs = sections.publications_new || []
  const broadcasts = sections.broadcasts || []
  const governance = sections.governance_pending || []
  const engagements = sections.engagements_new || []
  const achievements = sections.achievements || {}
  const certs = achievements.certificates_issued || []
  const xp = Number(achievements.xp_delta || 0)

  const sectionBlock = (title: string, count: number, color: string, contentHtml: string) => `
    <div style="background: white; border: 1px solid #e9ecef; border-radius: 8px; margin: 0 0 16px 0; overflow: hidden;">
      <div style="background: ${color}; padding: 10px 14px;">
        <h3 style="color: white; font-size: 13px; margin: 0; font-weight: 600;">${escapeHtml(title)} <span style="opacity: 0.85;">(${count})</span></h3>
      </div>
      <div style="padding: 12px 16px;">${contentHtml}</div>
    </div>`

  const renderCardList = (items: any[], showOverdue: boolean) => items.length === 0 ? '' :
    `<ul style="margin: 0; padding-left: 18px; color: #495057; font-size: 13px; line-height: 1.6;">
      ${items.map(c => `<li><strong>${escapeHtml(c.title)}</strong>${c.due_date ? ` — ${escapeHtml(String(c.due_date))}` : ''}${showOverdue && c.days_overdue ? ` <span style="color: #d32f2f;">(${c.days_overdue}d atrasado)</span>` : ''}${c.initiative_title ? ` <span style="color: #868e96;">· ${escapeHtml(c.initiative_title)}</span>` : ''}</li>`).join('')}
    </ul>`

  const renderEventList = (items: any[]) => items.length === 0 ? '' :
    `<ul style="margin: 0; padding-left: 18px; color: #495057; font-size: 13px; line-height: 1.6;">
      ${items.map(e => `<li><strong>${escapeHtml(e.title)}</strong> — ${escapeHtml(String(e.date))}${e.type ? ` <span style="color: #868e96;">(${escapeHtml(e.type)})</span>` : ''}${e.initiative_title ? ` · ${escapeHtml(e.initiative_title)}` : ''}</li>`).join('')}
    </ul>`

  const renderTitleList = (items: any[]) => items.length === 0 ? '' :
    `<ul style="margin: 0; padding-left: 18px; color: #495057; font-size: 13px; line-height: 1.6;">
      ${items.map(x => `<li>${escapeHtml(x.title || x.type || 'Sem título')}</li>`).join('')}
    </ul>`

  const overdue = cards.overdue_7plus || []
  const thisWeek = cards.this_week_pending || []
  const nextWeek = cards.next_week_due || []
  const cardsCount = overdue.length + thisWeek.length + nextWeek.length

  let cardsContent = ''
  if (overdue.length > 0) cardsContent += `<p style="margin: 0 0 6px 0; color: #d32f2f; font-size: 13px; font-weight: 600;">Atrasados há mais de 7 dias:</p>${renderCardList(overdue, true)}`
  if (thisWeek.length > 0) cardsContent += `<p style="margin: 12px 0 6px 0; color: #f57c00; font-size: 13px; font-weight: 600;">Esta semana (vencem nos próximos 7 dias atrás):</p>${renderCardList(thisWeek, true)}`
  if (nextWeek.length > 0) cardsContent += `<p style="margin: 12px 0 6px 0; color: #1976d2; font-size: 13px; font-weight: 600;">Próxima semana:</p>${renderCardList(nextWeek, false)}`

  const certsContent = certs.length > 0
    ? `<p style="margin: 0 0 6px 0; color: #495057; font-size: 13px; line-height: 1.6;">Certificados emitidos:</p>${renderTitleList(certs)}`
    : ''
  const xpContent = xp > 0
    ? `<p style="margin: ${certs.length > 0 ? '12px' : '0'} 0 0 0; color: #495057; font-size: 13px; line-height: 1.6;"><strong>+${xp} XP</strong> ganhos esta semana 🎉</p>`
    : ''
  const achievementsCount = certs.length + (xp > 0 ? 1 : 0)

  const totalItems = cardsCount + events.length + pubs.length + broadcasts.length + governance.length + engagements.length + achievementsCount

  return `
    <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 640px; margin: 0 auto; background: #f8f9fa;">
      <div style="background: #003B5C; padding: 24px 20px; text-align: center;">
        <h1 style="color: white; font-size: 20px; margin: 0;">Núcleo IA &amp; GP — Resumo Semanal</h1>
        <p style="color: #b8d8e8; font-size: 12px; margin: 8px 0 0 0;">${totalItems} itens nesta semana</p>
      </div>
      <div style="padding: 20px 16px;">
        ${cardsCount > 0 ? sectionBlock('📋 Seus cards', cardsCount, '#003B5C', cardsContent) : ''}
        ${events.length > 0 ? sectionBlock('📅 Próximos eventos (7 dias)', events.length, '#1976d2', renderEventList(events)) : ''}
        ${engagements.length > 0 ? sectionBlock('🤝 Novos vínculos', engagements.length, '#388e3c', renderTitleList(engagements)) : ''}
        ${broadcasts.length > 0 ? sectionBlock('📢 Comunicados da tribo', broadcasts.length, '#f57c00', renderTitleList(broadcasts)) : ''}
        ${pubs.length > 0 ? sectionBlock('📚 Publicações novas', pubs.length, '#7b1fa2', renderTitleList(pubs)) : ''}
        ${governance.length > 0 ? sectionBlock('⚖️ Governança pendente', governance.length, '#c62828', renderTitleList(governance)) : ''}
        ${achievementsCount > 0 ? sectionBlock('🏆 Conquistas', achievementsCount, '#ffa000', certsContent + xpContent) : ''}

        <div style="text-align: center; margin: 24px 0 0 0;">
          <a href="https://nucleoia.vitormr.dev/profile" style="display: inline-block; background: #003B5C; color: white; padding: 12px 28px; text-decoration: none; border-radius: 8px; font-size: 14px; font-weight: 600;">Abrir minha plataforma</a>
        </div>
        <p style="color: #adb5bd; font-size: 11px; margin: 24px 0 0 0; line-height: 1.5; text-align: center;">
          Este resumo consolida ${totalItems} notificação(ões) que você receberia em emails separados ao longo da semana. Quer mudar a cadência? <a href="https://nucleoia.vitormr.dev/settings/notifications" style="color: #6c757d;">Preferências de notificação</a>.
        </p>
      </div>
      <div style="padding: 16px; text-align: center; font-size: 11px; color: #868e96; background: white; border-top: 1px solid #e9ecef;">
        <p>Núcleo de Estudos e Pesquisa em IA &amp; GP</p>
      </div>
    </div>`
}

// ADR-0022 W3: leader digest aggregate-only renderer. Body is JSON from
// get_weekly_tribe_digest RPC. Privacy-preserving — no individual member
// names or card titles, only counts/percentages.
function buildWeeklyTribeDigestLeaderHtml(notification: any): string {
  let payload: any = {}
  try { payload = JSON.parse(notification.body || '{}') } catch { payload = {} }
  const tribeName = payload.tribe_name || 'sua tribo'
  const agg = payload.aggregates || {}
  const overdue = Number(agg.cards_overdue_total || 0)
  const dueNext = Number(agg.cards_due_next_7d || 0)
  const noAssignee = Number(agg.cards_without_assignee || 0)
  const noDate = Number(agg.cards_without_due_date || 0)
  const completed = Number(agg.cards_completed_window || 0)
  const membersOverdue = Number(agg.members_with_overdue_cards || 0)
  const activeMembers = Number(agg.active_members || 0)
  const healthPct = Number(agg.tribe_health_pct || 100)

  const healthColor = healthPct >= 80 ? '#388e3c' : healthPct >= 50 ? '#f57c00' : '#d32f2f'
  const statRow = (label: string, value: number, color: string) => `
    <tr>
      <td style="padding: 10px 12px; color: #495057; font-size: 13px; border-bottom: 1px solid #f1f3f5;">${escapeHtml(label)}</td>
      <td style="padding: 10px 12px; text-align: right; color: ${color}; font-size: 16px; font-weight: 600; border-bottom: 1px solid #f1f3f5;">${value}</td>
    </tr>`

  return `
    <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 640px; margin: 0 auto; background: #f8f9fa;">
      <div style="background: #003B5C; padding: 24px 20px; text-align: center;">
        <h1 style="color: white; font-size: 20px; margin: 0;">Resumo da Tribo ${escapeHtml(tribeName)}</h1>
        <p style="color: #b8d8e8; font-size: 12px; margin: 8px 0 0 0;">Visão de líder · ${activeMembers} membros ativos</p>
      </div>
      <div style="padding: 20px 16px;">
        <div style="background: white; border: 1px solid #e9ecef; border-radius: 8px; padding: 20px; margin-bottom: 16px; text-align: center;">
          <div style="font-size: 11px; color: #868e96; margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.5px;">Tribe Health</div>
          <div style="font-size: 36px; font-weight: 700; color: ${healthColor};">${healthPct}%</div>
          <div style="font-size: 11px; color: #868e96; margin-top: 4px;">% de cards ativos com baseline definido</div>
        </div>

        <div style="background: white; border: 1px solid #e9ecef; border-radius: 8px; overflow: hidden; margin-bottom: 16px;">
          <div style="background: #003B5C; padding: 10px 14px;">
            <h3 style="color: white; font-size: 13px; margin: 0; font-weight: 600;">📊 Indicadores agregados</h3>
          </div>
          <table style="width: 100%; border-collapse: collapse;">
            ${statRow('Cards atrasados', overdue, overdue > 0 ? '#d32f2f' : '#868e96')}
            ${statRow('Membros com cards atrasados', membersOverdue, membersOverdue > 0 ? '#d32f2f' : '#868e96')}
            ${statRow('Cards vencendo nos próximos 7 dias', dueNext, dueNext > 0 ? '#f57c00' : '#868e96')}
            ${statRow('Cards sem assignee', noAssignee, noAssignee > 0 ? '#f57c00' : '#868e96')}
            ${statRow('Cards sem data de entrega', noDate, noDate > 0 ? '#f57c00' : '#868e96')}
            ${statRow('Cards concluídos esta semana', completed, completed > 0 ? '#388e3c' : '#868e96')}
          </table>
        </div>

        <div style="background: #fff8e1; border-left: 4px solid #ffc107; padding: 12px 14px; margin: 0 0 16px 0; border-radius: 4px;">
          <p style="color: #6b4e00; font-size: 12px; margin: 0; line-height: 1.5;">
            <strong>Privacy-preserving:</strong> este resumo mostra apenas contadores agregados.
            Para ver o detalhe (quais cards, quais membros), abra o portfolio do board.
          </p>
        </div>

        <div style="text-align: center; margin: 24px 0 0 0;">
          <a href="https://nucleoia.vitormr.dev/admin/portfolio" style="display: inline-block; background: #003B5C; color: white; padding: 12px 28px; text-decoration: none; border-radius: 8px; font-size: 14px; font-weight: 600;">Abrir portfolio</a>
        </div>
        <p style="color: #adb5bd; font-size: 11px; margin: 24px 0 0 0; line-height: 1.5; text-align: center;">
          Você recebe este resumo porque é líder da tribo ${escapeHtml(tribeName)}.
          <a href="https://nucleoia.vitormr.dev/settings/notifications" style="color: #6c757d;">Preferências de notificação</a>.
        </p>
      </div>
      <div style="padding: 16px; text-align: center; font-size: 11px; color: #868e96; background: white; border-top: 1px solid #e9ecef;">
        <p>Núcleo de Estudos e Pesquisa em IA &amp; GP</p>
      </div>
    </div>`
}

function buildHtml(notification: any): string {
  if (notification.type === WEEKLY_MEMBER_DIGEST_TYPE) {
    return buildWeeklyMemberDigestHtml(notification)
  }
  if (notification.type === WEEKLY_TRIBE_DIGEST_LEADER_TYPE) {
    return buildWeeklyTribeDigestLeaderHtml(notification)
  }
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

      // ADR-0022 W2: respect notify_delivery_mode_pref='suppress_all' (member opt-out)
      const { data: memberPrefs } = await sb
        .from('members')
        .select('notify_delivery_mode_pref')
        .eq('id', notif.recipient_id)
        .single()

      if (memberPrefs?.notify_delivery_mode_pref === 'suppress_all') continue

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
