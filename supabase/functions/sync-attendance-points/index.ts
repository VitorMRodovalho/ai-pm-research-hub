import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function parseBearer(authHeader: string | null): string | null {
  if (!authHeader) return null
  const m = authHeader.match(/^Bearer\s+(.+)$/i)
  return m?.[1] || null
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const authHeader = req.headers.get('Authorization')
    const token = parseBearer(authHeader)
    if (!token) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing bearer token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

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

    const sb = createClient(supabaseUrl, serviceRole)

    const { data: me, error: meError } = await sb
      .from('members')
      .select('id, is_superadmin')
      .eq('auth_id', user.id)
      .maybeSingle()
    if (meError || !me?.is_superadmin) {
      return new Response(
        JSON.stringify({ success: false, error: 'Only superadmin can run attendance sync' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { data: attendance, error: attendanceError } = await sb
      .from('attendance')
      .select('member_id, event_id, status')
      .eq('status', 'present')
      .not('member_id', 'is', null)
      .not('event_id', 'is', null)
      .limit(5000)
    if (attendanceError) throw attendanceError

    const eventIds = Array.from(new Set((attendance || []).map((a: any) => a.event_id)))
    const { data: events, error: eventsError } = await sb
      .from('events')
      .select('id, title, date')
      .in('id', eventIds.length ? eventIds : ['00000000-0000-0000-0000-000000000000'])
    if (eventsError) throw eventsError
    const eventMap = new Map((events || []).map((e: any) => [String(e.id), e]))

    const { data: existing, error: existingError } = await sb
      .from('gamification_points')
      .select('member_id, reason')
      .eq('category', 'attendance')
      .like('reason', 'Presença evento %')
      .limit(10000)
    if (existingError) throw existingError
    const existingKey = new Set((existing || []).map((p: any) => `${p.member_id}::${p.reason}`))

    const inserts: any[] = []
    for (const a of attendance || []) {
      const ev = eventMap.get(String(a.event_id))
      if (!ev) continue
      const reason = `Presença evento ${a.event_id}`
      const key = `${a.member_id}::${reason}`
      if (existingKey.has(key)) continue
      inserts.push({
        member_id: a.member_id,
        points: 10,
        reason,
        category: 'attendance',
        created_at: ev.date ? `${ev.date}T12:00:00.000Z` : new Date().toISOString(),
      })
      existingKey.add(key)
    }

    if (inserts.length) {
      const { error: insertError } = await sb.from('gamification_points').insert(inserts)
      if (insertError) throw insertError
    }

    return new Response(
      JSON.stringify({
        success: true,
        points_created: inserts.length,
        attendance_rows: (attendance || []).length,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (err: any) {
    return new Response(
      JSON.stringify({ success: false, error: err?.message || 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
