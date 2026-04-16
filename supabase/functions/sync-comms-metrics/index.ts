import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

// Retry with exponential backoff for external API calls
async function fetchWithRetry(url: string, options: RequestInit = {}, maxRetries = 3): Promise<Response> {
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
  channels?: string[]  // optional: sync only specific channels
}

type ChannelConfig = {
  channel: string
  api_key: string | null
  oauth_token: string | null
  oauth_refresh_token: string | null
  token_expires_at: string | null
  sync_status: string
  config: Record<string, unknown>
}

const RUN_KEY_PREFIX = 'comms_metrics'
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000

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

    const resp = await fetchWithRetry(sourceUrl, {
      method: 'GET',
      headers,
      signal: controller.signal,
    }, 2)

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

// ─── Per-channel API fetchers ───

async function fetchYouTubeMetrics(cfg: ChannelConfig): Promise<NormalizedMetric[]> {
  const apiKey = cfg.api_key
  const channelId = (cfg.config as any)?.channel_id
  if (!apiKey || !channelId) return []

  const today = new Date().toISOString().slice(0, 10)
  const metrics: NormalizedMetric[] = []

  try {
    // Fetch channel stats (subscribers, views)
    const channelResp = await fetchWithRetry(
      `https://www.googleapis.com/youtube/v3/channels?part=statistics&id=${channelId}&key=${apiKey}`
    )
    if (!channelResp.ok) throw new Error(`YouTube channels API: ${channelResp.status}`)
    const channelData = await channelResp.json()
    const stats = channelData?.items?.[0]?.statistics

    if (stats) {
      metrics.push({
        metric_date: today,
        channel: 'youtube',
        audience: parseInteger(stats.subscriberCount),
        reach: parseInteger(stats.viewCount),
        engagement_rate: null,
        leads: null,
        source: 'api',
        payload: { api: 'youtube_channels', ...stats },
      })
    }

    // Fetch recent videos for engagement data
    const searchResp = await fetchWithRetry(
      `https://www.googleapis.com/youtube/v3/search?part=id&channelId=${channelId}&type=video&order=date&maxResults=10&key=${apiKey}`
    )
    if (searchResp.ok) {
      const searchData = await searchResp.json()
      const videoIds = (searchData?.items || []).map((i: any) => i.id?.videoId).filter(Boolean)
      if (videoIds.length > 0) {
        const videosResp = await fetchWithRetry(
          `https://www.googleapis.com/youtube/v3/videos?part=statistics&id=${videoIds.join(',')}&key=${apiKey}`
        )
        if (videosResp.ok) {
          const videosData = await videosResp.json()
          let totalViews = 0, totalLikes = 0
          for (const v of videosData?.items || []) {
            totalViews += parseInt(v.statistics?.viewCount || '0', 10)
            totalLikes += parseInt(v.statistics?.likeCount || '0', 10)
          }
          if (totalViews > 0 && metrics[0]) {
            metrics[0].engagement_rate = parseEngagement(totalLikes / totalViews)
            metrics[0].payload = { ...metrics[0].payload, recent_videos: videoIds.length, total_views: totalViews, total_likes: totalLikes }
          }
        }
      }
    }
  } catch (e) {
    console.error('YouTube fetch error:', e)
  }

  return metrics
}

