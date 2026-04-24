# Spec: ADR-0022 W1 — `notifications.delivery_mode` schema migration + EF split

> **Status**: Draft for dev team review (2026-04-25 p45)
> **Owner**: PM Vitor Rodovalho (decision) + Claude (drafting)
> **Parent**: [ADR-0022](../adr/ADR-0022-communication-batching-weekly-digest-default.md) — Communication Batching, Weekly Digest as Default
> **Sibling specs**: [SPEC_WEEKLY_MEMBER_DIGEST](./SPEC_WEEKLY_MEMBER_DIGEST.md) (W2 content), [SPEC_ENGAGEMENT_WELCOME_EMAIL](./SPEC_ENGAGEMENT_WELCOME_EMAIL.md) (W2 first integrator)
> **Estimate**: ~1 sprint dev time (1 migration + 1 EF refactor + 1 contract test)

---

## 1. Goal

Land the **schema substrate** for ADR-0022 so subsequent work (W2 digest content, W3 leader digest) can opt into delivery routing without further DDL.

Concrete deliverables:

1. Migration `notifications.delivery_mode` + `digest_delivered_at` + `digest_batch_id` + partial index.
2. Backfill: classify the 16 existing `notifications.type` values per ADR-0022 catalog.
3. EF refactor: existing `send-notification-emails` (or split — see §6) routes by `delivery_mode`.
4. Contract test: every NEW migration that adds a `notifications.type` value MUST also declare its delivery_mode (in catalog or via inline mapping).

What W1 does **not** do:
- Implement digest content (`get_weekly_member_digest` RPC) — that's W2.
- Add settings UI for member opt-out — W2.
- Leader digest — W3.
- Smart-skip empty digest — W3.

---

## 2. Current state (snapshot 2026-04-25)

`public.notifications` has **2349 rows** across 16 distinct types:

