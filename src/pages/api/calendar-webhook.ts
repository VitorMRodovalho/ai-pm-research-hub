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
 *     - #1611: a RPC devolve SEMPRE uma linha, com `match_outcome`. Os três
 *       desfechos de recusa (no_application / status_not_allowed / cycle_closed)
 *       têm ação de auditoria PRÓPRIA — antes iam todos para
 *       `calendar_booking_unmatched`, misturando "a plataforma tem um buraco"
 *       com "a plataforma funcionou". A resposta 404 carrega `reason` e
 *       `retryable` para que a origem saiba quando desistir.
 *     - #1609: toda tentativa recusada é CONTADA em selection_booking_attempts
 *       (uma linha por evento+convidado), e só gera linha de auditoria quando
 *       record_booking_attempt autoriza — primeira aparição, mudança de desfecho,
 *       o corte, e a resolução. Medido em 2026-08-05: 11 reservas tinham gerado
 *       16.722 linhas de log (~1.093 por evento) porque o Apps Script reenvia o
 *       mesmo evento a cada 5 min enquanto ele não casar, e o branch 404 do
 *       script DELIBERADAMENTE não o marca como processado.
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

/**
 * #1611 — um desfecho de recusa, uma ação de auditoria.
 *
 * Os três casos viviam no MESMO balde (`calendar_booking_unmatched`), o que
 * misturava dois fatos operacionais OPOSTOS: "a plataforma tem um buraco"
 * (nenhuma candidatura resolve o e-mail — acionável, é preciso reparar o
 * vínculo) e "a plataforma funcionou" (a candidatura existe e a reserva foi
 * recusada CORRETAMENTE porque já foi decidida, ou porque o ciclo fechou).
 * Quem media "quantas reservas se perderam" contava os dois.
 */
const UNMATCHED_AUDIT_ACTION: Record<string, string> = {
  no_application: 'calendar_booking_unmatched',
  status_not_allowed: 'calendar_booking_already_decided',
  cycle_closed: 'calendar_booking_stale_cycle',
};

/**
 * Só o buraco real merece nova tentativa. Uma candidatura já decidida ou um
 * ciclo fechado NÃO mudam sozinhos — reenviar a mesma reserva a cada 5 min é
 * garantia de tempestade sem chance de sucesso. O Apps Script de origem lê este
 * campo para decidir entre desistir e tentar de novo com backoff.
 */
