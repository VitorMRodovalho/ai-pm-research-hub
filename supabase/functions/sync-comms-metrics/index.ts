import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

type RawMetric = Record<string, unknown>

type NormalizedMetric = {
  metric_date: string
  channel: string
  audience: number | null
  reach: number | null
  engagement_rate: number | null
  leads: number | null
  source: string
  payload: RawMetric
}

type IngestionPayload = {
  rows?: RawMetric[]
  source?: string
  run_key?: string
  triggered_by?: string
  dry_run?: boolean
}

const RUN_KEY_PREFIX = 'comms_metrics'

function parseInteger(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value)
  if (typeof value === 'string') {
    const normalized = value.replace(/[^\d.-]/g, '')
    if (!normalized) return null
    const parsed = Number(normalized)
    if (!Number.isFinite(parsed)) return null
    return Math.trunc(parsed)
  }
  return null
}

function parseEngagement(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null
  if (typeof value !== 'number' && typeof value !== 'string') return null

  const raw = typeof value === 'number'
    ? value
    : Number(String(value).replace('%', '').replace(',', '.').trim())

  if (!Number.isFinite(raw)) return null
  if (raw > 1 && raw <= 100) return Number((raw / 100).toFixed(4))
  if (raw < 0) return null
  return Number(raw.toFixed(4))
}

function normalizeDate(value: unknown): string {
  if (typeof value !== 'string' || !value.trim()) {
    return new Date().toISOString().slice(0, 10)
  }

  const trimmed = value.trim()
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return trimmed

  const parsed = new Date(trimmed)
  if (Number.isNaN(parsed.getTime())) {
    return new Date().toISOString().slice(0, 10)
  }
  return parsed.toISOString().slice(0, 10)
}

function normalizeChannel(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const normalized = value.trim().toLowerCase().replace(/\s+/g, '_')
  return normalized || null
}

function normalizeRow(raw: RawMetric, defaultSource: string): NormalizedMetric | null {
  const channel = normalizeChannel(raw.channel ?? raw.platform ?? raw.network)
  if (!channel) return null

  const sourceCandidate = raw.source
  const source = typeof sourceCandidate === 'string' && sourceCandidate.trim()
    ? sourceCandidate.trim().toLowerCase()
    : defaultSource

  return {
    metric_date: normalizeDate(raw.metric_date ?? raw.date ?? raw.metricDate),
    channel,
    audience: parseInteger(raw.audience ?? raw.followers ?? raw.subscribers),
    reach: parseInteger(raw.reach ?? raw.impressions),
    engagement_rate: parseEngagement(raw.engagement_rate ?? raw.engagement ?? raw.engagementRate),
    leads: parseInteger(raw.leads ?? raw.conversions),
    source,
    payload: raw,
  }
}

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

async function fetchRowsFromEndpoint(defaultSource: string): Promise<{ rows: RawMetric[]; source: string }> {
  const sourceUrl = Deno.env.get('COMMS_METRICS_SOURCE_URL')
  if (!sourceUrl) {
    throw new Error('COMMS_METRICS_SOURCE_URL is not configured')
  }

  const token = Deno.env.get('COMMS_METRICS_SOURCE_TOKEN')
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort('timeout'), 20_000)

  try {
    const headers: HeadersInit = { 'Accept': 'application/json' }
    if (token) headers['Authorization'] = `Bearer ${token}`

    const resp = await fetch(sourceUrl, {
      method: 'GET',
      headers,
      signal: controller.signal,
    })

    if (!resp.ok) throw new Error(`Source fetch failed: ${resp.status}`)

    const json = await resp.json()
    if (Array.isArray(json)) return { rows: json, source: defaultSource }
    if (json && Array.isArray(json.rows)) {
      const src = typeof json.source === 'string' && json.source.trim()
        ? json.source.trim().toLowerCase()
        : defaultSource
      return { rows: json.rows, source: src }
    }

    throw new Error('Source payload must be an array or object with rows[]')
  } finally {
    clearTimeout(timeout)
  }
}

async function logRun(
  sb: ReturnType<typeof createClient>,
  payload: {
    run_key: string
    source: string
    triggered_by: string
    status: 'running' | 'success' | 'error'
    fetched_rows: number
    upserted_rows: number
    invalid_rows: number
    error_message?: string
    context?: Record<string, unknown>
    finished?: boolean
  },
) {
  const body: Record<string, unknown> = {
    run_key: payload.run_key,
    source: payload.source,
    triggered_by: payload.triggered_by,
    status: payload.status,
    fetched_rows: payload.fetched_rows,
    upserted_rows: payload.upserted_rows,
    invalid_rows: payload.invalid_rows,
    error_message: payload.error_message ?? null,
    context: payload.context ?? {},
  }

  if (payload.finished) body.finished_at = new Date().toISOString()

  await sb.from('comms_metrics_ingestion_log').upsert(body, { onConflict: 'run_key' })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const syncSecret = Deno.env.get('SYNC_COMMS_METRICS_SECRET')
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
  const defaultSource = body.source?.trim().toLowerCase() || 'external'
  const dryRun = !!body.dry_run

  try {
    const sourceData = Array.isArray(body.rows)
      ? { rows: body.rows, source: defaultSource }
      : await fetchRowsFromEndpoint(defaultSource)

    const normalized: NormalizedMetric[] = []
    let invalidRows = 0

    for (const row of sourceData.rows) {
      const parsed = normalizeRow(row, sourceData.source)
      if (!parsed) {
        invalidRows += 1
        continue
      }
      normalized.push(parsed)
    }

    await logRun(sb, {
      run_key: runKey,
      source: sourceData.source,
      triggered_by: triggeredBy,
      status: 'running',
      fetched_rows: sourceData.rows.length,
      upserted_rows: 0,
      invalid_rows: invalidRows,
      context: { dry_run: dryRun },
    }).catch(() => {})

    if (!dryRun && normalized.length) {
      const { error } = await sb
        .from('comms_metrics_daily')
        .upsert(normalized, { onConflict: 'metric_date,channel,source' })

      if (error) throw error
    }

    await logRun(sb, {
      run_key: runKey,
      source: sourceData.source,
      triggered_by: triggeredBy,
      status: 'success',
      fetched_rows: sourceData.rows.length,
      upserted_rows: dryRun ? 0 : normalized.length,
      invalid_rows: invalidRows,
      context: {
        dry_run: dryRun,
        sample: normalized.slice(0, 3),
      },
      finished: true,
    }).catch(() => {})

    return new Response(JSON.stringify({
      success: true,
      run_key: runKey,
      dry_run: dryRun,
      source: sourceData.source,
      fetched_rows: sourceData.rows.length,
      upserted_rows: dryRun ? 0 : normalized.length,
      invalid_rows: invalidRows,
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'

    await logRun(sb, {
      run_key: runKey,
      source: defaultSource,
      triggered_by: triggeredBy,
      status: 'error',
      fetched_rows: 0,
      upserted_rows: 0,
      invalid_rows: 0,
      error_message: message,
      finished: true,
    }).catch(() => {})

    return new Response(JSON.stringify({
      success: false,
      run_key: runKey,
      error: message,
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
