import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Keep scoring keywords aligned with verify-credly to support legacy hardening.
const TIER1_KEYWORDS = [
  'pmp', 'cpmai', 'pmi-cpmai', 'cognitive project management',
  'pmi-acp', 'pmi-cp', 'pgmp', 'pfmp', 'pmi-rmp', 'pmi-sp',
  'project management professional',
]

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

const AI_PM_KEYWORDS = [
  'artificial intelligence', 'machine learning', 'deep learning',
  'generative ai', 'gen ai', 'genai', 'prompt engineering',
  'data science', 'data landscape', 'business intelligence',
  'cognitive', 'ai ', ' ai', 'ml ', ' ml',
  'project management', 'agile', 'scrum',
]

function parseBearer(authHeader: string | null): string | null {
  if (!authHeader) return null
  const m = authHeader.match(/^Bearer\s+(.+)$/i)
  return m?.[1] || null
}

function safeEqual(a: string, b: string): boolean {
  if (!a || !b) return false
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

function toInt(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return Math.trunc(v)
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v)
    if (Number.isFinite(n)) return Math.trunc(n)
  }
  return null
}

function pointsFromTier(tier: number): number {
  if (tier === 1) return 50
  if (tier === 2) return 25
  if (tier === 3) return 15
  return 10
}

function tierFromPoints(points: number): number {
  if (points === 50) return 1
  if (points === 25) return 2
  if (points === 15) return 3
  return 4
}

function classifyTierAndPoints(name: string, slug: string, category: string | null, rawTier: unknown, rawPoints: unknown) {
  const combined = `${name || ''} ${slug || ''}`.toLowerCase()
  if (category === 'pmi_trail') return { tier: 3, points: 15 }

  for (const trail of PMI_TRAIL_KEYWORDS) {
    if (trail.keywords.every((kw) => combined.includes(kw))) return { tier: 3, points: 15 }
  }
  if (TIER1_KEYWORDS.some((kw) => combined.includes(kw))) return { tier: 1, points: 50 }
  if (TIER2_KEYWORDS.some((kw) => combined.includes(kw))) return { tier: 2, points: 25 }
  if (AI_PM_KEYWORDS.some((kw) => combined.includes(kw))) return { tier: 3, points: 15 }

  const oldTier = toInt(rawTier)
  if (oldTier && oldTier >= 1 && oldTier <= 4) return { tier: oldTier, points: pointsFromTier(oldTier) }
  const oldPoints = toInt(rawPoints)
  if (oldPoints) return { tier: tierFromPoints(oldPoints), points: oldPoints }
  return { tier: 4, points: 10 }
}

function detectLegacyTrailCompletions(badges: any[]) {
  const out: { code: string; issued_at: string }[] = []
  for (const badge of badges) {
    if (!badge || typeof badge !== 'object') continue
    const name = String(badge.name || '')
    const slug = String(badge.slug || '')
    const combined = `${name} ${slug}`.toLowerCase()
    const category = badge.category ? String(badge.category) : ''

    for (const trail of PMI_TRAIL_KEYWORDS) {
      if (category === 'pmi_trail' || trail.keywords.every((kw) => combined.includes(kw))) {
        out.push({ code: trail.code, issued_at: String(badge.issued_at || new Date().toISOString()) })
        break
      }
    }
  }
  return out
}

async function syncTrailProgressFromLegacy(
  sb: ReturnType<typeof createClient>,
  memberId: string,
  completions: { code: string; issued_at: string }[],
) {
  if (!completions.length) return 0

  const { data: courses, error: coursesError } = await sb
    .from('courses')
    .select('id, code')
    .in('code', completions.map((c) => c.code))
  if (coursesError) throw coursesError
  const byCode = new Map((courses || []).map((c: any) => [String(c.code), Number(c.id)]))

  let synced = 0
  for (const c of completions) {
    const courseId = byCode.get(c.code)
    if (!courseId) continue

    const { data: existing, error: existingError } = await sb
      .from('course_progress')
      .select('id, status')
      .eq('member_id', memberId)
      .eq('course_id', courseId)
      .maybeSingle()
    if (existingError) throw existingError

    if (!existing) {
      const { error: insertError } = await sb.from('course_progress').insert({
        member_id: memberId,
        course_id: courseId,
        status: 'completed',
        completed_at: c.issued_at || new Date().toISOString(),
      })
      if (insertError) throw insertError
      synced++
      continue
    }

    if (existing.status !== 'completed') {
      const { error: updateError } = await sb
        .from('course_progress')
        .update({ status: 'completed' })
        .eq('member_id', memberId)
        .eq('course_id', courseId)
      if (updateError) throw updateError
      synced++
    }
  }

  return synced
}

