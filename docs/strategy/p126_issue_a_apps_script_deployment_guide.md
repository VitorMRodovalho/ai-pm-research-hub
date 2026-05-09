# Issue A — Apps Script Calendar Webhook Deployment Guide

**Date:** 2026-05-09
**Sessão:** p126 E3 reduced (continuation)
**Status:** Backend ready (RPC `sync_calendar_booking_to_interview` deployed since 2026-05-06 via ADR-0073 migration `20260516920000`); secret rotated this session; **Apps Script deployment pending PM action**.

## What was done in p126 (auto-applicable steps)

1. **Audit `site_config`**:
   - `webhook_url`: NULL (placeholder — never set)
   - `arm116_calendar_webhook_secret`: was `CHANGE_ME_IN_PRODUCTION_*` (placeholder)

2. **Rotated `arm116_calendar_webhook_secret`** via SQL:
   - Old: `CHANGE_ME_IN_PRODUCTION_3f4f5ede8e311ea625008b22e03c405f`
   - New: crypto-random UUID-based value (NOT in this doc — query DB to get it)
   - `admin_audit_log` entry registered: `action='p126_arm116_secret_rotation'`

3. **Backend confirmed working**:
   - RPC `sync_calendar_booking_to_interview` deployed since 2026-05-06
   - Schema gate intentionally bypasses `schedule_interview` gates per ADR-0073 design
   - Idempotent on `calendar_event_id`

## What PM must do (manual Apps Script deployment)

### Step 1 — Get the rotated secret

Query Supabase via MCP or dashboard:
```sql
SELECT value FROM site_config WHERE key = 'arm116_calendar_webhook_secret';
```
Copy the value. **Do NOT paste in commits or shared docs.** Treat as production secret.

### Step 2 — Locate Apps Script project

Per memory `handoff_p119`: existing Apps Script project usado em "auto-add guests" flow. Provavelmente:
- Project name like "PMI Calendar Booking" or similar
- Owner: Vitor's Google Workspace account
- Login: https://script.google.com/

If projeto não existe (handoff p119 disse "auth dep deferred"), criar novo:
- New Apps Script project
- Bind to Vitor's Calendar (the one used for `https://calendar.app.google/gh9WjefjcmisVLoh7`)

### Step 3 — Paste this code into Apps Script editor

Filename: `appsscript.gs` (or `Code.gs` default)

```javascript
// p126 ARM-116 Calendar Booking → Núcleo Selection Interview Sync
// ADR-0073 + Decision 10 + p126 deployment guide
// Owner: Vitor Maia Rodovalho (PMI-GO Núcleo IA)
// Last deployed: 2026-MM-DD

const SUPABASE_URL = 'https://ldrfrvwhxsmgaabwmaik.supabase.co';

// Anon key — public-by-design per CLAUDE.md (RLS gates protect data).
// Get from: https://supabase.com/dashboard/project/ldrfrvwhxsmgaabwmaik/settings/api
const SUPABASE_ANON_KEY = '<PASTE_ANON_KEY_FROM_DASHBOARD>';

// Secret rotated 2026-05-09 — query SELECT value FROM site_config
// WHERE key = 'arm116_calendar_webhook_secret' to get current value.
const ARM116_SECRET = '<PASTE_FROM_site_config>';

const NUCLEO_TEAM_DOMAINS = ['pmigo.org.br', 'nucleoia.vitormr.dev'];

function syncCalendarBookingToInterview(eventId, calendarId) {
  try {
    const event = CalendarApp.getCalendarById(calendarId).getEventById(eventId);
    if (!event) {
      Logger.log('arm116 sync skip: event not found ' + eventId);
      return;
    }

    // Skip events that are clearly not selection interviews
    const title = event.getTitle().toLowerCase();
    const isSelectionInterview = title.includes('entrevista') || title.includes('selection') || title.includes('candidat');
    if (!isSelectionInterview) {
      Logger.log('arm116 sync skip: not a selection interview event "' + event.getTitle() + '"');
      return;
    }

    // Find first non-organizer guest that's not internal team
    const organizerEmail = event.getCreators()[0];
    const guests = event.getGuestList();
    const guestEmail = guests
      .map(g => g.getEmail())
      .find(email => {
        if (email === organizerEmail) return false;
        const domain = email.split('@')[1] || '';
        if (NUCLEO_TEAM_DOMAINS.some(d => domain.includes(d))) return false;
        return true;
      });

    if (!guestEmail) {
      Logger.log('arm116 sync skip: no external guest found in event ' + eventId);
      return;
    }

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

    const code = response.getResponseCode();
    const body = response.getContentText();
    Logger.log(`arm116 sync ${code}: ${body.substring(0, 500)}`);

    if (code >= 400) {
      // Optional: send error notification to Vitor email
      // MailApp.sendEmail('vitor.rodovalho@outlook.com', 'arm116 sync failed', body);
    }

  } catch (e) {
    Logger.log('arm116 sync error: ' + e.toString());
  }
}

// ────────────────────────────────────────────────────────────────────────
// Trigger setup — run this ONCE manually after pasting code
// ────────────────────────────────────────────────────────────────────────
function setupTriggers() {
  // Remove existing triggers
  ScriptApp.getProjectTriggers().forEach(t => ScriptApp.deleteTrigger(t));

  // Calendar event change trigger (fires on event create/update/delete)
  ScriptApp.newTrigger('onCalendarChange')
    .forUserCalendar(Session.getActiveUser().getEmail())
    .onEventUpdated()
    .create();

  Logger.log('Triggers installed');
}

// ────────────────────────────────────────────────────────────────────────
// Trigger handler — extracts eventId + calendarId from event
// ────────────────────────────────────────────────────────────────────────
function onCalendarChange(e) {
  if (!e || !e.calendarId) {
    Logger.log('onCalendarChange: missing calendarId; skip');
    return;
  }

  // The event triggers on ANY calendar change. We sync only events that
  // were created or updated in the past hour (avoid re-syncing old events).
  const calendar = CalendarApp.getCalendarById(e.calendarId);
  if (!calendar) return;

  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
  const recentEvents = calendar.getEvents(oneHourAgo, new Date(Date.now() + 24 * 60 * 60 * 1000));

  recentEvents.forEach(event => {
    syncCalendarBookingToInterview(event.getId(), e.calendarId);
  });
}

// ────────────────────────────────────────────────────────────────────────
// Manual smoke test — run this after setup to verify backend reachable
// ────────────────────────────────────────────────────────────────────────
function smokeTest() {
  const testPayload = {
    secret: ARM116_SECRET,
    guest_email: 'arm116-smoke-test@example.com',  // unmatched email
    scheduled_at: new Date().toISOString(),
    calendar_event_id: 'arm116-smoke-' + Date.now(),
    event_title: '[TEST] arm116 smoke from Apps Script'
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
      payload: JSON.stringify({ p_payload: testPayload }),
      muteHttpExceptions: true
    }
  );

  Logger.log(`Smoke test code: ${response.getResponseCode()}`);
  Logger.log(`Smoke test body: ${response.getContentText()}`);
  // Expected: 200 OK, body contains '{"matched": false, ...}' (unmatched email
  // is OK — just confirms RPC is reachable and secret is correct)
}
```

