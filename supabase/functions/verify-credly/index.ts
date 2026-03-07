import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

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

function extractUsername(url: string): string | null {
  const match = url.match(/credly\.com\/users\/([^\/\?]+)/)
  return match ? match[1] : null
}

async function fetchBadges(username: string): Promise<CredlyBadge[]> {
  const resp = await fetch(`https://www.credly.com/users/${username}/badges.json`, {
    headers: { 'Accept': 'application/json', 'User-Agent': 'NucleoIA-GP/1.0' },
  })
  if (!resp.ok) throw new Error(`Credly ${resp.status}: ${username}`)
  const data = await resp.json()
  return data.data || data || []
}

// ── Tier classification ──
// Returns: { tier: 1|2|3|4, category: string, points: number }
function classifyBadge(name: string, slug: string): { tier: number; category: string; points: number } {
  const combined = (name + ' ' + slug).toLowerCase()

  // Tier 1: Master certifications (+50 XP)
  if (TIER1_KEYWORDS.some(kw => combined.includes(kw))) {
    return { tier: 1, category: 'master_cert', points: 50 }
  }

  // PMI Trail (strict match — Tier 3 but category 'pmi_trail' for KPI tracking)
  for (const trail of PMI_TRAIL_KEYWORDS) {
    if (trail.keywords.every(kw => combined.includes(kw))) {
      return { tier: 3, category: 'pmi_trail', points: 15 }
    }
  }

  // Tier 2: Specializations (+25 XP)
  if (TIER2_KEYWORDS.some(kw => combined.includes(kw))) {
    return { tier: 2, category: 'specialization', points: 25 }
  }

  // Tier 3: AI/PM knowledge (+15 XP)
  if (AI_PM_KEYWORDS.some(kw => combined.includes(kw))) {
    return { tier: 3, category: 'knowledge_ai_pm', points: 15 }
  }

  // Tier 4: Other recognized badges (+10 XP)
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

    // Track PMI Trail separately for KPI
    if (classification.category === 'pmi_trail') {
      const combined = (name + ' ' + slug).toLowerCase()
      for (const trail of PMI_TRAIL_KEYWORDS) {
        if (trail.keywords.every(kw => combined.includes(kw))) {
          pmiTrail.push({ code: trail.code, name, issued_at: b.issued_at })
          break
        }
      }
    }

    // Track CPMAI separately
    if (classification.tier === 1) {
      const combined = (name + ' ' + slug).toLowerCase()
      if (['cpmai', 'cognitive project management', 'pmi-cpmai'].some(kw => combined.includes(kw))) {
        cpmai.push({ name, issued_at: b.issued_at })
      }
    }
  }

  return {
    pmiTrail,
    cpmai,
    all,
    hasCPMAI: cpmai.length > 0,
    pmiTrailCount: pmiTrail.length,
    totalBadges: badges.length,
    // Tier breakdown
    tier1Count: all.filter(b => b.tier === 1).length,
    tier2Count: all.filter(b => b.tier === 2).length,
    tier3Count: all.filter(b => b.tier === 3).length,
    tier4Count: all.filter(b => b.tier === 4).length,
    totalPoints: all.reduce((sum, b) => sum + b.points, 0),
  }
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
      await sb.from('members').update({
        credly_verified_at: new Date().toISOString(),
        credly_badges: result.all.filter(b => b.tier <= 3), // Store relevant badges
        cpmai_certified: result.hasCPMAI,
        cpmai_certified_at: result.cpmai[0]?.issued_at || null,
      }).eq('id', member_id)

      // Award gamification points (with tier-based scoring)
      for (const badge of result.all) {
        const reason = `Credly: ${badge.name}`

        const { data: existing } = await sb.from('gamification_points')
          .select('id, points').eq('member_id', member_id)
          .eq('reason', reason).maybeSingle()

        if (!existing) {
          // New badge — insert with tier points
          await sb.from('gamification_points').insert({
            member_id, points: badge.points, reason, category: 'course',
            created_at: badge.issued_at || new Date().toISOString(),
          })
        } else if (existing.points !== badge.points) {
          // Existing badge but points changed (tier recalculation) — update
          await sb.from('gamification_points')
            .update({ points: badge.points })
            .eq('id', existing.id)
        }
      }

      // Remove old manual course points that Credly now covers
      for (const trail of result.pmiTrail) {
        await sb.from('gamification_points')
          .delete()
          .eq('member_id', member_id)
          .eq('category', 'course')
          .like('reason', `Curso: ${trail.code}%`)
      }
    }

    return new Response(JSON.stringify({
      success: true,
      credly_username: username,
      total_badges: result.totalBadges,
      pmi_trail: result.pmiTrail,
      pmi_trail_count: result.pmiTrailCount,
      cpmai: result.cpmai,
      has_cpmai: result.hasCPMAI,
      all_matched: result.all.filter(b => b.tier <= 3).length,
      total_points: result.totalPoints,
      tiers: {
        master: result.tier1Count,
        specialization: result.tier2Count,
        trail_knowledge: result.tier3Count,
        other: result.tier4Count,
      },
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (err: any) {
    return new Response(JSON.stringify({ success: false, error: err.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
  }
})
