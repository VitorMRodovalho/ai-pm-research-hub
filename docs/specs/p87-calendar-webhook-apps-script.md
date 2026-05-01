# Calendar Webhook → schedule_interview Sync — Apps Script Setup

**Issue**: [#116](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/116) Calendar booking → selection_interviews sync gap closure
**Endpoint**: `POST https://nucleoia.vitormr.dev/api/calendar-webhook`
**Status**: Endpoint LIVE p87. Apps Script setup pending PM action.

---

## Overview

PM Vitor's Google Calendar (`vitorodovalho@gmail.com`) and Fabricio's calendar (`fabriciorcc@gmail.com`) are both shared with `nucleoia@pmigo.org.br` (free/busy permission, p87 confirmed). Apps Script attached ao Calendar **nucleoia@pmigo.org.br** triggers on event creation and POSTs to the webhook with booking metadata.

Webhook handler:
1. Validates shared secret header
2. Looks up application by guest email (case-insensitive, prefer interview-pending status)
3. Looks up interviewers by email → members.id
4. INSERT/UPDATE `selection_interviews` row (idempotent via `calendar_event_id`)
5. Advances `selection_applications.status` to `interview_scheduled`

---

## Apps Script setup (PM action)

### 1. Create Apps Script project bound to nucleoia@pmigo.org.br Calendar

1. Login as `nucleoia@pmigo.org.br` (or PM with delegated access)
2. Open Google Apps Script: `https://script.google.com/`
3. New project → name: `nucleoia-calendar-sync`

### 2. Add script properties (project settings → properties)

| Key | Value |
|---|---|
| `WEBHOOK_URL` | `https://nucleoia.vitormr.dev/api/calendar-webhook` |
| `WEBHOOK_SECRET` | (gerar 32-char random hex; copy to Cloudflare Worker env `CALENDAR_WEBHOOK_SECRET` — must match) |

### 3. Code.gs

```javascript
const WEBHOOK_URL = PropertiesService.getScriptProperties().getProperty('WEBHOOK_URL');
const WEBHOOK_SECRET = PropertiesService.getScriptProperties().getProperty('WEBHOOK_SECRET');

/**
 * Calendar trigger handler — fires on event creation.
 * Setup: Apps Script Triggers → Add → "onCalendarEventCreated", from Calendar,
 * trigger on "Calendar updated" → save.
 */
function onCalendarEventCreated(e) {
  // Calendar API trigger event provides calendarId
  const calendarId = e.calendarId || 'nucleoia@pmigo.org.br';
  const cal = CalendarApp.getCalendarById(calendarId);
  if (!cal) return;

  // Process recently created events (last 5 min window)
  const since = new Date(Date.now() - 5 * 60 * 1000);
  const events = cal.getEventsForDay(new Date()).filter(ev =>
    ev.getDateCreated() > since
  );

  events.forEach(ev => {
    syncEventToWebhook(ev);
  });
}

function syncEventToWebhook(ev) {
  const guests = ev.getGuestList(true);  // includes owner
  const guestEmails = guests.map(g => g.getEmail()).filter(e => e);

  // Identify candidate (non-team email) — exclude PM/Fabricio
  const teamEmails = [
    'vitorodovalho@gmail.com',
    'fabriciorcc@gmail.com',
    'nucleoia@pmigo.org.br'
  ];
  const candidateEmail = guestEmails.find(e => !teamEmails.includes(e.toLowerCase()));
  const interviewerEmails = guestEmails.filter(e => teamEmails.includes(e.toLowerCase()) && e !== 'nucleoia@pmigo.org.br');

  if (!candidateEmail) {
    Logger.log('No candidate email identified in event ' + ev.getId());
    return;
  }

  const payload = {
    guest_email: candidateEmail.toLowerCase(),
    scheduled_at: ev.getStartTime().toISOString(),
    calendar_event_id: ev.getId(),
    interviewer_emails: interviewerEmails,
    calendar_event_url: ev.getOriginalCalendarId() ? `https://calendar.google.com/calendar/u/0/r/eventedit/${encodeURIComponent(ev.getId())}` : undefined,
  };

  const response = UrlFetchApp.fetch(WEBHOOK_URL, {
    method: 'post',
    contentType: 'application/json',
    headers: { 'X-Calendar-Secret': WEBHOOK_SECRET },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true,
  });

  const code = response.getResponseCode();
  const body = response.getContentText();

  if (code === 200) {
    Logger.log('Webhook OK for ' + candidateEmail + ': ' + body);
  } else if (code === 404) {
    // Application not found — could comment on Calendar event for committee visibility
    Logger.log('Webhook 404 (no application) for ' + candidateEmail);
    // Optional: ev.setDescription((ev.getDescription() || '') + '\n[ALERT: candidate not in plataforma]');
  } else {
    Logger.log('Webhook error ' + code + ': ' + body);
  }
}

