import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

// ── Artia GraphQL API ──
const ARTIA_GQL = 'https://api.artia.com/graphql'
const ARTIA_ACCOUNT_ID = 6345833
const ARTIA_PROJECT_ID = 6391775

// Artia activity IDs + folder per KPI
// Pre-Phase C.2.5: 9 KPIs in folder 6399649 (04 - Monitoramento e Controle root)
// Phase C.2.5 added 4 new KPIs in folder 6516663 (04.01 - KPIs Anuais 2026 sub-folder)
// NOTE: 9 existing not movable via updateActivity (Artia validates folder ownership) — they stay in 6399649
const KPI_ACTIVITY_MAP: Record<string, { id: number; label: string; folderId: number }> = {
  chapters_participating: { id: 32528756, label: 'KPI: 8 Capítulos Participantes', folderId: 6399649 },
  entities_partners: { id: 32528757, label: 'KPI: 3 Entidades Parceiras', folderId: 6399649 },
  trail_completion: { id: 32528758, label: 'KPI: 70% Trilha IA Completa', folderId: 6399649 },
  cpmai_certified: { id: 32528759, label: 'KPI: 2+ CPMAI Certificados no Ano', folderId: 6399649 },
  articles_published: { id: 32528760, label: 'KPI: 10+ Artigos Publicados', folderId: 6399649 },
  webinars_realized: { id: 32528762, label: 'KPI: 6+ Webinares ou Talks', folderId: 6399649 },
  pilots_ia_copilot: { id: 32528763, label: 'KPI: 3+ Pilotos IA Copiloto', folderId: 6399649 },
  hours_meetings: { id: 32528764, label: 'KPI: 90+ Horas de Encontros', folderId: 6399649 },
  hours_impact: { id: 32528765, label: 'KPI: 1800+ Horas de Impacto', folderId: 6399649 },
  // Phase C.2.5 — 4 new KPIs in 04.01 sub-folder (6516663)
  lim_lima_accepted: { id: 32811576, label: 'KPI: LATAM LIM Lima 2026 (Sessão Aceita)', folderId: 6516663 },
  detroit_submission: { id: 32811577, label: 'KPI: PMI Global Summit Detroit 2026 (Submissão)', folderId: 6516663 },
  ip_policy_ratified: { id: 32811578, label: 'KPI: Política IP aprovada Comitê de Curadoria', folderId: 6516663 },
  cooperation_agreements_signed: { id: 32811579, label: 'KPI: Acordos de Cooperação Bilateral assinados', folderId: 6516663 },
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
const ARTIA_RESPONSIBLE_ID = 298786 // "GP Projeto Núcleo IA"

async function updateArtiaActivity(token: string, activityId: number, pct: number, desc: string, title: string, folderId: number): Promise<boolean> {
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
      query: `mutation { changeCustomStatusActivity(id: "${activityId}", accountId: ${ARTIA_ACCOUNT_ID}, folderId: ${folderId}, customStatusId: ${targetStatus}, status: ${isClosed}) { id status } }`,
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

    // ── Backfill-risk-ids mode (Phase C.3 prep): map 11 risk activities (folder 6516562) → program_risks.artia_activity_id ──
    if (mode === 'backfill-risk-ids') {
      const RISKS_FOLDER_ID = 6516562
      const token = await getArtiaToken()
      // List activities in 04.06 Riscos folder
      const q = `{ listingActivities(accountId: ${ARTIA_ACCOUNT_ID}, folderId: ${RISKS_FOLDER_ID}) { id title } }`
      const res = await fetch(ARTIA_GQL, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({ query: q }),
      })
      const data = await res.json()
      const activities = data?.data?.listingActivities ?? []
      const matched: any[] = []
      const unmatched: any[] = []

      for (const act of activities) {
        // Title format: "R-XX: ..." — extract code
        const m = act.title?.match(/^(R-\d{2}):/)
        if (!m) { unmatched.push({ id: act.id, title: act.title }); continue }
        const riskCode = m[1]
        const { error } = await sb.from('program_risks')
          .update({ artia_activity_id: parseInt(act.id), artia_synced_at: new Date().toISOString() })
          .eq('cycle_year', 2026).eq('risk_code', riskCode)
        if (error) {
          unmatched.push({ id: act.id, title: act.title, error: error.message })
        } else {
          matched.push({ risk_code: riskCode, activity_id: act.id })
        }
      }

      return new Response(JSON.stringify({
        mode: 'backfill-risk-ids',
        activities_in_folder: activities.length,
        matched: matched.length,
        unmatched: unmatched.length,
        matched_detail: matched,
        unmatched_detail: unmatched,
      }, null, 2), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // ── Cron-daily mode (Phase C.3): updates Project.lastInformations + folder 04.04 atas tribos ──
    if (mode === 'cron-daily') {
      const NUCLEO_PROJECT_ID = 6391775
      const FOLDER_ATAS_TRIBOS = 6516561 // 04.04 - Atas de Tribos Semanais
      const FOLDER_ATAS_PLENARIAS = 6516560 // 04.03 - Atas Plenárias Mensais
      const token = await getArtiaToken()
      const result: any = { updateProject: null, atas_tribos: null, atas_plenarias: null, errors: [] }

      const escapeStr = (s: string) => s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ')

      // 1. Compute current snapshot for Project.lastInformations
      const today = new Date()
      const ymd = today.toISOString().split('T')[0]
      const yyyy = today.getUTCFullYear()
      const mm = today.getUTCMonth() + 1

      const { data: monthMetrics } = await sb.rpc('_artia_safe_monthly_metrics', { p_year: yyyy, p_month: mm })

      // Count board_items updated last 10 days (Bloco 6a "Atividades atualizadas ≤10d")
      const { count: cards10d } = await sb.from('board_items').select('id', { count: 'exact', head: true })
        .gte('updated_at', new Date(Date.now() - 10 * 86400000).toISOString())

      const lastInfo = `Status atual ${ymd}:\n` +
        `- Voluntários ativos: ${monthMetrics?.active_volunteers_total ?? 'n/a'}\n` +
        `- Iniciativas ativas: ${monthMetrics?.initiatives_active_total ?? 'n/a'}\n` +
        `- Eventos no mês ${yyyy}-${String(mm).padStart(2, '0')}: ${monthMetrics?.events_in_month ?? 0} (${monthMetrics?.duration_hours_in_month ?? 0}h)\n` +
        `- Pilotos IA ativos: ${monthMetrics?.pilots_active_total ?? 0}\n` +
        `- Atividades plataforma atualizadas últimos 10d: ${cards10d ?? 0}\n` +
        `- 7 tribos ativas (M.O.R.E. quadrantes 1-4) + 4 frentes operacionais\n` +
        `- 5 capítulos PMI parceiros (PMI-GO sponsor + CE/DF/MG/RS via Acordos Cooperação)\n` +
        `- Status governance: TAP em revisão · Política IP em revisão Comitê Curadoria · Manual aprovado 2025-12\n` +
        `(Sync automático cron sync-artia-monitoring-daily 06:00 UTC)`

      // updateProject
      try {
        const upQ = `mutation { updateProject(id: "${NUCLEO_PROJECT_ID}", accountId: ${ARTIA_ACCOUNT_ID}, lastInformations: "${escapeStr(lastInfo)}") { id name } }`
        const upRes = await fetch(ARTIA_GQL, {
          method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
          body: JSON.stringify({ query: upQ }),
        })
        const upData = await upRes.json()
        result.updateProject = upData?.errors ? { errors: upData.errors } : { ok: true, length: lastInfo.length }
      } catch (e) {
        result.errors.push({ step: 'updateProject', error: (e as Error).message })
      }

      // 2. Update folder 04.04 Atas de Tribos Semanais — last 7 days events grouped by type
      const sevenDaysAgo = new Date(Date.now() - 7 * 86400000).toISOString().split('T')[0]
      const { data: weekSummary } = await sb.rpc('_artia_safe_event_summary', { p_start_date: sevenDaysAgo, p_end_date: ymd })

      const tribosDesc = `Atas consolidadas das 7 tribos (M.O.R.E.) — semana ${sevenDaysAgo} a ${ymd}\n\n` +
        `Total eventos: ${weekSummary?.total_events ?? 0}\n` +
        `Duração total: ${weekSummary?.total_duration_hours ?? 0}h\n\n` +
        `Eventos por tipo:\n` +
        Object.entries(weekSummary?.by_type || {}).map(([type, count]) => `- ${type}: ${count}`).join('\n') +
        `\n\nÚltimos 7 eventos:\n` +
        ((weekSummary?.event_titles_sample || []).slice(0, 7).map((t: string) => `- ${t}`).join('\n')) +
        `\n\nLGPD-safe: agregados sem nomes individuais. Sync diário 06:00 UTC.`

      // Find activity inside folder 04.04 via listingActivities (idempotent — single activity inside)
      try {
        const lq = `{ listingActivities(accountId: ${ARTIA_ACCOUNT_ID}, folderId: ${FOLDER_ATAS_TRIBOS}) { id title } }`
        const lRes = await fetch(ARTIA_GQL, {
          method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
          body: JSON.stringify({ query: lq }),
        })
        const lData = await lRes.json()
        const acts = lData?.data?.listingActivities ?? []
        if (acts.length > 0) {
          const ataActId = parseInt(acts[0].id)
          const ok = await updateArtiaActivity(token, ataActId, 50, tribosDesc, 'Atas Consolidadas das 7 Tribos', FOLDER_ATAS_TRIBOS)
          result.atas_tribos = ok ? { ok: true, activity_id: ataActId, length: tribosDesc.length } : { ok: false, activity_id: ataActId }
        } else {
          result.atas_tribos = { skipped: 'no activity in folder', folder_id: FOLDER_ATAS_TRIBOS }
        }
      } catch (e) {
        result.errors.push({ step: 'atas_tribos', error: (e as Error).message })
      }

      return new Response(JSON.stringify({ mode: 'cron-daily', result }, null, 2), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // ── Cron-monthly mode (Phase C.3): generates Status Report + syncs program_risks ──
    if (mode === 'cron-monthly') {
      const STATUS_REPORT_FOLDER = 6516559 // 04.02 - Status Reports Mensais 2026
      const token = await getArtiaToken()
      const result: any = { status_report: null, risks_synced: [], errors: [] }

      const escapeStr = (s: string) => s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ')

      // 1. Compute prior month metrics
      const today = new Date()
      const lastMonth = new Date(today.getUTCFullYear(), today.getUTCMonth() - 1, 1)
      const yyyy = lastMonth.getUTCFullYear()
      const mm = lastMonth.getUTCMonth() + 1
      const reportMonth = `${yyyy}-${String(mm).padStart(2, '0')}-01`

      const { data: monthMetrics } = await sb.rpc('_artia_safe_monthly_metrics', { p_year: yyyy, p_month: mm })

      const reportBody = `# Status Report — ${yyyy}.${mm <= 6 ? '1' : '2'} Mês ${String(mm).padStart(2, '0')}\n\n` +
        `## Métricas Plataforma (LGPD-safe agregados)\n\n` +
        `- Voluntários ativos: ${monthMetrics?.active_volunteers_total ?? 'n/a'}\n` +
        `- Iniciativas ativas: ${monthMetrics?.initiatives_active_total ?? 'n/a'}\n` +
        `- Eventos no mês: ${monthMetrics?.events_in_month ?? 0}\n` +
        `- Duração horas no mês: ${monthMetrics?.duration_hours_in_month ?? 0}h\n` +
        `- Pilotos IA ativos: ${monthMetrics?.pilots_active_total ?? 0}\n` +
        `- Publicações concluídas no mês: ${monthMetrics?.publications_done_in_month ?? 0}\n\n` +
        `## Estrutura\n\n` +
        `- 5 capítulos PMI (GO sponsor + CE/DF/MG/RS via Acordos Cooperação Bilateral)\n` +
        `- 7 tribos M.O.R.E. ativas + 4 frentes operacionais\n` +
        `- Plataforma nucleoia.vitormr.dev open source no GitHub\n\n` +
        `## Próximos passos\n` +
        `- Pipeline +10 artigos / +6 webinares (TAP §16)\n` +
        `- LATAM LIM Lima Aug 2026 / PMI Global Summit Detroit Out 2026\n` +
        `- Política IP aguardando assinaturas Comitê Curadoria\n\n` +
        `Sync automático cron sync-artia-status-report-monthly (1º dia mês 07:00 UTC).`

      // 2. Persist to artia_status_reports
      try {
        await sb.from('artia_status_reports').upsert({
          cycle_year: 2026,
          report_month: reportMonth,
          body_md: reportBody,
          metrics_json: monthMetrics || {},
          generated_at: new Date().toISOString(),
          generated_by_cron: true,
        }, { onConflict: 'cycle_year,report_month' })
        result.status_report = { ok: true, length: reportBody.length, month: reportMonth }
      } catch (e) {
        result.errors.push({ step: 'persist_report', error: (e as Error).message })
      }

      // 3. Sync 11 program_risks → folder 04.06 activities (using artia_activity_id from backfill)
      const { data: risksData } = await sb.from('program_risks')
        .select('risk_code, risk_title, status, treatment, probability, impact, artia_activity_id')
        .eq('cycle_year', 2026)
        .not('artia_activity_id', 'is', null)
        .order('risk_code')

      for (const risk of risksData || []) {
        const pct = risk.status === 'mitigado' || risk.status === 'encerrado' ? 100
                  : risk.status === 'em_tratamento' ? 50 : 0
        const statusId = risk.status === 'mitigado' || risk.status === 'encerrado' ? ARTIA_STATUS.ENCERRADO
                       : risk.status === 'em_tratamento' ? ARTIA_STATUS.ANDAMENTO : ARTIA_STATUS.A_INICIAR
        const title = `${risk.risk_code}: ${risk.risk_title}`
        const desc = `[${(risk.probability || 'n/a').toUpperCase()} prob × ${(risk.impact || 'n/a').toUpperCase()} impacto] Status: ${risk.status}. Tratamento: ${risk.treatment}. Sync: ${new Date().toISOString().split('T')[0]}.`

        try {
          const ok = await updateArtiaActivity(token, risk.artia_activity_id, pct, desc, title, 6516562)
          if (ok) {
            result.risks_synced.push({ risk_code: risk.risk_code, activity_id: risk.artia_activity_id, pct, status: risk.status })
            await sb.from('program_risks')
              .update({ artia_synced_at: new Date().toISOString() })
              .eq('risk_code', risk.risk_code).eq('cycle_year', 2026)
          } else {
            result.errors.push({ step: 'sync_risk', risk_code: risk.risk_code })
          }
        } catch (e) {
          result.errors.push({ step: 'sync_risk_exception', risk_code: risk.risk_code, error: (e as Error).message })
        }
        await new Promise(r => setTimeout(r, 300))
      }

      return new Response(JSON.stringify({ mode: 'cron-monthly', result }, null, 2), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // ── Move-9-KPIs mode (Phase C.2.5 fix): retry moves with title arg required by Artia ──
    if (mode === 'move-9-kpis') {
      const NEW_FOLDER_ID = 6516663 // 04.01 - KPIs Anuais 2026 (created in prior run)
      const token = await getArtiaToken()
      const result: any = { moved: [], errors: [] }

      const escapeStr = (s: string) => s.replace(/\\/g, '\\\\').replace(/"/g, '\\"')

      for (const [kpiKey, mapping] of Object.entries(KPI_ACTIVITY_MAP)) {
        // updateActivity requires title arg (mandatory per Artia schema)
        const moveQuery = `mutation { updateActivity(id: "${mapping.id}", accountId: ${ARTIA_ACCOUNT_ID}, folderId: ${NEW_FOLDER_ID}, title: "${escapeStr(mapping.label)}") { id title } }`
        try {
          const res = await fetch(ARTIA_GQL, {
            method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
            body: JSON.stringify({ query: moveQuery }),
          })
          const data = await res.json()
          if (data?.errors) {
            result.errors.push({ kpi: kpiKey, errors: data.errors })
          } else {
            result.moved.push({ kpi_key: kpiKey, activity_id: mapping.id, new_folder: NEW_FOLDER_ID })
          }
        } catch (e) {
          result.errors.push({ kpi: kpiKey, exception: (e as Error).message })
        }
        await new Promise(r => setTimeout(r, 300))
      }

      return new Response(JSON.stringify({ mode: 'move-9-kpis', result }, null, 2), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // ── Reorganize-KPIs mode (Phase C.2.5): create sub-folder 04.01 + move 9 + create 4 new KPIs ──
    if (mode === 'reorganize-kpis') {
      const dryRun = url.searchParams.get('dry_run') !== 'false'
      const token = await getArtiaToken()
      const result: any = { folder: null, moved: [], created: [], errors: [] }

      const escapeStr = (s: string) => s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ')

      // Step 1: Create sub-folder 04.01-KPIs Anuais 2026 under existing 04 Monitoramento (6399649)
      const newFolderName = '04.01 - KPIs Anuais 2026'
      const folderQuery = `mutation { createFolder(name: "${newFolderName}", parentId: 6399649, accountId: ${ARTIA_ACCOUNT_ID}, completedPercent: 0) { id name } }`

      if (dryRun) {
        // Dry-run preview
        return new Response(JSON.stringify({
          mode: 'reorganize-kpis',
          dry_run: true,
          plan: {
            step_1_create_folder: { name: newFolderName, parentId: 6399649 },
            step_2_move_activities: Object.entries(KPI_ACTIVITY_MAP).map(([k, v]) => ({ kpi_key: k, activity_id: v.id, target: 'NEW_FOLDER' })),
            step_3_create_new: ['lim_lima_accepted', 'detroit_submission', 'ip_policy_ratified', 'cooperation_agreements_signed'],
            total_mutations_estimate: 1 + 9 + 4,
          },
        }, null, 2), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }

      // LIVE: Step 1 — create folder
      try {
        const fRes = await fetch(ARTIA_GQL, {
          method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
          body: JSON.stringify({ query: folderQuery }),
        })
        const fData = await fRes.json()
        if (fData?.errors) {
          result.errors.push({ step: 'createFolder', errors: fData.errors })
          return new Response(JSON.stringify({ mode: 'reorganize-kpis', dry_run: false, result }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
        }
        const newFolderId = parseInt(fData?.data?.createFolder?.id)
        result.folder = { id: newFolderId, name: newFolderName }

        await sb.from('artia_discovery_dumps').insert({
          account_id: ARTIA_ACCOUNT_ID, project_id: 6391775, project_name: 'Núcleo de IA & GP',
          dump_kind: 'folders_list',
          payload: { code: '04.01', id: newFolderId, name: newFolderName, parent_id: 6399649 },
          source_query: folderQuery.slice(0, 500), notes: 'Phase C.2.5 sub-folder 04.01-KPIs',
        })

        await new Promise(r => setTimeout(r, 400))

        // Step 2: Move 9 existing KPI activities to new sub-folder via updateActivity(folderId=NEW)
        for (const [kpiKey, mapping] of Object.entries(KPI_ACTIVITY_MAP)) {
          const moveQuery = `mutation { updateActivity(id: "${mapping.id}", accountId: ${ARTIA_ACCOUNT_ID}, folderId: ${newFolderId}) { id title } }`
          try {
            const mRes = await fetch(ARTIA_GQL, {
              method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
              body: JSON.stringify({ query: moveQuery }),
            })
            const mData = await mRes.json()
            if (mData?.errors) {
              result.errors.push({ step: 'moveKPI', kpi: kpiKey, errors: mData.errors })
            } else {
              result.moved.push({ kpi_key: kpiKey, activity_id: mapping.id, new_folder: newFolderId })
            }
          } catch (e) {
            result.errors.push({ step: 'moveKPI exception', kpi: kpiKey, error: (e as Error).message })
          }
          await new Promise(r => setTimeout(r, 300))
        }

        // Step 3: Create 4 new KPI activities in new sub-folder
        const newKpis = [
          { key: 'lim_lima_accepted', title: 'KPI: LATAM LIM Lima 2026 (1/1 sessão aceita)', desc: 'TAP §16 Critério 10. Sessão aceita para apresentação Agosto 2026 em Lima/Peru.', pct: 100, status: ARTIA_STATUS.ENCERRADO },
          { key: 'detroit_submission', title: 'KPI: PMI Global Summit Detroit 2026 (0/1 em planejamento)', desc: 'TAP §16 Critério 11. Submissão em planejamento para Outubro 2026 em Detroit/EUA.', pct: 0, status: ARTIA_STATUS.A_INICIAR },
          { key: 'ip_policy_ratified', title: 'KPI: Política IP aprovada Comitê (em revisão — 6 chains v6/v5/v1)', desc: 'TAP §16 Critério 12. Doc cfb15185 status under_review. Aguardando assinaturas Roberto/Sarah/Fabricio.', pct: 75, status: ARTIA_STATUS.ANDAMENTO },
          { key: 'cooperation_agreements_signed', title: 'KPI: Acordos Cooperação Bilateral (4/4 assinados)', desc: 'TAP §16 Critério 13. PMI-GO ↔ PMI-CE/DF/MG/RS. 4/4 assinados. Drive PMI-GO institucional.', pct: 100, status: ARTIA_STATUS.ENCERRADO },
        ]

        for (const k of newKpis) {
          const createQuery = `mutation { createActivity(title: "${escapeStr(k.title)}", folderId: ${newFolderId}, accountId: ${ARTIA_ACCOUNT_ID}, responsibleId: ${ARTIA_RESPONSIBLE_ID}, description: "${escapeStr(k.desc)}", completedPercent: ${k.pct}, customStatusId: ${k.status}) { id title } }`
          try {
            const cRes = await fetch(ARTIA_GQL, {
              method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
              body: JSON.stringify({ query: createQuery }),
            })
            const cData = await cRes.json()
            if (cData?.errors) {
              result.errors.push({ step: 'createNewKPI', kpi: k.key, errors: cData.errors })
            } else {
              const actId = parseInt(cData?.data?.createActivity?.id)
              result.created.push({ kpi_key: k.key, activity_id: actId, folder_id: newFolderId })
            }
          } catch (e) {
            result.errors.push({ step: 'createNewKPI exception', kpi: k.key, error: (e as Error).message })
          }
          await new Promise(r => setTimeout(r, 300))
        }

      } catch (e) {
        result.errors.push({ step: 'overall', error: (e as Error).message })
      }

      return new Response(JSON.stringify({ mode: 'reorganize-kpis', dry_run: false, result }, null, 2), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // ── Create-structure mode (Phase C.2): build WBS folders + activities under Núcleo project ──
    if (mode === 'create-structure') {
      const dryRun = url.searchParams.get('dry_run') !== 'false' // default true (safe)
      const token = await getArtiaToken()

      // Núcleo project + known top-level folders (per discovery findings)
      const NUCLEO_PROJECT_ID = 6391775
      const NUCLEO_TOP_FOLDERS: Record<string, number> = {
        iniciacao: 6391776,      // 01 - Iniciação (confirmed)
        planejamento: 6391777,   // 02 - Planejamento (confirmed)
        execucao: 6399648,       // 03 - Execução (assumed — page 2 listing match)
        monitoramento: 6399649,  // 04 - Monitoramento e Controle (confirmed = ARTIA_KPI_FOLDER)
        encerramento: 6399650,   // 05 - Encerramento (assumed — page 2 listing match)
      }

      // Define structure plan: 15 sub-folders + ~30 activities
      type ActivitySpec = { title: string; description: string; statusId: number; completedPercent: number; recurrence?: 'weekly'|'monthly' }
      type FolderSpec = { code: string; parent: keyof typeof NUCLEO_TOP_FOLDERS; name: string; activities: ActivitySpec[] }

      const STRUCTURE_PLAN: FolderSpec[] = [
        // ── Iniciação ──
        { code: '01.01', parent: 'iniciacao', name: '01.01 - Termo de Abertura do Projeto (TAP)', activities: [
          { title: 'Elaborar TAP Ciclo 3 (2026.1)', description: 'TAP elaborado 2026-05-05 por Vitor Maia Rodovalho (GP). Drive: docs/TAP_CICLO3_2026.md no repo + Google Doc institucional em Núcleo IA & GP/2026/1. Iniciação/. Versão 1.0 (draft inicial). 18 seções + Apêndice A + Apêndice B.', statusId: ARTIA_STATUS.ENCERRADO, completedPercent: 100 },
          { title: 'Revisar TAP', description: 'Revisão técnica realizada por Vitor + análise estrutural via 7 confirmações PM (Tribos pausadas / sponsors / Política IP independente). Pronto para aprovação.', statusId: ARTIA_STATUS.ENCERRADO, completedPercent: 100 },
          { title: 'Aprovar TAP — Sponsor PMI-GO', description: 'Aguardando assinatura Ivan Lourenço (Presidente PMI-GO). Capítulo informal — assinatura formal não-bloqueante per PM directive 2026-05-05.', statusId: ARTIA_STATUS.ANDAMENTO, completedPercent: 50 },
          { title: 'Anexar TAP no Drive Institucional', description: 'TAP arquivado em Drive PMI-GO institucional Núcleo IA & GP/2026/1. Iniciação/ (Google Doc). Histórico fundacional 2024 preservado em zArchive.', statusId: ARTIA_STATUS.ENCERRADO, completedPercent: 100 },
        ]},
        { code: '01.02', parent: 'iniciacao', name: '01.02 - Registro das Partes Interessadas', activities: [
          { title: 'Matriz RACI consolidada — TAP §14', description: 'Sponsors (Ivan + 4 capítulos parceiros via Acordos Cooperação) + GP Vitor + Vice-GP Fabricio + Comitê Curadoria (Roberto/Sarah/Fabricio) + 7 líderes de tribo + Coordenação CPMAI Herlon + 48 voluntários + stakeholders externos (PMI Latam Natália, PMI Global PMI×AI Champion).', statusId: ARTIA_STATUS.ENCERRADO, completedPercent: 100 },
        ]},
        { code: '01.03', parent: 'iniciacao', name: '01.03 - Reunião de Kick-off Ciclo 3 (2026.1)', activities: [
          { title: 'Kick-off realizado 2026-03-05 17:15', description: 'Evento de Abertura Ciclo 3 (2026/1) realizado em 2026-03-05 às 17:15 EST. Drive recording: Núcleo IA & GP/2026/1. Iniciação/Kick-off Ciclo 3/. Migração da pasta Calendar event Drive pessoal → institucional realizada 2026-05-05.', statusId: ARTIA_STATUS.ENCERRADO, completedPercent: 100 },
        ]},
        { code: '01.04', parent: 'iniciacao', name: '01.04 - Templates Institucionais', activities: [
          { title: 'TAP institucional Ciclo 3 (2026.1)', description: 'Template PMI-GO 18 seções + Apêndices A/B. Localização: docs/TAP_CICLO3_2026.md (markdown source) + Google Doc institucional Drive.', statusId: ARTIA_STATUS.ENCERRADO, completedPercent: 100 },
          { title: 'Manual de Governança', description: 'Aprovado 2025-12 (Ciclo 2). Localização: Drive PMI-GO institucional. Próxima revisão: trimestral pós-aprovação TAP ou demanda mudança escopo material.', statusId: ARTIA_STATUS.ENCERRADO, completedPercent: 100 },
          { title: 'Política Institucional de Publicação e IP', description: 'Em revisão pelo Comitê de Curadoria (6 chains v6/v5/v1 em review aguardando assinaturas Roberto/Sarah/Fabricio). Independente do TAP — paralelo. Localização: instrumentos-ip/ + plataforma /governance.', statusId: ARTIA_STATUS.ANDAMENTO, completedPercent: 75 },
          { title: 'Acordos de Cooperação Bilateral (4)', description: '4/4 assinados: PMI-GO ↔ PMI-CE / DF / MG / RS. Drive PMI-GO institucional. Cobre adesão dos demais capítulos sem necessidade de assinatura no TAP.', statusId: ARTIA_STATUS.ENCERRADO, completedPercent: 100 },
        ]},
        // ── Planejamento ──
        { code: '02.01', parent: 'planejamento', name: '02.01 - Planejar Orçamento Ciclo 3', activities: [
          { title: 'Orçamento R$ 0,00 — operação voluntária', description: 'Operação 100% voluntária. Sem orçamento dedicado de salários, contratações ou compras. Recursos via voluntários PMI + PMI-GO sponsor (infraestrutura). Eventuais participações em LIM Lima/Detroit Summit custeadas individualmente.', statusId: ARTIA_STATUS.ENCERRADO, completedPercent: 100 },
        ]},
        { code: '02.02', parent: 'planejamento', name: '02.02 - Planejar Voluntários', activities: [
          { title: 'Processo seletivo metrificado — 48 voluntários ativos', description: 'Processo seletivo Ciclo 3 estruturado dentro da plataforma nucleoia.vitormr.dev. 33 candidatos em processo + 26 ativos + 6 inativados + 31 não selecionados. 3 vagas centralizadas IDs 64966/6497/66470.', statusId: ARTIA_STATUS.ENCERRADO, completedPercent: 80 },
        ]},
        { code: '02.03', parent: 'planejamento', name: '02.03 - Planejar Cronograma Anual 2026', activities: [
          { title: 'Cronograma Q1-Q4 — TAP §9 e §10', description: '16 marcos principais 2026: TAP aprovação Mai · Política IP Comitê Mai · LIM Lima Ago · Detroit Out · Lições aprendidas Dez · Pipeline 10 artigos + 6 webinares + 3 pilotos contínuo.', statusId: ARTIA_STATUS.ENCERRADO, completedPercent: 100 },
        ]},
        { code: '02.04', parent: 'planejamento', name: '02.04 - Planejar Publicações', activities: [
          { title: 'Pipeline +10 artigos publicados 2026', description: 'Meta TAP §16: 10 artigos publicados (revistas, ProjectManagement.com, blogs PMI). Atual 0/10. Pipeline ativo via 7 tribos + Comitê de Curadoria.', statusId: ARTIA_STATUS.ANDAMENTO, completedPercent: 0 },
        ]},
        { code: '02.05', parent: 'planejamento', name: '02.05 - Planejar Webinares e Eventos Externos', activities: [
          { title: 'Pipeline +6 webinares 2026 H2', description: 'Meta TAP §16: 6 webinares + Talks. Atual 0/6. + LIM Lima Aug 2026 (sessão aceita) + Detroit Out 2026 (submissão em planejamento).', statusId: ARTIA_STATUS.ANDAMENTO, completedPercent: 0 },
        ]},
        // ── Monitoramento e Controle ──
        { code: '04.02', parent: 'monitoramento', name: '04.02 - Status Reports Mensais 2026', activities: [
          { title: 'Status Report Mensal — Ciclo 3 (2026)', description: 'Status report mensal gerado automaticamente via cron sync-artia-status-report-monthly (1º dia do mês 07:00 UTC). Fonte: _artia_safe_monthly_metrics + cycle_evolution + weekly_member_digest. LGPD-safe: agregados, sem PII.', statusId: ARTIA_STATUS.ANDAMENTO, completedPercent: 0, recurrence: 'monthly' },
        ]},
        { code: '04.03', parent: 'monitoramento', name: '04.03 - Atas Plenárias Mensais', activities: [
          { title: 'Ata Plenária Mensal — Ciclo 3', description: 'Ata da reunião plenária mensal do programa. Atualizada via cron sync-artia-rituals-weekly (Seg 08:00 UTC). LGPD-safe: lista por roles agregados, sem nomes individuais.', statusId: ARTIA_STATUS.ANDAMENTO, completedPercent: 0, recurrence: 'monthly' },
        ]},
        { code: '04.04', parent: 'monitoramento', name: '04.04 - Atas de Tribos Semanais', activities: [
          { title: 'Atas Consolidadas das 7 Tribos', description: 'Resumo semanal das reuniões de 7 tribos ativas (Radar Tec / Agentes Autônomos / Cultura&Change / Talentos / ROI&Portfólio / Governança / Inclusão). Atualizada via cron sync-artia-rituals-weekly. LGPD-safe.', statusId: ARTIA_STATUS.ANDAMENTO, completedPercent: 0, recurrence: 'weekly' },
        ]},
        { code: '04.06', parent: 'monitoramento', name: '04.06 - Riscos do Programa 2026', activities: [
          // 11 risks loaded dynamically from program_risks table at execution time
        ]},
        // ── Encerramento ──
        { code: '05.01', parent: 'encerramento', name: '05.01 - Lições Aprendidas Ciclo 3', activities: [
          { title: 'Reunião de Lições Aprendidas — Dezembro 2026', description: 'Programada para 2026-12-10 (TAP §9). Encerramento Ciclo 3.', statusId: ARTIA_STATUS.A_INICIAR, completedPercent: 0 },
          { title: 'Documento de Lições Aprendidas Consolidado', description: 'A elaborar 2026-12-10 a 2026-12-15. Cobertura PMO Audit Bloco 7 (Lições Aprendidas N/A em ciclo ativo).', statusId: ARTIA_STATUS.A_INICIAR, completedPercent: 0 },
        ]},
        { code: '05.02', parent: 'encerramento', name: '05.02 - Termo de Encerramento (TEP) Ciclo 3', activities: [
          { title: 'Elaborar TEP', description: 'Termo de Encerramento do Projeto Ciclo 3. A elaborar em Dez/2026.', statusId: ARTIA_STATUS.A_INICIAR, completedPercent: 0 },
          { title: 'Aprovar TEP', description: 'Aprovação Sponsor PMI-GO + transição para Ciclo 4 (2027).', statusId: ARTIA_STATUS.A_INICIAR, completedPercent: 0 },
        ]},
      ]

      // Load 11 risks dynamically from DB (LGPD-safe — no PII)
      const { data: risksData } = await sb.from('program_risks')
        .select('risk_code, risk_title, cause, consequence, treatment, status, probability, impact, responsible_role')
        .eq('cycle_year', 2026)
        .order('risk_code')
      const riskActivities: ActivitySpec[] = (risksData || []).map((r: any) => ({
        title: `${r.risk_code}: ${r.risk_title}`,
        description: `[${(r.probability || 'n/a').toUpperCase()} prob × ${(r.impact || 'n/a').toUpperCase()} impacto] Causa: ${r.cause}\nConsequência: ${r.consequence}\nTratamento: ${r.treatment}\nResponsável: ${r.responsible_role || 'n/a'}\nStatus: ${r.status}`,
        statusId: r.status === 'mitigado' || r.status === 'encerrado' ? ARTIA_STATUS.ENCERRADO
                : r.status === 'em_tratamento' ? ARTIA_STATUS.ANDAMENTO
                : ARTIA_STATUS.A_INICIAR,
        completedPercent: r.status === 'mitigado' ? 100 : r.status === 'em_tratamento' ? 50 : r.status === 'encerrado' ? 100 : 0,
      }))
      // Inject risks into 04.06 folder spec
      const risksFolder = STRUCTURE_PLAN.find(f => f.code === '04.06')
      if (risksFolder) risksFolder.activities = riskActivities

      // ── Project metadata update plan ──
      const PROJECT_METADATA = {
        description: 'Núcleo de Estudos e Pesquisa em IA & GP — Ciclo 3 (2026). Programa voluntário inter-capítulos PMI Brasil sediado no PMI Goiás. 5 capítulos parceiros (PMI-GO/CE/DF/MG/RS), 7 tribos M.O.R.E., 48 voluntários ativos, plataforma própria nucleoia.vitormr.dev. Concebido 2024-03 (PMI-GO + Antonio Marcos GP), GP atual Vitor Maia Rodovalho desde 2024-04.',
        justification: 'PMI Global tem direcionado sinalização forte para AI (PMI×AI Champion, Detroit 2026, publicações). Núcleo atua como catalisador nacional (potencialmente internacional) reunindo voluntários selecionados. Estrutura comunitária replicável + alinhada framework M.O.R.E. + tripé sustentabilidade.',
        premise: 'Adesão capítulos PMI parceiros via Acordos Cooperação · apoio diretorias PMI-GO · filiação PMI dos voluntários · reuniões mensais por tribo + plenárias mensais · revisão Comitê de Curadoria · Vice-GP designado mitiga single-point-of-failure · plataforma nucleoia.vitormr.dev como tool operacional.',
        restriction: 'Não realização eventos em datas conflito calendário PMI-GO · operação 100% voluntária (sem orçamento) · LGPD compliance produção conteúdo · disclaimer PMI® obrigatório · aprovações externas via canal PMI-GO → PMI Latam → PMI Global · submissões via Comitê de Curadoria.',
        lastInformations: `Status atual ${new Date().toISOString().split('T')[0]}: Ciclo 3 em execução · 5 capítulos ativos · 7 tribos · 48 voluntários · 13 iniciativas ativas · TAP v1.0 elaborado aguardando assinatura · Política IP em revisão (6 chains) · LIM Lima Aug aceita · Detroit Out em planejamento · Auditoria PMO 17% → plano remediação Phase C ativo.`,
      }

      // ── Plan summary ──
      const totalFolders = STRUCTURE_PLAN.length
      const totalActivities = STRUCTURE_PLAN.reduce((s, f) => s + f.activities.length, 0)

      if (dryRun) {
        return new Response(JSON.stringify({
          mode: 'create-structure',
          dry_run: true,
          plan_summary: {
            project_metadata_update: 'updateProject(NUCLEO 6391775) — description/justification/premise/restriction/lastInformations',
            folders_to_create: totalFolders,
            activities_to_create: totalActivities,
            risks_loaded_from_db: riskActivities.length,
          },
          project_metadata: PROJECT_METADATA,
          structure_plan: STRUCTURE_PLAN,
        }, null, 2), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      // ── Live execution ──
      const created: any = { folders: [], activities: [], errors: [], updateProject: null }

      // 1. Update Project metadata
      try {
        const escapeStr = (s: string) => s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ')
        const updateProjectQuery = `mutation { updateProject(id: "${NUCLEO_PROJECT_ID}", accountId: ${ARTIA_ACCOUNT_ID}, description: "${escapeStr(PROJECT_METADATA.description)}", justification: "${escapeStr(PROJECT_METADATA.justification)}", premise: "${escapeStr(PROJECT_METADATA.premise)}", restriction: "${escapeStr(PROJECT_METADATA.restriction)}", lastInformations: "${escapeStr(PROJECT_METADATA.lastInformations)}") { id name } }`
        const res = await fetch(ARTIA_GQL, {
          method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
          body: JSON.stringify({ query: updateProjectQuery }),
        })
        const data = await res.json()
        created.updateProject = data?.errors ? { errors: data.errors } : { ok: true, id: data?.data?.updateProject?.id }
      } catch (e) {
        created.errors.push({ step: 'updateProject', error: (e as Error).message })
      }

      // 2. createFolder for each + createActivity for each child
      const escSimple = (s: string) => s.replace(/"/g, '\\"').replace(/\n/g, ' ').slice(0, 4500) // safety cap

      for (const folder of STRUCTURE_PLAN) {
        const parentId = NUCLEO_TOP_FOLDERS[folder.parent]
        const folderQuery = `mutation { createFolder(name: "${folder.name.replace(/"/g, '\\"')}", parentId: ${parentId}, accountId: ${ARTIA_ACCOUNT_ID}, completedPercent: 0) { id name } }`
        try {
          const res = await fetch(ARTIA_GQL, {
            method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
            body: JSON.stringify({ query: folderQuery }),
          })
          const data = await res.json()
          if (data?.errors) {
            created.errors.push({ step: 'createFolder', folder: folder.name, errors: data.errors })
            continue
          }
          const folderId = parseInt(data?.data?.createFolder?.id)
          created.folders.push({ code: folder.code, name: folder.name, id: folderId })

          // Persist back to artia_discovery_dumps for audit
          await sb.from('artia_discovery_dumps').insert({
            account_id: ARTIA_ACCOUNT_ID,
            project_id: NUCLEO_PROJECT_ID,
            project_name: 'Núcleo de IA & GP',
            dump_kind: 'folders_list',
            payload: { code: folder.code, id: folderId, name: folder.name, parent_id: parentId },
            source_query: folderQuery.slice(0, 500),
            notes: `Phase C.2 createFolder ${folder.code}`,
          })

          await new Promise(r => setTimeout(r, 400)) // rate limit safety

          // 3. Create activities under this new folder
          for (const act of folder.activities) {
            const actQuery = `mutation { createActivity(title: "${escSimple(act.title)}", folderId: ${folderId}, accountId: ${ARTIA_ACCOUNT_ID}, responsibleId: ${ARTIA_RESPONSIBLE_ID}, description: "${escSimple(act.description)}", completedPercent: ${act.completedPercent}, customStatusId: ${act.statusId}) { id title } }`
            try {
              const aRes = await fetch(ARTIA_GQL, {
                method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
                body: JSON.stringify({ query: actQuery }),
              })
              const aData = await aRes.json()
              if (aData?.errors) {
                created.errors.push({ step: 'createActivity', folder: folder.code, title: act.title, errors: aData.errors })
              } else {
                const actId = parseInt(aData?.data?.createActivity?.id)
                created.activities.push({ folder_code: folder.code, folder_id: folderId, activity_id: actId, title: act.title })
              }
            } catch (e) {
              created.errors.push({ step: 'createActivity exception', error: (e as Error).message })
            }
            await new Promise(r => setTimeout(r, 300))
          }
        } catch (e) {
          created.errors.push({ step: 'createFolder exception', folder: folder.name, error: (e as Error).message })
        }
      }

      await sb.from('mcp_usage_log').insert({
        tool_name: 'sync-artia-create-structure',
        success: created.errors.length === 0,
        execution_ms: 0,
        response_summary: JSON.stringify({ folders_created: created.folders.length, activities_created: created.activities.length, errors: created.errors.length }),
      })

      return new Response(JSON.stringify({
        mode: 'create-structure',
        dry_run: false,
        result: created,
      }, null, 2), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // ── Introspect-types mode (Phase C.1.7): dump Activity/Comment type schemas + key mutation args ──
    if (mode === 'introspect-types') {
      const token = await getArtiaToken()
      const typesToInspect = ['Activity', 'Comment', 'Project', 'Folder', 'CustomStatus', 'TimeEntry']
      const typeData: Record<string, any> = {}
      for (const t of typesToInspect) {
        const res = await fetch(ARTIA_GQL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
          body: JSON.stringify({
            query: `{ __type(name: "${t}") { fields { name type { name kind ofType { name kind } } } } }`,
          }),
        })
        const data = await res.json()
        typeData[t] = data?.data?.__type?.fields?.map((f: any) => `${f.name}: ${f.type?.name || f.type?.ofType?.name || 'list'}`) ?? null
      }

      // Inspect key mutation args
      const mutationsToInspect = ['createActivity', 'updateActivity', 'createComment', 'createFolder', 'updateFolder']
      const mutationData: Record<string, any> = {}
      for (const m of mutationsToInspect) {
        const res = await fetch(ARTIA_GQL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
          body: JSON.stringify({
            query: `{ __schema { mutationType { fields(includeDeprecated: false) { name args { name type { name kind ofType { name kind } } } } } } }`,
          }),
        })
        const data = await res.json()
        const fields = data?.data?.__schema?.mutationType?.fields ?? []
        const target = fields.find((f: any) => f.name === m)
        if (target) mutationData[m] = target.args.map((a: any) => `${a.name}: ${a.type?.name || a.type?.ofType?.name || a.type?.kind}`)
      }

      await sb.from('artia_discovery_dumps').insert({
        account_id: ARTIA_ACCOUNT_ID,
        dump_kind: 'projects_list',
        payload: { types: typeData, mutations: mutationData },
        source_query: '__type Activity/Comment/etc + mutation args',
        notes: 'introspect-types comprehensive dump',
      })

      return new Response(JSON.stringify({
        mode: 'introspect-types',
        types: typeData,
        mutation_args: mutationData,
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // ── Show-childs mode (Phase C.1.6): confirm folder structure per project via showProject.childs ──
    if (mode === 'show-childs') {
      const token = await getArtiaToken()
      const knownProjects = [
        { id: 6391775, name: 'Núcleo de IA & GP' },
        { id: 6354910, name: 'PMLab' },
        { id: 6399637, name: 'Programa PMThanks' },
        { id: 6399640, name: 'Student Club' },
      ]
      const results: any[] = []

      // Try various childs query shapes
      const childsQueryVariants = [
        `{ showProject(accountId: ${ARTIA_ACCOUNT_ID}, id: "PROJID") { id name childs { edges { node { ... on Folder { id name } } } } } }`,
        `{ showProject(accountId: ${ARTIA_ACCOUNT_ID}, id: "PROJID") { id name childs { id name } } }`,
        `{ showProject(accountId: ${ARTIA_ACCOUNT_ID}, id: "PROJID") { id name } }`,
      ]

      for (const proj of knownProjects) {
        let success = false
        for (const tmpl of childsQueryVariants) {
          const q = tmpl.replace('PROJID', String(proj.id))
          const res = await fetch(ARTIA_GQL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
            body: JSON.stringify({ query: q }),
          })
          const data = await res.json()
          if (!data.errors) {
            results.push({ project: proj.name, project_id: proj.id, query: q, response: data?.data?.showProject })
            await sb.from('artia_discovery_dumps').insert({
              account_id: ARTIA_ACCOUNT_ID,
              project_id: proj.id,
              project_name: proj.name,
              dump_kind: 'projects_list',
              payload: data?.data?.showProject,
              source_query: q,
              notes: `show-childs project ${proj.name}`,
            })
            success = true
            break
          }
        }
        if (!success) {
          results.push({ project: proj.name, project_id: proj.id, error: 'all variants failed' })
        }
        await new Promise(r => setTimeout(r, 200))
      }

      // Also test scope: try to access a hypothetical project ID we don't see in listing
      const hiddenIdTests = ['9999999', '1', '6390000', '6400000']
      const hiddenResults: any[] = []
      for (const hid of hiddenIdTests) {
        const q = `{ showProject(accountId: ${ARTIA_ACCOUNT_ID}, id: "${hid}") { id name } }`
        const res = await fetch(ARTIA_GQL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
          body: JSON.stringify({ query: q }),
        })
        const data = await res.json()
        hiddenResults.push({ id: hid, errors: data.errors, data: data?.data?.showProject })
        await new Promise(r => setTimeout(r, 200))
      }

      return new Response(JSON.stringify({
        mode: 'show-childs',
        known_projects_results: results,
        hidden_id_scope_tests: hiddenResults,
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // ── Verify-access mode (Phase C.1.5): test if other PMI-GO projects exist beyond our visible 4 ──
    if (mode === 'verify-access') {
      const token = await getArtiaToken()
      const findings: any = { pages_tried: [], folders_per_page: {}, total_folders: 0, project_ids_inferred: new Set<number>(), folder_type_fields: null, project_type_fields: null }

      // 1. Paginate listingFolders to discover all folders in account
      for (let page = 1; page <= 10; page++) {
        const q = `{ listingFolders(accountId: ${ARTIA_ACCOUNT_ID}, page: ${page}) { id name } }`
        const res = await fetch(ARTIA_GQL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
          body: JSON.stringify({ query: q }),
        })
        const data = await res.json()
        const list = data?.data?.listingFolders ?? []
        findings.pages_tried.push(page)
        findings.folders_per_page[`page_${page}`] = list.length
        if (list.length === 0) break
        findings.total_folders += list.length
        await sb.from('artia_discovery_dumps').insert({
          account_id: ARTIA_ACCOUNT_ID,
          dump_kind: 'folders_list',
          payload: list,
          source_query: q,
          notes: `verify-access page ${page} (${list.length} folders)`,
        })
        // Brief rate limit
        await new Promise(r => setTimeout(r, 300))
      }

      // 2. Introspect Folder type fields
      const folderTypeRes = await fetch(ARTIA_GQL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({
          query: `{ __type(name: "Folder") { fields { name type { name kind ofType { name kind } } } } }`,
        }),
      })
      const folderTypeData = await folderTypeRes.json()
      findings.folder_type_fields = folderTypeData?.data?.__type?.fields ?? null

      // 3. Introspect Project type fields
      const projectTypeRes = await fetch(ARTIA_GQL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({
          query: `{ __type(name: "Project") { fields { name type { name kind ofType { name kind } } } } }`,
        }),
      })
      const projectTypeData = await projectTypeRes.json()
      findings.project_type_fields = projectTypeData?.data?.__type?.fields ?? null

      await sb.from('artia_discovery_dumps').insert({
        account_id: ARTIA_ACCOUNT_ID,
        dump_kind: 'projects_list',
        payload: { folder_type: findings.folder_type_fields, project_type: findings.project_type_fields },
        source_query: '__type Folder + __type Project',
        notes: 'verify-access type introspection',
      })

      return new Response(JSON.stringify({
        mode: 'verify-access',
        pages_tried: findings.pages_tried,
        folders_per_page: findings.folders_per_page,
        total_folders: findings.total_folders,
        folder_type_fields: findings.folder_type_fields?.map((f: any) => `${f.name}: ${f.type?.name || f.type?.ofType?.name}`),
        project_type_fields: findings.project_type_fields?.map((f: any) => `${f.name}: ${f.type?.name || f.type?.ofType?.name}`),
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

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

    // ── Phase C.2.5 — 4 new KPIs (read manual values from annual_kpi_targets, auto-update ip_policy from governance_documents) ──

    // 10. LIM Lima accepted (manual=1)
    const { data: limData } = await sb.from('annual_kpi_targets')
      .select('current_value, target_value')
      .eq('kpi_key', 'lim_lima_accepted').eq('cycle', 3).maybeSingle()
    const limCurrent = Number(limData?.current_value ?? 1)
    const limTarget = Number(limData?.target_value ?? 1)
    results.lim_lima_accepted = { current: limCurrent, pct: Math.round((limCurrent / limTarget) * 100), synced: false }

    // 11. Detroit submission (manual=0 currently, in_planning)
    const { data: detData } = await sb.from('annual_kpi_targets')
      .select('current_value, target_value')
      .eq('kpi_key', 'detroit_submission').eq('cycle', 3).maybeSingle()
    const detCurrent = Number(detData?.current_value ?? 0)
    const detTarget = Number(detData?.target_value ?? 1)
    results.detroit_submission = { current: detCurrent, pct: Math.round((detCurrent / detTarget) * 100), synced: false }

    // 12. IP Policy ratified (auto from governance_documents.current_ratified_at)
    const { data: ipDoc } = await sb.from('governance_documents')
      .select('current_ratified_at')
      .eq('id', 'cfb15185-2800-4441-9ff1-f36096e83aa8')
      .maybeSingle()
    const ipRatified = ipDoc?.current_ratified_at ? 1 : 0
    // Auto-update annual_kpi_targets to reflect ratification state
    await sb.from('annual_kpi_targets')
      .update({ current_value: ipRatified, updated_at: new Date().toISOString() })
      .eq('kpi_key', 'ip_policy_ratified').eq('cycle', 3)
    results.ip_policy_ratified = { current: ipRatified, pct: ipRatified === 1 ? 100 : 75, synced: false }

    // 13. Cooperation agreements signed (manual=4)
    const { data: coopData } = await sb.from('annual_kpi_targets')
      .select('current_value, target_value')
      .eq('kpi_key', 'cooperation_agreements_signed').eq('cycle', 3).maybeSingle()
    const coopCurrent = Number(coopData?.current_value ?? 4)
    const coopTarget = Number(coopData?.target_value ?? 4)
    results.cooperation_agreements_signed = { current: coopCurrent, pct: Math.round((coopCurrent / coopTarget) * 100), synced: false }

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
        const ok = await updateArtiaActivity(artiaToken, mapping.id, val.pct, desc, title, mapping.folderId)
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