| type | rows | proposed delivery_mode |
|---|---:|---|
| `attendance_reminder` | 1733 | `digest_weekly` if event > 48h, else `transactional_immediate` |
| `assignment_new` | 367 | `digest_weekly` |
| `tribe_broadcast` | 100 | conditional — see §3.2 |
| `attendance_detractor` | 49 | `suppress` |
| `volunteer_agreement_signed` | 20 | `transactional_immediate` |
| `ip_ratification_gate_pending` | 15 | `transactional_immediate` |
| `webinar_status_confirmed` | 15 | `digest_weekly` |
| `card_assigned` | 13 | `digest_weekly` |
| `publication` | 12 | `digest_weekly` |
| `card_status_changed` | 7 | `digest_weekly` |
| `info` | 5 | `suppress` |
| `governance_vote_reminder` | 5 | conditional — see §3.2 |
| `system_alert` | 3 | `transactional_immediate` |
| `certificate_issued` | 2 | `digest_weekly` |
| `system` | 2 | `suppress` |
| `certificate_ready` | 1 | `transactional_immediate` |
| `member_offboarded` (#91 G6) | n/a | `transactional_immediate` |

Schema today (post p44):

```sql
public.notifications (
  id              uuid PK,
  recipient_id    uuid NOT NULL,
  type            text NOT NULL,
  title           text NOT NULL,
  body            text,
  link            text,
  source_type     text,
  source_id       uuid,
  is_read         boolean DEFAULT false,
  read_at         timestamptz,
  created_at      timestamptz DEFAULT now(),
  actor_id        uuid,
  email_sent_at   timestamptz                 -- ← email cron sets this
)
```

Note: column is **`recipient_id`** (not `member_id`). EF `send-notification-emails` already uses `recipient_id`.

---

## 3. Migration design

### 3.1 Schema (DDL)

```sql
-- Migration: ADR-0022 W1 — delivery_mode column + digest tracking
-- Depends on: nothing (additive, default 'digest_weekly' coerces existing rows)
-- Rollback:
--   DROP INDEX IF EXISTS idx_notifications_digest_pending;
--   ALTER TABLE public.notifications
--     DROP COLUMN IF EXISTS digest_batch_id,
--     DROP COLUMN IF EXISTS digest_delivered_at,
--     DROP COLUMN IF EXISTS delivery_mode;

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS delivery_mode text NOT NULL
    DEFAULT 'digest_weekly'
    CHECK (delivery_mode IN ('transactional_immediate','digest_weekly','suppress')),
  ADD COLUMN IF NOT EXISTS digest_delivered_at timestamptz,
  ADD COLUMN IF NOT EXISTS digest_batch_id uuid;

-- Partial index for the W2 digest aggregation query
CREATE INDEX IF NOT EXISTS idx_notifications_digest_pending
  ON public.notifications (recipient_id, created_at)
  WHERE delivery_mode = 'digest_weekly' AND digest_delivered_at IS NULL;

-- Backfill catalog (no-op if column default already correct, but explicit
-- so future audits can grep for the mapping)
UPDATE public.notifications SET delivery_mode = 'transactional_immediate'
  WHERE type IN (
    'volunteer_agreement_signed','ip_ratification_gate_pending',
    'system_alert','certificate_ready','member_offboarded'
  );

UPDATE public.notifications SET delivery_mode = 'suppress'
  WHERE type IN ('attendance_detractor','info','system');

-- Conditional types (attendance_reminder, governance_vote_reminder, tribe_broadcast)
-- get the default 'digest_weekly' via column default. Producers will set
-- 'transactional_immediate' on a per-row basis for time-critical instances.

COMMENT ON COLUMN public.notifications.delivery_mode IS
  'ADR-0022: transactional_immediate | digest_weekly | suppress. Default digest_weekly. Producers set explicitly when row should bypass digest (urgent/transactional).';
COMMENT ON COLUMN public.notifications.digest_delivered_at IS
  'ADR-0022: when the row was sent as part of a weekly digest batch. NULL = not yet delivered (or non-digest mode).';
COMMENT ON COLUMN public.notifications.digest_batch_id IS
  'ADR-0022: groups rows that were delivered in the same digest send (one batch per recipient per send).';
```

**Rationale on `NOT NULL DEFAULT 'digest_weekly'`**: 1733 attendance_reminder rows + 2349 total — coercing all to safe default avoids a long backfill lock. Producers updating to `transactional_immediate` is a per-row UPDATE, not a schema-level concern.

**Rationale on partial index**: only ~10-30 digest-pending rows per recipient at any time. Full index would scan 2349 rows + grow unbounded as historical rows accumulate. Partial index keeps the hot path tight.

### 3.2 Conditional rules — producers

Three types need per-row decisions (cannot be classified by `type` alone):

#### `attendance_reminder`

```sql
-- In notify_attendance_reminders() trigger / EF:
INSERT INTO notifications (..., delivery_mode)
VALUES (..., CASE
  WHEN event.starts_at <= now() + INTERVAL '48 hours' THEN 'transactional_immediate'
  ELSE 'digest_weekly'
END);
```

Effect: reminders for events in next 48h ship immediately; reminders for next week's events bundle into Saturday digest.

#### `governance_vote_reminder`

```sql
-- In create_governance_vote_reminder():
INSERT INTO notifications (..., delivery_mode)
VALUES (..., CASE
  WHEN voting.deadline <= now() + INTERVAL '7 days' THEN 'transactional_immediate'
  ELSE 'digest_weekly'
END);
```

#### `tribe_broadcast`

Two implementation paths — **dev decides**:

**Option A (caller-controlled, simpler)**: leader passes `urgent: bool` flag.

```sql
-- send_notification_to_tribe(p_tribe_id, p_title, p_body, p_urgent boolean DEFAULT false)
INSERT INTO notifications (..., delivery_mode)
VALUES (..., CASE WHEN p_urgent THEN 'transactional_immediate' ELSE 'digest_weekly' END);
```

**Option B (rate-limited, ADR-0022 §Riscos)**: enforce 1 urgent broadcast per leader per ISO week.

```sql
IF p_urgent THEN
  IF (SELECT count(*) FROM notifications
      WHERE source_type = 'tribe_broadcast'
        AND actor_id = v_actor
        AND created_at >= date_trunc('week', now())
        AND delivery_mode = 'transactional_immediate') > 0 THEN
    RAISE EXCEPTION 'Urgent broadcast rate limit (1/week). Use non-urgent or wait.';
  END IF;
END IF;
```

**Recommendation**: Option A in W1 (simpler, ship it). Option B as W3 hardening. Document urgent quota in the leader UI tooltip.

---

## 4. Producer touch-points (audit)

Every place in code/SQL that does `INSERT INTO public.notifications` needs to either:
1. Explicitly set `delivery_mode` (recommended for clarity), OR
2. Rely on the default `'digest_weekly'` (acceptable for most digest-mode types).

Audit results (grep `INSERT INTO public.notifications` across migrations + functions):

| Producer | File / Function | Recommended setting |
|---|---|---|
| `notify_offboard_cascade` | migration 20260509040000 | `'transactional_immediate'` (offboard notice) |
| `attendance_reminder` cron | EF `send-attendance-reminders` | conditional (see §3.2) |
| `attendance_detractor` cron | EF `attendance-detractor` | `'suppress'` (already in-app only via existing send-skip) |
| `card_assigned` / `card_status_changed` | trigger `trg_notify_card_assignee` (or similar) | default `'digest_weekly'` |
| `volunteer_agreement_signed` | `sign_volunteer_agreement` RPC | `'transactional_immediate'` |
| `ip_ratification_gate_pending` | `_enqueue_ip_ratification_email` helper | `'transactional_immediate'` |
| `certificate_ready` / `certificate_issued` | `_emit_certificate_notification` | `ready` → immediate, `issued` → digest |
| `tribe_broadcast` | `send_notification_to_tribe` RPC | conditional (see §3.2) |
| `webinar_status_confirmed` | `link_webinar_event` flow | `'digest_weekly'` |
| `publication` | publication submission flow | `'digest_weekly'` |
| `system_alert` / `system` / `info` | various | per catalog (system_alert → immediate, system/info → suppress) |

**Dev team decision**: do we update all producers in W1 (single big PR), or rely on the column default and update producers opportunistically in W2/W3?

**Recommendation**: minimal update in W1 — only the 4-5 producers where `transactional_immediate` is mandatory (offboard, agreement, ratification, system_alert, certificate_ready). Everything else stays on default. Reduces W1 scope.

---

## 5. Edge Function changes

### 5.1 Current state

Single EF `send-notification-emails`:
- Cron every ~5 min.
- Query: `SELECT * FROM notifications WHERE email_sent_at IS NULL ORDER BY created_at LIMIT N`.
- For each row: render template by `type`, send via Resend, mark `email_sent_at = now()`.

### 5.2 Proposed: 2 EFs vs 1 EF with mode dispatch

#### Option A — Split into 2 EFs (recommended)

- `send-transactional-emails` — runs every 5 min.
  ```
  WHERE delivery_mode = 'transactional_immediate'
    AND email_sent_at IS NULL
  ```
- `send-weekly-member-digest` — runs Saturday 12:00 UTC.
  ```
  WHERE delivery_mode = 'digest_weekly'
    AND digest_delivered_at IS NULL
    AND created_at < <last_saturday_12h_utc>
  ```
  Aggregates per `recipient_id`, calls `get_weekly_member_digest(p_member_id)` (W2 RPC), sends 1 consolidated email per recipient, sets `digest_delivered_at = now(), digest_batch_id = <new uuid>` for all rows in the batch.
- `suppress` rows: never picked by either EF; in-app only.

**Pros**: clean separation of concerns, independent failure domains, different schedules natural.
**Cons**: 2 EFs to maintain, requires renaming current EF.

#### Option B — Single EF with mode dispatch

- Keep `send-notification-emails` cron 5 min.
- Branch by `delivery_mode`: `transactional_immediate` → send-now; `digest_weekly` → only process when `now() ≥ next saturday 12:00 UTC` AND aggregate per recipient.
- `suppress` → set `email_sent_at = now()` immediately to mark "intentionally not sent".

**Pros**: single EF.
**Cons**: scheduling 2 different cadences in 1 cron is awkward. Saturday job interferes with 5-min cadence (skip if not Saturday hour, makes 5 min checks idle 99% of time). Logic harder to test.

**Recommendation**: **Option A**. Operational cost (2 cron entries instead of 1) is trivial vs the cleanliness gain.

### 5.3 EF deploy plan

1. Rename current `send-notification-emails` → `send-transactional-emails`.
2. Create `send-weekly-member-digest` (stub for W1: just iterates digest_pending rows, sends a placeholder email "Your weekly digest is ready" — full content comes in W2).
3. Update cron entries:
   - Old: `send-notification-emails` every 5 min → DROP.
   - New: `send-transactional-emails` every 5 min.
   - New: `send-weekly-member-digest` Saturday 12:00 UTC.

The placeholder digest in W1 lets us validate the routing without committing to W2 content yet. Members would receive a `[TEST] Núcleo IA — your weekly digest will be ready next week` email until W2 ships.

---

## 6. Contract test

Add `tests/contracts/adr-0022-delivery-mode.test.mjs`:

```js
// ADR-0022 contract: every notification type that appears in migrations 2026-04-25+
// must have a documented delivery_mode (either via column default or explicit set).

import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
// ...

const KNOWN_TYPES = JSON.parse(fs.readFileSync('docs/adr/ADR-0022-notification-types-catalog.json', 'utf8'));

test('all notification types are declared in ADR-0022 catalog', () => {
  // Scan migrations from CUTOVER (20260512+) for INSERT INTO notifications
  // and extract type values. Each must be in KNOWN_TYPES.
  // ...
});

test('delivery_mode column has CHECK constraint', () => {
  // Read the migration file, verify CHECK clause matches expected enum.
});
```

The ADR ships with a JSON catalog file (`docs/adr/ADR-0022-notification-types-catalog.json`) — a single source of truth that tests, EFs, and audit reports can reference.

---

## 7. Backwards compatibility

- **Existing rows (2349)** — auto-coerced to default `'digest_weekly'` on `ADD COLUMN`. Producers can update specific rows post-migration if needed.
- **Existing producers** — continue working unchanged because column has default. They just won't set `delivery_mode` explicitly until refactored.
- **Existing EF `send-notification-emails`** — keeps working until renamed in §5.3. Plan: rename in same deploy as new digest EF.
- **Test fixtures** — none reference `delivery_mode`; no test breakage expected.

---

## 8. Rollback

If something breaks post-deploy:

```sql
-- Drop the column entirely (nuclear)
ALTER TABLE public.notifications
  DROP COLUMN IF EXISTS delivery_mode,
  DROP COLUMN IF EXISTS digest_delivered_at,
  DROP COLUMN IF EXISTS digest_batch_id;
DROP INDEX IF EXISTS idx_notifications_digest_pending;
```

EF rollback: redeploy previous `send-notification-emails` from git tag pre-W1.
Cron rollback: re-add original cron entry, drop the 2 new ones.

Loss: any digest_delivered_at timestamp set during the W1 window. Acceptable — recipients would just receive a fresh batch in next non-rolled-back digest.

---

## 9. Open questions for PM / dev team

1. **Opt-out modes**: ADR-0022 §Pendências — is `digest_weekly` the only default, or do we ship 4 modes (`immediate_all` / `weekly_digest` / `suppress_all` / `custom_per_type`)? Affects W2 settings UI scope.
2. **EF split (§5.2)**: dev team confirms Option A?
3. **Column name `delivery_mode`** — final, or prefer alternate (e.g., `dispatch_mode`, `routing_class`)?
4. **Stakeholder review**: any of Roberto / Ivan / Fabricio / Sarah notification types we missed? Specifically: review-gate-pending, mentor-pairing, anything in curation backlog?
5. **CR-051**: ADR-0022 + W1 spec packaged as formal CR for ratification, or keeps as Proposed until dev review concludes?
6. **Producer audit cutoff**: update only mandatory-immediate producers in W1 (5 producers — recommended) vs all 12 producers (single big PR)?
7. **Legacy `attendance_reminder` 1733 rows**: backfill specific delivery_mode (case-by-case based on event timestamp) or accept default `digest_weekly` for everything? Affects: ~50 rows are for events still upcoming and may need immediate routing.
8. **Auth-gate on `tribe_broadcast` urgent** (§3.2 Option B): rate-limit in W1 or W3?

---

## 10. Estimate breakdown

| Task | Hours |
|---|---:|
| Migration DDL + backfill | 1 |
| Producer update (5 mandatory immediate) | 3 |
| EF rename + new digest EF stub | 4 |
| Cron entries update (3 changes) | 0.5 |
| Contract test + catalog JSON | 2 |
| Smoke + manual QA across 16 types | 4 |
| Docs sync (ADR Status flip Proposed → Accepted, CLAUDE.md, this spec) | 1 |
| **Total** | **~15.5h** (~2 dev days) |

---

## 11. Acceptance criteria

- [ ] Migration applied; `delivery_mode` column present with CHECK + default + index
- [ ] 2349 existing rows have non-NULL `delivery_mode` (auto-coerced + 5 mandatory-immediate types backfilled)
- [ ] EF `send-transactional-emails` deployed + cron 5 min active
- [ ] EF `send-weekly-member-digest` deployed + cron Saturday 12:00 UTC active (placeholder content for W1)
- [ ] Contract test `adr-0022-delivery-mode.test.mjs` passes
- [ ] ADR-0022 status flipped Proposed → Accepted (after dev review sign-off)
- [ ] No regression: existing transactional flows (volunteer_agreement, ip_ratification, system_alert) still send within 5 min
- [ ] Smoke: send-weekly-member-digest fires correctly on test Saturday (or via manual trigger)

---

## 12. References

- [ADR-0022](../adr/ADR-0022-communication-batching-weekly-digest-default.md) — parent decision
- [SPEC_WEEKLY_MEMBER_DIGEST](./SPEC_WEEKLY_MEMBER_DIGEST.md) — W2 content scope
- [SPEC_ENGAGEMENT_WELCOME_EMAIL](./SPEC_ENGAGEMENT_WELCOME_EMAIL.md) — W2 first integrator
- Issue #97 (G7), #98, #88, #91 — features that depend on or interact with this substrate
- Issue #82 — `idx_notif_recipient_unread` (198k scans baseline) — partial index reduces overlap

---

**Assisted-By**: Claude (Anthropic)
