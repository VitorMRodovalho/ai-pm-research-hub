/// <reference types="https://esm.sh/@supabase/functions-js/src/edge-runtime.d.ts" />
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/**
 * Edge Function: send-weekly-member-digest
 *
 * ADR-0022 W1 STUB (2026-04-26): infrastructure-only EF. Pickup target is
 * `notifications` rows where `delivery_mode = 'digest_weekly'` AND
 * `digest_delivered_at IS NULL` AND `created_at` is older than the last
 * Saturday 12:00 UTC.
 *
 * W1 behavior: counts pending rows per recipient and returns the count.
 * Does NOT mark rows as delivered. Does NOT send any email. The actual
 * aggregation + email shaping ships in W2 (SPEC_WEEKLY_MEMBER_DIGEST).
 *
 * Why a stub now: ADR-0022 acceptance criterion §11 requires the EF to be
 * deployed + cron entry active in W1 so subsequent waves can iterate without
 * deploying new EFs. Marking rows as delivered prematurely would consume the
 * pending queue before W2 fills in actual content — so we deliberately skip.
 *
 * Cron: pg_cron entry runs Saturday 12:00 UTC. Manual invocation also OK.
 *
 * Migration path:
 *   - W2: replace this body with actual aggregation (call get_weekly_member_digest
 *     RPC), build email HTML, send via Resend, set digest_delivered_at + digest_batch_id.
 *   - W3: smart-skip empty digest, leader digest variant.
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

    // Last Saturday 12:00 UTC (cron fires Saturday 12 UTC; this function may
    // run later — we always look back at the most recent past Saturday window).
    const lastSaturdayCutoff = lastSaturdayAtNoonUTC(new Date())

    const { data: pending, error } = await sb
      .from('notifications')
      .select('recipient_id, id, type, created_at')
      .eq('delivery_mode', 'digest_weekly')
      .is('digest_delivered_at', null)
      .lt('created_at', lastSaturdayCutoff.toISOString())
      .limit(5000)

    if (error) return json({ error: 'db query failed', detail: error.message }, 500)

    const byRecipient: Record<string, number> = {}
    for (const row of pending ?? []) {
      byRecipient[row.recipient_id] = (byRecipient[row.recipient_id] ?? 0) + 1
    }

    return json({
      stage: 'W1_stub',
      cutoff: lastSaturdayCutoff.toISOString(),
      total_pending_rows: pending?.length ?? 0,
      recipients_with_pending: Object.keys(byRecipient).length,
      message: 'Digest content is implemented in W2 — this stub does not send emails or mark rows as delivered.',
    })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})

/**
 * Returns the most recent past Saturday at 12:00 UTC (inclusive of "today
 * if it is Saturday and current UTC hour ≥ 12"). Used to bound the digest
 * batch — rows created before this cutoff are eligible for the current batch.
 */
function lastSaturdayAtNoonUTC(now: Date): Date {
  const dayOfWeek = now.getUTCDay() // 0 = Sun, 6 = Sat
  let daysBack = dayOfWeek - 6
  if (daysBack < 0) daysBack += 7
  // If today is Saturday but before 12 UTC, use the previous Saturday.
  if (daysBack === 0 && now.getUTCHours() < 12) daysBack = 7
  const target = new Date(now)
  target.setUTCDate(now.getUTCDate() - daysBack)
  target.setUTCHours(12, 0, 0, 0)
  return target
}
