// supabase/functions/resend-webhook/index.ts
// Receives webhooks from Resend and updates campaign_recipients tracking
// Deploy: npx supabase functions deploy resend-webhook --no-verify-jwt

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, svix-id, svix-timestamp, svix-signature',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (d: Record<string, unknown>, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

    const payload = await req.json()
    const eventType: string = payload.type // 'email.delivered', 'email.opened', etc.
    const data = payload.data
    const resendId: string | undefined = data?.email_id
    const recipientEmail: string | undefined = data?.to?.[0]

    console.log(`[resend-webhook] ${eventType} for ${resendId} to ${recipientEmail}`)

    if (!resendId || !eventType) {
      return json({ error: 'Missing resend_id or event_type' }, 400)
    }

    const sb = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 1. Log raw event for audit
    const { error: logErr } = await sb.from('email_webhook_events').insert({
      resend_id: resendId,
      event_type: eventType,
      recipient_email: recipientEmail,
      payload,
    })
    if (logErr) console.error('[resend-webhook] log insert error:', logErr.message)

    // 2. Build update fields for bounce type
    const updateFields: Record<string, string> = {}
    if (eventType === 'email.bounced') {
      updateFields.bounce_type = data?.bounce?.type || 'unknown'
    }

    // 3. Process via RPC (idempotent updates)
    const validEvents = ['email.delivered', 'email.opened', 'email.clicked', 'email.bounced', 'email.complained']
    if (validEvents.includes(eventType)) {
      const { error: rpcErr } = await sb.rpc('process_email_webhook', {
        p_resend_id: resendId,
        p_event_type: eventType,
        p_update_fields: updateFields,
      })
      if (rpcErr) {
        console.error(`[resend-webhook] RPC error: ${rpcErr.message}`)
      } else {
        console.log(`[resend-webhook] processed ${eventType} for ${resendId}`)
      }
    } else {
      console.log(`[resend-webhook] unhandled event type: ${eventType}`)
    }

    return json({ received: true })
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e)
    console.error('[resend-webhook] FATAL:', msg)
    return json({ error: msg }, 500)
  }
})
