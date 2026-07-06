// publish-instagram — organic content publishing to the Núcleo Instagram
// (@nucleo.ia.gp) via the Instagram Graph API (Facebook Login path).
//
// Mirrors sync-comms-metrics: reads the permanent Page token + ig_user_id from
// comms_channel_config (channel='instagram'), so reading insights and publishing
// share ONE credential. The token must carry the instagram_content_publish scope.
//
// Two-step publish per Meta docs: create a media container (POST /{ig}/media) then
// publish it (POST /{ig}/media_publish). Video/Reels containers are async → poll
// status_code until FINISHED. Media is referenced by PUBLIC URL (use the
// comms-media Storage bucket), Graph fetches it server-side.
//
// Auth: Bearer or x-sync-secret = INSTAGRAM_PUBLISH_SECRET or SUPABASE_SERVICE_ROLE_KEY.
// Invoke with dry_run:true to build the container WITHOUT publishing (safe E2E check).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { isServiceRoleToken } from '../_shared/service-auth.ts'

const GRAPH = 'https://graph.facebook.com/v19.0'

type MediaType = 'IMAGE' | 'CAROUSEL' | 'REELS' | 'STORIES'

interface CarouselChild {
  image_url?: string
  video_url?: string
}

interface PublishPayload {
  media_type?: MediaType
  image_url?: string
  video_url?: string
  caption?: string
  children?: CarouselChild[]
  share_to_feed?: boolean // Reels: also show in the main grid (default true)
  dry_run?: boolean // build container(s) but do not publish
}

