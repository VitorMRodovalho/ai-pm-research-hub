// publish-linkedin — organic content publishing to the Núcleo LinkedIn company
// page (/company/nucleo-ia) via the versioned Community Management API (/rest/posts).
//
// Mirrors publish-instagram: reads the org token + organization_urn from
// comms_channel_config (channel='linkedin') — the SAME row sync-comms-metrics reads
// for follower/engagement stats. Reading metrics and publishing share one credential;
// the token must carry the w_organization_social scope (publishing) on top of the
// read scopes. Token freshness (60d access / auto-refresh) is maintained by
// sync-comms-metrics' refreshLinkedInToken; this function uses the current token and
// surfaces LinkedIn's 401 if it has gone stale (the row then retries).
//
// Unlike Instagram (Graph fetches media from a public URL server-side), LinkedIn
// requires us to UPLOAD the bytes: initializeUpload -> PUT binary -> reference the
// returned asset URN in the post. We fetch image_url/video_url (public comms-media
// bucket) and relay the bytes.
//
// Post types (payload.post_type): TEXT, IMAGE, VIDEO, ARTICLE (link). LinkedIn
// linkifies bare URLs in the commentary, so TEXT with a URL gives a clickable CTA
// (unlike IG's "link in bio"); ARTICLE renders a rich link card.
//
// Auth: Bearer / x-sync-secret = INSTAGRAM_PUBLISH_SECRET (shared comms-publish
// manual secret) OR a cryptographically valid service_role token (the pg_cron drain
// path, verified via isServiceRoleToken — never literal-compared, #738/#850/#928).
// Invoke with dry_run:true to validate config + payload WITHOUT uploading or posting.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { isServiceRoleToken } from '../_shared/service-auth.ts'

const LINKEDIN_API = 'https://api.linkedin.com/rest'
// Keep in lockstep with sync-comms-metrics' LINKEDIN_VERSION (versioned API moniker).
const LINKEDIN_VERSION = '202606'

type PostType = 'TEXT' | 'IMAGE' | 'VIDEO' | 'ARTICLE'

interface PublishPayload {
  post_type?: PostType
  text?: string             // commentary (URLs are auto-linkified by LinkedIn)
  image_url?: string        // public URL to fetch + upload
  video_url?: string        // public URL to fetch + upload
  alt_text?: string         // image alt text
  title?: string            // video title / article title
  article_url?: string      // ARTICLE: the link to render as a card
  article_description?: string
  dry_run?: boolean
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

function liHeaders(token: string): Record<string, string> {
  return {
    'Authorization': `Bearer ${token}`,
    'LinkedIn-Version': LINKEDIN_VERSION,
    'X-Restli-Protocol-Version': '2.0.0',
    'Content-Type': 'application/json',
  }
}

async function fetchMediaBytes(url: string): Promise<Uint8Array> {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`fetch media ${url} -> ${res.status}`)
  return new Uint8Array(await res.arrayBuffer())
}

// Image: initializeUpload -> PUT bytes -> return the image URN.
async function uploadImage(orgUrn: string, token: string, imageUrl: string): Promise<string> {
  const initRes = await fetch(`${LINKEDIN_API}/images?action=initializeUpload`, {
    method: 'POST',
    headers: liHeaders(token),
    body: JSON.stringify({ initializeUploadRequest: { owner: orgUrn } }),
  })
  const initData = await initRes.json().catch(() => ({}))
  if (!initRes.ok) throw new Error(`image initializeUpload ${initRes.status}: ${JSON.stringify(initData).slice(0, 300)}`)
  const uploadUrl = initData?.value?.uploadUrl
  const imageUrn = initData?.value?.image
  if (!uploadUrl || !imageUrn) throw new Error('image initializeUpload missing uploadUrl/image')

  const bytes = await fetchMediaBytes(imageUrl)
  const putRes = await fetch(uploadUrl, {
    method: 'PUT',
    headers: { 'Authorization': `Bearer ${token}` },
    body: bytes,
  })
  if (!putRes.ok) throw new Error(`image upload PUT ${putRes.status}`)
  return imageUrn
}

// Video: initializeUpload -> PUT each part (capturing ETags) -> finalizeUpload ->
// return the video URN. Small clips (the repurposed Reels MP4s) fit one part.
async function uploadVideo(orgUrn: string, token: string, videoUrl: string): Promise<string> {
  const bytes = await fetchMediaBytes(videoUrl)
  const initRes = await fetch(`${LINKEDIN_API}/videos?action=initializeUpload`, {
    method: 'POST',
    headers: liHeaders(token),
    body: JSON.stringify({
      initializeUploadRequest: {
        owner: orgUrn,
        fileSizeBytes: bytes.byteLength,
        uploadCaptions: false,
        uploadThumbnail: false,
      },
    }),
  })
  const initData = await initRes.json().catch(() => ({}))
  if (!initRes.ok) throw new Error(`video initializeUpload ${initRes.status}: ${JSON.stringify(initData).slice(0, 300)}`)
  const videoUrn = initData?.value?.video
  const uploadToken = initData?.value?.uploadToken ?? ''
  const instructions = initData?.value?.uploadInstructions ?? []
  if (!videoUrn || !instructions.length) throw new Error('video initializeUpload missing video/uploadInstructions')

  const uploadedPartIds: string[] = []
  for (const ins of instructions) {
    const part = bytes.subarray(ins.firstByte, ins.lastByte + 1)
    const putRes = await fetch(ins.uploadUrl, {
      method: 'PUT',
      headers: { 'Authorization': `Bearer ${token}` },
      body: part,
    })
    if (!putRes.ok) throw new Error(`video upload PUT ${putRes.status}`)
    const etag = putRes.headers.get('etag') ?? putRes.headers.get('ETag')
    if (etag) uploadedPartIds.push(etag.replaceAll('"', ''))
  }

  const finRes = await fetch(`${LINKEDIN_API}/videos?action=finalizeUpload`, {
    method: 'POST',
    headers: liHeaders(token),
    body: JSON.stringify({ finalizeUploadRequest: { video: videoUrn, uploadToken, uploadedPartIds } }),
  })
  if (!finRes.ok) throw new Error(`video finalizeUpload ${finRes.status}: ${(await finRes.text()).slice(0, 300)}`)
  return videoUrn
}