async function fetchLinkedInMetrics(cfg: ChannelConfig): Promise<NormalizedMetric[]> {
  const token = cfg.oauth_token
  const orgUrn = (cfg.config as any)?.organization_urn
  if (!token || !orgUrn) return []

  const today = new Date().toISOString().slice(0, 10)
  const metrics: NormalizedMetric[] = []

  try {
    // Fetch follower count
    const followersResp = await fetchWithRetry(
      `https://api.linkedin.com/v2/organizationalEntityFollowerStatistics?q=organizationalEntity&organizationalEntity=${encodeURIComponent(orgUrn)}`,
      { headers: { 'Authorization': `Bearer ${token}`, 'X-Restli-Protocol-Version': '2.0.0' } }
    )

    let followers: number | null = null
    if (followersResp.ok) {
      const followersData = await followersResp.json()
      const element = followersData?.elements?.[0]
      if (element) {
        followers = parseInteger(
          (element.followerCounts?.organicFollowerCount || 0) +
          (element.followerCounts?.paidFollowerCount || 0)
        )
      }
    }

    // Fetch share statistics
    const shareResp = await fetchWithRetry(
      `https://api.linkedin.com/v2/organizationalEntityShareStatistics?q=organizationalEntity&organizationalEntity=${encodeURIComponent(orgUrn)}`,
      { headers: { 'Authorization': `Bearer ${token}`, 'X-Restli-Protocol-Version': '2.0.0' } }
    )

    let reach: number | null = null
    let engagement: number | null = null
    if (shareResp.ok) {
      const shareData = await shareResp.json()
      const totals = shareData?.elements?.[0]?.totalShareStatistics
      if (totals) {
        reach = parseInteger(totals.impressionCount)
        const clicks = totals.clickCount || 0
        const impressions = totals.impressionCount || 1
        engagement = parseEngagement(clicks / impressions)
      }
    }

    metrics.push({
      metric_date: today,
      channel: 'linkedin',
      audience: followers,
      reach,
      engagement_rate: engagement,
      leads: null,
      source: 'api',
      payload: { api: 'linkedin_org_stats' },
    })
  } catch (e) {
    console.error('LinkedIn fetch error:', e)
  }

  return metrics
}

async function fetchInstagramMetrics(cfg: ChannelConfig): Promise<NormalizedMetric[]> {
  const token = cfg.oauth_token
  const igUserId = (cfg.config as any)?.ig_user_id
  if (!token || !igUserId) return []

  const today = new Date().toISOString().slice(0, 10)
  const metrics: NormalizedMetric[] = []

  try {
    // Fetch user profile (followers count)
    const profileResp = await fetchWithRetry(
      `https://graph.facebook.com/v19.0/${igUserId}?fields=followers_count,media_count&access_token=${token}`
    )

    let followers: number | null = null
    let mediaCount: number | null = null
    if (profileResp.ok) {
      const profileData = await profileResp.json()
      followers = parseInteger(profileData?.followers_count)
      mediaCount = parseInteger(profileData?.media_count)
    }

    // Fetch reach (period=day, returns time series)
    let reach: number | null = null
    const reachResp = await fetchWithRetry(
      `https://graph.facebook.com/v19.0/${igUserId}/insights?metric=reach&period=day&access_token=${token}`
    )
    if (reachResp.ok) {
      const reachData = await reachResp.json()
      for (const m of reachData?.data || []) {
        if (m.name === 'reach') {
          const latest = m.values?.[m.values.length - 1]
          reach = parseInteger(latest?.value)
        }
      }
    }

    // Fetch engagement metrics (metric_type=total_value)
    let accountsEngaged: number | null = null
    let totalInteractions: number | null = null
    const engagementResp = await fetchWithRetry(
      `https://graph.facebook.com/v19.0/${igUserId}/insights?metric=accounts_engaged,total_interactions&metric_type=total_value&period=day&access_token=${token}`
    )
    if (engagementResp.ok) {
      const engData = await engagementResp.json()
      for (const m of engData?.data || []) {
        if (m.name === 'accounts_engaged') accountsEngaged = parseInteger(m.total_value?.value)
        if (m.name === 'total_interactions') totalInteractions = parseInteger(m.total_value?.value)
      }
    }

    // Fetch online_followers (best time to post)
    let onlineFollowers: Record<string, number> | null = null
    try {
      const onlineResp = await fetchWithRetry(
        `https://graph.facebook.com/v19.0/${igUserId}/insights?metric=online_followers&period=lifetime&access_token=${token}`
      )
      if (onlineResp.ok) {
        const onlineData = await onlineResp.json()
        const metric = onlineData?.data?.find((m: any) => m.name === 'online_followers')
        if (metric?.values?.[0]?.value) {
          onlineFollowers = metric.values[0].value
        }
      }
    } catch { /* online_followers may not be available */ }

    // Calculate engagement rate: accounts_engaged / followers
    const engagementRate = (accountsEngaged && followers && followers > 0)
      ? parseEngagement(accountsEngaged / followers)
      : null

    metrics.push({
      metric_date: today,
      channel: 'instagram',
      audience: followers,
      reach,
      engagement_rate: engagementRate,
      leads: null,
      source: 'api',
      payload: {
        api: 'instagram_graph',
        media_count: mediaCount,
        accounts_engaged: accountsEngaged,
        total_interactions: totalInteractions,
        ...(onlineFollowers ? { online_followers: onlineFollowers } : {}),
      },
    })
  } catch (e) {
    console.error('Instagram fetch error:', e)
  }

  return metrics
}

