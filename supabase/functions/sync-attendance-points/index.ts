import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const POINTS_PER_ATTENDANCE = 10
const CATEGORY = 'attendance'
const BATCH_SIZE = 500

function unauthorizedResponse() {
  return new Response(JSON.stringify({ success: false, error: 'Unauthorized' }), {
    status: 401,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  const authHeader = req.headers.get('Authorization') ?? ''
  const token = authHeader.replace(/^Bearer\s+/i, '')
  if (!token) return unauthorizedResponse()

  const isServiceRole = token === serviceRoleKey

  const sb = createClient(supabaseUrl, serviceRoleKey)

  let callerMemberId: string | null = null

  if (!isServiceRole) {
    const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    })
    const { data: { user }, error: userError } = await userClient.auth.getUser()
    if (userError || !user) return unauthorizedResponse()

    const { data: member } = await sb
      .from('members')
      .select('id, is_superadmin')
      .eq('auth_id', user.id)
      .single()

    if (!member) return unauthorizedResponse()
    if (!member.is_superadmin) {
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
      return new Response(JSON.stringify({ success: true, points_created: 0 }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const attendanceIds = attendanceRows.map((r) => r.id)

    const existingRefIds = new Set<string>()
    for (let i = 0; i < attendanceIds.length; i += BATCH_SIZE) {
      const batch = attendanceIds.slice(i, i + BATCH_SIZE)
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
      for (let i = 0; i < toInsert.length; i += BATCH_SIZE) {
        const batch = toInsert.slice(i, i + BATCH_SIZE)
        const { error: insertError } = await sb.from('gamification_points').insert(batch)
        if (insertError) throw insertError
      }
    }

    return new Response(JSON.stringify({ success: true, points_created: toInsert.length }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return new Response(JSON.stringify({ success: false, error: message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
