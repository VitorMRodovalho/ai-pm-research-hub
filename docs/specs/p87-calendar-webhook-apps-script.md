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
 *
 * IMPORTANTE: para testar manualmente via "Run" no editor, use `smokeTest()`
 * (não `onCalendarEventCreated`). Ao rodar onCalendarEventCreated diretamente,
 * o param `e` vem undefined e o código abaixo cai no fallback `nucleoia@…`.
 */
function onCalendarEventCreated(e) {
  // Quando rodado manualmente via "Run" no editor, e === undefined → usar fallback.
  // Trigger real fornece e.calendarId.
  const calendarId = (e && e.calendarId) || 'nucleoia@pmigo.org.br';
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

### 5. Configure Cloudflare Worker env (PM action — apenas 1 secret novo)

**O que é:** O webhook que está em `nucleoia.vitormr.dev/api/calendar-webhook` precisa acessar Supabase com permissão de service_role para escrever em `selection_interviews` + atualizar `selection_applications`. Esse acesso usa um secret guardado no Worker da Cloudflare.

**O que falta:** Apenas **1 secret novo** — `SUPABASE_SERVICE_ROLE_KEY`. Os outros 2 (`CALENDAR_WEBHOOK_SECRET` e `PUBLIC_SUPABASE_URL`) já estão configurados (p92 verificado).

**Caminho A — Cloudflare Dashboard (recomendado se CLI auth quebrar)**

Esse caminho NÃO usa wrangler CLI, evita auth issues:

1. Abrir https://dash.cloudflare.com/ e login
2. Account: navegar até **Workers & Pages**
3. Selecionar Worker `platform`
4. Aba **Settings** → seção **Variables and Secrets** → botão **+ Add**
5. Type: `Secret`. Variable name: `SUPABASE_SERVICE_ROLE_KEY`. Value: cole do Supabase dashboard → Settings → API → secção "service_role secret" (esse é o JWT longo que começa com `eyJ...`)
6. **Save**

Pronto. O Worker vai usar esse valor automaticamente nas próximas requisições — não precisa redeploy.

**Caminho B — wrangler CLI (alternativa)**

```bash
cd /home/vitormrodovalho/projects/ai-pm-research-hub
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
# Cole o valor quando perguntado
```

⚠️ Se aparecer erro `Authentication error [code: 10000]` ou `Invalid access token [code: 9109]`, o token wrangler expirou (caught p92 2026-05-05 ~07:00 UTC). Soluções:
- Re-autenticar: `npx wrangler login` (abre browser local)
- Ou usar Caminho A (dashboard)

**p92 verification — webhook response shape após shipping**:
- `HTTP 503 {"error":"webhook_not_configured"}` ← *current state*; ocorre quando `SUPABASE_SERVICE_ROLE_KEY` ausente
- `HTTP 401 {"error":"unauthorized"}` ← secret set mas header `X-Calendar-Secret` errado
- `HTTP 200 {success: true, ...}` ← tudo correto + body válido
- `HTTP 404 {"error":"application_not_found"}` ← guest_email não bate com candidato no DB

Quando o secret estiver setado, próximo `curl` retorna 401 (não 503) — confirma config OK.

### 6. OAuth authorization (acontece automaticamente — não é "step" manual separado)

**Não é uma ação separada.** É só uma nota: na primeira vez que você clica "Run" em qualquer função do Apps Script (incluindo `smokeTest()`), o Google abre uma janela popup pedindo autorização para acessar o Calendar e fazer requisições externas. Você aceita uma vez e funciona daí em diante.

Scopes que o Google vai pedir:
- `https://www.googleapis.com/auth/calendar.readonly` — ler eventos + lista de convidados
- `https://www.googleapis.com/auth/script.external_request` — fazer POST para o webhook (`nucleoia.vitormr.dev`)

**Importante**: a primeira execução pode mostrar "Esta aplicação não foi verificada pelo Google". É **normal** para Apps Scripts pessoais ou bound a contas não-Workspace. Caminho:

1. Clicar **"Avançado"** (no canto inferior do warning)
2. Clicar **"Acessar nucleoia-calendar-sync (não seguro)"**
3. Aprovar os 2 scopes
4. Pronto — não pedirá novamente para esse projeto

**TL;DR**: você não precisa fazer nada para "configurar" OAuth. Só precisa clicar Run e aceitar quando o Google perguntar.

### 7. Smoke test (primeira validação)

⚠️ **NÃO clique Run em `onCalendarEventCreated`** — essa função espera o param `e` que só vem do trigger. Rodar manualmente lança `TypeError: Cannot read properties of undefined (reading 'calendarId')` (caught p92 quando PM tentou).

✅ **Use `smokeTest()` para teste manual:**

1. No editor Apps Script, no dropdown "Selecionar função", escolher **`smokeTest`**
2. Clicar **Run** (▶)
3. Primeira vez: Google pede autorização — aceitar (ver step 6)
4. Aba **Execução log** deve mostrar `"Webhook OK for ..."` ou erro específico
5. Verificar DB:
   ```sql
   SELECT id, application_id, scheduled_at, status, calendar_event_id, created_at
   FROM selection_interviews
   ORDER BY created_at DESC LIMIT 1;
   ```
6. Deve aparecer linha nova com `calendar_event_id` populado

**Para testar o trigger automático** (não só manual): crie um evento no Calendar `nucleoia@pmigo.org.br` com um candidato real como guest → o trigger fire dentro de ~1 minuto → webhook recebe → linha em `selection_interviews`.

---

## Webhook contract (referência apenas — não exige ação PM)

⚠️ **Esta seção é DOCUMENTAÇÃO técnica do que o webhook aceita/retorna**. Você (PM) não precisa fazer nada com ela. É útil para:
- Debugar erros se algo não funcionar (saber o que cada HTTP status significa)
- Futuras integrações com outros sistemas
- Auditoria de quem chama o webhook

O Apps Script faz a chamada automática — você não constrói o payload manualmente.

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
