import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

type RawKnowledgeRow = Record<string, unknown>

type KnowledgeRow = {
  source: 'youtube'
  external_id: string
  source_url: string | null
  title: string
  summary: string | null
  tags: string[]
  language: string
  published_at: string | null
  transcript: string
  metadata: Record<string, unknown>
}

type IngestionPayload = {
  rows?: RawKnowledgeRow[]
  run_key?: string
  triggered_by?: string
  dry_run?: boolean
}

const RUN_KEY_PREFIX = 'knowledge_youtube'

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

function normalizeText(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

function normalizeDate(value: unknown): string | null {
  if (typeof value !== 'string' || !value.trim()) return null
  const trimmed = value.trim()
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return `${trimmed}T00:00:00Z`
  const parsed = new Date(trimmed)
  if (Number.isNaN(parsed.getTime())) return null
  return parsed.toISOString()
}

function normalizeTags(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value
      .map((v) => (typeof v === 'string' ? v.trim().toLowerCase() : ''))
      .filter(Boolean)
      .slice(0, 20)
  }
  if (typeof value === 'string') {
    return value
      .split(',')
      .map((v) => v.trim().toLowerCase())
      .filter(Boolean)
      .slice(0, 20)
  }
  return []
}

function splitTranscript(input: string, maxLen = 1200): string[] {
  const text = input.trim().replace(/\s+/g, ' ')
  if (!text) return []

  const out: string[] = []
  let cursor = 0
  while (cursor < text.length) {
    const next = Math.min(cursor + maxLen, text.length)
    let cut = text.lastIndexOf('. ', next)
    if (cut <= cursor + 300) cut = next
    const chunk = text.slice(cursor, cut).trim()
    if (chunk) out.push(chunk)
    cursor = cut + 1
  }
  return out
}

function normalizeRow(raw: RawKnowledgeRow): KnowledgeRow | null {
  const externalId = normalizeText(raw.external_id ?? raw.video_id ?? raw.id)
  const title = normalizeText(raw.title ?? raw.video_title)
  const transcript = normalizeText(raw.transcript ?? raw.caption_text ?? raw.content)

  if (!externalId || !title || !transcript) return null

  return {
    source: 'youtube',
    external_id: externalId,
    source_url: normalizeText(raw.source_url ?? raw.url) || null,
    title,
    summary: normalizeText(raw.summary) || null,
    tags: normalizeTags(raw.tags),
    language: normalizeText(raw.language) || 'pt-BR',
    published_at: normalizeDate(raw.published_at ?? raw.publishedAt ?? raw.video_published_at),
    transcript,
    metadata: (typeof raw.metadata === 'object' && raw.metadata !== null)
      ? (raw.metadata as Record<string, unknown>)
      : {},
  }
}

async function fetchRowsFromEndpoint(): Promise<RawKnowledgeRow[]> {
  const sourceUrl = Deno.env.get('KNOWLEDGE_INGEST_SOURCE_URL')
  if (!sourceUrl) throw new Error('KNOWLEDGE_INGEST_SOURCE_URL is not configured')

  const token = Deno.env.get('KNOWLEDGE_INGEST_SOURCE_TOKEN')
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort('timeout'), 25_000)

  try {
    const headers: HeadersInit = { 'Accept': 'application/json' }
    if (token) headers['Authorization'] = `Bearer ${token}`

    const resp = await fetch(sourceUrl, { method: 'GET', headers, signal: controller.signal })
    if (!resp.ok) throw new Error(`Source fetch failed: ${resp.status}`)

    const json = await resp.json()
    if (Array.isArray(json)) return json as RawKnowledgeRow[]
    if (json && Array.isArray(json.rows)) return json.rows as RawKnowledgeRow[]
    throw new Error('Source payload must be array or object with rows[]')
  } finally {
    clearTimeout(timeout)
  }
}

async function logRun(
  sb: ReturnType<typeof createClient>,
  payload: {
    run_key: string
    status: 'started' | 'success' | 'error' | 'partial'
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
    source: 'youtube',
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

  const syncSecret = Deno.env.get('SYNC_KNOWLEDGE_INGEST_SECRET')
  const bearer = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '')
  const headerSecret = req.headers.get('x-sync-secret')

  if (!syncSecret || (bearer !== syncSecret && headerSecret !== syncSecret)) {
    return unauthorizedResponse()
  }

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  const body: IngestionPayload = req.method === 'POST' ? await req.json().catch(() => ({})) : {}
  const runKey = buildRunKey(body.run_key)
  const triggeredBy = body.triggered_by?.trim() || 'cron'
  const dryRun = !!body.dry_run

  try {
    const rawRows = Array.isArray(body.rows) ? body.rows : await fetchRowsFromEndpoint()
    const rows = rawRows.map(normalizeRow).filter((r): r is KnowledgeRow => !!r)
    const invalidRows = rawRows.length - rows.length

    await logRun(sb, {
      run_key: runKey,
      status: 'started',
      triggered_by: triggeredBy,
      rows_received: rawRows.length,
      rows_upserted: 0,
      rows_chunked: 0,
      metadata: { dry_run: dryRun, invalid_rows: invalidRows },
    }).catch(() => {})

    let upserted = 0
    let chunked = 0

    if (!dryRun) {
      for (const row of rows) {
        const { data: asset, error: upsertError } = await sb
          .from('knowledge_assets')
          .upsert({
            source: row.source,
            external_id: row.external_id,
            source_url: row.source_url,
            title: row.title,
            summary: row.summary,
            tags: row.tags,
            language: row.language,
            published_at: row.published_at,
            metadata: row.metadata,
          }, { onConflict: 'source,external_id' })
          .select('id')
          .single()

        if (upsertError) throw upsertError
        upserted += 1

        const assetId = asset?.id as string
        if (!assetId) continue

        const chunks = splitTranscript(row.transcript)
        const { error: purgeError } = await sb.from('knowledge_chunks').delete().eq('asset_id', assetId)
        if (purgeError) throw purgeError

        if (chunks.length) {
          const payload = chunks.map((content, idx) => ({
            asset_id: assetId,
            chunk_index: idx,
            content,
            token_estimate: Math.ceil(content.length / 4),
          }))
          const { error: insertChunkError } = await sb.from('knowledge_chunks').insert(payload)
          if (insertChunkError) throw insertChunkError
          chunked += chunks.length
        }
      }
    }

    await logRun(sb, {
      run_key: runKey,
      status: invalidRows > 0 ? 'partial' : 'success',
      triggered_by: triggeredBy,
      rows_received: rawRows.length,
      rows_upserted: dryRun ? 0 : upserted,
      rows_chunked: dryRun ? 0 : chunked,
      metadata: {
        dry_run: dryRun,
        invalid_rows: invalidRows,
      },
    }).catch(() => {})

    return new Response(JSON.stringify({
      success: true,
      run_key: runKey,
      dry_run: dryRun,
      rows_received: rawRows.length,
      rows_valid: rows.length,
      rows_invalid: invalidRows,
      rows_upserted: dryRun ? 0 : upserted,
      rows_chunked: dryRun ? 0 : chunked,
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
    }).catch(() => {})

    return new Response(JSON.stringify({ success: false, run_key: runKey, error: message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
