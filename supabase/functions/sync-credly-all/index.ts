import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

// ── Tier 1: Master / Global Certifications (+50 XP) ──
const TIER1_KEYWORDS = [
  'pmp', 'cpmai', 'pmi-cpmai', 'cognitive project management',
  'pmi-acp', 'pmi-cp', 'pgmp', 'pfmp', 'pmi-rmp', 'pmi-sp',
  'project management professional',
]

// ── Tier 2: Specializations (+25 XP) ──
const TIER2_KEYWORDS = [
  'capm', 'pmi-pbsm', 'disciplined agile',
  'professional scrum master', 'psm', 'pspo',
  'safe', 'scaled agile', 'csm', 'certified scrum',
  'prosci', 'change management',
  'finops', 'aws certified', 'azure', 'google cloud certified',
  'data analyst', 'data engineer', 'data scientist',
  'itil', 'togaf', 'cobit',
  'business intelligence', 'scrum foundation', 'sfpc',
]

// ── PMI AI Trail (strict KPI tracking — Tier 3: +15 XP) ──
const PMI_TRAIL_KEYWORDS = [
  { keywords: ['generative ai overview', 'project managers'], code: 'GENAI_OVERVIEW' },
  { keywords: ['data landscape', 'genai', 'project managers'], code: 'DATA_LANDSCAPE' },
  { keywords: ['prompt engineering', 'project managers'], code: 'PROMPT_ENG' },
  { keywords: ['practical application', 'gen ai', 'project managers'], code: 'PRACTICAL_GENAI' },
  { keywords: ['citizen developer', 'cdba'], code: 'CDBA_INTRO' },
  { keywords: ['introduction', 'cognitive', 'cpmai'], code: 'CPMAI_INTRO' },
  { keywords: ['ai in infrastructure', 'construction'], code: 'AI_INFRA' },
  { keywords: ['ai in agile delivery'], code: 'AI_AGILE' },
]

// ── Broad knowledge categories (Tier 3: +15 XP for AI/PM, +10 XP for others) ──
const AI_PM_KEYWORDS = [
  'artificial intelligence', 'machine learning', 'deep learning',
  'generative ai', 'gen ai', 'genai', 'prompt engineering',
  'data science', 'data landscape', 'business intelligence',
  'cognitive', 'ai ', ' ai', 'ml ', ' ml',
  'project management', 'agile', 'scrum',
]

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
  const resp = await fetch(`https://www.credly.com/users/${username}/badges.json`, {
    headers: { 'Accept': 'application/json', 'User-Agent': 'NucleoIA-GP/1.0' },
  })
  if (!resp.ok) throw new Error(`Credly ${resp.status}: ${username}`)
  const data = await resp.json()
  return data.data || data || []
}

function classifyBadge(name: string, slug: string): { tier: number; category: string; points: number } {
  const combined = (name + ' ' + slug).toLowerCase()

  for (const trail of PMI_TRAIL_KEYWORDS) {
    if (trail.keywords.every(kw => combined.includes(kw))) {
      return { tier: 3, category: 'pmi_trail', points: 15 }
    }
  }

  if (TIER1_KEYWORDS.some(kw => combined.includes(kw))) {
    return { tier: 1, category: 'master_cert', points: 50 }
  }

  if (TIER2_KEYWORDS.some(kw => combined.includes(kw))) {
    return { tier: 2, category: 'specialization', points: 25 }
  }

  if (AI_PM_KEYWORDS.some(kw => combined.includes(kw))) {
    return { tier: 3, category: 'knowledge_ai_pm', points: 15 }
  }

  return { tier: 4, category: 'other', points: 10 }
}

function analyzeBadges(badges: CredlyBadge[]) {
  const pmiTrail: { code: string; name: string; issued_at: string }[] = []
  const cpmai: { name: string; issued_at: string }[] = []
  const all: { name: string; issued_at: string; slug: string; category: string; tier: number; points: number }[] = []

  for (const b of badges) {
    const name = b.badge_template?.name || ''
    const slug = b.badge_template?.vanity_slug || ''
    const classification = classifyBadge(name, slug)

    all.push({
      name,
      issued_at: b.issued_at,
      slug,
      category: classification.category,
      tier: classification.tier,
      points: classification.points,
    })

    if (classification.category === 'pmi_trail') {
      const combined = (name + ' ' + slug).toLowerCase()
      for (const trail of PMI_TRAIL_KEYWORDS) {
        if (trail.keywords.every(kw => combined.includes(kw))) {
          pmiTrail.push({ code: trail.code, name, issued_at: b.issued_at })
          break
        }
      }
    }

    if (classification.tier === 1) {
      const combined = (name + ' ' + slug).toLowerCase()
      if (['cpmai', 'cognitive project management', 'pmi-cpmai'].some(kw => combined.includes(kw))) {
        cpmai.push({ name, issued_at: b.issued_at })
      }
    }
  }

  return { pmiTrail, cpmai, all, hasCPMAI: cpmai.length > 0, totalPoints: all.reduce((sum, b) => sum + b.points, 0) }
}

