import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { classifyBadge, PMI_TRAIL_KEYWORDS } from '../_shared/classify-badge.ts'

// Retry with exponential backoff for external API calls
async function fetchWithRetry(url: string, options: RequestInit, maxRetries = 3): Promise<Response> {
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

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// classifyBadge and PMI_TRAIL_KEYWORDS imported from _shared/classify-badge.ts (GC-083)

interface CredlyBadge {
  badge_template: { name: string; vanity_slug?: string }
  issued_at: string
  expires_at: string | null
  state: string
}

const USERNAME_RE = /^[A-Za-z0-9._-]{2,100}$/

function extractUsername(url: string): string | null {
  const raw = (url || '').replace(/[\u200B-\u200D\uFEFF]/g, '').trim()
  if (!raw) return null

  if (USERNAME_RE.test(raw) && !raw.includes('/')) return raw

  const withScheme = /^https?:\/\//i.test(raw) ? raw : `https://${raw}`
  try {
    const parsed = new URL(withScheme)
    const host = parsed.hostname.toLowerCase().replace(/^www\./, '')
    if (!host.endsWith('credly.com')) return null

    const segments = parsed.pathname.split('/').filter(Boolean)
    const usersIndex = segments.findIndex((s) => s.toLowerCase() === 'users')
    if (usersIndex === -1 || !segments[usersIndex + 1]) return null

    const username = decodeURIComponent(segments[usersIndex + 1]).trim()
    return USERNAME_RE.test(username) ? username : null
  } catch {
    return null
  }
}

async function fetchBadges(username: string): Promise<CredlyBadge[]> {
  const resp = await fetchWithRetry(`https://www.credly.com/users/${username}/badges.json`, {
    headers: { 'Accept': 'application/json', 'User-Agent': 'NucleoIA-GP/1.0' },
  })
  if (!resp.ok) throw new Error(`Credly ${resp.status}: ${username}`)
  const data = await resp.json()
  return data.data || data || []
}

async function upsertCredlyPoints(
  sb: ReturnType<typeof createClient>,
  memberId: string,
  badge: { name: string; points: number; issued_at: string; category: string },
) {
  const reason = `Credly: ${badge.name}`
  const { data: rows, error: rowsError } = await sb.from('gamification_points')
    .select('id, points, category, created_at')
    .eq('member_id', memberId)
    .eq('reason', reason)
    .order('created_at', { ascending: true })
    .order('id', { ascending: true })

  if (rowsError) throw rowsError

  if (!rows || rows.length === 0) {
    const { error: insertError } = await sb.from('gamification_points').insert({
      member_id: memberId,
      points: badge.points,
      reason,
      category: badge.category,
      created_at: badge.issued_at || new Date().toISOString(),
    })
    if (insertError) throw insertError
    return
  }

  const keeper = rows[0]
  const needsUpdate = keeper.points !== badge.points || keeper.category !== badge.category
  if (needsUpdate) {
    const { error: updateError } = await sb.from('gamification_points')
      .update({ points: badge.points, category: badge.category })
      .eq('id', keeper.id)
    if (updateError) throw updateError
  }

  if (rows.length > 1) {
    const dupIds = rows.slice(1).map(r => r.id)
    const { error: deleteDupError } = await sb.from('gamification_points')
      .delete()
      .in('id', dupIds)
    if (deleteDupError) throw deleteDupError
  }
}

async function syncTrailProgressFromCredly(
  sb: ReturnType<typeof createClient>,
  memberId: string,
  pmiTrail: { code: string; issued_at: string }[],
) {
  if (!pmiTrail.length) return { synced: 0, missingCourses: [] as string[] }

  const trailCodes = Array.from(new Set(pmiTrail.map((t) => t.code).filter(Boolean)))
  const { data: courses, error: coursesError } = await sb
    .from('courses')
    .select('id, code')
    .in('code', trailCodes)

  if (coursesError) throw coursesError

  const codeToCourseId = new Map<string, string>()
  for (const c of courses || []) {
    if (c?.code && c?.id) codeToCourseId.set(String(c.code), String(c.id))
  }

  let synced = 0
  const missingCourses: string[] = []

  for (const t of pmiTrail) {
    const courseId = codeToCourseId.get(t.code)
    if (!courseId) {
      missingCourses.push(t.code)
      continue
    }

    const { data: existingRows, error: existingError } = await sb
      .from('course_progress')
      .select('id, status')
      .eq('member_id', memberId)
      .eq('course_id', courseId)
      .limit(20)

    if (existingError) throw existingError

    if (!existingRows || existingRows.length === 0) {
      const { error: insertError } = await sb.from('course_progress').insert({
        member_id: memberId,
        course_id: courseId,
        status: 'completed',
      })
      if (insertError) throw insertError
      synced++
      continue
    }

    const hasCompleted = existingRows.some((r: any) => r.status === 'completed')
    if (!hasCompleted) {
      const { error: updateError } = await sb
        .from('course_progress')
        .update({ status: 'completed' })
        .eq('member_id', memberId)
        .eq('course_id', courseId)
      if (updateError) throw updateError
      synced++
    }
  }

  return { synced, missingCourses }
}

// classifyBadge imported from _shared/classify-badge.ts (GC-083 — W143-aligned 10 categories)

function analyzeBadges(badges: CredlyBadge[]) {
  const pmiTrail: { code: string; name: string; issued_at: string }[] = []
  const cpmai: { name: string; issued_at: string }[] = []
  const all: { name: string; issued_at: string; slug: string; category: string; points: number }[] = []

  for (const b of badges) {
    const name = b.badge_template?.name || ''
    const slug = b.badge_template?.vanity_slug || ''
    const classification = classifyBadge(name, slug)

    all.push({
      name,
      issued_at: b.issued_at,
      slug,
      category: classification.category,
      points: classification.points,
    })

    if (classification.category === 'trail') {
      const combined = (name + ' ' + slug).toLowerCase()
      for (const trail of PMI_TRAIL_KEYWORDS) {
        if (trail.keywords.every(kw => combined.includes(kw))) {
          pmiTrail.push({ code: trail.code, name, issued_at: b.issued_at })
          break
        }
      }
    }

    if (classification.category === 'cert_cpmai') {
      cpmai.push({ name, issued_at: b.issued_at })
    }
  }

  return { pmiTrail, cpmai, all, hasCPMAI: cpmai.length > 0, totalPoints: all.reduce((sum, b) => sum + b.points, 0) }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { member_id, credly_url } = await req.json()
    const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

    // Resolve username
    let username: string | null = credly_url ? extractUsername(credly_url) : null

    if (!username && member_id) {
      const { data: m } = await sb.from('members').select('credly_url').eq('id', member_id).single()
      if (m?.credly_url) username = extractUsername(m.credly_url)
    }

    if (!username) {
      return new Response(JSON.stringify({
        success: false,
        error: 'No Credly URL found. Add your public Credly profile URL in Profile settings.',
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
    }

    // Fetch and analyze
    const badges = await fetchBadges(username)
    const result = analyzeBadges(badges)

    // Update member if ID provided
    if (member_id) {
      const canonicalCredlyUrl = `https://www.credly.com/users/${username}`
      await sb.from('members').update({
        credly_verified_at: new Date().toISOString(),
        credly_badges: result.all.filter(b => b.category !== 'badge'),
        cpmai_certified: result.hasCPMAI,
        cpmai_certified_at: result.cpmai[0]?.issued_at || null,
        credly_url: credly_url || canonicalCredlyUrl,
        credly_profile_url: canonicalCredlyUrl,
      }).eq('id', member_id)

      // Award gamification points (with tier-based scoring)
      for (const badge of result.all) {
        await upsertCredlyPoints(sb, member_id, badge)
      }

      // Remove old manual course points that Credly now covers
      for (const trail of result.pmiTrail) {
        await sb.from('gamification_points')
          .delete()
          .eq('member_id', member_id)
          .eq('category', 'course')
          .ilike('reason', `curso:%${trail.code}%`)
      }

      // Keep trail source-of-truth aligned with Credly verification.
      // This updates course_progress used by /#trail and other UX panels.
      const trailSync = await syncTrailProgressFromCredly(
        sb,
        member_id,
        result.pmiTrail.map((t) => ({ code: t.code, issued_at: t.issued_at })),
      )

      return new Response(JSON.stringify({
        success: true,
        credly_username: username,
        total_badges: badges.length,
        pmi_trail: result.pmiTrail,
        pmi_trail_count: result.pmiTrail.length,
        pmi_trail_synced: trailSync.synced,
        pmi_trail_missing_courses: trailSync.missingCourses,
        cpmai: result.cpmai,
        has_cpmai: result.hasCPMAI,
        all_matched: result.all.filter(b => b.category !== 'badge').length,
        total_points: result.totalPoints,
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    return new Response(JSON.stringify({
      success: true,
      credly_username: username,
      total_badges: badges.length,
      pmi_trail: result.pmiTrail,
      pmi_trail_count: result.pmiTrail.length,
      cpmai: result.cpmai,
      has_cpmai: result.hasCPMAI,
      all_matched: result.all.filter(b => b.category !== 'badge').length,
      total_points: result.totalPoints,
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (err: any) {
  return new Response(
    JSON.stringify({ success: false, error: err?.message || 'Unknown error' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
  }
})
