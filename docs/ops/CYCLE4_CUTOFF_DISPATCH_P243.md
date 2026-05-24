# Cycle 4 Cutoff Dispatch Runbook — PM operational (p243)

**Sessão:** p243 (2026-05-24)
**Purpose:** Step-by-step runbook for the PM committee to dispatch
`selection_cutoff_approved` notifications to the 5 above-target cycle4-2026
apps identified by the p242 audit. Includes pre-flight checks, error matrix,
post-dispatch verification, rollback notes, and cron-validation script for
the Mon 2026-05-25 13:00 UTC first fire.
**Scope:** Operational runbook only. No migrations, no schema changes,
no automated dispatch from this PR. PM executes from an authenticated
MCP-Claude session.

## TL;DR (3-step PM action)

1. **Set `cycle4-2026.interview_booking_url`** to PM's Calendly/cal.com link
   (currently `NULL` — without this, the dispatch RPC raises
   `CUTOFF_NO_BOOKING_URL` errcode `P0020` and refuses to send).
2. **Run the 5 dispatch SQL statements** (one per app — copy-paste block
   below) from authenticated MCP-Claude session.
3. **Mon 2026-05-25 13:00 UTC**: cron jobid 47 first scheduled fire;
   verify with the SQL recipe in §5.

## 1. Pre-flight live state (audited 2026-05-24 ≈16:00 UTC, post-recompute)

### 1.1 BLOCKER — `cycle4-2026.interview_booking_url IS NULL`

| Cycle | URL | Dispatch gate |
|---|---|---|
| cycle4-2026 | NULL | **BLOCKER**: `CUTOFF_NO_BOOKING_URL P0020` would raise |
| cycle3-2026-b2 | NULL | (same blocker — also has 2 apps in scope post-recompute) |
| cycle3-2026 | NULL | (announcement phase, no dispatch scope) |

The column was added in p228 Wave 2 Leaf 4 (migration
`20260805000011`) but no cycle has ever been populated — the 22+
cycle3-2026-b2 interviews that fired historically used manual
link-sharing outside this RPC dispatch path.

**Unblock options**:

- **Path A (canonical, audited)**: PM sets the URL via `/admin/selection`
  cycle config UI OR direct SQL:
  ```sql
  UPDATE public.selection_cycles
  SET interview_booking_url = '<PM-supplied Calendly/cal.com URL>',
      updated_at = now()
  WHERE cycle_code = 'cycle4-2026';
  ```
  (Same for `cycle3-2026-b2` if PM wants to dispatch those 2 in scope.)
- **Path B (manual, historical)**: PM shares the link via the same
  channel used historically (email/WhatsApp). No audit trail in
  `admin_audit_log`, no `cutoff_approved_email_sent_at` flip, no
  `campaign_send_one_off` row — but matches the pattern that has been
  working through p228+ for the 22+ cycle3-b2 interviews.

This runbook documents **Path A** (canonical) for the 5 cycle4 apps.

### 1.2 Template + apps state (all ✅)

- `campaign_templates.selection_cutoff_approved` present in 3 langs
  (pt/en/es); `category='operational'`; variables `first_name` +
  `interview_booking_url`; `updated_at=2026-05-23 16:54 UTC` (p228 W2
  Leaf 4 ship).
- All 5 above-target apps: status=`screening`, email set,
  `cutoff_approved_email_sent_at IS NULL`, objective_score_avg >
  `pert_target_score` (155.42). Detail table:

| Applicant | obj_avg | email (redacted) | Idempotency |
|---|---|---|---|
| Henrique Diniz S. Silva | 227.00 | `h.***ok.com` | OK: not sent yet |
| João Coelho Júnior | 171.00 | `j_***uff.br` | OK: not sent yet |
| Francisleila Melo Santos | 164.00 | `fr***am.com` | OK: not sent yet |
| Cristiano de Oliveira Santos Filho | 163.00 | `co***il.com` | OK: not sent yet |
| Edinan Soares | 157.50 | `ed***com.br` | OK: not sent yet |

