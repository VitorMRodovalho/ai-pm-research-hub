import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

// ── Artia GraphQL API ──
const ARTIA_GQL = 'https://api.artia.com/graphql'
const ARTIA_ACCOUNT_ID = 6345833
const ARTIA_PROJECT_ID = 6391775

// Artia activity IDs and PT titles for each KPI (folder 04 - Monitoramento)
const KPI_ACTIVITY_MAP: Record<string, { id: number; label: string }> = {
  chapters_participating: { id: 32528756, label: 'KPI: 8 Capítulos Participantes' },
  entities_partners: { id: 32528757, label: 'KPI: 3 Entidades Parceiras' },
  trail_completion: { id: 32528758, label: 'KPI: 70% Trilha IA Completa' },
  cpmai_certified: { id: 32528759, label: 'KPI: 2+ CPMAI Certificados no Ano' },
  articles_published: { id: 32528760, label: 'KPI: 10+ Artigos Publicados' },
  webinars_realized: { id: 32528762, label: 'KPI: 6+ Webinares ou Talks' },
  pilots_ia_copilot: { id: 32528763, label: 'KPI: 3+ Pilotos IA Copiloto' },
  hours_meetings: { id: 32528764, label: 'KPI: 90+ Horas de Encontros' },
  hours_impact: { id: 32528765, label: 'KPI: 1800+ Horas de Impacto' },
}

interface ArtiaToken { token: string }

async function getArtiaToken(): Promise<string> {
  const clientId = Deno.env.get('ARTIA_CLIENT_ID')
  const secret = Deno.env.get('ARTIA_CLIENT_SECRET')
  if (!clientId || !secret) throw new Error('ARTIA_CLIENT_ID or ARTIA_CLIENT_SECRET not set')

  const res = await fetch(ARTIA_GQL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      query: `mutation { authenticationByClient(clientId: "${clientId}", secret: "${secret}") { token } }`,
    }),
  })
  const data = await res.json()
  return data.data.authenticationByClient.token
}

