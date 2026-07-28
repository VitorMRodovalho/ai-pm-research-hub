import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { isServiceRoleToken, bearerFrom } from '../_shared/service-auth.ts'

// #1513: read once at module scope so the caller gate and the handler share it.
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // #1513: service-role only.
  //
  // This one differs from its siblings: it deploys with verify_jwt=TRUE, which
  // the #1513 sweep first read as "the gateway already protects it". Measured
  // 2026-07-28, that is false in effect — verify_jwt accepts ANY valid project
  // JWT, and the anon key is public (it ships to every browser). A live probe
  // with the public anon key returned HTTP 200 with the organization's comms
  // metrics (audience, reach, engagement_rate, leads), read with the SERVICE
  // ROLE and therefore bypassing RLS. So it was effectively public.
  //
  // It has ZERO references anywhere in the repo or in the PMO tooling — the
  // comms_report MCP tool reads comms_metrics_daily directly. Gating is
  // therefore non-breaking; if some unknown consumer exists it now fails loudly
  // with 401 rather than silently serving org metrics to the internet.
  //
  // NOTE: deploy this one WITHOUT --no-verify-jwt so verify_jwt stays true.
  // Deploying it like its siblings would LOOSEN the gateway.
  if (!(await isServiceRoleToken(SUPABASE_URL, bearerFrom(req)))) {
    return new Response(
      JSON.stringify({ error: 'unauthorized', detail: 'service-role only' }),
      { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  try {
    const sb = createClient<any, "public", any>(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data, error } = await sb
      .from('comms_metrics_daily')
      .select('metric_date, channel, audience, reach, engagement_rate, leads, source, updated_at')
      .order('metric_date', { ascending: false })
      .order('updated_at', { ascending: false })
      .limit(300)

    if (error) throw error

    const rows = data || []
    if (!rows.length) {
      return new Response(JSON.stringify({ source: 'comms_metrics_daily', rows: [] }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const latestDate = String(rows[0].metric_date)
    const latestRows = rows
      .filter((r) => String(r.metric_date) === latestDate)
      .map((r) => ({
        metric_date: r.metric_date,
        channel: r.channel,
        audience: r.audience,
        reach: r.reach,
        engagement_rate: r.engagement_rate,
        leads: r.leads,
        source: r.source || 'comms_metrics_daily',
      }))

    return new Response(JSON.stringify({ source: 'comms_metrics_daily', rows: latestRows }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
