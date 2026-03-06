import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// ── PMI AI Trail (strict KPI tracking) ──
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

// ── CPMAI Certification (strict) ──
const CPMAI_KEYWORDS = ['cpmai', 'cognitive project management', 'pmi-cpmai']

// ── Broad knowledge categories (gamification) ──
const KNOWLEDGE_KEYWORDS = [
  'artificial intelligence', 'machine learning', 'deep learning',
  'generative ai', 'gen ai', 'genai', 'prompt engineering',
  'data science', 'data landscape', 'business intelligence',
  'project management', 'pmp', 'agile', 'scrum',
  'cognitive', 'ai ', ' ai', 'ml ', ' ml',
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

function analyzeBadges(badges: CredlyBadge[]) {
  const pmiTrail: { code: string; name: string; issued_at: string }[] = []
  const cpmai: { name: string; issued_at: string }[] = []
  const knowledge: { name: string; issued_at: string; slug: string }[] = []
  const all: { name: string; issued_at: string; slug: string; category: string }[] = []

  for (const b of badges) {
    const name = b.badge_template?.name || ''
    const slug = b.badge_template?.vanity_slug || ''
    const nameLower = name.toLowerCase()
    const slugLower = slug.toLowerCase()
    const combined = nameLower + ' ' + slugLower
    let categorized = false

    // Check PMI Trail (strict)
    for (const trail of PMI_TRAIL_KEYWORDS) {
      if (trail.keywords.every(kw => combined.includes(kw))) {
        pmiTrail.push({ code: trail.code, name, issued_at: b.issued_at })
        all.push({ name, issued_at: b.issued_at, slug, category: 'pmi_trail' })
        categorized = true
        break
      }
    }

    // Check CPMAI cert (strict)
    if (!categorized && CPMAI_KEYWORDS.some(kw => combined.includes(kw))) {
      cpmai.push({ name, issued_at: b.issued_at })
      all.push({ name, issued_at: b.issued_at, slug, category: 'cpmai' })
      categorized = true
    }

    // Check broad knowledge (gamification)
    if (!categorized && KNOWLEDGE_KEYWORDS.some(kw => combined.includes(kw))) {
      knowledge.push({ name, issued_at: b.issued_at, slug })
      all.push({ name, issued_at: b.issued_at, slug, category: 'knowledge' })
      categorized = true
    }

    // Anything else still gets tracked
    if (!categorized) {
      all.push({ name, issued_at: b.issued_at, slug, category: 'other' })
    }
  }

  return {
    pmiTrail,
    cpmai,
    knowledge,
    all,
    hasCPMAI: cpmai.length > 0,
    pmiTrailCount: pmiTrail.length,
    knowledgeCount: knowledge.length,
    totalBadges: badges.length,
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
      // Save all matched badges (Credly has priority over manual entries)
      await sb.from('members').update({
        credly_verified_at: new Date().toISOString(),
        credly_badges: result.all.filter(b => b.category !== 'other'),
        cpmai_certified: result.hasCPMAI,
        cpmai_certified_at: result.cpmai[0]?.issued_at || null,
      }).eq('id', member_id)

      // Award gamification points
      for (const badge of result.all) {
        if (badge.category === 'other') continue
        const points = badge.category === 'cpmai' ? 50
          : badge.category === 'pmi_trail' ? 15
          : 10 // knowledge badges
        const reason = `Credly: ${badge.name}`

        const { data: existing } = await sb.from('gamification_points')
          .select('id').eq('member_id', member_id)
          .eq('reason', reason).maybeSingle()

        if (!existing) {
          await sb.from('gamification_points').insert({
            member_id, points, reason, category: 'course',
            created_at: badge.issued_at || new Date().toISOString(),
          })
        }
      }

      // Remove old manual course points that Credly now covers (Credly = source of truth)
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
      knowledge: result.knowledge,
      knowledge_count: result.knowledgeCount,
      all_matched: result.all.filter(b => b.category !== 'other').length,
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (err) {
    return new Response(JSON.stringify({ success: false, error: err.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
  }
})