async function updateArtiaActivity(token: string, activityId: number, pct: number, desc: string, title: string): Promise<boolean> {
  const safeDesc = desc.replace(/"/g, '\\"').replace(/\n/g, ' ')
  const safeTitle = title.replace(/"/g, '\\"')
  const res = await fetch(ARTIA_GQL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
    body: JSON.stringify({
      query: `mutation { updateActivity(id: "${activityId}", accountId: ${ARTIA_ACCOUNT_ID}, title: "${safeTitle}", completedPercent: ${pct}, description: "${safeDesc}") { id completedPercent } }`,
    }),
  })
  const data = await res.json()
  return !!data?.data?.updateActivity?.id
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const sb = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const results: Record<string, { current: number; pct: number; synced: boolean }> = {}
    const now = new Date().toISOString().split('T')[0]

    // ── Calculate KPI values from platform ──

    // 1. Chapters
    const { data: chapData } = await sb.rpc('get_public_platform_stats')
    const chapters = chapData?.chapters_active ?? 5
    results.chapters_participating = { current: chapters, pct: Math.round((chapters / 8) * 100), synced: false }

    // 2. Entities (manual for now)
    results.entities_partners = { current: 0, pct: 0, synced: false }

    // 3. Trail completion (use existing RPC)
    const { data: trailPct } = await sb.rpc('calc_trail_completion_pct')
    const trail = trailPct ?? 0
    results.trail_completion = { current: trail, pct: Math.round((trail / 70) * 100), synced: false }

    // 4. CPMAI certified in 2026
    const { data: cpmaiData } = await sb.from('members')
      .select('credly_badges')
      .eq('cpmai_certified', true)
    let cpmaiThisYear = 0
    for (const m of cpmaiData || []) {
      const badges = m.credly_badges || []
      for (const b of badges) {
        if (b.slug?.includes('cpmai') && b.issued_at?.startsWith('2026')) {
          cpmaiThisYear++
          break
        }
      }
    }
    results.cpmai_certified = { current: cpmaiThisYear, pct: Math.round((cpmaiThisYear / 2) * 100), synced: false }

    // 5. Articles published (done + publicacao tag)
    const { count: articlesCount } = await sb.from('board_items')
      .select('id', { count: 'exact', head: true })
      .eq('status', 'done')
      .contains('tags', ['publicacao'])
    results.articles_published = { current: articlesCount ?? 0, pct: Math.round(((articlesCount ?? 0) / 10) * 100), synced: false }

    // 6. Webinars realized
    const { count: webCount } = await sb.from('webinars')
      .select('id', { count: 'exact', head: true })
      .in('status', ['published', 'completed'])
    results.webinars_realized = { current: webCount ?? 0, pct: Math.round(((webCount ?? 0) / 6) * 100), synced: false }

    // 7. Pilots active/completed
    const { count: pilotsCount } = await sb.from('pilots')
      .select('id', { count: 'exact', head: true })
      .in('status', ['active', 'completed'])
    results.pilots_ia_copilot = { current: pilotsCount ?? 0, pct: Math.round(((pilotsCount ?? 0) / 3) * 100), synced: false }

    // 8. Hours of meetings (realized only)
    const { data: eventsData } = await sb.from('events')
      .select('duration_minutes')
      .lte('date', now)
      .gte('date', '2026-01-01')
    const totalHours = Math.round(((eventsData || []).reduce((s, e) => s + (e.duration_minutes || 0), 0)) / 60 * 10) / 10
    results.hours_meetings = { current: totalHours, pct: Math.round((totalHours / 90) * 100), synced: false }

    // 9. Impact hours
    const { data: impactData } = await sb.rpc('get_public_platform_stats')
    // Calculate from attendance
    const { data: attData } = await sb.from('events')
      .select('duration_minutes, attendance(id)')
      .lte('date', now)
      .gte('date', '2026-01-01')
    let impactHours = 0
    for (const e of attData || []) {
      const attCount = Array.isArray(e.attendance) ? e.attendance.length : 0
      impactHours += ((e.duration_minutes || 0) / 60) * attCount
    }
    impactHours = Math.round(impactHours * 10) / 10
    results.hours_impact = { current: impactHours, pct: Math.round((impactHours / 1800) * 100), synced: false }

    // ── Update annual_kpi_targets (current_value for non-auto KPIs) ──
    for (const [key, val] of Object.entries(results)) {
      await sb.from('annual_kpi_targets')
        .update({ current_value: val.current, updated_at: new Date().toISOString() })
        .eq('kpi_key', key)
        .eq('cycle', 3)
        .eq('year', 2026)
    }

    // ── Sync to Artia ──
    let artiaToken: string | null = null
    try {
      artiaToken = await getArtiaToken()
    } catch (e) {
      console.error('Artia auth failed:', e)
    }

    if (artiaToken) {
      for (const [key, val] of Object.entries(results)) {
        const mapping = KPI_ACTIVITY_MAP[key]
        if (!mapping) continue
        const desc = `Sincronizado automaticamente em ${now}. Valor: ${val.current}. Meta progress: ${val.pct}%.`
        const title = `${mapping.label} (atual: ${val.current})`
        const ok = await updateArtiaActivity(artiaToken, mapping.id, val.pct, desc, title)
        results[key].synced = ok
      }
    }

    // ── Log sync ──
    await sb.from('mcp_usage_log').insert({
      tool_name: 'sync-artia',
      success: true,
      execution_ms: 0,
      response_summary: JSON.stringify({
        synced_at: now,
        kpis: Object.fromEntries(Object.entries(results).map(([k, v]) => [k, { current: v.current, pct: v.pct, artia: v.synced }])),
      }),
    })

    return new Response(JSON.stringify({
      status: 'ok',
      synced_at: now,
      kpis: results,
      artia_synced: artiaToken !== null,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('sync-artia error:', error)
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