interface ChannelConfig {
  channel: string
  oauth_token: string | null
  config: Record<string, unknown>
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// POST to the Graph API with params in the query string (Meta's publishing
// endpoints accept this). Returns parsed JSON or throws with the Graph error.
async function graphPost(path: string, params: Record<string, string>, token: string): Promise<any> {
  const qs = new URLSearchParams({ ...params, access_token: token }).toString()
  const res = await fetch(`${GRAPH}/${path}?${qs}`, { method: 'POST' })
  const data = await res.json().catch(() => ({}))
  if (!res.ok || data?.error) {
    const e = data?.error
    throw new Error(`Graph POST /${path} failed: ${e?.message ?? res.status} (code ${e?.code ?? '?'}, subcode ${e?.error_subcode ?? '-'})`)
  }
  return data
}

async function graphGet(path: string, fields: string, token: string): Promise<any> {
  const res = await fetch(`${GRAPH}/${path}?fields=${fields}&access_token=${token}`)
  const data = await res.json().catch(() => ({}))
  if (!res.ok || data?.error) {
    throw new Error(`Graph GET /${path} failed: ${data?.error?.message ?? res.status}`)
  }
  return data
}

// Reels/video containers finish processing asynchronously. Poll status_code.
async function waitForContainer(containerId: string, token: string, maxTries = 30, delayMs = 4000): Promise<void> {
  for (let i = 0; i < maxTries; i++) {
    const { status_code } = await graphGet(containerId, 'status_code', token)
    if (status_code === 'FINISHED') return
    if (status_code === 'ERROR' || status_code === 'EXPIRED') {
      throw new Error(`Container ${containerId} processing ${status_code}`)
    }
    await new Promise(r => setTimeout(r, delayMs))
  }
  throw new Error(`Container ${containerId} not FINISHED after ${maxTries} polls`)
}

// Build the (single) container to publish and return its creation id.
async function buildContainer(
  igUserId: string,
  token: string,
  p: PublishPayload,
): Promise<string> {
  const mt: MediaType = p.media_type ?? 'IMAGE'
  const caption = p.caption ?? ''

  if (mt === 'IMAGE') {
    if (!p.image_url) throw new Error('IMAGE requires image_url')
    const { id } = await graphPost(`${igUserId}/media`, { image_url: p.image_url, caption }, token)
    return id
  }

  if (mt === 'STORIES') {
    const params: Record<string, string> = { media_type: 'STORIES' }
    if (p.image_url) params.image_url = p.image_url
    else if (p.video_url) params.video_url = p.video_url
    else throw new Error('STORIES requires image_url or video_url')
    const { id } = await graphPost(`${igUserId}/media`, params, token)
    // Story containers (image included) must reach FINISHED before publish, else
    // media_publish returns 9007/2207027 "Media ID is not available".
    await waitForContainer(id, token)
    return id
  }

  if (mt === 'REELS') {
    if (!p.video_url) throw new Error('REELS requires video_url')
    const { id } = await graphPost(`${igUserId}/media`, {
      media_type: 'REELS',
      video_url: p.video_url,
      caption,
      share_to_feed: String(p.share_to_feed !== false),
    }, token)
    await waitForContainer(id, token)
    return id
  }

  if (mt === 'CAROUSEL') {
    const children = p.children ?? []
    if (children.length < 2 || children.length > 10) {
      throw new Error('CAROUSEL requires 2-10 children')
    }
    const childIds: string[] = []
    for (const child of children) {
      const params: Record<string, string> = { is_carousel_item: 'true' }
      if (child.image_url) params.image_url = child.image_url
      else if (child.video_url) { params.media_type = 'VIDEO'; params.video_url = child.video_url }
      else throw new Error('each carousel child needs image_url or video_url')
      const { id } = await graphPost(`${igUserId}/media`, params, token)
      if (child.video_url) await waitForContainer(id, token)
      childIds.push(id)
    }
    const { id } = await graphPost(`${igUserId}/media`, {
      media_type: 'CAROUSEL',
      children: childIds.join(','),
      caption,
    }, token)
    // The carousel parent container must reach FINISHED before media_publish, else
    // Graph returns 9007/2207027 "Media ID is not available" (same trap the STORIES
    // branch documents; hit live on the first CAROUSEL publish, 2026-07-04).
    await waitForContainer(id, token)
    return id
  }

  throw new Error(`unsupported media_type: ${mt}`)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ success: false, error: 'POST only' }, 405)

  // Auth: dedicated secret (manual callers) OR a cryptographically-verified service_role token.
  // INSTAGRAM_PUBLISH_SECRET is a shared secret for manual callers. The pg_cron drain delegates
  // via publish-scheduled which sends a service JWT; a dispatcher could also send the vault
  // `service_role_key` — a genuine service credential but NOT the env-injected key (the #738/#849
  // trap) — so it must be verified via PostgREST, never literal-compared (#928). Mirrors
  // publish-scheduled / publish-linkedin.
  const publishSecret = Deno.env.get('INSTAGRAM_PUBLISH_SECRET')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const bearer = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '')
  const headerSecret = req.headers.get('x-sync-secret')
  const secretOk = !!publishSecret && (bearer === publishSecret || headerSecret === publishSecret)
  const serviceOk = await isServiceRoleToken(supabaseUrl, bearer)
  if (!secretOk && !serviceOk) {
    return json({ success: false, error: 'Unauthorized' }, 401)
  }

  const sb = createClient<any, "public", any>(supabaseUrl, serviceKey!)
  const payload: PublishPayload = await req.json().catch(() => ({}))

  // Load the Instagram channel credential (same row the metrics cron reads).
  const { data: cfg, error: cfgErr } = await sb
    .from('comms_channel_config')
    .select('channel, oauth_token, config')
    .eq('channel', 'instagram')
    .maybeSingle()

  if (cfgErr || !cfg) return json({ success: false, error: 'instagram channel config not found' }, 500)
  const token = (cfg as ChannelConfig).oauth_token
  const igUserId = ((cfg as ChannelConfig).config as any)?.ig_user_id as string | undefined
  if (!token || !igUserId) return json({ success: false, error: 'missing oauth_token or ig_user_id' }, 500)

  try {
    const creationId = await buildContainer(igUserId, token, payload)

    if (payload.dry_run) {
      return json({ success: true, dry_run: true, creation_id: creationId, published: false })
    }

    const { id: mediaId } = await graphPost(`${igUserId}/media_publish`, { creation_id: creationId }, token)

    // Record the published item (best-effort; a failure here does not unpublish).
    let permalink: string | null = null
    try {
      const info = await graphGet(mediaId, 'permalink,media_type,timestamp', token)
      permalink = info?.permalink ?? null
      await sb.from('comms_media_items').upsert({
        channel: 'instagram',
        external_id: mediaId,
        media_type: info?.media_type ?? payload.media_type ?? null,
        caption: payload.caption ?? null,
        permalink,
        published_at: info?.timestamp ?? new Date().toISOString(),
        payload: { source: 'publish-instagram' },
        synced_at: new Date().toISOString(),
      }, { onConflict: 'channel,external_id' })
    } catch (recErr) {
      console.warn('publish-instagram: record step failed', String(recErr))
    }

    return json({ success: true, published: true, media_id: mediaId, permalink, creation_id: creationId })
  } catch (err) {
    return json({ success: false, error: String(err instanceof Error ? err.message : err) }, 502)
  }
})
