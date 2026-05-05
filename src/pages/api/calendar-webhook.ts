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
// Astro v6 removed `locals.runtime.env` — use `cloudflare:workers` env binding instead.
// Fallback to import.meta.env for local dev where runtime is null.
import { env as cfEnv } from 'cloudflare:workers';

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export const POST: APIRoute = async ({ request }) => {
  // PUBLIC_SUPABASE_URL is build-time injected (import.meta.env). Service role key
  // and webhook secret are runtime (cfEnv). Read from each source individually
  // — using a generic fallback would hide misconfigurations.
  const supabaseUrl = (cfEnv as any)?.SUPABASE_URL || import.meta.env.PUBLIC_SUPABASE_URL;
  const serviceRoleKey = (cfEnv as any)?.SUPABASE_SERVICE_ROLE_KEY;
  const sharedSecret = (cfEnv as any)?.CALENDAR_WEBHOOK_SECRET;

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

  // Lookup application by email (case-insensitive). Include all pre-interview pipeline
  // statuses — candidato pode agendar quando está em qualquer fase ativa do pipeline
  // antes de aprovado/rejeitado terminal. p92 fix: 'objective_eval' (peer review em curso)
  // estava ausente após Phase C status transition, causando 404 falsos.
  const { data: candidates } = await sb.from('selection_applications')
    .select('id, applicant_name, status, interview_status, cycle_id')
    .ilike('email', guest_email)
    .in('status', [
      'submitted',
      'screening',
      'objective_eval',
      'objective_cutoff',
      'interview_pending',
      'interview_scheduled',
    ])
    .order('created_at', { ascending: false })
    .limit(1);

  const app = candidates?.[0];
  if (!app) {
    return jsonResponse({
      error: 'application_not_found',
      hint: 'No selection_applications row matched the guest_email in active pipeline statuses (submitted/screening/objective_eval/objective_cutoff/interview_pending/interview_scheduled)',
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

  // Advance application status + clear pending reschedule flags (Bug #6 p92 Phase B B3).
  // If the candidate previously requested reschedule, this booking is the response —
  // mark interview_status as 'rescheduled' (audit-friendly differentiation).
  // Otherwise (first-time booking via webhook), mark as 'scheduled'.
  // Both clear the amber "Já solicitado" badge in admin/selection.astro:759.
  const newInterviewStatus = app.interview_status === 'needs_reschedule' ? 'rescheduled' : 'scheduled';
  const appUpdates: Record<string, any> = {
    updated_at: new Date().toISOString(),
    interview_status: newInterviewStatus,
    interview_reschedule_reason: null,
    interview_reschedule_requested_at: null,
  };
  if (app.status !== 'interview_scheduled') {
    appUpdates.status = 'interview_scheduled';
  }
  await sb.from('selection_applications').update(appUpdates).eq('id', app.id);

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
