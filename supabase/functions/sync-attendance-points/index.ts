import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const POINTS_PER_ATTENDANCE = 10
const CATEGORY = 'attendance'
// Keep batch size small to avoid PostgREST URL length limits on .in() queries
// Each UUID is 36 chars; 100 * 36 = 3.6KB, well within the ~8KB limit
const LOOKUP_BATCH = 100
const INSERT_BATCH = 200

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function extractError(err: unknown): string {
  if (err && typeof err === 'object') {
    const e = err as Record<string, unknown>
    if (typeof e.message === 'string' && e.message) return e.message
    if (typeof e.msg === 'string' && e.msg) return e.msg
    if (typeof e.error_description === 'string') return e.error_description
    try { return JSON.stringify(err) } catch { /* fallthrough */ }
  }
  return String(err || 'Unknown error')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  const authHeader = req.headers.get('Authorization') ?? ''
  const token = authHeader.replace(/^Bearer\s+/i, '')
  if (!token) return jsonResponse({ success: false, error: 'Unauthorized' }, 401)

  const isServiceRole = token === serviceRoleKey

  const sb = createClient(supabaseUrl, serviceRoleKey)

  let callerMemberId: string | null = null

  if (!isServiceRole) {
    const { data: { user }, error: userError } = await sb.auth.getUser(token)
    if (userError || !user) return jsonResponse({ success: false, error: `Auth failed: ${userError?.message || 'no user'}` }, 401)

    const { data: member, error: memberError } = await sb
      .from('members')
      .select('id, is_superadmin, operational_role')
      .eq('auth_id', user.id)
      .single()

    if (!member) return jsonResponse({ success: false, error: `Member not found: ${memberError?.message || user.id}` }, 401)

    const isAdmin = member.is_superadmin === true
      || member.operational_role === 'manager'
      || member.operational_role === 'deputy_manager'

    if (!isAdmin) {
      callerMemberId = member.id
    }
  }

  try {
    let attendanceQuery = sb
      .from('attendance')
      .select('id, member_id')
      .eq('present', true)

    if (callerMemberId) {
      attendanceQuery = attendanceQuery.eq('member_id', callerMemberId)
    }

    const { data: attendanceRows, error: attendanceError } = await attendanceQuery
    if (attendanceError) throw attendanceError
    if (!attendanceRows || attendanceRows.length === 0) {
      return jsonResponse({ success: true, points_created: 0 })
    }

    const attendanceIds = attendanceRows.map((r) => r.id)

    // Look up existing ref_ids in small batches to avoid URL length limits
    const existingRefIds = new Set<string>()
    for (let i = 0; i < attendanceIds.length; i += LOOKUP_BATCH) {
      const batch = attendanceIds.slice(i, i + LOOKUP_BATCH)
      const { data: existing, error: existingError } = await sb
        .from('gamification_points')
        .select('ref_id')
        .eq('category', CATEGORY)
        .in('ref_id', batch)

      if (existingError) throw existingError
      for (const row of existing || []) {
        if (row.ref_id) existingRefIds.add(row.ref_id)
      }
    }

    const toInsert = attendanceRows
      .filter((a) => !existingRefIds.has(a.id))
      .map((a) => ({
        member_id: a.member_id,
        category: CATEGORY,
        points: POINTS_PER_ATTENDANCE,
        reason: 'Presença em evento',
        ref_id: a.id,
      }))

    if (toInsert.length > 0) {
      for (let i = 0; i < toInsert.length; i += INSERT_BATCH) {
        const batch = toInsert.slice(i, i + INSERT_BATCH)
        const { error: insertError } = await sb.from('gamification_points').insert(batch)
        if (insertError) throw insertError
      }
    }

    return jsonResponse({ success: true, points_created: toInsert.length })
  } catch (error) {
    return jsonResponse({ success: false, error: extractError(error) }, 500)
  }
})
