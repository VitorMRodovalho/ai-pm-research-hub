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
 *   - Lookup application via match_booking_application(guest_email) — exact
 *     LOWER(TRIM) match (no `_`/`%` wildcard trap), OPEN/ACTIVE cycle scope, and
 *     a same-member alternate-email bridge (member_emails). #472 corr.1 mirror.
 *     - If not found → 404 (Apps Script may notify lead via Calendar comment)
 *   - Lookup interviewers via member_emails (citext) → members.id array
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

  // Lookup application via the canonical matcher (#472 corr.1 webhook mirror).
  // It does LOWER(TRIM(email)) = guest (exact, case-insensitive) so a `_`/`%` in
  // the address is NOT a wildcard — selection_applications.email is `text`, and
  // the prior `.ilike('email', guest)` mis-matched real emails like
  // `j_coelho@id.uff.br`. The matcher also adds the corr.1 robustness: OPEN/ACTIVE
  // cycle scope, a same-member ALTERNATE-email bridge (member_emails — zero
  // cross-candidate risk, primary always preferred), and the pre-interview status
  // allow-list, all in one place shared with the canonical RPC.
  const { data: matchRows, error: matchErr } = await sb.rpc('match_booking_application', {
    p_guest_email: guest_email,
  });
  if (matchErr) {
    return jsonResponse({ error: 'match_failed', detail: matchErr.message }, 500);
  }
  const matched = (Array.isArray(matchRows) ? matchRows[0] : matchRows) as
    | { application_id: string; applicant_name: string; app_status: string; interview_status: string | null; cycle_id: string; matched_by: string }
    | undefined;
  if (!matched) {
    // Observability for the corr-5 consistency cron: record the unmatched booking
    // so the cron can surface "a candidate booked but matched no application" (B1
    // recurrence). Best-effort — never block the response on the audit write.
    await sb.from('admin_audit_log').insert({
      action: 'calendar_booking_unmatched',
      target_type: 'system',
      changes: { guest_email, scheduled_at },
      metadata: { calendar_event_id, source: 'calendar_webhook', reason: 'no matching application in open/active cycle + pre-interview status' },
    });
    return jsonResponse({
      error: 'application_not_found',
      hint: 'No selection_applications row matched the guest_email (primary or same-member alternate via member_emails) in an OPEN/ACTIVE cycle and a pre-interview status (submitted/screening/objective_eval/objective_cutoff/interview_pending/interview_scheduled)',
      guest_email,
    }, 404);
  }
  const app = {
    id: matched.application_id,
    applicant_name: matched.applicant_name,
    status: matched.app_status,
    interview_status: matched.interview_status,
  };
  const matchedBy = matched.matched_by;

  // Lookup interviewers (best effort — empty array if not matched). Resolve via
  // member_emails (citext, full primary coverage + alternates) so an interviewer
  // who books from a personal/alternate address still maps to their member_id —
  // the prior members.email-only lookup left interviewer_ids empty whenever the
  // Apps Script forwarded the organiser's Gmail rather than their primary email.
  let interviewerIds: string[] = [];
  if (Array.isArray(interviewer_emails) && interviewer_emails.length > 0) {
    const normalizedInterviewerEmails = interviewer_emails
      .filter((e: unknown): e is string => typeof e === 'string' && e.trim().length > 0)
      .map((e: string) => e.trim().toLowerCase());
    if (normalizedInterviewerEmails.length > 0) {
      const { data: interviewers } = await sb.from('member_emails')
        .select('member_id')
        .in('email', normalizedInterviewerEmails);
      interviewerIds = [...new Set((interviewers ?? []).map((m: any) => m.member_id as string))];
    }
  }

  const notes = `Auto-synced from Calendar webhook ${new Date().toISOString()}. Event URL: ${calendar_event_url ?? 'n/a'}. Guests: ${(interviewer_emails ?? []).join(', ') || 'n/a'}.`;

  // INSERT or UPDATE selection_interviews (idempotent by calendar_event_id)
  const { data: existing } = await sb.from('selection_interviews')
    .select('id')
    .eq('calendar_event_id', calendar_event_id)
    .limit(1);

  let interviewId: string;
  if (existing && existing.length > 0) {
    // Update existing. Intentionally wider than the corr-1 RPC (which only
    // refreshes scheduled_at): a re-fire also re-resolves interviewer_ids, so a
    // row created before its interviewers were resolvable gets healed on re-fire.
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

  // Observability for the corr-5 consistency cron (parity with the canonical RPC's
  // audit trail). Best-effort — never block the response on the audit write.
  await sb.from('admin_audit_log').insert({
    action: 'calendar_booking_synced',
    target_type: 'selection_interview',
    target_id: interviewId,
    changes: { application_id: app.id, guest_email, previous_app_status: app.status, status_changed: app.status !== 'interview_scheduled' },
    metadata: { calendar_event_id, source: 'calendar_webhook', matched_by: matchedBy, interviewer_count: interviewerIds.length },
  });

  return jsonResponse({
    success: true,
    interview_id: interviewId,
    application_id: app.id,
    applicant_name: app.applicant_name,
    previous_status: app.status,
    interviewer_count: interviewerIds.length,
    matched_by: matchedBy,
  }, 200);
};

export const GET: APIRoute = async () => {
  return jsonResponse({
    error: 'POST only',
    docs: 'https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/116',
  }, 405);
};