async function upsertCredlyPoints(
  sb: ReturnType<typeof createClient>,
  memberId: string,
  badge: { name: string; points: number; issued_at: string },
) {
  const reason = `Credly: ${badge.name}`
  const { data: rows, error: rowsError } = await sb.from('gamification_points')
    .select('id, points, created_at')
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
      category: 'course',
      created_at: badge.issued_at || new Date().toISOString(),
    })
    if (insertError) throw insertError
    return
  }

  const keeper = rows[0]
  if (keeper.points !== badge.points) {
    const { error: updateError } = await sb.from('gamification_points')
      .update({ points: badge.points })
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

async function processMember(
  sb: ReturnType<typeof createClient>,
  member: { id: string; credly_url: string },
): Promise<{ success: boolean; member_id: string; error?: string; total_points?: number }> {
  const username = extractUsername(member.credly_url)
  if (!username) {
    return { success: false, member_id: member.id, error: 'Invalid credly_url' }
  }

  const badges = await fetchBadges(username)
  const result = analyzeBadges(badges)

  await sb.from('members').update({
    credly_verified_at: new Date().toISOString(),
    credly_badges: result.all.filter(b => b.tier <= 3),
    cpmai_certified: result.hasCPMAI,
    cpmai_certified_at: result.cpmai[0]?.issued_at || null,
  }).eq('id', member.id)

  for (const badge of result.all) {
    await upsertCredlyPoints(sb, member.id, badge)
  }

  for (const trail of result.pmiTrail) {
    await sb.from('gamification_points')
      .delete()
      .eq('member_id', member.id)
      .eq('category', 'course')
      .ilike('reason', `curso:%${trail.code}%`)
  }

  await syncTrailProgressFromCredly(
    sb,
    member.id,
    result.pmiTrail.map((t) => ({ code: t.code, issued_at: t.issued_at })),
  )

  return { success: true, member_id: member.id, total_points: result.totalPoints }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const jsonHeaders = { ...corsHeaders, 'Content-Type': 'application/json' }

  try {
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ success: false, error: 'Method not allowed' }),
        { headers: jsonHeaders, status: 405 },
      )
    }

    const authHeader = req.headers.get('Authorization') ?? ''
    if (!authHeader.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing Authorization header' }),
        { headers: jsonHeaders, status: 401 },
      )
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const token = authHeader.replace(/^Bearer\s+/i, '')
    const isServiceRole = token === serviceRoleKey

    const sb = createClient(supabaseUrl, serviceRoleKey)

    // Admin-only: verify caller has tier >= admin (batch operation)
    if (!isServiceRole) {
      const uc = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: 'Bearer ' + token } },
      })
      const ur = await uc.auth.getUser()
      if (ur.error || !ur.data?.user) {
        return new Response(
          JSON.stringify({ success: false, error: 'Invalid token' }),
          { headers: jsonHeaders, status: 401 },
        )
      }
      const { data: caller } = await sb
        .from('members')
        .select('is_superadmin, operational_role')
        .eq('auth_id', ur.data.user.id)
        .single()

      const isAdmin = caller?.is_superadmin === true
        || caller?.operational_role === 'manager'
        || caller?.operational_role === 'deputy_manager'

      if (!isAdmin) {
        return new Response(
          JSON.stringify({ success: false, error: 'Admin access required for batch sync' }),
          { headers: jsonHeaders, status: 403 },
        )
      }
    }

    const { data: members, error: membersError } = await sb
      .from('members')
      .select('id, credly_url')
      .eq('active', true)
      .not('credly_url', 'is', null)
      .neq('credly_url', '')

    if (membersError) {
      return new Response(
        JSON.stringify({ success: false, error: `Failed to query members: ${membersError.message}` }),
        { headers: jsonHeaders, status: 500 },
      )
    }

    if (!members || members.length === 0) {
      return new Response(
        JSON.stringify({ success: true, total_candidates: 0, success_count: 0, fail_count: 0, details: [] }),
        { headers: jsonHeaders },
      )
    }

    let successCount = 0
    let failCount = 0
    const details: { member_id: string; success: boolean; error?: string; total_points?: number }[] = []

    for (const member of members) {
      try {
        const result = await processMember(sb, member)
        if (result.success) {
          successCount++
        } else {
          failCount++
        }
        details.push(result)
      } catch (err: any) {
        failCount++
        details.push({ member_id: member.id, success: false, error: err?.message || 'Unknown error' })
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        total_candidates: members.length,
        success_count: successCount,
        fail_count: failCount,
        details,
      }),
      { headers: jsonHeaders },
    )
  } catch (err: any) {
    return new Response(
      JSON.stringify({ success: false, error: err?.message || 'Unknown error' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 },
    )
  }
})