## 2. Dispatch SQL (Path A — canonical, run from authenticated MCP-Claude session)

After Step 1.1 (Path A) sets `cycle4-2026.interview_booking_url`, run
the 5 statements below. Each is **idempotent** (no-op if
`cutoff_approved_email_sent_at` already set) and returns a structured
envelope.

```sql
-- Henrique Diniz S. Silva (obj_avg 227.00)
SELECT public.notify_selection_cutoff_approved(
  'bcc54dfc-ac79-4a26-a05f-eeb571d48fd9'::uuid
);

-- João Coelho Júnior (obj_avg 171.00)
SELECT public.notify_selection_cutoff_approved(
  'cef2b25e-4bc0-4e0e-a642-a3f3fec68549'::uuid
);

-- Francisleila Melo Santos (obj_avg 164.00)
SELECT public.notify_selection_cutoff_approved(
  '72ea1a45-8dc8-4b0b-b4cb-f1427968ff22'::uuid
);

-- Cristiano de Oliveira Santos Filho (obj_avg 163.00)
SELECT public.notify_selection_cutoff_approved(
  'f82f5ec7-1a76-4960-8c0d-5a94b502ffc3'::uuid
);

-- Edinan Soares (obj_avg 157.50)
SELECT public.notify_selection_cutoff_approved(
  '77fdb870-5398-4c52-abda-b292b594b558'::uuid
);
```

### 2.1 Expected return shape (per call)

Success (first call on each app):
```json
{
  "success": true,
  "application_id": "<uuid>",
  "cycle_id": "08c1e301-9f7b-4d01-a13c-43ac7775c0f7",
  "email_sent": true,
  "recipient_email_redacted": "ab***xy.com",
  "objective_done": <int — count of objective evaluations on this app>,
  "research_score": <numeric>
}
```

Idempotent no-op (if re-run on already-dispatched app):
```json
{
  "success": true,
  "application_id": "<uuid>",
  "email_sent": false,
  "reason": "already_sent",
  "previously_sent_at": "<timestamp>"
}
```

## 3. Error matrix

| Error | Cause | Fix |
|---|---|---|
| `Unauthorized: member not found` | Service-role caller (no `auth.uid()` → no `members` row) | Use authenticated MCP-Claude session as Vitor (platform admin) or as committee lead |
| `Unauthorized: must be committee lead or have manage_member` | Caller member exists but not in `selection_committee` for this cycle as `role='lead'` AND not `manage_member` via `can_by_member()` | Vitor (platform admin) satisfies `manage_member`; otherwise add caller to committee or use platform admin account |
| `CUTOFF_NO_BOOKING_URL ... P0020` | `cycle.interview_booking_url IS NULL` or empty | Step 1.1 Path A first |
| `Application not found` | UUID typo or app deleted | Re-copy UUID from §2 block above |
| `Application has no email — cannot dispatch` | `selection_applications.email IS NULL` (would have been flagged in §1.2 pre-flight; none of the 5 above-target apps trigger this currently) | UPDATE the app's email field first; then re-run |
| Resend-side delivery failure | Email accepted by RPC but Resend rejects (bounce / hard-fail) | Check `campaign_send_one_off` failure path; `cutoff_approved_email_sent_at` won't flip because `campaign_send_one_off` raises before the UPDATE |

## 4. Post-dispatch verification

After all 5 calls return `email_sent: true`, run:

```sql
-- Verify the 5 apps now have cutoff_approved_email_sent_at populated
SELECT id, applicant_name, status, cutoff_approved_email_sent_at,
  CASE WHEN cutoff_approved_email_sent_at IS NOT NULL
       THEN 'DISPATCHED' ELSE 'PENDING' END AS dispatch_state
FROM public.selection_applications
WHERE id IN (
  'bcc54dfc-ac79-4a26-a05f-eeb571d48fd9'::uuid,
  'cef2b25e-4bc0-4e0e-a642-a3f3fec68549'::uuid,
  '72ea1a45-8dc8-4b0b-b4cb-f1427968ff22'::uuid,
  'f82f5ec7-1a76-4960-8c0d-5a94b502ffc3'::uuid,
  '77fdb870-5398-4c52-abda-b292b594b558'::uuid
)
ORDER BY objective_score_avg DESC;

-- Verify 5 audit rows landed in admin_audit_log
SELECT actor_id, action, target_id, created_at,
  metadata->>'cycle_code' AS cycle_code,
  metadata->>'objective_done' AS objective_done,
  metadata->>'rpc_version' AS rpc_version
FROM public.admin_audit_log
WHERE action = 'selection.cutoff_approved_email_dispatched'
  AND target_id IN (
    'bcc54dfc-ac79-4a26-a05f-eeb571d48fd9'::uuid,
    'cef2b25e-4bc0-4e0e-a642-a3f3fec68549'::uuid,
    '72ea1a45-8dc8-4b0b-b4cb-f1427968ff22'::uuid,
    'f82f5ec7-1a76-4960-8c0d-5a94b502ffc3'::uuid,
    '77fdb870-5398-4c52-abda-b292b594b558'::uuid
  )
ORDER BY created_at DESC;
```

Expected: 5 rows in each query, all with `dispatch_state=DISPATCHED`
and `rpc_version='p228_w2_leaf4'`.

### 4.1 Natural status advance (post-candidate-booking)

