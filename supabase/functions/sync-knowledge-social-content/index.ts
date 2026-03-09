import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/**
 * sync-knowledge-social-content
 * Ingests social media post content (LinkedIn, Instagram) from either:
 * 1. A Trello Social Media board JSON export (cards with text/links)
 * 2. Future: Direct API payloads from social platform integrations
 *
 * Each post is stored in hub_resources with source='social',
 * curation_status='pending_review' for Human-in-the-Loop approval.
 */

interface SocialPost {
  platform: string
  title: string
  body?: string
  url?: string
  date?: string
  tags?: string[]
  author?: string
}

Deno.serve(async (req) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
  const json = (d: Record<string, unknown>, s = 200) =>
    new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  let raw = ''
  try { raw = await req.text() } catch { raw = '' }

  try {
    if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const srk = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? ''

    const ah = req.headers.get('Authorization') ?? ''
    const tk = ah.replace(/^Bearer\s+/i, '').trim()
    if (!tk) return json({ error: 'No token' }, 401)

    const uc = createClient(url, anon, { global: { headers: { Authorization: 'Bearer ' + tk } } })
    const ur = await uc.auth.getUser()
    if (ur.error || !ur.data?.user) return json({ error: 'Bad token' }, 401)

    const sb = createClient(url, srk)

    const cr = await sb.from('members')
      .select('id, is_superadmin, operational_role')
      .eq('auth_id', ur.data.user.id).single()
    if (!cr.data) return json({ error: 'No member' }, 403)

    const isAdmin = cr.data.is_superadmin === true
      || cr.data.operational_role === 'manager'
      || cr.data.operational_role === 'deputy_manager'
    if (!isAdmin) return json({ error: 'Admin access required' }, 403)

    let payload: { posts?: SocialPost[]; trello_json?: any } = {}
    try { payload = JSON.parse(raw) } catch { return json({ error: 'Bad JSON' }, 400) }

    const posts: SocialPost[] = []

    // Mode 1: Direct posts array
    if (Array.isArray(payload.posts)) {
      posts.push(...payload.posts)
    }

    // Mode 2: Trello Social Media board JSON
    if (payload.trello_json) {
      const board = payload.trello_json
      const cards = board.cards || []
      for (const card of cards) {
        if (card.closed) continue
        const platform = detectPlatform(card.name || '', card.desc || '')
        posts.push({
          platform,
          title: card.name || 'Untitled Post',
          body: card.desc || '',
          url: card.shortUrl || card.url || '',
          date: card.dateLastActivity || card.due || new Date().toISOString(),
          tags: (card.labels || []).map((l: any) => l.name?.toLowerCase()).filter(Boolean),
          author: card.idMembers?.[0] || undefined,
        })
      }
    }

    if (!posts.length) return json({ error: 'No posts to process' }, 400)

    let inserted = 0
    let skipped = 0

    for (const post of posts) {
      const suggestedTags = autoTagSocial(post)

      const { error } = await sb.from('hub_resources').upsert({
        title: post.title.substring(0, 500),
        description: (post.body || '').substring(0, 2000),
        url: post.url || '',
        asset_type: 'reference',
        source: 'social',
        tags: [...new Set([...(post.tags || []), ...suggestedTags])],
        curation_status: 'pending_review',
        is_active: false,
      }, { onConflict: 'title', ignoreDuplicates: true })

      if (error) {
        console.warn('Insert error:', error.message)
        skipped++
      } else {
        inserted++
      }
    }

    return json({
      success: true,
      total_posts: posts.length,
      inserted,
      skipped,
    })

  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err)
    return json({ error: 'Internal error', detail: msg }, 500)
  }
})

function detectPlatform(title: string, body: string): string {
  const text = (title + ' ' + body).toLowerCase()
  if (text.includes('linkedin')) return 'linkedin'
  if (text.includes('instagram') || text.includes('insta')) return 'instagram'
  if (text.includes('youtube') || text.includes('youtu.be')) return 'youtube'
  if (text.includes('twitter') || text.includes('x.com')) return 'twitter'
  return 'other'
}

function autoTagSocial(post: SocialPost): string[] {
  const tags: string[] = []
  const text = ((post.title || '') + ' ' + (post.body || '')).toLowerCase()

  if (text.includes('webinar') || text.includes('pmi')) tags.push('webinar')
  if (text.includes('capitulo') || text.includes('chapter') || text.includes('pmi-')) tags.push('chapter_partnership')
  if (text.includes('artigo') || text.includes('article') || text.includes('publicacao')) tags.push('article')
  if (text.includes('curso') || text.includes('course') || text.includes('trilha')) tags.push('course')
  if (text.includes('voluntari') || text.includes('impacto')) tags.push('volunteer_hours')

  if (post.platform === 'linkedin') tags.push('external_talk')
  if (post.platform === 'youtube') tags.push('webinar')

  if (tags.length === 0) tags.push('untagged')
  return [...new Set(tags)]
}
