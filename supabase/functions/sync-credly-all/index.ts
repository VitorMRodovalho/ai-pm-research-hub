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

    const sb = createClient(supabaseUrl, serviceRole)

    let caller: any = null
    const { data: callerByRpc } = await authClient.rpc('get_member_by_auth')
    if (callerByRpc) caller = callerByRpc
    if (!caller) {
      const { data: me } = await sb
        .from('members')
        .select('id, is_superadmin, email, secondary_emails')
        .eq('auth_id', user.id)
        .maybeSingle()
      caller = me
    }
    if (!caller && user.email) {
      const mail = String(user.email).toLowerCase()
      const { data: byEmail } = await sb
        .from('members')
        .select('id, is_superadmin, email, secondary_emails')
        .or(`email.eq.${mail},secondary_emails.cs.{${mail}}`)
        .maybeSingle()
      caller = byEmail
    }
    if (!caller?.is_superadmin) {
      return new Response(
        JSON.stringify({ success: false, error: 'Only superadmin can run bulk Credly sync' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { data: members, error: membersError } = await sb
      .from('members')
      .select('id, name, credly_url, current_cycle_active')
      .eq('current_cycle_active', true)
      .not('credly_url', 'is', null)
      .order('name')
      .limit(500)
    if (membersError) throw membersError

    const candidates = (members || []).filter((m: any) => String(m.credly_url || '').trim().length > 0)
    const baseFnUrl = `${supabaseUrl}/functions/v1/verify-credly`

    const report = {
      success: true,
      total_candidates: candidates.length,
      processed: 0,
      success_count: 0,
      fail_count: 0,
      total_badges: 0,
      total_matched: 0,
      total_trail_detected: 0,
      total_trail_synced: 0,
      failures: [] as Array<{ member_id: string; name: string; error: string }>,
    }

    for (const m of candidates) {
      report.processed++
      try {
        const resp = await fetch(baseFnUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            apikey: anonKey,
            Authorization: `Bearer ${token}`,
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

    return new Response(JSON.stringify(report), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err: any) {
    return new Response(
      JSON.stringify({ success: false, error: err?.message || 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
