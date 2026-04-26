/// <reference types="https://esm.sh/@supabase/functions-js/src/edge-runtime.d.ts" />
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/**
 * Edge Function: send-weekly-member-digest
 *
 * ADR-0022 W2 (2026-04-26): orchestrator caller. Invokes
 * `generate_weekly_member_digest_cron()` which:
 *   - Iterates active members opted into weekly digest
 *   - For each: builds 7-section digest via get_weekly_member_digest()
 *   - If has_content: inserts a `weekly_member_digest` notification with
 *     delivery_mode='transactional_immediate' (so the existing
 *     `send-notification-email` cron picks it up within 5min for actual
 *     Resend delivery), AND marks consumed digest_weekly notifications as
 *     digest_delivered_at + digest_batch_id (preventing redelivery).
 *
 * Architecture: this EF is the orchestration trigger. The actual email
 * sending happens in `send-notification-email` (which now has a
 * `weekly_member_digest` template renderer parsing the JSON body).
 *
 * Cron: pg_cron entry runs Saturday 12:00 UTC (jobid switched in W2 migration
 * `20260426193225`/`20260426193357`). Manual invocation also OK for testing.
 *
 * W3 backlog: smart-skip empty digest (already done — orchestrator skips
 * recipients with 0 content), leader digest variant, configurable cadence.
 */
Deno.serve(async (req) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
  const json = (d: Record<string, unknown>, s = 200) =>
    new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const srk = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    if (!url || !srk) return json({ error: 'missing env' }, 500)

    const sb = createClient(url, srk, { auth: { autoRefreshToken: false, persistSession: false } })

    const { data, error } = await sb.rpc('generate_weekly_member_digest_cron')
    if (error) return json({ error: 'orchestrator_failed', detail: error.message }, 500)

    const rows = (data ?? []) as Array<{ member_id: string; notified: boolean; reason: string; batch_id: string | null }>
    const sent = rows.filter(r => r.notified).length
    const skipped = rows.filter(r => !r.notified).length

    return json({
      stage: 'W2',
      total_members_checked: rows.length,
      digests_inserted: sent,
      skipped_no_content: skipped,
      message: 'Digest notifications inserted with delivery_mode=transactional_immediate. send-notification-email cron (every 5min) will deliver them via Resend.',
    })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})