async function hardenLegacyMemberCredlyData(
  sb: ReturnType<typeof createClient>,
  member: { id: string; credly_badges: any[] | null },
) {
  const rawBadges = Array.isArray(member.credly_badges) ? member.credly_badges : []
  if (rawBadges.length === 0) {
    return { touched: false, badges_sanitized: 0, points_recalculated: 0, trail_synced: 0 }
  }

  const nextBadges = [...rawBadges]
  let badgesSanitized = 0
  let pointsRecalculated = 0
  let trailSynced = 0

  for (let i = 0; i < rawBadges.length; i++) {
    const badge = rawBadges[i]
    if (!badge || typeof badge !== 'object') continue

    const name = String(badge.name || '')
    const slug = String(badge.slug || '')
    const category = badge.category ? String(badge.category) : null
    const currentTier = toInt(badge.tier)
    const currentPoints = toInt(badge.points)
    const classified = classifyTierAndPoints(name, slug, category, badge.tier, badge.points)

    if (currentTier !== classified.tier || currentPoints !== classified.points) {
      nextBadges[i] = { ...badge, tier: classified.tier, points: classified.points }
      badgesSanitized++
    }

    if (!name) continue
    const reason = `Credly: ${name}`
    const { data: pointRows, error: pointReadError } = await sb
      .from('gamification_points')
      .select('id, points, created_at')
      .eq('member_id', member.id)
      .eq('reason', reason)
      .order('created_at', { ascending: true })
      .order('id', { ascending: true })

    if (pointReadError || !pointRows?.length) continue

    const keeper = pointRows[0]
    const keeperPoints = toInt(keeper.points)
    if (keeperPoints !== classified.points) {
      const { error: pointUpdateError } = await sb
        .from('gamification_points')
        .update({ points: classified.points })
        .eq('id', keeper.id)
      if (!pointUpdateError) pointsRecalculated++
    }

    if (pointRows.length > 1) {
      const dupIds = pointRows.slice(1).map((r: any) => r.id)
      const { error: deleteDupError } = await sb
        .from('gamification_points')
        .delete()
        .in('id', dupIds)
      if (deleteDupError) throw deleteDupError
    }
  }

  if (badgesSanitized > 0) {
    const { error: memberUpdateError } = await sb
      .from('members')
      .update({ credly_badges: nextBadges, credly_verified_at: new Date().toISOString() })
      .eq('id', member.id)
    if (memberUpdateError) throw memberUpdateError
  }
  trailSynced = await syncTrailProgressFromLegacy(sb, member.id, detectLegacyTrailCompletions(nextBadges))

  return {
    touched: badgesSanitized > 0 || pointsRecalculated > 0 || trailSynced > 0,
    badges_sanitized: badgesSanitized,
    points_recalculated: pointsRecalculated,
    trail_synced: trailSynced,
  }
}

