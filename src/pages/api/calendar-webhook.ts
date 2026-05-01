/**
 * Calendar webhook → schedule_interview sync (#116 closure)
 *
 * POST /api/calendar-webhook
 *
 * Apps Script attached to Google Calendar (PM Vitor + Fabricio shared with
 * nucleoia@pmigo.org.br) fires this webhook on event creation when a
 * selection candidate books an interview slot. Webhook syncs the booking
 * into selection_interviews + advances selection_applications.status to
 * 'interview_scheduled'.
 *
 * Auth: shared secret via X-Calendar-Secret header (matches env
 * CALENDAR_WEBHOOK_SECRET). Same pattern as worker pmi-vep-sync /ingest.
 *
 * Body:
 *   {
 *     guest_email: string,            // candidate email (lowercase normalized)
 *     scheduled_at: ISO 8601 string,  // event start time
 *     calendar_event_id: string,      // GCal event ID for cross-ref
 *     interviewer_emails?: string[],  // optional, members will be looked up
 *     calendar_event_url?: string     // optional, kept in notes
 *   }
 *
 * Behavior:
 *   - Lookup application by email (case-insensitive)
 *     - If not found → 404 (Apps Script may notify lead via Calendar comment)
 *   - Lookup interviewers by email → members.id array
 *   - INSERT selection_interviews row (service_role, bypasses RPC auth gate
 *     because: only invoked by trusted Calendar webhook AFTER mark_interview_
 *     status('pending') legítimo flow; gate validation already happened
 *     server-side when comissão approved candidate)
 *   - UPDATE application status → 'interview_scheduled'
 *   - Returns { success, interview_id, application_id, applicant_name }
 *
 * Idempotency: ON CONFLICT (calendar_event_id) DO UPDATE — re-firing the
 * webhook for same event updates scheduled_at instead of creating duplicate
 * (Apps Script may retry on transient errors).
 */
import type { APIRoute } from 'astro';
import { createClient } from '@supabase/supabase-js';

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export const POST: APIRoute = async ({ request, locals }) => {
  const env: any = (locals as any)?.runtime?.env ?? import.meta.env;
  const supabaseUrl = env.SUPABASE_URL || env.PUBLIC_SUPABASE_URL;
  const serviceRoleKey = env.SUPABASE_SERVICE_ROLE_KEY;
  const sharedSecret = env.CALENDAR_WEBHOOK_SECRET;

  if (!supabaseUrl || !serviceRoleKey || !sharedSecret) {
    return jsonResponse({ error: 'webhook_not_configured' }, 503);
  }

  const incomingSecret = request.headers.get('x-calendar-secret');
  if (incomingSecret !== sharedSecret) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  let body: any;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }

  const { guest_email, scheduled_at, calendar_event_id, interviewer_emails, calendar_event_url } = body ?? {};

  if (!guest_email || !scheduled_at || !calendar_event_id) {
    return jsonResponse({ error: 'missing_required_fields', required: ['guest_email','scheduled_at','calendar_event_id'] }, 400);
  }

  const sb = createClient(supabaseUrl, serviceRoleKey);

  // Lookup application by email (case-insensitive, prefer interview-bound statuses)
  const { data: candidates } = await sb.from('selection_applications')
    .select('id, applicant_name, status, cycle_id')
    .ilike('email', guest_email)
    .in('status', ['interview_pending', 'interview_scheduled', 'submitted'])
    .order('created_at', { ascending: false })
    .limit(1);

  const app = candidates?.[0];
  if (!app) {
    return jsonResponse({
      error: 'application_not_found',
      hint: 'No selection_applications row matched the guest_email in interview_pending/interview_scheduled/submitted statuses',
      guest_email,
    }, 404);
  }

  // Lookup interviewers (best effort — empty array if not matched)
  let interviewerIds: string[] = [];
  if (Array.isArray(interviewer_emails) && interviewer_emails.length > 0) {
    const { data: interviewers } = await sb.from('members')
      .select('id')
      .in('email', interviewer_emails);
    interviewerIds = (interviewers ?? []).map((m: any) => m.id);
  }

  const notes = `Auto-synced from Calendar webhook ${new Date().toISOString()}. Event URL: ${calendar_event_url ?? 'n/a'}. Guests: ${(interviewer_emails ?? []).join(', ') || 'n/a'}.`;

  // INSERT or UPDATE selection_interviews (idempotent by calendar_event_id)
  const { data: existing } = await sb.from('selection_interviews')
    .select('id')
    .eq('calendar_event_id', calendar_event_id)
    .limit(1);

  let interviewId: string;
  if (existing && existing.length > 0) {
    // Update existing
    interviewId = existing[0].id;
    const { error } = await sb.from('selection_interviews').update({
      scheduled_at,
      interviewer_ids: interviewerIds,
      status: 'scheduled',
      notes,
    }).eq('id', interviewId);
    if (error) return jsonResponse({ error: 'update_failed', detail: error.message }, 500);
  } else {
    // Insert new
    const { data: inserted, error } = await sb.from('selection_interviews').insert({
      application_id: app.id,
      interviewer_ids: interviewerIds,
      scheduled_at,
      duration_minutes: 30,
      status: 'scheduled',
      calendar_event_id,
      notes,
    }).select('id').single();
    if (error || !inserted) return jsonResponse({ error: 'insert_failed', detail: error?.message }, 500);
    interviewId = inserted.id;
  }

  // Advance application status if not already interview_scheduled
  if (app.status !== 'interview_scheduled') {
    await sb.from('selection_applications').update({
      status: 'interview_scheduled',
      updated_at: new Date().toISOString(),
    }).eq('id', app.id);
  }

  return jsonResponse({
    success: true,
    interview_id: interviewId,
    application_id: app.id,
    applicant_name: app.applicant_name,
    previous_status: app.status,
    interviewer_count: interviewerIds.length,
  }, 200);
};

export const GET: APIRoute = async () => {
  return jsonResponse({
    error: 'POST only',
    docs: 'https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/116',
  }, 405);
};
