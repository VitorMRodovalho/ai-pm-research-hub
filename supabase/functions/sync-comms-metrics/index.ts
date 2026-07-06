import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
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
  force_refresh?: boolean  // force LinkedIn token refresh regardless of expiry (verification)
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

// LinkedIn Community Management API version (YYYYMM). The legacy /v2/ endpoints
// were sunset; current org-statistics live under /rest/ and REQUIRE this header
// alongside X-Restli-Protocol-Version: 2.0.0. Keep current — stale monikers 410.
// Docs: learn.microsoft.com/linkedin/marketing/community-management/organizations
const LINKEDIN_VERSION = '202606'

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


async function logRun(
  sb: SupabaseClient<any, "public", any>,
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

  // Versioned Community Management API headers. /rest/ requires BOTH the
  // LinkedIn-Version moniker and the Rest.li 2.0.0 protocol header.
  const liHeaders = {
    'Authorization': `Bearer ${token}`,
    'LinkedIn-Version': LINKEDIN_VERSION,
    'X-Restli-Protocol-Version': '2.0.0',
  }

  try {
    // ── Follower count ──
    // The /rest/ organizationalEntityFollowerStatistics endpoint no longer
    // returns total follower counts (only demographic facets), so the total
    // comes from the dedicated networkSizes endpoint. The org URN is a path
    // key here and MUST be URL-encoded — the raw colon form returns
    // 400 ILLEGAL_ARGUMENT "Syntax exception in path variables".
    let followers: number | null = null
    const networkResp = await fetchWithRetry(
      `https://api.linkedin.com/rest/networkSizes/${encodeURIComponent(orgUrn)}?edgeType=COMPANY_FOLLOWED_BY_MEMBER`,
      { headers: liHeaders }
    )
    if (networkResp.ok) {
      const networkData = await networkResp.json()
      followers = parseInteger(networkData?.firstDegreeSize)
    } else {
      console.warn(`LinkedIn networkSizes ${networkResp.status}: ${(await networkResp.text()).slice(0, 300)}`)
    }

    // ── Lifetime share statistics (impressions, clicks, engagement) ──
    const shareResp = await fetchWithRetry(
      `https://api.linkedin.com/rest/organizationalEntityShareStatistics?q=organizationalEntity&organizationalEntity=${encodeURIComponent(orgUrn)}`,
      { headers: liHeaders }
    )

    let reach: number | null = null
    let engagement: number | null = null
    let shareExtras: Record<string, unknown> = {}
    if (shareResp.ok) {
      const shareData = await shareResp.json()
      const totals = shareData?.elements?.[0]?.totalShareStatistics
      if (totals) {
        reach = parseInteger(totals.impressionCount)
        // LinkedIn supplies an official org engagement rate
        // ((clicks+likes+comments+shares)/impressions). Use it when present,
        // else fall back to clicks/impressions.
        if (typeof totals.engagement === 'number') {
          engagement = parseEngagement(totals.engagement)
        } else {
          const clicks = totals.clickCount || 0
          const impressions = totals.impressionCount || 1
          engagement = parseEngagement(clicks / impressions)
        }
        shareExtras = {
          unique_impressions: parseInteger(totals.uniqueImpressionsCount),
          clicks: parseInteger(totals.clickCount),
          likes: parseInteger(totals.likeCount),
          comments: parseInteger(totals.commentCount),
          shares: parseInteger(totals.shareCount),
        }
      }
    } else {
      console.warn(`LinkedIn shareStatistics ${shareResp.status}: ${(await shareResp.text()).slice(0, 300)}`)
    }

    metrics.push({
      metric_date: today,
      channel: 'linkedin',
      audience: followers,
      reach,
      engagement_rate: engagement,
      leads: null,
      source: 'api',
      payload: {
        api: 'linkedin_org_stats',
        version: LINKEDIN_VERSION,
        followers_source: 'networkSizes',
        ...shareExtras,
      },
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
  // #889: transient — source image to cache (IG IMAGE posts have no thumbnail_url,
  // only media_url). NOT persisted to comms_media_items; used only by cacheMediaImage.
  media_url?: string | null
  published_at: string | null
  likes: number
  comments: number
  shares: number
  saves: number
  reach: number | null
  views: number | null
  payload: Record<string, unknown>
}

// #889: download a remote image (IG thumbnail/media URL — short-lived cdninstagram)
// and cache it in the public 'comms-media' bucket; returns the stable public URL.
// Non-fatal: any failure returns null and the caller leaves cached_image_url unset.
async function cacheMediaImage(sb: any, channel: string, externalId: string, srcUrl: string): Promise<string | null> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort('timeout'), 15_000)
  try {
    const res = await fetch(srcUrl, { signal: controller.signal })
    if (!res.ok) return null
    const ct = (res.headers.get('content-type') || '').toLowerCase()
    if (!ct.startsWith('image/')) return null
    const bytes = new Uint8Array(await res.arrayBuffer())
    if (bytes.byteLength === 0 || bytes.byteLength > 5_000_000) return null
    const ext = ct.includes('png') ? 'png' : ct.includes('webp') ? 'webp' : 'jpg'
    const path = `${channel}/${externalId}.${ext}`
    const { error } = await sb.storage.from('comms-media').upload(path, bytes, { upsert: true, contentType: ct })
    if (error) { console.warn('comms-media upload failed', externalId, error.message); return null }
    const { data } = sb.storage.from('comms-media').getPublicUrl(path)
    return data?.publicUrl || null
  } catch (e) {
    console.warn('cacheMediaImage failed', externalId, e instanceof Error ? e.message : e)
    return null
  } finally {
    clearTimeout(timer)
  }
}

async function fetchInstagramMedia(cfg: ChannelConfig): Promise<MediaItem[]> {
  const token = cfg.oauth_token
  const igUserId = (cfg.config as any)?.ig_user_id
  if (!token || !igUserId) return []

  const items: MediaItem[] = []
  try {
    // Fetch recent media list
    const mediaResp = await fetchWithRetry(
      // #889: media_url added — IG IMAGE posts return no thumbnail_url (video-only field);
      // media_url is the image source for those. Both are short-lived cdninstagram URLs,
      // which is why we cache them to Storage below.
      `https://graph.facebook.com/v19.0/${igUserId}/media?fields=id,caption,media_type,timestamp,like_count,comments_count,permalink,thumbnail_url,media_url&limit=25&access_token=${token}`
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
        media_url: m.media_url || null,
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

// ─── LinkedIn 3-legged token auto-refresh ───
// LinkedIn access tokens live 60 days; the stored refresh token lives ~1 year.
// When the access token is expired/expiring (or force=true for verification),
// exchange the refresh token for a fresh access token (LinkedIn rotates the
// refresh token too) and persist. Requires LINKEDIN_CLIENT_ID + _SECRET as EF
// secrets. No-op for non-LinkedIn channels. Returns the (possibly updated) cfg;
// on any failure leaves the stored token untouched (downstream flags expiry).
async function maybeRefreshLinkedInToken(
  sb: SupabaseClient<any, "public", any>,
  cfg: ChannelConfig,
  force = false,
): Promise<ChannelConfig> {
  if (cfg.channel !== 'linkedin' || !cfg.oauth_refresh_token) return cfg

  const expiresAt = cfg.token_expires_at ? new Date(cfg.token_expires_at).getTime() : 0
  const needsRefresh = force || !cfg.oauth_token || !expiresAt || expiresAt < Date.now() + SEVEN_DAYS_MS
  if (!needsRefresh) return cfg

  const clientId = Deno.env.get('LINKEDIN_CLIENT_ID')
  const clientSecret = Deno.env.get('LINKEDIN_CLIENT_SECRET')
  if (!clientId || !clientSecret) {
    console.warn('LinkedIn token needs refresh but LINKEDIN_CLIENT_ID/LINKEDIN_CLIENT_SECRET not configured')
    return cfg
  }

  try {
    const form = new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: cfg.oauth_refresh_token,
      client_id: clientId,
      client_secret: clientSecret,
    })
    const resp = await fetchWithRetry('https://www.linkedin.com/oauth/v2/accessToken', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form.toString(),
    }, 2)

    if (!resp.ok) {
      console.warn(`LinkedIn token refresh ${resp.status}: ${(await resp.text()).slice(0, 300)}`)
      return cfg
    }

    const data = await resp.json()
    const newToken = data?.access_token as string | undefined
    if (!newToken) {
      console.warn('LinkedIn token refresh: response missing access_token')
      return cfg
    }
    const expiresIn = Number(data.expires_in) || 0
    const newExpiry = new Date(Date.now() + expiresIn * 1000).toISOString()
    // LinkedIn rotates the refresh token — keep the new one (fall back to the old).
    const newRefresh = (data.refresh_token as string | undefined) || cfg.oauth_refresh_token
    const refreshExpiresIn = Number(data.refresh_token_expires_in) || 0

    const newConfig = {
      ...(cfg.config || {}),
      token_refreshed_at: new Date().toISOString(),
      ...(refreshExpiresIn
        ? { refresh_token_expires_at: new Date(Date.now() + refreshExpiresIn * 1000).toISOString() }
        : {}),
    }

    const { error: updErr } = await sb.from('comms_channel_config').update({
      oauth_token: newToken,
      oauth_refresh_token: newRefresh,
      token_expires_at: newExpiry,
      config: newConfig,
      sync_status: 'active',
    }).eq('channel', 'linkedin')
    if (updErr) {
      console.warn('LinkedIn token refresh persist failed:', updErr.message)
      return cfg
    }

    console.log(`LinkedIn token refreshed (force=${force}); new access expiry ${newExpiry}`)
    return { ...cfg, oauth_token: newToken, oauth_refresh_token: newRefresh, token_expires_at: newExpiry, config: newConfig }
  } catch (e) {
    console.warn('LinkedIn token refresh error:', e instanceof Error ? e.message : String(e))
    return cfg
  }
}

// ─── Per-channel sync orchestrator ───

async function syncFromChannelConfigs(
  sb: SupabaseClient<any, "public", any>,
  triggeredBy: string,
  dryRun: boolean,
  filterChannels?: string[],
  forceRefresh = false,
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

    // Auto-refresh the LinkedIn 3-legged token when expired/expiring (no-op for
    // other channels). Skipped on dry-run to keep it side-effect free, unless
    // forceRefresh is set (verification path).
    let activeCfg = cfg
    if (!dryRun || forceRefresh) {
      activeCfg = await maybeRefreshLinkedInToken(sb, cfg, forceRefresh)
    }

    // Check token validity
    if (!isTokenValid(activeCfg)) {
      await sb.from('comms_channel_config')
        .update({ sync_status: 'token_expired' })
        .eq('channel', activeCfg.channel)
      channelResults.push({ channel: activeCfg.channel, status: 'token_expired' })
      continue
    }

    // Check if expiring soon (still sync but flag)
    if (isTokenExpiringSoon(activeCfg)) {
      channelResults.push({ channel: activeCfg.channel, warning: 'token_expiring_soon' })
    }

    const runKey = `${RUN_KEY_PREFIX}_${activeCfg.channel}_${new Date().toISOString()}`

    try {
      const metrics = await fetcher(activeCfg)

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
          const mediaItems = await mediaFetcher(activeCfg)
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

            // #889: cache Instagram thumbnails to Storage (cdninstagram URLs expire;
            // image posts have no thumbnail_url at all). Idempotent (skip already-cached)
            // and non-fatal (a download failure never breaks the metrics sync).
            if (cfg.channel === 'instagram') {
              try {
                const ids = mediaItems.map(m => m.external_id)
                const { data: existing } = await sb
                  .from('comms_media_items')
                  .select('external_id, cached_image_url')
                  .eq('channel', 'instagram')
                  .in('external_id', ids)
                const alreadyCached = new Set(
                  (existing || []).filter((r: any) => r.cached_image_url).map((r: any) => r.external_id)
                )
                for (const m of mediaItems) {
                  if (alreadyCached.has(m.external_id)) continue
                  // video → thumbnail_url (an image); image/carousel → media_url
                  const src = m.media_type === 'VIDEO' ? m.thumbnail_url : (m.media_url || m.thumbnail_url)
                  if (!src) continue
                  const publicUrl = await cacheMediaImage(sb, 'instagram', m.external_id, src)
                  if (publicUrl) {
                    await sb.from('comms_media_items')
                      .update({ cached_image_url: publicUrl })
                      .eq('channel', 'instagram')
                      .eq('external_id', m.external_id)
                  }
                }
              } catch (e) { console.warn('Comms media cache:', e) }
            }
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
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const bearer = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '')
  const headerSecret = req.headers.get('x-sync-secret')

  // Accept either SYNC_COMMS_METRICS_SECRET or service_role_key (for pg_cron)
  const validSecrets = [syncSecret, serviceKey].filter(Boolean)
  if (!validSecrets.length || (!validSecrets.includes(bearer ?? '') && !validSecrets.includes(headerSecret ?? ''))) {
    return unauthorizedResponse()
  }

  const sb = createClient<any, "public", any>(
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
    const result = await syncFromChannelConfigs(sb, triggeredBy, dryRun, body.channels, !!body.force_refresh)

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