/**
 * Manual smoke test — invoke from Apps Script editor
 */
function smokeTest() {
  const cal = CalendarApp.getCalendarById('nucleoia@pmigo.org.br');
  const tomorrowEvents = cal.getEventsForDay(new Date(Date.now() + 24 * 60 * 60 * 1000));
  if (tomorrowEvents.length === 0) {
    Logger.log('No events tomorrow — create test event manually');
    return;
  }
  syncEventToWebhook(tomorrowEvents[0]);
}
```

### 4. Trigger setup

Apps Script editor → **Triggers** (clock icon) → **Add Trigger**:
- Function: `onCalendarEventCreated`
- Event source: `From calendar`
- Calendar owner email: `nucleoia@pmigo.org.br`
- Event type: `Calendar updated`
- Save

### 5. Configure Cloudflare Worker env

Worker (`platform.ai-pm-research-hub.workers.dev`) needs `CALENDAR_WEBHOOK_SECRET` matching Apps Script:

```bash
npx wrangler secret put CALENDAR_WEBHOOK_SECRET
# Paste same hex value as Apps Script WEBHOOK_SECRET
```

### 6. Smoke test

1. Apps Script editor → run `smokeTest()` function manually
2. Check execution log → should show "Webhook OK" or specific error
3. Verify in DB: `SELECT * FROM selection_interviews ORDER BY created_at DESC LIMIT 1`
4. Should see new row with `calendar_event_id` populated

---

## Webhook contract

### Request

```http
POST /api/calendar-webhook HTTP/1.1
Host: nucleoia.vitormr.dev
Content-Type: application/json
X-Calendar-Secret: <CALENDAR_WEBHOOK_SECRET>

{
  "guest_email": "candidate@example.com",
  "scheduled_at": "2026-05-02T14:00:00.000Z",
  "calendar_event_id": "abc123def456",
  "interviewer_emails": ["vitorodovalho@gmail.com", "fabriciorcc@gmail.com"],
  "calendar_event_url": "https://calendar.google.com/event?eid=..."
}
```

### Response (200)

```json
{
  "success": true,
  "interview_id": "uuid",
  "application_id": "uuid",
  "applicant_name": "Candidate Name",
  "previous_status": "interview_pending",
  "interviewer_count": 2
}
```

### Error responses

- `401 unauthorized` — secret mismatch
- `400 missing_required_fields` — guest_email/scheduled_at/calendar_event_id missing
- `404 application_not_found` — guest_email não bate com nenhuma application em interview_pending/scheduled/submitted (Apps Script pode comentar no Calendar event)
- `500 insert_failed` / `update_failed` — DB error
- `503 webhook_not_configured` — env vars missing on Worker

---

## Limitations + future work

### Current
- **Idempotência via calendar_event_id** — re-firing webhook para mesmo event UPDATEs scheduled_at sem duplicar
- **Bypass do gate atual** (Sprint A.1 schedule_interview gate): webhook insere direto via service_role, NÃO chama RPC schedule_interview que requer gate. Justificativa: webhook só deveria fire DEPOIS do legitimate flow (mark_interview_status → email link → candidate books) — gate validation já aconteceu antes do candidate ter acesso ao link
- **Sem alertas ativos**: 404 returns ao Apps Script mas Apps Script não comenta automatically no Calendar event. PM pode adicionar logic se desejar

### Sprint future (if needed)
- Apps Script comments on Calendar event when 404 received (signal to committee)
- Webhook calls schedule_interview RPC (com new param `p_caller_member_id` → SECDEF accepts service_role context)
- Dashboard indicator: count de webhook 404s última semana

---

## Tracing

- p87 Sprint E (#116 closure): commit `<this-commit>`
- Endpoint: `src/pages/api/calendar-webhook.ts`
- Worker version (deploy after this commit): pendente
- ADR-0066 PMI Journey + Amendment 2026-05-01

Assisted-By: Claude (Anthropic)
