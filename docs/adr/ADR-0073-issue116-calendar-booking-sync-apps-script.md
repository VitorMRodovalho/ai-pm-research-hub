# ADR-0073: Issue #116 Calendar Booking Sync via Apps Script

**Status**: Accepted (Decision 3 path B = Apps Script smoke; A = #92 full bidirectional remains future state)
**Date**: 2026-05-06
**Decider**: PM Vitor Maia Rodovalho
**Trigger**: Issue #116 CRITICAL (Fabricio WhatsApp 2026-05-01) + plano ABCD bloco D

---

## Context

Candidatos do processo seletivo bookam entrevistas via Calendar link público (`https://calendar.app.google/gh9WjefjcmisVLoh7`). Apps Script "auto-add guests" (p82) adiciona Fabricio como attendee. Mas **selection_interviews** permanece vazia — ninguém chamava `schedule_interview` RPC.

Resultado pré-fix:
- Fabricio vê 2 entrevistas amanhã no Calendar dele
- Plataforma cega: `selection_applications.status='interview_pending'` ainda
- Wave 5d (#86 reschedule) não funciona — sem row em `selection_interviews`
- Comitê sem registro auditável de quem está marcado

Decisão 3 do plano ABCD: B agora (Apps Script smoke), A em paralelo (#92 full GCal/Outlook bidirectional = caminho final).

## Decision

**Apps Script atual (p82) é estendido para POST em RPC anon-callable após event creation.** RPC `sync_calendar_booking_to_interview` autentica via shared secret, faz lookup da application por email, cria `selection_interviews` row.

### Bypass intencional dos gates do `schedule_interview`

`schedule_interview` RPC tem gates rígidos (GATE_NO_AI, GATE_NO_PEER_REVIEW, GATE_NO_SCORE) que protegem contra "schedule before scoring". Mas booking via Calendar é **informational** — não significa decisão de avançar. Aplicar gates aqui causaria falha silenciosa e perda de evidência.

`sync_calendar_booking_to_interview` bypassa intencionalmente esses gates. Os gates ainda se aplicam quando comissão submete scores via `submit_interview_scores` (gate at score-submission, não at scheduling).

### Idempotência

Idempotente em `calendar_event_id`: re-call com mesmo event_id atualiza `scheduled_at` (caso reagendamento via Calendar) sem criar duplicata.

### Audit trail

Cada chamada gera entry em `admin_audit_log`:
- `arm116.calendar_booking_synced` (sucesso)
- `arm116.calendar_booking_unmatched` (warning, email não bate em nenhuma application open/active)

### Status promotion

Se `selection_applications.status` está em `submitted`/`in_review`/`interview_pending`, é promovido para `interview_scheduled`. NÃO downgrade de `interview_done`/`accepted`/`rejected`.

## Implementation

### Backend (shipped 2026-05-06)

Migration: `20260516920000_issue116_calendar_booking_sync_to_interview.sql`

- RPC `sync_calendar_booking_to_interview(p_payload jsonb)` SECURITY DEFINER, anon-callable
- `site_config.arm116_calendar_webhook_secret` setting (default random; PM rotaciona)

### Apps Script template (PM owns deployment)

Adicionar à Apps Script existente que faz "auto-add guests":

```javascript
// File: appsscript.gs (Project: PMI Calendar Booking)
// Trigger: onCalendarChange OR setEventCreated

const SUPABASE_URL = 'https://ldrfrvwhxsmgaabwmaik.supabase.co';
const SUPABASE_ANON_KEY = '<ANON_KEY>'; // Public — see CLAUDE.md
const ARM116_SECRET = '<COPY_FROM_site_config_arm116_calendar_webhook_secret>';

function syncCalendarBookingToInterview(eventId, calendarId) {
  const event = CalendarApp.getCalendarById(calendarId).getEventById(eventId);
  if (!event) return;

  // Guest email — first non-organizer attendee that's not internal team
  const guests = event.getGuestList();
  const guestEmail = guests.find(g => g.getEmail() !== event.getCreators()[0])?.getEmail();
  if (!guestEmail) return;

  const payload = {
    secret: ARM116_SECRET,
    guest_email: guestEmail,
    scheduled_at: event.getStartTime().toISOString(),
    calendar_event_id: eventId,
    event_title: event.getTitle()
  };

  const response = UrlFetchApp.fetch(
    `${SUPABASE_URL}/rest/v1/rpc/sync_calendar_booking_to_interview`,
    {
      method: 'post',
      contentType: 'application/json',
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
      },
      payload: JSON.stringify({ p_payload: payload }),
      muteHttpExceptions: true
    }
  );
  Logger.log('arm116 sync: ' + response.getContentText());
}

// Trigger setup (run once):
function installArm116Trigger() {
  ScriptApp.newTrigger('onCalendarUpdated')
    .forUserCalendar(Session.getActiveUser().getEmail())
    .onEventUpdated()
    .create();
}

function onCalendarUpdated(e) {
  if (e.calendarId && e.eventId) {
    syncCalendarBookingToInterview(e.eventId, e.calendarId);
  }
}
```

### Ownership

- **Apps Script project**: PM Vitor (owner) + Fabricio (editor) + plataforma email service-account (executor recommended for production)
- **Secret rotation**: PM atualiza `site_config.arm116_calendar_webhook_secret` via SQL editor + atualiza `ARM116_SECRET` no Apps Script. Recomendado a cada 90 dias OU em case of compromise.
- **Logs**: `Logger.log` em Apps Script (Stackdriver) + `admin_audit_log` no DB
- **Disable**: deletar trigger no Apps Script project; RPC permanece no DB

## Consequences

### Positive

- Fabricio bug resolvido: bookings aparecem em `selection_interviews` automaticamente
- Wave 5d reschedule flow agora funciona (precondição satisfeita)
- Audit trail completo de bookings
- Status promotion automatica para `interview_scheduled`
- Idempotente: reagendamentos atualizam, não duplicam
- Bypass gates é INTENCIONAL e auditado (não falha silenciosa)

### Negative

- **Shadow infra**: Apps Script project em conta Google de alguém. Risk: se conta perder acesso, sync para. Mitigation: documentado aqui + Service Account migration recomendada
- **Secret em config**: `site_config.arm116_calendar_webhook_secret` é text plain. Rotação manual. Future: vault.secrets ou env var em Worker proxy
- **Sem validação de event ownership**: Apps Script confia que event vem do Calendar correto. Future: adicionar `calendar_id` whitelist no RPC
- **Webhook endpoint não criado** (Worker route `/api/calendar-webhook` per #116 proposta): Apps Script chama Supabase REST direto. Mais simples, sem middleware. Future: Worker route para HMAC validation + rate limit + observability

### Future State (Decision 3 path A — #92 full)

- Bidirectional GCal/Outlook integration (não só GCal)
- Webhook subscriber em vez de polling
- Conflict detection (re-schedule, cancellations)
- Recurring event support
- Service Account ownership (não personal Google account)
- Worker route com HMAC + rate limit
- MCP tools `sync_calendar_event` + `list_pending_calendar_events`

#92 issue cobre essa visão completa. ADR-0073 é stop-gap até #92 ship.

## References

- Migration: `supabase/migrations/20260516920000_issue116_calendar_booking_sync_to_interview.sql`
- RPC: `public.sync_calendar_booking_to_interview(p_payload jsonb)`
- Issue: https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/116
- Cross-ref: #92 (calendar integration full), #86 Wave 5d (interview reschedule)
- ADR-0028: cron-context auth bypass pattern
- Site config secret: `arm116_calendar_webhook_secret` (rotate periodically)