// ─── Per-post media item fetchers ───

type MediaItem = {
  channel: string
  external_id: string
  media_type: string | null
  caption: string | null
  permalink: string | null
  thumbnail_url: string | null
  published_at: string | null
  likes: number
  comments: number
  shares: number
  saves: number
  reach: number | null
  views: number | null
  payload: Record<string, unknown>
}

async function fetchInstagramMedia(cfg: ChannelConfig): Promise<MediaItem[]> {
  const token = cfg.oauth_token
  const igUserId = (cfg.config as any)?.ig_user_id
  if (!token || !igUserId) return []

  const items: MediaItem[] = []
  try {
    // Fetch recent media list
    const mediaResp = await fetchWithRetry(
      `https://graph.facebook.com/v19.0/${igUserId}/media?fields=id,caption,media_type,timestamp,like_count,comments_count,permalink,thumbnail_url&limit=25&access_token=${token}`
    )
    if (!mediaResp.ok) return []
    const mediaData = await mediaResp.json()

    for (const m of mediaData?.data || []) {
      const item: MediaItem = {
        channel: 'instagram',
        external_id: m.id,
        media_type: m.media_type || null,
        caption: m.caption ? m.caption.slice(0, 500) : null,
        permalink: m.permalink || null,
        thumbnail_url: m.thumbnail_url || null,
        published_at: m.timestamp || null,
        likes: parseInt(m.like_count || '0', 10),
        comments: parseInt(m.comments_count || '0', 10),
        shares: 0,
        saves: 0,
        reach: null,
        views: null,
        payload: {},
      }

      // Fetch per-media insights (reach, saved, shares) — may fail for some media types
      try {
        const insightsResp = await fetchWithRetry(
          `https://graph.facebook.com/v19.0/${m.id}/insights?metric=reach,saved,shares&access_token=${token}`
        )
        if (insightsResp.ok) {
          const insightsData = await insightsResp.json()
          for (const metric of insightsData?.data || []) {
            if (metric.name === 'reach') item.reach = parseInteger(metric.values?.[0]?.value) ?? null
            if (metric.name === 'saved') item.saves = parseInt(metric.values?.[0]?.value || '0', 10)
            if (metric.name === 'shares') item.shares = parseInt(metric.values?.[0]?.value || '0', 10)
          }
        }
      } catch { /* per-media insights may fail for stories/reels */ }

      items.push(item)
    }
  } catch (e) {
    console.error('Instagram media fetch error:', e)
  }
  return items
}