function isRetryable(outcome: string): boolean {
  return outcome === 'no_application';
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
  // #1611: a RPC devolve SEMPRE uma linha. Ausência de linha aqui seria um defeito
  // da própria RPC, não "não achei" — por isso o fallback é explícito e não um
  // `if (!matched)` que confundiria os dois.
  const matched = (Array.isArray(matchRows) ? matchRows[0] : matchRows) as
    | { application_id: string | null; applicant_name: string | null; app_status: string | null; interview_status: string | null; cycle_id: string | null; matched_by: string | null; match_outcome: string }
    | undefined;
  const outcome = matched?.match_outcome ?? 'no_application';

  if (outcome !== 'matched') {
    // #1609: a tentativa é CONTADA sempre; a linha de auditoria só sai quando o
    // contador autoriza. Antes disto o Apps Script (5 em 5 min, horizonte de 90
    // dias) gravava uma linha por varredura enquanto a reserva não casasse —
    // 5.693 linhas para um único evento foi o pior caso medido em 2026-08-05.
    const { data: attemptRows } = await sb.rpc('record_booking_attempt', {
      p_calendar_event_id: calendar_event_id,
      p_guest_email: guest_email,
      p_outcome: outcome,
      p_scheduled_at: scheduled_at,
    });
    const attempt = (Array.isArray(attemptRows) ? attemptRows[0] : attemptRows) as
      | { attempts: number; should_audit: boolean; suppressed: boolean; outcome_changed: boolean }
      | undefined;

    if (attempt?.should_audit !== false) {
      // Best-effort — never block the response on the audit write. O `!== false`
      // é deliberado: se a RPC do contador falhar, o log volta a ser escrito em
      // vez de sumir calado (uma falha de observabilidade não pode APAGAR o fato).
      const action = UNMATCHED_AUDIT_ACTION[outcome] ?? 'calendar_booking_unmatched';
      if (action === 'calendar_booking_unmatched') {
        await sb.from('admin_audit_log').insert({
          action: 'calendar_booking_unmatched',
          target_type: 'system',
          changes: { guest_email, scheduled_at },
          metadata: { calendar_event_id, source: 'calendar_webhook', match_outcome: outcome, attempts: attempt?.attempts ?? null, reason: 'no application resolves this guest_email' },
        });
      } else {
        await sb.from('admin_audit_log').insert({
          action,
          target_type: 'selection_application',
          target_id: matched?.application_id ?? null,
          changes: { guest_email, scheduled_at, app_status: matched?.app_status ?? null },
          metadata: { calendar_event_id, source: 'calendar_webhook', match_outcome: outcome, attempts: attempt?.attempts ?? null, reason: outcome === 'status_not_allowed' ? 'application already decided — refusal is correct by design' : 'application belongs to a closed cycle — refusal is correct by design' },
        });
      }
    }

    return jsonResponse({
      error: 'application_not_found',
      reason: outcome,
      retryable: isRetryable(outcome),
      attempts: attempt?.attempts ?? null,
      suppressed: attempt?.suppressed ?? false,
      hint: outcome === 'no_application'
        ? 'No selection_applications row matched the guest_email (primary or same-member alternate via member_emails) in ANY cycle'
        : outcome === 'status_not_allowed'
          ? 'An application matched, but its status is outside the pre-interview allow-list (submitted/screening/objective_eval/objective_cutoff/interview_pending/interview_scheduled) — a decided application is never re-opened by a booking. Do NOT retry.'
          : 'An application matched, but it belongs to a cycle that is no longer open/active. Do NOT retry.',
      guest_email,
    }, 404);
  }
  // `matched` sem application_id violaria o contrato da RPC (#1611). Falhar alto
  // aqui é melhor do que promover uma candidatura inexistente — e é o que impede
  // o TypeScript de tratar as colunas nuláveis do desfecho de recusa como se
  // fossem do desfecho de sucesso.
  if (!matched?.application_id) {
    return jsonResponse({
      error: 'match_contract_violation',
      detail: 'match_booking_application returned match_outcome=matched without an application_id',
    }, 500);
  }
  const app = {
    id: matched.application_id,
    applicant_name: matched.applicant_name ?? '',
    status: matched.app_status ?? '',
    interview_status: matched.interview_status,
  };
  const matchedBy = matched.matched_by ?? 'primary';

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

  // #1609: o sucesso também passa pelo contador. Duas razões: (a) fecha o par na
  // fila de exceção (`resolved_at`), de modo que uma reserva que estava presa e
  // depois casou SAI da fila em vez de exigir limpeza manual; (b) o sucesso deixa
  // de poder virar a próxima tempestade — hoje ele é silencioso porque o Apps
  // Script marca o evento como processado em 2xx, mas isso é uma propriedade da
  // ORIGEM, e a origem já provou que não é confiável.
  const { data: syncRows } = await sb.rpc('record_booking_attempt', {
    p_calendar_event_id: calendar_event_id,
    p_guest_email: guest_email,
    p_outcome: 'matched',
    p_scheduled_at: scheduled_at,
  });
  const syncAttempt = (Array.isArray(syncRows) ? syncRows[0] : syncRows) as
    | { attempts: number; should_audit: boolean; outcome_changed: boolean }
    | undefined;

  // Observability for the corr-5 consistency cron (parity with the canonical RPC's
  // audit trail). Best-effort — never block the response on the audit write.
  if (syncAttempt?.should_audit !== false) {
    await sb.from('admin_audit_log').insert({
      action: 'calendar_booking_synced',
      target_type: 'selection_interview',
      target_id: interviewId,
      changes: { application_id: app.id, guest_email, previous_app_status: app.status, status_changed: app.status !== 'interview_scheduled' },
      metadata: { calendar_event_id, source: 'calendar_webhook', matched_by: matchedBy, interviewer_count: interviewerIds.length, attempts: syncAttempt?.attempts ?? null, recovered_after_failures: (syncAttempt?.attempts ?? 1) > 1 },
    });
  }

  return jsonResponse({
    success: true,
    interview_id: interviewId,
    application_id: app.id,
    applicant_name: app.applicant_name,
    previous_status: app.status,
    interviewer_count: interviewerIds.length,
    matched_by: matchedBy,
    attempts: syncAttempt?.attempts ?? null,
  }, 200);
};

export const GET: APIRoute = async () => {
  return jsonResponse({
    error: 'POST only',
    docs: 'https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/116',
  }, 405);
};
