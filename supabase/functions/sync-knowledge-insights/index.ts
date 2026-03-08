import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

type SyncPayload = {
  dry_run?: boolean
  run_key?: string
  triggered_by?: string
  source?: 'youtube' | 'drive' | 'linkedin' | 'manual' | 'meeting_notes'
  days?: number
  limit?: number
}

type SourceKind = 'youtube' | 'drive' | 'linkedin' | 'manual' | 'meeting_notes'
type InsightType = 'friction' | 'request' | 'idea' | 'risk' | 'opportunity' | 'decision'
type Taxonomy = 'product' | 'process' | 'data' | 'adoption' | 'governance' | 'skills' | 'comms' | 'operations' | 'other'

type ChunkRow = {
  id: string
  asset_id: string
  content: string
  knowledge_assets: {
    id: string
    source: SourceKind
    title: string
    source_url: string | null
    tags: string[] | null
    is_active: boolean
  }
}

type Candidate = {
  chunk_id: string
  asset_id: string
  source: SourceKind
  insight_type: InsightType
  taxonomy_area: Taxonomy
  title: string
  summary: string
  evidence_quote: string
  evidence_url: string | null
  impact_score: number
  urgency_score: number
  confidence_score: number
  metadata: Record<string, unknown>
}

const RUN_KEY_PREFIX = 'knowledge_insights'
const RULE_VERSION = 'knw8_rules_v1'

const insightRules: Array<{ type: InsightType; keywords: string[]; title: string }> = [
  { type: 'friction', keywords: ['gargalo', 'bloqueio', 'dificuldade', 'problema', 'erro', 'falha', 'friccao', 'fricção', 'atraso'], title: 'Fricção operacional identificada' },
  { type: 'request', keywords: ['precisamos', 'necessario', 'necessário', 'falta', 'gostaria', 'deveria', 'need to', 'should'], title: 'Solicitação recorrente identificada' },
  { type: 'idea', keywords: ['ideia', 'sugestao', 'sugestão', 'proposta', 'experimentar', 'piloto'], title: 'Ideia de melhoria identificada' },
  { type: 'risk', keywords: ['risco', 'compliance', 'governanca', 'governança', 'lgpd', 'privacidade', 'seguranca', 'segurança', 'etica', 'ética'], title: 'Risco ou atenção de governança' },
  { type: 'opportunity', keywords: ['oportunidade', 'ganho', 'acelerar', 'escala', 'eficiencia', 'eficiência', 'beneficio', 'benefício'], title: 'Oportunidade de alavancagem' },
  { type: 'decision', keywords: ['decidimos', 'aprovado', 'definimos', 'priorizado', 'combinado'], title: 'Decisão registrada' },
]

const taxonomyRules: Array<{ taxonomy: Taxonomy; keywords: string[] }> = [
  { taxonomy: 'product', keywords: ['produto', 'feature', 'ux', 'interface', 'experiencia', 'experiência'] },
  { taxonomy: 'process', keywords: ['processo', 'fluxo', 'ritual', 'sprint', 'backlog', 'kanban'] },
  { taxonomy: 'data', keywords: ['dados', 'metrica', 'métrica', 'kpi', 'sql', 'dashboard'] },
  { taxonomy: 'adoption', keywords: ['adocao', 'adoção', 'engajamento', 'adesao', 'adesão', 'onboarding'] },
  { taxonomy: 'governance', keywords: ['governanca', 'governança', 'compliance', 'policy', 'auditoria'] },
  { taxonomy: 'skills', keywords: ['trilha', 'curso', 'capacitacao', 'capacitação', 'certificacao', 'certificação'] },
  { taxonomy: 'comms', keywords: ['comunicacao', 'comunicação', 'linkedin', 'youtube', 'instagram', 'conteudo', 'conteúdo'] },
  { taxonomy: 'operations', keywords: ['operacao', 'operação', 'execucao', 'execução', 'deploy', 'incidente'] },
]