After candidates click the booking URL + reserve their slot:
- Calendar webhook (#116) fires → `register_calendar_event` → resolves
  candidate by email → INSERTs `selection_interviews` row with
  `status='scheduled'`.
- p240 trigger `trg_sync_interview_to_app_status` fires on the new row
  → advances `selection_applications.status` from `screening` →
  `interview_scheduled`.
- p241 hoist of `submit_interview_scores` then ensures status
  progresses to `interview_done` after even partial evaluator
  submission.

PM doesn't run anything more for the status advance — it cascades from
the booking event. Verify with:

```sql
SELECT id, applicant_name, status, updated_at
FROM public.selection_applications
WHERE id IN (<the 5 uuids>)
ORDER BY updated_at DESC;
```

Expected progression over the next N days as candidates book:
`screening` → `interview_scheduled` → `interview_done` → (eventually)
`final_eval` once all evaluator submissions are in.

## 5. Cron validation — Mon 2026-05-25 13:00 UTC first fire

The `recompute-pert-cutoffs-weekly` cron (jobid 47, schedule
`0 13 * * 1` UTC) has never fired live — installed in p228 (Sat
2026-05-23 ≈22:00 UTC), so Mon 2026-05-25 13:00 UTC is the first
scheduled window. The p242 audit manually invoked
`recompute_all_active_pert_cutoffs()` at 2026-05-24 15:40:38 UTC; the
cron's first fire should advance `pert_calc_at` again.

Run **after** 2026-05-25 13:05 UTC (give it 5min slack):

```sql
-- 5.1 cron job ran cleanly
SELECT runid, jobid, start_time, end_time, status,
  CASE WHEN length(return_message) > 200
       THEN left(return_message, 200)||'…'
       ELSE return_message END AS msg
FROM cron.job_run_details
WHERE jobid = 47
ORDER BY start_time DESC LIMIT 3;

-- Expected: 1 row with status='succeeded' and start_time ≈ 2026-05-25 13:00 UTC

-- 5.2 pert_calc_at advanced for cycle4 + cycle3-b2 apps
SELECT c.cycle_code,
  count(*) AS apps,
  max(a.pert_calc_at) AS most_recent_recompute,
  min(a.pert_calc_at) AS oldest_recompute
FROM public.selection_applications a
JOIN public.selection_cycles c ON c.id = a.cycle_id
WHERE c.cycle_code IN ('cycle4-2026', 'cycle3-2026-b2')
GROUP BY c.cycle_code;

-- Expected: most_recent_recompute = oldest_recompute ≈ 2026-05-25 13:00 UTC
-- (recompute updates all in-scope apps atomically; min/max collapse to same value)
```

If cron jobid 47 status is `failed` or `start_time` doesn't show a row
near 2026-05-25 13:00 UTC, open an investigation issue:

```bash
gh issue create \
  --title "p243 follow-up: cron jobid 47 recompute-pert-cutoffs-weekly first fire failed/missed" \
  --label "bug,foundation,selection" \
  --body "Mon 2026-05-25 13:00 UTC first scheduled fire did not run cleanly. cron.job_run_details query returned [N] rows / status [X]. Investigation needed: pg_cron extension health, recompute_all_active_pert_cutoffs() permissions under cron user, schedule string interpretation. Cross-ref P162 #210 RESOLVED-WATCH-240.C."
```

## 6. Rollback notes

- **Emails sent**: cannot un-send. If PM regrets a dispatch (wrong app
  picked), candidate may receive a booking link they shouldn't have
  acted on. Mitigate by follow-up email clarification.
- **`cutoff_approved_email_sent_at` flip**: can be reset via direct
  UPDATE if PM wants to "re-arm" idempotency for an app, but the audit
  row in `admin_audit_log` is **immutable** (no DELETE permitted) — so
  the historical record will show the original dispatch.
  ```sql
  -- Only if PM explicitly wants to re-arm an app for re-dispatch:
  UPDATE public.selection_applications
  SET cutoff_approved_email_sent_at = NULL, updated_at = now()
  WHERE id = '<uuid>';
  ```
- **Path A vs Path B mix**: if PM later changes mind and wants to use
  Path B (manual link share) instead, simply skip the SQL block and the
  `cutoff_approved_email_sent_at` column stays NULL — no harm. The 5
  apps continue in `screening` until manual UI move or natural webhook
  → trigger advance.

## 7. Open follow-ups (deferred to PM)

1. **cycle3-2026-b2 (2 apps in recompute scope)**: same booking URL
   gap. PM decides if any of those 2 also need dispatch (WATCH-240.B
   audit pending — verify they're legit late-evaluations).
2. **Persistent NULL booking URL across all 3 cycles**: structural
   question — is the system supposed to require this field at cycle
   creation? Could be a backlog item to add a `NOT NULL` constraint OR
   a default value at insert time. Defer unless PM signals demand.
3. **Auto-trigger for cutoff_approved post-recompute** (p230 fast-follow
   carry, still open): when cron jobid 47 fires + finds N above-target
   apps, should it auto-dispatch the notifications? Or stay
   manual-PM-gated as today? Decision deferred (governance question).
4. **Manual link-share Path B**: if PM continues that pattern, no
   `cutoff_approved_email_sent_at` audit trail accumulates. Backlog:
   add a "dispatch_method" enum to the column or a sibling table so
   Path B is also auditable.

## Cross-ref

- `docs/audit/CYCLE4_PERT_CUTOFF_P242_WATCH_240_C.md` (p242 audit —
  origin of this runbook)
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` entry #210 (WATCH-240.C
  disposition)
- Migration `supabase/migrations/20260805000011_p228_260_w2_leaf4_selection_cutoff_approved.sql`
  (`notify_selection_cutoff_approved` RPC body — gate ladder, idempotency,
  template dispatch, audit log)
- `campaign_templates.selection_cutoff_approved` (template body in 3
  langs, p228 W2 Leaf 4 ship 2026-05-23 16:54 UTC)
- p240 trigger migration `20260805000025` (`screening`/`interview_pending`
  → `interview_done` on conducted_at OR status='completed')
- p241 hoist migration `20260805000026` (`submit_interview_scores`
  partial-submission defense-in-depth)
- WATCH-240.B parallel carry (cycle3-2026-b2 4-row late-evaluation audit)
