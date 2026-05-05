# Calendar Webhook → schedule_interview Sync — Apps Script Setup

**Issue**: [#116](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/116) Calendar booking → selection_interviews sync gap closure
**Endpoint**: `POST https://nucleoia.vitormr.dev/api/calendar-webhook`
**Status**: Endpoint LIVE p87 + B3 webhook fix shipped p92 Phase B (clear reschedule flags). **Apps Script setup ainda pendente PM action** — usar código corrigido abaixo (B1+B2 fixes incorporados 2026-05-05 após audit p91).

## Audit history

- **2026-05-05 (p91 audit)**: 3 BLOCKERs + 3 IMPORTANT + 2 MINOR identificados em `docs/specs/p91-selection-journey-audit.md` §4. Fixes B1, B2, B3, B4, B5, B6 + B7+B8 cosméticos.
- **2026-05-05 (p92 Phase B)**: B3 webhook fix (clear reschedule flags) shipped. Spec atualizado com B1, B2, B4, B5, B6 corretos. PM segue spec atual sem patch adicional.

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

// B2 fix (p92 audit): Apps Script trigger sees Gmail pessoal dos interviewers,
// mas members.email armazena emails institucionais. Translate aqui ANTES de
// POST → webhook lookup `members.email IN (...)` retorna interviewer_ids correto.
//
// Manter sincronizado quando interviewers entram/saem do time. Source of truth =
// public.members.email no Núcleo plataforma.
const EMAIL_ALIAS = {
  'vitorodovalho@gmail.com': 'vitor.rodovalho@outlook.com',
  // 'fabricio.personal@gmail.com': 'fabriciorcc@gmail.com'  // adicionar se Fabricio tiver Gmail pessoal distinto do institucional
};

/**
 * Calendar trigger handler — fires on event creation OR update.
 *
 * Setup: Apps Script Triggers → Add → trigger from "Calendar", calendar
 * "nucleoia@pmigo.org.br", event type "Calendar updated" → save.
 *
 * B6 (p92): "Calendar updated" trigger fires for create/edit/delete. Webhook
 * é idempotente em `calendar_event_id` (UPDATE no segundo fire). `getDateCreated`
 * filter abaixo garante que só processamos eventos novos (criados nos últimos
 * 5 min) — edits a eventos antigos não dispatcham (acceptable: candidatos
 * raramente editam após booking).
 */
function onCalendarEventCreated(e) {
  // Calendar API trigger event provides calendarId
  const calendarId = e.calendarId || 'nucleoia@pmigo.org.br';
  const cal = CalendarApp.getCalendarById(calendarId);
  if (!cal) return;

  // B1 fix (p92): janela ampla (90 dias futuros) — candidatos podem agendar
  // entrevista para 2+ dias no futuro; getEventsForDay(today) era míope.
  // `getDateCreated > since` filtra para apenas eventos NOVOS (created nos
  // últimos 5 min) → evita reprocessar eventos antigos quando trigger fires
  // para qualquer mudança no calendário.
  const since = new Date(Date.now() - 5 * 60 * 1000);
  const now = new Date();
  const farFuture = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000);
  const events = cal.getEvents(now, farFuture).filter(ev =>
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
  const interviewerEmailsRaw = guestEmails.filter(e =>
    teamEmails.includes(e.toLowerCase()) && e !== 'nucleoia@pmigo.org.br'
  );

  // B2 fix (p92): translate Gmail pessoal → email institucional ANTES de POST
  const interviewerEmails = interviewerEmailsRaw.map(e =>
    EMAIL_ALIAS[e.toLowerCase()] || e
  );

  if (!candidateEmail) {
    Logger.log('No candidate email identified in event ' + ev.getId());
    return;
  }

  const payload = {
    guest_email: candidateEmail.toLowerCase(),
    scheduled_at: ev.getStartTime().toISOString(),
    calendar_event_id: ev.getId(),
    interviewer_emails: interviewerEmails,
    // B7 (p92): calendar event URL format invalid for direct event open;
    // webhook salva no notes apenas para audit display (low impact).
    calendar_event_url: ev.getOriginalCalendarId()
      ? `https://calendar.google.com/calendar/u/0/r/eventedit/${encodeURIComponent(ev.getId())}`
      : undefined,
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
 * Manual smoke test — invoke from Apps Script editor.
 *
 * B8 fix (p92): aceita `eventId` opcional. Sem param: pega primeiro evento
 * dos próximos 7 dias (ao invés de "amanhã" — falha silenciosamente se vazio).
 *
 * Uso:
 *   smokeTest()              → primeiro evento próximos 7 dias
 *   smokeTest('abc123def')   → evento específico por GCal ID
 */
function smokeTest(eventId) {
  const cal = CalendarApp.getCalendarById('nucleoia@pmigo.org.br');
  let ev;
  if (eventId) {
    ev = cal.getEventById(eventId);
  } else {
    const upcoming = cal.getEvents(
      new Date(),
      new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
    );
    ev = upcoming[0];
  }
  if (!ev) {
    Logger.log('No event found — create one or pass an explicit eventId');
    return;
  }
  syncEventToWebhook(ev);
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

Worker (canonical domain `nucleoia.vitormr.dev`, deployed em `astro-pm-hub-v2`) precisa **3 secrets** para o webhook funcionar:

```bash
# B4 fix (p92): worker URL canonical é nucleoia.vitormr.dev — legacy
# `platform.ai-pm-research-hub.workers.dev` redireciona via 301.
# Wrangler deploy do projeto root (NÃO subdir cloudflare-workers/pmi-vep-sync).
cd /path/to/ai-pm-research-hub

# 1) Calendar webhook shared secret — PM já configurou (wrangler secret list confirma 2026-05-05)
npx wrangler secret put CALENDAR_WEBHOOK_SECRET
# Paste same hex value as Apps Script WEBHOOK_SECRET

# 2) Supabase service role key — REQUIRED para webhook acessar selection_applications/selection_interviews
# (p92 audit identificou: webhook retornava 503 webhook_not_configured pois SERVICE_ROLE_KEY ausente)
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
# Paste from Supabase dashboard → Settings → API → service_role secret
# DO NOT commit this value; treat as production credential.

# 3) (Optional) SUPABASE_URL — webhook fallback to PUBLIC_SUPABASE_URL (build-time .env) is fine
#    Set explicitly only if PUBLIC_SUPABASE_URL diverges from runtime URL.
```

**p92 verification** (2026-05-05 02:25 UTC): após Astro v6 env-access fix shipped (`b01eea33`), webhook responde:
- `HTTP 503 {"error":"webhook_not_configured"}` quando `SUPABASE_SERVICE_ROLE_KEY` ausente (current state)
- `HTTP 401 {"error":"unauthorized"}` quando secret está set mas X-Calendar-Secret header errado
- `HTTP 200 {success: true, ...}` quando tudo correto + body válido
- `HTTP 404 {"error":"application_not_found"}` quando email não bate

PM precisa rodar `npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY` antes do Apps Script setup.

### 6. OAuth authorization (primeira execução)

B5 fix (p92): Na primeira execução do `smokeTest()` (ou primeiro fire do trigger), Google solicita autorização para os scopes:

- `https://www.googleapis.com/auth/calendar.readonly` — ler eventos + guests
- `https://www.googleapis.com/auth/script.external_request` — POST para webhook URL externa

Aceitar todas as permissões. Se aparecer warning "App não verificada", clicar em "Avançado" → "Acessar nucleoia-calendar-sync (não verificada)" — é normal para Apps Script bound a contas não-Workspace.

### 7. Smoke test

1. Apps Script editor → run `smokeTest()` function manually (sem args = pega primeiro evento próximos 7 dias)
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

- p87 Sprint E (#116 closure): endpoint shipped, Apps Script setup deferred
- p91 audit (`docs/specs/p91-selection-journey-audit.md` §4): 3 BLOCKER + 3 IMPORTANT identified
- p92 Phase B: webhook B3 fix (clear `interview_status` reschedule flags) + spec patches B1+B2+B4+B5+B6+B8
- Endpoint: `src/pages/api/calendar-webhook.ts`
- ADR-0066 PMI Journey + Amendments 1-3 (Amendment 3 = Bug #2 worker filter, related)

Assisted-By: Claude (Anthropic)
