// supabase/functions/verify-credly/index.ts
// Supabase Edge Function — Verify Credly Certifications
//
// Fetches a member's public Credly profile and checks for PMI AI Trail
// badges and CPMAI certification. Updates member record with results.
//
// Invoke: POST /functions/v1/verify-credly
// Body: { member_id: uuid } or { credly_url: string, emails: string[] }
//
// Public Credly profile: https://www.credly.com/users/{username}/badges.json

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

// ── Target badges we want to validate ──
const TARGET_BADGES = [
  // PMI AI Mini Trail (4 core)
  'generative-ai-overview-for-project-managers',
  'data-landscape-of-genai-for-project-managers',
  'talking-to-ai-prompt-engineering-for-project-managers',
  'practical-application-of-generative-ai-for-project-managers',
  // Complementary
  'pmi-citizen-developer-business-architect',
  'free-introduction-to-cognitive-pm-in-ai-cpmai',
  'ai-in-infrastructure-and-construction-projects',
  'ai-in-agile-delivery',
  // CPMAI Certification
  'cognitive-project-management-for-ai',
  'pmi-cpmai',
  'cpmai',
]

// Friendly names for matching
const BADGE_FRIENDLY: Record<string, string> = {
  'generative-ai-overview-for-project-managers': 'Generative AI Overview for Project Managers',
  'data-landscape-of-genai-for-project-managers': 'Data Landscape of GenAI for Project Managers',
  'talking-to-ai-prompt-engineering-for-project-managers': 'Talking to AI: Prompt Engineering for PMs',
  'practical-application-of-generative-ai-for-project-managers': 'Practical Application of GenAI for PMs',
  'pmi-citizen-developer-business-architect': 'PMI Citizen Developer: CDBA',
  'free-introduction-to-cognitive-pm-in-ai-cpmai': 'Free Introduction to Cognitive PM in AI (CPMAI)',
  'ai-in-infrastructure-and-construction-projects': 'AI in Infrastructure and Construction Projects',
  'ai-in-agile-delivery': 'AI in Agile Delivery',
  'cognitive-project-management-for-ai': 'Cognitive Project Management for AI (CPMAI)™',
  'pmi-cpmai': 'PMI-CPMAI',
  'cpmai': 'CPMAI',
}

// CPMAI-specific badge slugs
const CPMAI_SLUGS = ['cognitive-project-management-for-ai', 'pmi-cpmai', 'cpmai']

interface CredlyBadge {
  id: string
  badge_template: {
    name: string
    vanity_slug?: string
    badge_template_activities?: { title: string }[]
  }
  issued_at: string
  expires_at: string | null
  state: string
}

// ── Extract username from Credly URL ──
function extractCredlyUsername(url: string): string | null {
  // https://www.credly.com/users/vitor-maia-rodovalho.edbf9ddd/
  const match = url.match(/credly\.com\/users\/([^\/\?]+)/)
  return match ? match[1] : null
}

// ── Fetch badges from Credly public profile ──
async function fetchCredlyBadges(username: string): Promise<CredlyBadge[]> {
  const url = `https://www.credly.com/users/${username}/badges.json`
  const resp = await fetch(url, {
    headers: {
      'Accept': 'application/json',
      'User-Agent': 'NucleoIA-GP-Hub/1.0',
    },
  })

  if (!resp.ok) {
    if (resp.status === 404) {
      throw new Error(`Credly profile not found: ${username}`)
    }
    throw new Error(`Credly API error: ${resp.status}`)
  }

  const data = await resp.json()
  return data.data || data || []
}

// ── Match badges against our targets ──
function matchBadges(badges: CredlyBadge[]) {
  const matched: { slug: string; name: string; issued_at: string }[] = []
  let hasCPMAI = false

  for (const badge of badges) {
    const name = badge.badge_template?.name || ''
    const slug = badge.badge_template?.vanity_slug || ''
    const nameLower = name.toLowerCase()
    const slugLower = slug.toLowerCase()

    for (const target of TARGET_BADGES) {
      if (
        slugLower.includes(target) ||
        nameLower.includes(target.replace(/-/g, ' ')) ||
        nameLower.includes(BADGE_FRIENDLY[target]?.toLowerCase() || '___')
      ) {
        matched.push({
          slug: target,
          name: name,
          issued_at: badge.issued_at,
        })

        if (CPMAI_SLUGS.includes(target)) {
          hasCPMAI = true
        }
        break
      }
    }
  }

  return { matched, hasCPMAI, totalCredlyBadges: badges.length }
}

// ── Main handler ──
Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const body = await req.json()
    const { member_id, credly_url, emails } = body

    // Create Supabase client with service role for DB updates
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const sb = createClient(supabaseUrl, supabaseKey)

    let username: string | null = null
    let memberId = member_id

    // Strategy 1: Use credly_url directly
    if (credly_url) {
      username = extractCredlyUsername(credly_url)
    }

    // Strategy 2: If member_id provided, fetch their credly_url
    if (!username && member_id) {
      const { data: member } = await sb
        .from('members')
        .select('credly_url, email, secondary_emails')
        .eq('id', member_id)
        .single()

      if (member?.credly_url) {
        username = extractCredlyUsername(member.credly_url)
      }
    }

    if (!username) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'No Credly profile URL found. Please add your Credly profile URL in your profile settings.',
          suggestion: 'Go to Profile → Credly field → paste your public Credly URL (e.g., https://www.credly.com/users/your-name)',
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // Fetch and match badges
    const badges = await fetchCredlyBadges(username)
    const result = matchBadges(badges)

    // Update member record if member_id provided
    if (memberId && result.matched.length > 0) {
      const updatePayload: Record<string, unknown> = {
        credly_verified_at: new Date().toISOString(),
        credly_badges: result.matched,
      }

      if (result.hasCPMAI) {
        updatePayload.cpmai_certified = true
        updatePayload.cpmai_certified_at = result.matched
          .find(b => CPMAI_SLUGS.includes(b.slug))?.issued_at || new Date().toISOString()
      }

      await sb
        .from('members')
        .update(updatePayload)
        .eq('id', memberId)

      // Award gamification points for verified badges
      for (const badge of result.matched) {
        const existing = await sb
          .from('gamification_points')
          .select('id')
          .eq('member_id', memberId)
          .eq('category', 'course')
          .eq('reason', `Credly: ${badge.name}`)
          .maybeSingle()

        if (!existing.data) {
          await sb.from('gamification_points').insert({
            member_id: memberId,
            points: CPMAI_SLUGS.includes(badge.slug) ? 50 : 15,
            reason: `Credly: ${badge.name}`,
            category: 'course',
          })
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        credly_username: username,
        total_credly_badges: result.totalCredlyBadges,
        matched_badges: result.matched,
        has_cpmai: result.hasCPMAI,
        matched_count: result.matched.length,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ success: false, error: err.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