function unauthorizedResponse() {
  return new Response(JSON.stringify({ success: false, error: 'Unauthorized' }), {
    status: 401,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function buildRunKey(input?: string): string {
  if (input && input.trim()) return input.trim()
  return `${RUN_KEY_PREFIX}_${new Date().toISOString()}`
}

function normalizeLower(input: string): string {
  return input.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
}

function sanitizeTitle(text: string): string {
  const out = text.replace(/\s+/g, ' ').trim()
  return out.length <= 140 ? out : `${out.slice(0, 137)}...`
}

function excerptAroundKeyword(text: string, keyword: string): string {
  const normalized = normalizeLower(text)
  const key = normalizeLower(keyword)
  const idx = normalized.indexOf(key)
  if (idx < 0) return sanitizeTitle(text.slice(0, 220))
  const start = Math.max(0, idx - 90)
  const end = Math.min(text.length, idx + key.length + 130)
  return sanitizeTitle(text.slice(start, end))
}

function detectTaxonomy(text: string): Taxonomy {
  const normalized = normalizeLower(text)
  for (const rule of taxonomyRules) {
    if (rule.keywords.some((k) => normalized.includes(normalizeLower(k)))) return rule.taxonomy
  }
  return 'other'
}

function classifyScores(type: InsightType, text: string): { impact: number; urgency: number; confidence: number } {
  const normalized = normalizeLower(text)
  const severe = ['critico', 'crítico', 'bloqueio', 'urgente', 'alto risco'].some((k) => normalized.includes(normalizeLower(k)))
  const impactBase = type === 'risk' || type === 'friction' ? 4 : type === 'opportunity' ? 4 : 3
  const urgencyBase = type === 'friction' || type === 'request' ? 4 : type === 'decision' ? 3 : 2
  const impact = Math.max(1, Math.min(5, impactBase + (severe ? 1 : 0)))
  const urgency = Math.max(1, Math.min(5, urgencyBase + (severe ? 1 : 0)))
  const confidence = severe ? 0.85 : 0.7
  return { impact, urgency, confidence }
}

function extractCandidates(chunk: ChunkRow): Candidate[] {
  const text = chunk.content || ''
  const normalized = normalizeLower(text)
  const taxonomy = detectTaxonomy(text)
  const out: Candidate[] = []

  for (const rule of insightRules) {
    const matched = rule.keywords.find((k) => normalized.includes(normalizeLower(k)))
    if (!matched) continue

    const scores = classifyScores(rule.type, text)
    const evidence = excerptAroundKeyword(text, matched)
    const title = sanitizeTitle(`${rule.title}: ${chunk.knowledge_assets.title}`)

    out.push({
      chunk_id: chunk.id,
      asset_id: chunk.asset_id,
      source: chunk.knowledge_assets.source,
      insight_type: rule.type,
      taxonomy_area: taxonomy,
      title,
      summary: sanitizeTitle(evidence),
      evidence_quote: evidence,
      evidence_url: chunk.knowledge_assets.source_url,
      impact_score: scores.impact,
      urgency_score: scores.urgency,
      confidence_score: scores.confidence,
      metadata: {
        rule_version: RULE_VERSION,
        matched_keyword: matched,
      },
    })
  }

  return out
}

function dedupKey(c: Candidate): string {
  return `${c.chunk_id}|${c.insight_type}|${c.taxonomy_area}|${normalizeLower(c.title)}`
}

async function logRun(
  sb: ReturnType<typeof createClient>,
  payload: {
    run_key: string
    status: 'started' | 'success' | 'partial' | 'error'
    triggered_by: string
    rows_received: number
    rows_upserted: number
    rows_chunked: number
    error_message?: string
    metadata?: Record<string, unknown>
  },
) {
  await sb.from('knowledge_ingestion_runs').upsert({
    run_key: payload.run_key,
    source: 'insights',
    status: payload.status,
    triggered_by: payload.triggered_by,
    rows_received: payload.rows_received,
    rows_upserted: payload.rows_upserted,
    rows_chunked: payload.rows_chunked,
    error_message: payload.error_message ?? null,
    metadata: payload.metadata ?? {},
  }, { onConflict: 'run_key' })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const syncSecret = Deno.env.get('SYNC_KNOWLEDGE_INSIGHTS_SECRET')
  const bearer = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '')
  const headerSecret = req.headers.get('x-sync-secret')

  if (!syncSecret || (bearer !== syncSecret && headerSecret !== syncSecret)) {
    return unauthorizedResponse()
  }

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  const body: SyncPayload = req.method === 'POST' ? await req.json().catch(() => ({})) : {}
  const runKey = buildRunKey(body.run_key)
  const triggeredBy = body.triggered_by?.trim() || 'cron'
  const dryRun = !!body.dry_run
  const limit = Math.max(10, Math.min(body.limit ?? 300, 1000))
  const days = Math.max(1, Math.min(body.days ?? 45, 365))
  const source = body.source

  try {
    const cutoffIso = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString()
    let query = sb
      .from('knowledge_chunks')
      .select('id,asset_id,content,knowledge_assets!inner(id,source,title,source_url,tags,is_active,published_at)')
      .eq('knowledge_assets.is_active', true)
      .gte('knowledge_assets.published_at', cutoffIso)
      .order('created_at', { ascending: false })
      .limit(limit)

    if (source) query = query.eq('knowledge_assets.source', source)

    const { data: chunksData, error: chunksError } = await query
    if (chunksError) throw chunksError

    const chunks = (chunksData || []) as unknown as ChunkRow[]

    await logRun(sb, {
      run_key: runKey,
      status: 'started',
      triggered_by: triggeredBy,
      rows_received: chunks.length,
      rows_upserted: 0,
      rows_chunked: 0,
      metadata: { dry_run: dryRun, rule_version: RULE_VERSION, source: source ?? null, days, limit },
    }).catch(() => {})

    const candidates = chunks.flatMap(extractCandidates)

    const chunkIds = [...new Set(candidates.map((c) => c.chunk_id))]
    const existingSet = new Set<string>()
    if (chunkIds.length) {
      const { data: existingData, error: existingError } = await sb
        .from('knowledge_insights')
        .select('chunk_id,insight_type,taxonomy_area,title')
        .in('chunk_id', chunkIds)
        .limit(5000)
      if (existingError) throw existingError
      for (const row of existingData || []) {
        const key = `${row.chunk_id}|${row.insight_type}|${row.taxonomy_area}|${normalizeLower(String(row.title || ''))}`
        existingSet.add(key)
      }
    }

    const deduped = candidates.filter((c) => !existingSet.has(dedupKey(c)))
    let inserted = 0

    if (!dryRun && deduped.length) {
      const payload = deduped.map((c) => ({
        source: c.source,
        asset_id: c.asset_id,
        chunk_id: c.chunk_id,
        insight_type: c.insight_type,
        taxonomy_area: c.taxonomy_area,
        title: c.title,
        summary: c.summary,
        evidence_quote: c.evidence_quote,
        evidence_url: c.evidence_url,
        impact_score: c.impact_score,
        urgency_score: c.urgency_score,
        confidence_score: c.confidence_score,
        metadata: c.metadata,
      }))

      const { error: insertError } = await sb.from('knowledge_insights').insert(payload)
      if (insertError) throw insertError
      inserted = payload.length
    }

    await logRun(sb, {
      run_key: runKey,
      status: 'success',
      triggered_by: triggeredBy,
      rows_received: chunks.length,
      rows_upserted: dryRun ? 0 : inserted,
      rows_chunked: candidates.length,
      metadata: {
        dry_run: dryRun,
        rule_version: RULE_VERSION,
        candidates_total: candidates.length,
        candidates_new: deduped.length,
        source: source ?? null,
        days,
        limit,
      },
    }).catch(() => {})

    return new Response(JSON.stringify({
      success: true,
      run_key: runKey,
      dry_run: dryRun,
      chunks_scanned: chunks.length,
      candidates_total: candidates.length,
      candidates_new: deduped.length,
      inserted: dryRun ? 0 : inserted,
      rule_version: RULE_VERSION,
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    await logRun(sb, {
      run_key: runKey,
      status: 'error',
      triggered_by: triggeredBy,
      rows_received: 0,
      rows_upserted: 0,
      rows_chunked: 0,
      error_message: message,
      metadata: { rule_version: RULE_VERSION },
    }).catch(() => {})

    return new Response(JSON.stringify({ success: false, run_key: runKey, error: message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