### Step 4 — Deploy as Web App

1. In Apps Script editor, click **Deploy** → **New deployment**
2. Type: **Web app**
3. Description: `arm116 Calendar Booking Sync v1`
4. Execute as: **Me (your email)**
5. Who has access: **Anyone** (the RPC itself is gated by secret, so this is OK)
6. Click **Deploy**
7. Copy the **Web App URL** (looks like `https://script.google.com/macros/s/.../exec`)

### Step 5 — Update site_config.webhook_url

Via SQL or Supabase dashboard:
```sql
UPDATE site_config 
SET value = to_jsonb('<PASTE_WEB_APP_URL_FROM_STEP_4>'::text)
WHERE key = 'webhook_url';

-- Audit log
INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
VALUES (
  NULL,
  'p126_webhook_url_set',
  'site_config',
  NULL,
  jsonb_build_object(
    'key', 'webhook_url',
    'reason', 'Apps Script Web App deployed per ADR-0073 + Issue A resolution',
    'session', 'p126'
  )
);
```

### Step 6 — Run smoke test

In Apps Script editor:
1. Select function `smokeTest` from dropdown
2. Click **Run** (▶)
3. Authorize the script if prompted
4. Check **Execution log** at bottom — expect `code: 200` + body with `{"matched": false, ...}`

### Step 7 — Setup triggers

In Apps Script editor:
1. Select function `setupTriggers` from dropdown
2. Click **Run** (▶)
3. Authorize Calendar access if prompted
4. Verify trigger active: **Triggers** menu (clock icon) → should show 1 trigger for `onCalendarChange`

### Step 8 — End-to-end test

1. Create a test event on YOUR Calendar with title containing "entrevista"
2. Add a guest with a non-PMI-GO email (e.g., `arm116-test@gmail.com`)
3. Save event
4. Wait 30-60 seconds for trigger
5. Check Apps Script execution log for sync output
6. Check Supabase: `SELECT * FROM selection_interviews WHERE calendar_event_id = '<EVENT_ID>'`

### Rollback

If anything goes wrong:
1. Delete Apps Script Web App deployment
2. Reset `site_config.webhook_url` to NULL
3. Old behavior restores (no sync, manual interview entry only)

## Verification post-deploy

After all steps:
```sql
-- Check site_config has both values populated
SELECT key, 
       CASE 
         WHEN value::text = '"null"' OR value IS NULL THEN 'NOT SET'
         WHEN value::text LIKE '%CHANGE_ME%' THEN 'PLACEHOLDER'
         ELSE 'PRODUCTION' 
       END AS status
FROM site_config 
WHERE key IN ('webhook_url', 'arm116_calendar_webhook_secret')
ORDER BY key;

-- Expected post-deploy: both rows status='PRODUCTION'
```

```sql
-- Check sync activity (should populate after Apps Script trigger fires)
SELECT 
  COUNT(*) FILTER (WHERE action = 'arm116.calendar_booking_synced') AS synced,
  COUNT(*) FILTER (WHERE action = 'arm116.calendar_booking_unmatched') AS unmatched,
  MAX(created_at) FILTER (WHERE action LIKE 'arm116.%') AS last_sync_attempt
FROM admin_audit_log
WHERE created_at > now() - interval '7 days';
```

## Notes

- **NOT in p126 commit**: Apps Script project lives in Google Workspace (Vitor's account); Web App URL é per-deployment; secret é per-rotation. Repo holds template only.
- **Deferred from p126**: 30-day audit of "0 sync events" historical data — once webhook live, growth signal will be observable in `admin_audit_log` action='arm116.calendar_booking_synced'.
- **Tracking**: T-3 (chapter VP coordination for cron compliance) é separate work — not gated by Apps Script deploy.
