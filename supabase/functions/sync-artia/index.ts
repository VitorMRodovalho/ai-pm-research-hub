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

// Artia custom status IDs (PMI-GO standard)
const ARTIA_STATUS = { A_INICIAR: 317052, ANDAMENTO: 328049, ENCERRADO: 317054 }
const ARTIA_KPI_FOLDER = 6399649
const ARTIA_RESPONSIBLE_ID = 298786 // "GP Projeto Núcleo IA"

async function updateArtiaActivity(token: string, activityId: number, pct: number, desc: string, title: string): Promise<boolean> {
  const safeDesc = desc.replace(/"/g, '\\"').replace(/\n/g, ' ')
  const safeTitle = title.replace(/"/g, '\\"')
  // Update % and title
  const res = await fetch(ARTIA_GQL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
    body: JSON.stringify({
      query: `mutation { updateActivity(id: "${activityId}", accountId: ${ARTIA_ACCOUNT_ID}, title: "${safeTitle}", completedPercent: ${pct}, description: "${safeDesc}", responsibleId: ${ARTIA_RESPONSIBLE_ID}) { id completedPercent } }`,
    }),
  })
  const data = await res.json()
  const updated = !!data?.data?.updateActivity?.id
  if (!updated) return false

  // Sync status: 0% → A Iniciar, 1-99% → Andamento, 100% → Encerrado
  const targetStatus = pct >= 100 ? ARTIA_STATUS.ENCERRADO : pct > 0 ? ARTIA_STATUS.ANDAMENTO : ARTIA_STATUS.A_INICIAR
  const isClosed = pct >= 100
  await fetch(ARTIA_GQL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
    body: JSON.stringify({
      query: `mutation { changeCustomStatusActivity(id: "${activityId}", accountId: ${ARTIA_ACCOUNT_ID}, folderId: ${ARTIA_KPI_FOLDER}, customStatusId: ${targetStatus}, status: ${isClosed}) { id status } }`,
    }),
  })
  return true
}