async function resolveSuperadminCaller(
  authClient: ReturnType<typeof createClient>,
  sb: ReturnType<typeof createClient>,
  user: { id: string; email?: string | null },
) {
  const { data: callerByRpc } = await authClient.rpc('get_member_by_auth')
  if (callerByRpc?.is_superadmin) return callerByRpc

  const { data: superadmins } = await sb
    .from('members')
    .select('id, auth_id, email, secondary_emails, is_superadmin')
    .eq('is_superadmin', true)
    .limit(20)

  const uid = String(user.id || '')
  const mail = String(user.email || '').toLowerCase()
  return (superadmins || []).find((m: any) => {
    if (m.auth_id && String(m.auth_id) === uid) return true
    if (mail && m.email && String(m.email).toLowerCase() === mail) return true
    const secs = Array.isArray(m.secondary_emails) ? m.secondary_emails.map((x: any) => String(x).toLowerCase()) : []
    return mail && secs.includes(mail)
  }) || null
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const anonKey = req.headers.get('apikey') || Deno.env.get('SUPABASE_ANON_KEY') || ''
    const authHeader = req.headers.get('Authorization')
    const token = parseBearer(authHeader)
    const cronSecret = req.headers.get('x-cron-secret') || ''
    const expectedCronSecret = Deno.env.get('SYNC_CREDLY_CRON_SECRET') || ''
    const isCronAuthorized = safeEqual(cronSecret, expectedCronSecret)

    if (!anonKey) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing anon key for auth validation' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const sb = createClient(supabaseUrl, serviceRole)
    const mode = isCronAuthorized ? 'cron' : 'manual'
    let callerLabel = 'cron'

    if (!isCronAuthorized) {
      if (!token) {
        return new Response(
          JSON.stringify({ success: false, error: 'Missing bearer token' }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }

      // Caller identity (user JWT) to validate admin permission.
      const authClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: `Bearer ${token}` } },
      })
      const {
        data: { user },
        error: userError,
      } = await authClient.auth.getUser()
      if (userError || !user) {
        return new Response(
          JSON.stringify({ success: false, error: 'Unauthorized caller' }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }

      const caller = await resolveSuperadminCaller(authClient, sb, user)
      if (!caller?.is_superadmin) {
        return new Response(
          JSON.stringify({ success: false, error: 'Only superadmin can run bulk Credly sync' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
      callerLabel = String(user.email || user.id || 'manual-superadmin')
    }

    const { data: members, error: membersError } = await sb
      .from('members')
      .select('id, name, credly_url, credly_badges, current_cycle_active')
      .eq('current_cycle_active', true)
      .order('name')
      .limit(500)
    if (membersError) throw membersError

    const allActive = members || []
    const candidates = allActive.filter((m: any) => String(m.credly_url || '').trim().length > 0)
    const legacyOnly = allActive.filter((m: any) =>
      String(m.credly_url || '').trim().length === 0 &&
      Array.isArray(m.credly_badges) &&
      m.credly_badges.length > 0,
    )
    const baseFnUrl = `${supabaseUrl}/functions/v1/verify-credly`

    const report = {
      success: true,
      total_active_members: allActive.length,
      total_candidates: candidates.length,
      total_legacy_only: legacyOnly.length,
      processed: 0,
      success_count: 0,
      fail_count: 0,
      total_badges: 0,
      total_matched: 0,
      total_trail_detected: 0,
      total_trail_synced: 0,
      legacy_sanitized_members: 0,
      legacy_badges_sanitized: 0,
      legacy_points_recalculated: 0,
      legacy_trail_synced: 0,
      failures: [] as Array<{ member_id: string; name: string; error: string }>,
    }

    for (const m of candidates) {
      report.processed++
      try {
        const downstreamBearer = token || anonKey
        const resp = await fetch(baseFnUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            apikey: anonKey,
            Authorization: `Bearer ${downstreamBearer}`,
          },
          body: JSON.stringify({ member_id: m.id, credly_url: m.credly_url }),
        })
        const body = await resp.json()
        if (!resp.ok || !body?.success) {
          throw new Error(body?.error || `verify-credly ${resp.status}`)
        }

        report.success_count++
        report.total_badges += body.total_badges || 0
        report.total_matched += body.all_matched || 0
        report.total_trail_detected += body.pmi_trail_count || 0
        report.total_trail_synced += body.pmi_trail_synced || 0
      } catch (err: any) {
        report.fail_count++
        report.failures.push({
          member_id: m.id,
          name: m.name,
          error: err?.message || 'Unknown error',
        })
      }
    }

    for (const m of legacyOnly) {
      report.processed++
      try {
        const hardened = await hardenLegacyMemberCredlyData(sb, m)
        if (hardened.touched) {
          report.legacy_sanitized_members++
          report.legacy_badges_sanitized += hardened.badges_sanitized
          report.legacy_points_recalculated += hardened.points_recalculated
          report.legacy_trail_synced += hardened.trail_synced || 0
        }
        report.success_count++
      } catch (err: any) {
        report.fail_count++
        report.failures.push({
          member_id: m.id,
          name: m.name,
          error: err?.message || 'Unknown legacy hardening error',
        })
      }
    }

    return new Response(JSON.stringify({
      ...report,
      execution_mode: mode,
      triggered_by: callerLabel,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err: any) {
    return new Response(
      JSON.stringify({ success: false, error: err?.message || 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
