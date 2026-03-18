import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const sb = createClient(
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
