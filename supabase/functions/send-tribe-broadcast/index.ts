/**
 * send-tribe-broadcast — Supabase Edge Function
 * 
 * Allows tribe leaders and admins to send broadcast emails to all active
 * members of a specific tribe, without exposing any email addresses.
 * 
 * Security:
 *   - JWT validated via Supabase Auth
 *   - Caller must be tribe_leader of target tribe OR has_min_tier(4)
 *   - Rate limited: max 3 broadcasts per tribe per day
 *   - Emails sent via BCC (recipients cannot see each other)
 *   - All dispatches logged to broadcast_log table
 * 
 * Payload: { tribe_id: number, subject: string, body: string }
 * Secret:  RESEND_API_KEY (set via supabase secrets set)
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const MAX_BROADCASTS_PER_DAY = 3

function jsonResponse(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ success: false, error: 'Method not allowed' }, 405)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const resendApiKey = Deno.env.get('RESEND_API_KEY')

  if (!resendApiKey) {
    return jsonResponse({ success: false, error: 'Email service not configured' }, 500)
  }

  // ── Auth: extract and validate JWT ──
  const authHeader = req.headers.get('Authorization') ?? ''
  const token = authHeader.replace(/^Bearer\s+/i, '')
  if (!token) {
    return jsonResponse({ success: false, error: 'Missing authorization token' }, 401)
  }

  const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  })
  const { data: { user }, error: userError } = await userClient.auth.getUser()
  if (userError || !user) {
    return jsonResponse({ success: false, error: 'Invalid or expired token' }, 401)
  }

  // Service-role client for privileged operations
  const sb = createClient(supabaseUrl, serviceRoleKey)

  // ── Get caller member ──
  const { data: caller } = await sb
    .from('members')
    .select('id, tribe_id, operational_role, is_superadmin, name')
    .eq('auth_id', user.id)
    .single()

  if (!caller) {
    return jsonResponse({ success: false, error: 'Member not found' }, 403)
  }

  // ── Parse payload ──
  let payload: { tribe_id: number; subject: string; body: string }
  try {
    payload = await req.json()
  } catch {
    return jsonResponse({ success: false, error: 'Invalid JSON payload' }, 400)
  }

  const { tribe_id, subject, body } = payload
  if (!tribe_id || !subject?.trim() || !body?.trim()) {
    return jsonResponse({ success: false, error: 'Missing required fields: tribe_id, subject, body' }, 400)
  }

  // ── Authorization: caller must be admin OR tribe_leader of this tribe ──
  const isAdmin = caller.is_superadmin === true
    || caller.operational_role === 'manager'
    || caller.operational_role === 'deputy_manager'
  const isTribeLeader = caller.operational_role === 'tribe_leader'
    && caller.tribe_id === tribe_id

  if (!isAdmin && !isTribeLeader) {
    return jsonResponse({ success: false, error: 'Not authorized to broadcast to this tribe' }, 403)
  }

  // ── Rate limit: max N per day per tribe ──
  const { data: countToday } = await sb.rpc('broadcast_count_today', { p_tribe_id: tribe_id })
  if (typeof countToday === 'number' && countToday >= MAX_BROADCASTS_PER_DAY) {
    return jsonResponse({
      success: false,
      error: `Rate limit exceeded. Maximum ${MAX_BROADCASTS_PER_DAY} broadcasts per tribe per day.`,
    }, 429)
  }

  // ── Fetch active tribe members' emails ──
  const { data: members, error: membersError } = await sb
    .from('members')
    .select('email')
    .eq('tribe_id', tribe_id)
    .eq('current_cycle_active', true)
    .not('email', 'is', null)

  if (membersError || !members?.length) {
    return jsonResponse({
      success: false,
      error: membersError?.message || 'No active members found in this tribe',
    }, 400)
  }

  const emails: string[] = members
    .map((m: { email: string }) => m.email)
    .filter((e: string) => e && e.includes('@'))

  if (emails.length === 0) {
    return jsonResponse({ success: false, error: 'No valid email addresses found' }, 400)
  }

  // ── Get tribe name for email context ──
  const { data: tribe } = await sb
    .from('tribes')
    .select('name')
    .eq('id', tribe_id)
    .single()

  const tribeName = tribe?.name || `Tribo ${tribe_id}`
  const senderName = caller.name || 'Líder de Tribo'

  // ── Send via Resend API (BCC for privacy) ──
  // Use RESEND_FROM_ADDRESS env or default to Resend test domain
  const fromAddress = Deno.env.get('RESEND_FROM_ADDRESS') || 'Núcleo IA & GP <onboarding@resend.dev>'

  const htmlBody = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
      <div style="background: #0F172A; color: white; padding: 16px 20px; border-radius: 12px 12px 0 0;">
        <strong>Núcleo IA & GP</strong> — ${tribeName}
      </div>
      <div style="background: white; border: 1px solid #E2E8F0; border-top: none; padding: 24px 20px; border-radius: 0 0 12px 12px;">
        <p style="color: #64748B; font-size: 13px; margin: 0 0 4px;">
          Comunicado de <strong>${senderName}</strong>
        </p>
        <h2 style="color: #0F172A; margin: 8px 0 16px; font-size: 18px;">${subject}</h2>
        <div style="color: #334155; font-size: 14px; line-height: 1.7; white-space: pre-wrap;">${body}</div>
        <hr style="border: none; border-top: 1px solid #E2E8F0; margin: 24px 0 16px;" />
        <p style="color: #94A3B8; font-size: 11px; margin: 0;">
          Você recebeu este e-mail por ser membro ativo da ${tribeName} no Núcleo IA & GP.
          Este é um envio automático — por favor, não responda diretamente.
        </p>
      </div>
    </div>`

  let sendStatus = 'sent'
  let errorDetail: string | null = null

  try {
    const resendResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: fromAddress,
        to: [fromAddress],
        bcc: emails,
        subject: `[${tribeName}] ${subject}`,
        html: htmlBody,
      }),
    })

    if (!resendResponse.ok) {
      const errBody = await resendResponse.text()
      sendStatus = 'failed'
      errorDetail = `Resend API ${resendResponse.status}: ${errBody}`
    }
  } catch (err: unknown) {
    sendStatus = 'failed'
    errorDetail = err instanceof Error ? err.message : String(err)
  }

  // ── Log broadcast (using service_role to bypass RLS) ──
  await sb.from('broadcast_log').insert({
    tribe_id,
    sender_id: caller.id,
    subject: subject.trim(),
    body: body.trim(),
    recipient_count: emails.length,
    status: sendStatus,
    error_detail: errorDetail,
  })

  if (sendStatus === 'failed') {
    return jsonResponse({
      success: false,
      error: 'Email dispatch failed',
      detail: errorDetail,
    }, 502)
  }

  return jsonResponse({
    success: true,
    recipient_count: emails.length,
    tribe: tribeName,
  })
})
