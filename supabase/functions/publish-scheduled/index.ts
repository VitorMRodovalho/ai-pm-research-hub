// publish-scheduled — drains the comms_scheduled_posts queue.
//
// The Instagram Content Publishing API publishes on call (no future-time field), so the
// platform owns scheduling. A pg_cron pings this EF every few minutes; it picks up rows
// whose scheduled_at has passed and publishes them through the existing publish-instagram
// function (one credential, one validated publish path — no logic duplicated here).
//
// Per row: pending -> publishing -> published | failed. Failures retry up to MAX_ATTEMPTS
// (left as 'pending' for the next run), then settle as 'failed'. A row stuck in
// 'publishing' (EF crashed mid-flight) is reclaimed after a stale window.
//
// Auth: Bearer / x-sync-secret = INSTAGRAM_PUBLISH_SECRET or SUPABASE_SERVICE_ROLE_KEY
// (same contract as publish-instagram, so the cron's vault service_role_key works).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const MAX_ATTEMPTS = 3
const BATCH = 5                         // publish at most N due rows per invocation
const STALE_PUBLISHING_MIN = 30         // reclaim rows stuck in 'publishing' this long

interface ScheduledRow {
  id: string
  channel: string
  media_type: string
  payload: Record<string, unknown>
  attempts: number
  label: string | null
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ success: false, error: 'POST only' }, 405)

  const publishSecret = Deno.env.get('INSTAGRAM_PUBLISH_SECRET')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const bearer = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '')
  const headerSecret = req.headers.get('x-sync-secret')
  const valid = [publishSecret, serviceKey].filter(Boolean)
  if (!valid.length || (!valid.includes(bearer ?? '') && !valid.includes(headerSecret ?? ''))) {
    return json({ success: false, error: 'Unauthorized' }, 401)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const sb = createClient(supabaseUrl, serviceKey!)

  // 1) reclaim rows stuck in 'publishing' (a prior run died mid-flight) back to pending.
  await sb
    .from('comms_scheduled_posts')
    .update({ status: 'pending' })
    .eq('status', 'publishing')
    .lt('created_at', new Date(Date.now() - STALE_PUBLISHING_MIN * 60_000).toISOString())

  // 2) claim due rows.
  const { data: due, error: dueErr } = await sb
    .from('comms_scheduled_posts')
    .select('id, channel, media_type, payload, attempts, label')
    .eq('status', 'pending')
    .lte('scheduled_at', new Date().toISOString())
    .order('scheduled_at', { ascending: true })
    .limit(BATCH)

  if (dueErr) return json({ success: false, error: dueErr.message }, 500)
  if (!due || due.length === 0) return json({ success: true, drained: 0, results: [] })

  const results: Array<Record<string, unknown>> = []

  for (const row of due as ScheduledRow[]) {
    // mark publishing (guard against a concurrent run grabbing the same row)
    const { data: claimed } = await sb
      .from('comms_scheduled_posts')
      .update({ status: 'publishing', attempts: row.attempts + 1 })
      .eq('id', row.id)
      .eq('status', 'pending')
      .select('id')
      .maybeSingle()
    if (!claimed) { results.push({ id: row.id, skipped: 'claimed by another run' }); continue }

    try {
      // delegate to the validated single-post function (service role auth)
      const res = await fetch(`${supabaseUrl}/functions/v1/publish-instagram`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceKey}` },
        body: JSON.stringify(row.payload),
      })
      const out = await res.json().catch(() => ({}))

      if (out?.success && out?.published) {
        await sb.from('comms_scheduled_posts').update({
          status: 'published',
          external_id: out.media_id ?? null,
          permalink: out.permalink ?? null,
          published_at: new Date().toISOString(),
          error: null,
        }).eq('id', row.id)
        results.push({ id: row.id, label: row.label, published: true, media_id: out.media_id })
      } else {
        throw new Error(out?.error ?? `publish-instagram returned ${res.status}`)
      }
    } catch (err) {
      const msg = String(err instanceof Error ? err.message : err)
      const exhausted = row.attempts + 1 >= MAX_ATTEMPTS
      await sb.from('comms_scheduled_posts').update({
        status: exhausted ? 'failed' : 'pending',   // retry next run unless out of attempts
        error: msg,
      }).eq('id', row.id)
      results.push({ id: row.id, label: row.label, published: false, error: msg, exhausted })
    }
  }

  return json({ success: true, drained: results.length, results })
})