async function fetchYouTubeMedia(cfg: ChannelConfig): Promise<MediaItem[]> {
  const apiKey = cfg.api_key
  const channelId = (cfg.config as any)?.channel_id
  if (!apiKey || !channelId) return []

  const items: MediaItem[] = []
  try {
    // Search for recent videos
    const searchResp = await fetchWithRetry(
      `https://www.googleapis.com/youtube/v3/search?part=id&channelId=${channelId}&type=video&order=date&maxResults=15&key=${apiKey}`
    )
    if (!searchResp.ok) return []
    const searchData = await searchResp.json()
    const videoIds = (searchData?.items || []).map((i: any) => i.id?.videoId).filter(Boolean)
    if (!videoIds.length) return []

    // Fetch video details + stats
    const videosResp = await fetchWithRetry(
      `https://www.googleapis.com/youtube/v3/videos?part=statistics,snippet&id=${videoIds.join(',')}&key=${apiKey}`
    )
    if (!videosResp.ok) return []
    const videosData = await videosResp.json()

    for (const v of videosData?.items || []) {
      const stats = v.statistics || {}
      const snippet = v.snippet || {}
      items.push({
        channel: 'youtube',
        external_id: v.id,
        media_type: 'VIDEO',
        caption: snippet.title ? snippet.title.slice(0, 500) : null,
        permalink: `https://www.youtube.com/watch?v=${v.id}`,
        thumbnail_url: snippet.thumbnails?.medium?.url || snippet.thumbnails?.default?.url || null,
        published_at: snippet.publishedAt || null,
        likes: parseInt(stats.likeCount || '0', 10),
        comments: parseInt(stats.commentCount || '0', 10),
        shares: 0,
        saves: parseInt(stats.favoriteCount || '0', 10),
        reach: null,
        views: parseInt(stats.viewCount || '0', 10),
        payload: { duration: snippet.duration },
      })
    }
  } catch (e) {
    console.error('YouTube media fetch error:', e)
  }
  return items
}

const MEDIA_FETCHERS: Record<string, (cfg: ChannelConfig) => Promise<MediaItem[]>> = {
  instagram: fetchInstagramMedia,
  youtube: fetchYouTubeMedia,
}

const CHANNEL_FETCHERS: Record<string, (cfg: ChannelConfig) => Promise<NormalizedMetric[]>> = {
  youtube: fetchYouTubeMetrics,
  linkedin: fetchLinkedInMetrics,
  instagram: fetchInstagramMetrics,
}

// ─── Token expiry helpers ───

function isTokenValid(cfg: ChannelConfig): boolean {
  // YouTube uses API key (never expires)
  if (cfg.channel === 'youtube') return !!cfg.api_key
  // OAuth channels need a valid token
  if (!cfg.oauth_token) return false
  if (!cfg.token_expires_at) return true // no expiry set = assume valid
  return new Date(cfg.token_expires_at).getTime() > Date.now()
}

function isTokenExpiringSoon(cfg: ChannelConfig): boolean {
  if (cfg.channel === 'youtube') return false
  if (!cfg.token_expires_at) return false
  const expiresAt = new Date(cfg.token_expires_at).getTime()
  return expiresAt > Date.now() && expiresAt < Date.now() + SEVEN_DAYS_MS
}

// ─── Per-channel sync orchestrator ───