// Create the organization share. Returns { urn, permalink }.
async function createPost(
  orgUrn: string,
  token: string,
  p: PublishPayload,
): Promise<{ urn: string; permalink: string | null }> {
  const pt: PostType = p.post_type ?? 'TEXT'
  const body: Record<string, unknown> = {
    author: orgUrn,
    commentary: p.text ?? '',
    visibility: 'PUBLIC',
    distribution: { feedDistribution: 'MAIN_FEED', targetEntities: [], thirdPartyDistributionChannels: [] },
    lifecycleState: 'PUBLISHED',
    isReshareDisabledByAuthor: false,
  }

  if (pt === 'IMAGE') {
    if (!p.image_url) throw new Error('IMAGE requires image_url')
    const imageUrn = await uploadImage(orgUrn, token, p.image_url)
    body.content = { media: { id: imageUrn, altText: p.alt_text ?? '' } }
  } else if (pt === 'VIDEO') {
    if (!p.video_url) throw new Error('VIDEO requires video_url')
    const videoUrn = await uploadVideo(orgUrn, token, p.video_url)
    body.content = { media: { id: videoUrn, title: p.title ?? '' } }
  } else if (pt === 'ARTICLE') {
    if (!p.article_url) throw new Error('ARTICLE requires article_url')
    body.content = {
      article: {
        source: p.article_url,
        title: p.title ?? '',
        description: p.article_description ?? '',
      },
    }
  } else if (pt !== 'TEXT') {
    throw new Error(`unsupported post_type: ${pt}`)
  }

  const res = await fetch(`${LINKEDIN_API}/posts`, {
    method: 'POST',
    headers: liHeaders(token),
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    throw new Error(`POST /posts ${res.status}: ${(await res.text()).slice(0, 400)}`)
  }
  // The created post URN comes back in a response header, not the (empty) body.
  const urn = res.headers.get('x-restli-id') ?? res.headers.get('x-linkedin-id') ?? ''
  const permalink = urn ? `https://www.linkedin.com/feed/update/${urn}/` : null
  return { urn, permalink }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ success: false, error: 'POST only' }, 405)

  const publishSecret = Deno.env.get('INSTAGRAM_PUBLISH_SECRET')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const bearer = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '')
  const headerSecret = req.headers.get('x-sync-secret')

  // Manual callers use the shared comms-publish secret; the pg_cron drain sends the
  // vault service_role_key (a genuine but non-env service JWT — must be verified
  // cryptographically, never literal-compared: #738/#850/#928).
  const secretOk = !!publishSecret && (bearer === publishSecret || headerSecret === publishSecret)
  const serviceOk = await isServiceRoleToken(supabaseUrl, bearer)
  if (!secretOk && !serviceOk) {
    return json({ success: false, error: 'Unauthorized' }, 401)
  }

  const sb = createClient(supabaseUrl, serviceKey)
  const payload: PublishPayload = await req.json().catch(() => ({}))

  // Load the LinkedIn channel credential (same row the metrics cron reads).
  const { data: cfg, error: cfgErr } = await sb
    .from('comms_channel_config')
    .select('channel, oauth_token, config')
    .eq('channel', 'linkedin')
    .maybeSingle()

  if (cfgErr || !cfg) return json({ success: false, error: 'linkedin channel config not found' }, 500)
  const token = (cfg as ChannelConfig).oauth_token
  const orgUrn = ((cfg as ChannelConfig).config as any)?.organization_urn as string | undefined
  if (!token || !orgUrn) return json({ success: false, error: 'missing oauth_token or organization_urn' }, 500)

  // Validate payload shape up front (also the dry_run contract).
  const pt: PostType = payload.post_type ?? 'TEXT'
  if (pt === 'IMAGE' && !payload.image_url) return json({ success: false, error: 'IMAGE requires image_url' }, 400)
  if (pt === 'VIDEO' && !payload.video_url) return json({ success: false, error: 'VIDEO requires video_url' }, 400)
  if (pt === 'ARTICLE' && !payload.article_url) return json({ success: false, error: 'ARTICLE requires article_url' }, 400)
  if (pt === 'TEXT' && !payload.text) return json({ success: false, error: 'TEXT requires text' }, 400)

  if (payload.dry_run) {
    return json({ success: true, dry_run: true, post_type: pt, published: false })
  }

  try {
    const { urn, permalink } = await createPost(orgUrn, token, payload)

    // Record the published item (best-effort; mirrors publish-instagram).
    try {
      await sb.from('comms_media_items').upsert({
        channel: 'linkedin',
        external_id: urn,
        media_type: pt,
        caption: payload.text ?? payload.title ?? null,
        permalink,
        published_at: new Date().toISOString(),
        payload: { source: 'publish-linkedin' },
        synced_at: new Date().toISOString(),
      }, { onConflict: 'channel,external_id' })
    } catch (recErr) {
      console.warn('publish-linkedin: record step failed', String(recErr))
    }

    // media_id/permalink keys match publish-instagram so publish-scheduled is channel-agnostic.
    return json({ success: true, published: true, media_id: urn, permalink })
  } catch (err) {
    return json({ success: false, error: String(err instanceof Error ? err.message : err) }, 502)
  }
})