// ── Discovery mode (Phase C.1) ──
// Triggered via ?mode=discover. Lists projects + folders + sample activities for the account.
// Persists results to artia_discovery_dumps for offline analysis.
async function runDiscoveryMode(sb: any, token: string): Promise<any> {
  const summary: any = {
    started_at: new Date().toISOString(),
    queries_attempted: 0,
    queries_succeeded: 0,
    queries_failed: 0,
    projects_found: 0,
    folders_found: 0,
    activities_sampled: 0,
    errors: [],
  }

  // Helper: GraphQL query with auth + dump persist
  async function gql(query: string, variables?: any): Promise<any> {
    const res = await fetch(ARTIA_GQL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
      body: JSON.stringify({ query, variables }),
    })
    return await res.json()
  }

  async function persistDump(kind: string, payload: any, opts?: { project_id?: number; project_name?: string; source_query?: string; notes?: string }) {
    await sb.from('artia_discovery_dumps').insert({
      account_id: ARTIA_ACCOUNT_ID,
      project_id: opts?.project_id ?? null,
      project_name: opts?.project_name ?? null,
      dump_kind: kind,
      payload: payload,
      source_query: opts?.source_query ?? null,
      notes: opts?.notes ?? null,
    })
  }

  // ── Step 1: List projects in account (Artia uses listing* prefix per introspection) ──
  // Try multiple field selection variants since Project type fields are unknown
  const projectsQueries = [
    { name: 'listingProjects+full', q: `{ listingProjects(accountId: ${ARTIA_ACCOUNT_ID}) { id title customStatus { id name } } }` },
    { name: 'listingProjects+title', q: `{ listingProjects(accountId: ${ARTIA_ACCOUNT_ID}) { id title } }` },
    { name: 'listingProjects+name', q: `{ listingProjects(accountId: ${ARTIA_ACCOUNT_ID}) { id name } }` },
    { name: 'listingProjects+id', q: `{ listingProjects(accountId: ${ARTIA_ACCOUNT_ID}) { id } }` },
  ]

  let projectsList: any[] = []
  for (const variant of projectsQueries) {
    summary.queries_attempted++
    try {
      const data = await gql(variant.q)
      if (data.errors) {
        summary.queries_failed++
        await persistDump('error', { query_variant: variant.name, errors: data.errors }, { source_query: variant.q, notes: `listingProjects attempt: ${variant.name}` })
        continue
      }
      const list = data?.data?.listingProjects ?? []
      if (Array.isArray(list) && list.length > 0) {
        summary.queries_succeeded++
        projectsList = list
        summary.projects_found = list.length
        await persistDump('projects_list', list, { source_query: variant.q, notes: `Successful variant: ${variant.name}` })
        break
      }
    } catch (e) {
      summary.queries_failed++
      summary.errors.push({ step: 'projects_list', variant: variant.name, error: (e as Error).message })
      await persistDump('error', { query_variant: variant.name, error: (e as Error).message }, { source_query: variant.q, notes: `listingProjects exception: ${variant.name}` })
    }
  }

  if (projectsList.length === 0) {
    summary.errors.push({ step: 'projects_list', fatal: true, note: 'All listingProjects field-selection variants failed.' })
    return summary
  }

  // ── Step 2: List ALL folders in account (account-scoped, not project-scoped per introspection) ──
  // Folders may have project_id or similar field linking them to a project
  const foldersQueries = [
    { name: 'listingFolders+full', q: `{ listingFolders(accountId: ${ARTIA_ACCOUNT_ID}, page: 1) { id title projectId } }` },
    { name: 'listingFolders+title', q: `{ listingFolders(accountId: ${ARTIA_ACCOUNT_ID}, page: 1) { id title } }` },
    { name: 'listingFolders+name', q: `{ listingFolders(accountId: ${ARTIA_ACCOUNT_ID}, page: 1) { id name } }` },
    { name: 'listingFolders+id', q: `{ listingFolders(accountId: ${ARTIA_ACCOUNT_ID}, page: 1) { id } }` },
  ]

  let allFolders: any[] = []
  for (const variant of foldersQueries) {
    summary.queries_attempted++
    try {
      const data = await gql(variant.q)
      if (data.errors) {
        summary.queries_failed++
        await persistDump('error', { query_variant: variant.name, errors: data.errors }, { source_query: variant.q, notes: `listingFolders attempt: ${variant.name}` })
        continue
      }
      const list = data?.data?.listingFolders ?? []
      if (Array.isArray(list) && list.length > 0) {
        summary.queries_succeeded++
        allFolders = list
        summary.folders_found = list.length
        await persistDump('folders_list', list, { source_query: variant.q, notes: `Account-level folders found via ${variant.name}` })
        break
      }
    } catch (e) {
      summary.queries_failed++
      summary.errors.push({ step: 'folders_list', variant: variant.name, error: (e as Error).message })
    }
  }

  // ── Step 2b: Show details of our project + 4 high-conformance projects ──
  // Per audit: PMO 74%, PM Lab 64%, Projeto Liderança 58%, Melhores do Ano 56%, Pacto Inovação 50%
  const projectsToInspect = projectsList.slice(0, 8)
  for (const proj of projectsToInspect) {
    const projId = parseInt(proj.id)
    if (!projId || isNaN(projId)) continue

    const showProjectQuery = `{ showProject(accountId: ${ARTIA_ACCOUNT_ID}, id: "${projId}") { id title } }`
    summary.queries_attempted++
    try {
      const data = await gql(showProjectQuery)
      if (data.errors) {
        summary.queries_failed++
        await persistDump('error', { query_variant: 'showProject', errors: data.errors }, { project_id: projId, project_name: proj.title, source_query: showProjectQuery })
        continue
      }
      summary.queries_succeeded++
      await persistDump('projects_list', data?.data?.showProject, { project_id: projId, project_name: proj.title, source_query: showProjectQuery, notes: 'showProject detail' })
    } catch (e) {
      summary.queries_failed++
    }

    await new Promise(r => setTimeout(r, 200))
  }

  // ── Step 3: For top 10 folders, sample up to 20 activities ──
  const foldersToInspect = allFolders.slice(0, 12)
  for (const folder of foldersToInspect) {
    const folderId = parseInt(folder.id)
    if (!folderId || isNaN(folderId)) continue

    const activitiesQueries = [
      { name: 'listingActivities+full', q: `{ listingActivities(accountId: ${ARTIA_ACCOUNT_ID}, folderId: ${folderId}) { id title description completedPercent customStatus { id name } } }` },
      { name: 'listingActivities+title', q: `{ listingActivities(accountId: ${ARTIA_ACCOUNT_ID}, folderId: ${folderId}) { id title } }` },
      { name: 'listingActivities+id', q: `{ listingActivities(accountId: ${ARTIA_ACCOUNT_ID}, folderId: ${folderId}) { id } }` },
    ]

    for (const variant of activitiesQueries) {
      summary.queries_attempted++
      try {
        const data = await gql(variant.q)
        if (data.errors) {
          summary.queries_failed++
          if (summary.queries_failed < 8) {
            await persistDump('error', { query_variant: variant.name, folder_title: folder.title, errors: data.errors }, { source_query: variant.q })
          }
          continue
        }
        const list = data?.data?.listingActivities ?? []
        if (Array.isArray(list)) {
          summary.queries_succeeded++
          summary.activities_sampled += list.length
          await persistDump('activities_sample', { folder_id: folderId, folder_title: folder.title, activities: list }, { source_query: variant.q, notes: `${list.length} activities in folder "${folder.title}" via ${variant.name}` })
          break
        }
      } catch (e) {
        summary.queries_failed++
      }
    }

    await new Promise(r => setTimeout(r, 200))
  }

  summary.completed_at = new Date().toISOString()
  return summary
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  // Parse mode from query params or JSON body
  const url = new URL(req.url)
  let mode = url.searchParams.get('mode') || ''
  if (!mode && req.method === 'POST') {
    try {
      const body = await req.clone().json()
      mode = body?.mode || ''
    } catch { /* ignore parse errors */ }
  }

  try {
    const sb = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // ── Introspection mode (Phase C.1.0): dump GraphQL schema fields ──
    if (mode === 'introspect') {
      const token = await getArtiaToken()
      // Query 1: list all root Query fields
      const queryFieldsRes = await fetch(ARTIA_GQL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({
          query: `{ __schema { queryType { name fields { name description args { name type { name kind ofType { name kind } } } type { name kind ofType { name kind } } } } } }`,
        }),
      })
      const queryFieldsData = await queryFieldsRes.json()
      // Query 2: list mutation fields (for context)
      const mutFieldsRes = await fetch(ARTIA_GQL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({
          query: `{ __schema { mutationType { name fields { name args { name } } } } }`,
        }),
      })
      const mutFieldsData = await mutFieldsRes.json()

      await sb.from('artia_discovery_dumps').insert({
        account_id: ARTIA_ACCOUNT_ID,
        dump_kind: 'projects_list', // overload for schema dump
        payload: { schema_query: queryFieldsData?.data, schema_mutation: mutFieldsData?.data },
        source_query: '__schema introspection',
        notes: 'Schema introspection dump — root Query and Mutation fields',
      })

      return new Response(JSON.stringify({
        mode: 'introspect',
        query_fields: queryFieldsData?.data?.__schema?.queryType?.fields?.map((f: any) => ({
          name: f.name,
          args: f.args?.map((a: any) => `${a.name}: ${a.type?.name || a.type?.ofType?.name}`),
          returns: f.type?.name || f.type?.ofType?.name,
        })) ?? [],
        mutation_fields: mutFieldsData?.data?.__schema?.mutationType?.fields?.map((f: any) => f.name) ?? [],
        errors: queryFieldsData?.errors || mutFieldsData?.errors || null,
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // ── Discovery mode (Phase C.1) ──
    if (mode === 'discover') {
      let token: string
      try {
        token = await getArtiaToken()
      } catch (e) {
        return new Response(JSON.stringify({
          mode: 'discover',
          error: 'Artia auth failed',
          details: (e as Error).message,
        }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }

      const summary = await runDiscoveryMode(sb, token)
      await sb.from('mcp_usage_log').insert({
        tool_name: 'sync-artia-discover',
        success: summary.queries_succeeded > 0,
        execution_ms: 0,
        response_summary: JSON.stringify(summary),
      })

      return new Response(JSON.stringify({ mode: 'discover', ...summary }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // ── Default mode: KPI sync (existing logic) ──
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
    // Impact hours: only count actual present (not excused)
    const { data: impactRaw } = await sb.rpc('get_impact_hours_excluding_excused')
    let impactHours = impactRaw ?? 0
    if (!impactRaw) {
      // Fallback: direct query excluding excused
      const { data: attData } = await sb.from('events')
        .select('duration_minutes, attendance(id, excused)')
        .lte('date', now)
        .gte('date', '2026-01-01')
      impactHours = 0
      for (const e of attData || []) {
        const attCount = Array.isArray(e.attendance) ? e.attendance.filter((a: any) => !a.excused).length : 0
        impactHours += ((e.duration_minutes || 0) / 60) * attCount
      }
      impactHours = Math.round(impactHours * 10) / 10
    }
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