async function syncFromChannelConfigs(
  sb: ReturnType<typeof createClient>,
  triggeredBy: string,
  dryRun: boolean,
  filterChannels?: string[],
): Promise<{ total_upserted: number; channel_results: Record<string, unknown>[] }> {
  const { data: configs, error } = await sb
    .from('comms_channel_config')
    .select('*')

  if (error || !configs?.length) {
    return { total_upserted: 0, channel_results: [] }
  }

  const channelResults: Record<string, unknown>[] = []
  let totalUpserted = 0

  for (const cfg of configs as ChannelConfig[]) {
    if (filterChannels?.length && !filterChannels.includes(cfg.channel)) continue

    const fetcher = CHANNEL_FETCHERS[cfg.channel]
    if (!fetcher) {
      channelResults.push({ channel: cfg.channel, status: 'no_fetcher' })
      continue
    }

    // Check token validity
    if (!isTokenValid(cfg)) {
      await sb.from('comms_channel_config')
        .update({ sync_status: 'token_expired' })
        .eq('channel', cfg.channel)
      channelResults.push({ channel: cfg.channel, status: 'token_expired' })
      continue
    }

    // Check if expiring soon (still sync but flag)
    if (isTokenExpiringSoon(cfg)) {
      channelResults.push({ channel: cfg.channel, warning: 'token_expiring_soon' })
    }

    const runKey = `${RUN_KEY_PREFIX}_${cfg.channel}_${new Date().toISOString()}`

    try {
      const metrics = await fetcher(cfg)

      if (!dryRun && metrics.length > 0) {
        const { error: upsertError } = await sb
          .from('comms_metrics_daily')
          .upsert(metrics, { onConflict: 'metric_date,channel,source' })

        if (upsertError) throw upsertError

        // Update last_sync_at
        await sb.from('comms_channel_config')
          .update({ last_sync_at: new Date().toISOString(), sync_status: 'active' })
          .eq('channel', cfg.channel)
      }

      await logRun(sb, {
        run_key: runKey,
        source: `api_${cfg.channel}`,
        triggered_by: triggeredBy,
        status: 'success',
        fetched_rows: metrics.length,
        upserted_rows: dryRun ? 0 : metrics.length,
        invalid_rows: 0,
        context: { dry_run: dryRun, channel: cfg.channel },
        finished: true,
      }).catch(() => {})

      totalUpserted += metrics.length

      // Fetch and upsert per-post media items
      let mediaCount = 0
      const mediaFetcher = MEDIA_FETCHERS[cfg.channel]
      if (mediaFetcher && !dryRun) {
        try {
          const mediaItems = await mediaFetcher(cfg)
          if (mediaItems.length > 0) {
            const { error: mediaError } = await sb
              .from('comms_media_items')
              .upsert(mediaItems.map(m => ({
                channel: m.channel,
                external_id: m.external_id,
                media_type: m.media_type,
                caption: m.caption,
                permalink: m.permalink,
                thumbnail_url: m.thumbnail_url,
                published_at: m.published_at,
                likes: m.likes,
                comments: m.comments,
                shares: m.shares,
                saves: m.saves,
                reach: m.reach,
                views: m.views,
                payload: m.payload,
                synced_at: new Date().toISOString(),
              })), { onConflict: 'channel,external_id' })
            if (!mediaError) mediaCount = mediaItems.length
          }
        } catch (e) { console.warn(`Media fetch ${cfg.channel}:`, e) }
      }

      channelResults.push({ channel: cfg.channel, status: 'success', rows: metrics.length, media_items: mediaCount })
    } catch (e) {
      const message = e instanceof Error ? e.message : 'Unknown error'
      await sb.from('comms_channel_config')
        .update({ sync_status: 'error' })
        .eq('channel', cfg.channel)

      await logRun(sb, {
        run_key: runKey,
        source: `api_${cfg.channel}`,
        triggered_by: triggeredBy,
        status: 'error',
        fetched_rows: 0,
        upserted_rows: 0,
        invalid_rows: 0,
        error_message: message,
        context: { channel: cfg.channel },
        finished: true,
      }).catch(() => {})

      channelResults.push({ channel: cfg.channel, status: 'error', error: message })
    }
  }

  return { total_upserted: totalUpserted, channel_results: channelResults }
}

// ─── Main handler ───

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
    // If rows are provided in the request body, use legacy ingestion path
    if (Array.isArray(body.rows) && body.rows.length > 0) {
      const sourceData = { rows: body.rows, source: defaultSource }

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
        context: { dry_run: dryRun, sample: normalized.slice(0, 3) },
        finished: true,
      }).catch(() => {})

      return new Response(JSON.stringify({
        success: true,
        mode: 'legacy_rows',
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
    }

    // New path: sync from comms_channel_config (per-channel API calls)
    const result = await syncFromChannelConfigs(sb, triggeredBy, dryRun, body.channels)

    return new Response(JSON.stringify({
      success: true,
      mode: 'channel_config',
      run_key: runKey,
      dry_run: dryRun,
      total_upserted: result.total_upserted,
      channel_results: result.channel_results,
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
