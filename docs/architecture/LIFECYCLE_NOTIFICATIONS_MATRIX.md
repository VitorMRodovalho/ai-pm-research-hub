# Lifecycle Notifications Matrix

**Status:** Proposed
**Author:** p205 / Issue #182
**Origin:** P202 Volunteer Lifecycle Remediation Spec §4 — "matriz de notificações/renovações/pending-authority"
**Scope:** descriptive (current state) + prescriptive (gap fixes). Implementation deferred to follow-up issues.

---

## 1. Why this exists

P202 audit (2026-05-19) found that "lifecycle communication failures surface as permission bugs because members do not receive the right agreement/onboarding next action." Concretely: 16 active engagements need an agreement, 2 cases sat without any detectable notification, and admin has no consolidated view of *why* authority is pending vs. silently missing.

This doc codifies the 9 lifecycle states a volunteer (or other agreement-bearing engagement) traverses, the surfaces that move them between states, and the audit-log + notification-template + idempotency-key expectations at each step. Where the current infrastructure already covers a transition, the row is descriptive. Where coverage is missing or broken, the row is prescriptive — the proposal lands as a separate follow-up issue, not in this doc.

The matrix is the single point of reference for:
- council reviews touching selection, agreement, or offboarding flows
- pre-deploy smoke checks (renewal cron, agreement queue, offboard cascade)
- admin troubleshooting ("Why is X pending? What was sent?")

---

## 2. Lifecycle state graph

```
candidate
  ↓ (approve_selection_application — #179 canonical)
approved_pending_member ──┐
  ↓                       │  (transient inside canonical RPC;
approved_pending_person   │   invariants R + S verify post-commit state)
  ↓                       │
agreement_pending ────────┘
  ↓ (sign_volunteer_agreement — #181 hash + IP/UA)
countersign_pending
  ↓ (counter_sign_certificate)
authoritative
  ├─→ renewal_due (end_date − 60d/30d/7d via v4_notify_expiring_engagements cron)
  └─→ offboarded
        ↓ (invite_alumni_to_re_engage)
       reengagement_pending
        ↓ (respond_re_engagement)
       (back to agreement_pending OR candidate)
```

States are gates, not statuses on a single column. A given engagement is in exactly one state at any time, derived from `engagements.status`, `engagements.is_authoritative`, `engagements.end_date`, certificate presence + counter-signature, and offboarding records.

The two transient `*_pending_*` states between `candidate` and `agreement_pending` exist only *inside* the canonical `approve_selection_application` RPC and are not externally observable — invariants R (`approved_application_has_member`) and S (`approved_member_has_person_id`) guarantee no engagement persists in those intermediate forms (issue #180).

---

## 3. Matrix

Each row covers one transition into the named state. `Idempotency key` is the tuple a follow-up call uses to short-circuit duplicate work (matches the existing `NOT EXISTS` guard pattern in `approve_selection_application`, `_enqueue_gate_notifications`, `detect_and_notify_detractors`, etc.).

| # | State | Trigger | Source table | Notification type(s) | Template | Idempotency key | Audit log | Owner (cron / RPC / trigger) | Status |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `candidate` | `selection_applications` INSERT | `selection_applications` | — (intentional: no notif on apply) | — | — | `data_anomaly_log` if validation fails | `capture_visitor_lead` / `promote_lead_to_application` | ✓ OK |
| 2 | `approved_pending_member` | inside `approve_selection_application` RPC | (transient) | n/a (atomic) | n/a | n/a | guaranteed by invariant R | `approve_selection_application` (#179) | ✓ OK post-#179 |
| 3 | `approved_pending_person` | inside `approve_selection_application` RPC | (transient) | n/a (atomic) | n/a | n/a | guaranteed by invariant S | `approve_selection_application` (#179) | ✓ OK post-#179 |
| 4 | `agreement_pending` (post-approval) | `engagements` INSERT with `requires_agreement=true` AND no certificate | `engagements` + `engagement_kinds` | `selection_termo_due` | `pmi_welcome_with_token` (campaign) | `(recipient_id, type, source_id=engagement_id)` | `admin_audit_log(action='selection_approval_canonical')` | `approve_selection_application` (#179) one-shot | ✓ initial notification OK |
| 4b | `agreement_pending` (recurring nudge) | engagement remains in `agreement_pending` for N days | `engagements` ∩ `certificates` (absent) | **`agreement_nudge_dN`** (proposed) | proposed: `agreement_nudge_d3`, `agreement_nudge_d7`, `agreement_nudge_d14_gp` | `(recipient_id, type, source_id=engagement_id, created_at > now()-7d)` | `admin_audit_log(action='agreement_nudge_sent')` | **proposed cron:** `nudge_pending_agreements_daily` @ 09:30 UTC | ✗ **GAP** |
| 5 | `countersign_pending` (admin alert) | `certificates.signed_at` set, `counter_signed_at IS NULL`, > 24h | `certificates` | **`countersign_pending`** (proposed) | proposed: `countersign_pending_alert` | `(recipient_id, type, source_id=certificate_id, created_at > now()-3d)` | `admin_audit_log(action='countersign_pending_alert')` | **proposed cron:** `alert_pending_countersigns_daily` @ 09:00 UTC | ✗ **GAP** |
| 6 | `authoritative` | `counter_sign_certificate` RPC sets `engagement.is_authoritative=true` | `engagements` UPDATE | `engagement_welcome` (existing) + `volunteer_agreement_signed` (existing) | (inline title/body — no template slug) | `(recipient_id, type, source_id=engagement_id)` | `admin_audit_log(action='counter_signed')` + `mcp_usage_log` | `_trg_engagement_welcome_notify` shim → `_enqueue_engagement_welcome(p_engagement_id)` | ⚠️ **PARTIAL** — `_enqueue_engagement_welcome` body lacks the `NOT EXISTS` guard |
| 7 | `renewal_due` D-60 | `engagements.end_date - 60d` | `engagements` | `engagement_renewal_d60_gp_aggregate` (existing) | (inline body, no template slug) | `(recipient_id, type, source_id=engagement_id, created_at > now()-7d)` | aggregate JSON return (per §9 Q5) | `v4_notify_expiring_engagements` daily 08:00 UTC | ✓ OK |
| 7b | `renewal_due` D-30 | `engagements.end_date - 30d` | `engagements` | `engagement_renewal_d30` (existing) | (inline body) | same shape | aggregate JSON return | `v4_notify_expiring_engagements` | ✓ OK |
| 7c | `renewal_due` D-7 URGENT | `engagements.end_date - 7d` | `engagements` | `engagement_renewal_d7_urgent` (existing) | (inline body) | same shape | aggregate JSON return | `v4_notify_expiring_engagements` | ✓ OK |
| 8 | `offboarded` | `offboarding_records` INSERT / `members.status='offboarded'` UPDATE | `offboarding_records`, `members` | `member_offboarded` (existing — migration `20260509040000`, ADR-0022 compliant via `20260513070000`) + `arm9_inactivity_alert` (cron) | (inline title/body — no template slug; recipients are GP/DM/leaders, not the offboarded member) | `(recipient_id, type, source_id=member_id)` | `admin_audit_log(action='offboard')` (exists) | `admin_offboard_member` + `trg_notify_offboard_cascade` trigger | ✓ OK |
| 9 | `reengagement_pending` | `invite_alumni_to_re_engage` RPC called | `re_engagement_pipeline` | (none until accept) | — | — | `admin_audit_log(action='reengagement_invite')` | `invite_alumni_to_re_engage` one-shot | ⚠️ **PARTIAL** — no follow-up nudge if alumnus doesn't respond |
| 9b | `reengagement_pending` (recurring nudge) | `re_engagement_pipeline.invited_at` > 7d / 14d / 30d without `responded_at` | `re_engagement_pipeline` | **`reengagement_nudge_dN`** (proposed) | proposed: 3 templates | `(recipient_id, type, source_id=pipeline_id)` | `admin_audit_log(action='reengagement_nudge_sent')` | **proposed cron:** `nudge_pending_reengagement_weekly` | ✗ **GAP** |
| 9c | `reengagement_accepted` | alumni responds yes (`re_engagement_pipeline.responded_at` set) | `re_engagement_pipeline` UPDATE | `re_engagement_accepted` (existing) | — | `(recipient_id, type, source_id=pipeline_id)` | `admin_audit_log` (exists) | `respond_re_engagement` | ✓ OK |

Totals at p205: **8 OK, 3 PARTIAL, 3 GAP** out of 14 transitions.

---

## 4. Special engagement kinds coverage

P202 audit noted that beyond `kind='volunteer'`, several engagement kinds also need agreements but have inconsistent coverage:

| Engagement kind | requires_agreement | Currently covered by rows above? | Notes |
|---|---|---|---|
| `volunteer` | yes (canonical path) | rows 4, 6, 7, 9 | full coverage post-#179/#181/#177 |
| `study_group_owner` | yes (e.g. Herlon) | rows 4 + 6 partial | Herlon is in `get_pending_agreement_engagements` queue (#177); historical 2026-04-13/14 batch admin_attestation only covered `kind='volunteer'` |
| `study_group_participant` | yes (1 case) | row 4 | same as above |
| `ambassador` | yes (~12 cases) | row 4 + Issue #160 deferred | PM team review pending; matrix row 4 covers nudge once decided |
| `chapter_board` | yes (~9 cases) | row 4 + Issue #160 deferred | same |
| `observer` | yes (~5 cases) | row 4 + Issue #160 deferred | same |
| `sponsor` | yes (~5 cases) | row 4 + Issue #160 deferred | same |

**Decision needed (carry from #160):** are the ~60 historical engagements of "special kinds" without certificate considered authoritative-by-attestation OR pending-agreement? Matrix treats them as pending until #160 closes. That means cron 4b (when implemented) would nudge all of them — PM must approve before flipping the cron on, to avoid notification storm.

---

## 5. Gap analysis (3 gaps + 2 partials)

### Gap 1 — agreement_pending recurring nudge (row 4b)

**Problem.** `approve_selection_application` fires `selection_termo_due` once at approval. If the volunteer doesn't sign within N days, nothing prompts them. P202 evidence: 2 historical engagements sat as `agreement_pending` without any detectable notification (this is the symptom that #177 surfaced via the queue).

**Proposed shape.**
- New notification types: `agreement_nudge_d3` (volunteer), `agreement_nudge_d7` (volunteer + GP cc), `agreement_nudge_d14_gp` (GP only, escalation).
- New cron: `nudge_pending_agreements_daily` @ 09:30 UTC. Reads same surface as `get_pending_agreement_engagements()` (#177), filters by elapsed days, inserts notifications with the same `NOT EXISTS` 7-day guard pattern as `v4_notify_expiring_engagements`.
- Templates land in `campaign_templates` (category=`onboarding` since they map to onboarding completion gating).

**PREREQ (hard).** Cron MUST launch with a `p_dry_run` parameter defaulting to `true`. Until #160 (special-kinds historical attestation) is resolved, scanning the pending-agreement set would surface ~16+60 candidates and notifying all in one run is a notification-storm risk (see §9 Q2). The first scheduled run must be dry-run with output to `admin_audit_log` for PM review before flipping `p_dry_run=false`.

**Effort estimate.** ~3-4h: 1 migration (3 new notification types accepted by `_delivery_mode_for`), 1 cron function (with dry_run param), 3 campaign_templates rows, 2-3 contract tests.

### Gap 2 — countersign_pending admin alert (row 5)

**Problem.** Counter-signature is the gate between `signed` and `authoritative` (capability turns on at `is_authoritative=true`). If admin (typically GP or chapter director) doesn't counter-sign within ~24h, the volunteer signed-but-can-do-nothing. There's no surface that flags this; only manual queue inspection on `/admin/certificates`. The Herlon case at p195 (counter-sign carry from p195-p199 sediment) is the canonical example — 4+ sessions of "PM-pending operational" item.

**Proposed shape.**
- New notification type: `countersign_pending_alert`.
- New cron: `alert_pending_countersigns_daily` @ 09:00 UTC (before the agreement nudge cron, so countersigns clear first). Reads `certificates WHERE signed_at IS NOT NULL AND counter_signed_at IS NULL AND signed_at < now() - interval '24 hours'`. Notifies GP + (when present) `voluntariado_director` designation.
- Template `countersign_pending_alert` in `campaign_templates` category=`operational`.

**Effort estimate.** ~2h: 1 migration, 1 cron, 1 template, 1-2 contract tests.

### Gap 3 — reengagement_pending nudge (row 9b)

**Problem.** `invite_alumni_to_re_engage` sends 1 invitation. If alumnus doesn't respond, the invitation sits forever. Only `re_engagement_accepted` notification exists (fires on acceptance, not on inaction).

**Proposed shape.**
- New notification types: `reengagement_nudge_d7`, `reengagement_nudge_d14`, `reengagement_nudge_d30_close` (the d30 also marks invitation as `expired` to keep the queue clean).
- New cron: `nudge_pending_reengagement_weekly` Monday 11:00 UTC.

**Effort estimate.** ~3h: 1 migration, 1 cron with auto-expire logic, 3 templates, 2-3 tests.

### Partial 1 — engagement_welcome helper lacks idempotency (row 6)

**Problem.** The trigger `_trg_engagement_welcome_notify` is a thin shim that calls `PERFORM public._enqueue_engagement_welcome(NEW.id)`. The actual `INSERT INTO notifications` lives in `_enqueue_engagement_welcome(p_engagement_id uuid)` (latest body captured in migration `20260686000000_p178_phase_b_drift_capture_1_touch_q_z_underscore_63fns.sql` lines 233-244). That helper lacks the `NOT EXISTS` guard, so a counter-sign rolled back and re-applied would duplicate the welcome notification. Today's volume (4 notifications) makes this hypothetical, but post-#180 invariant S enforcement makes counter-sign retries plausible.

**Proposed minimal shape.** Inside `_enqueue_engagement_welcome`, after resolving `v_member_id` (or the equivalent recipient variable), wrap the `INSERT INTO notifications` with:

```sql
INSERT INTO notifications (recipient_id, type, source_type, source_id, title, body, delivery_mode)
SELECT v_member_id, 'engagement_welcome', 'engagement', p_engagement_id, ...
WHERE NOT EXISTS (
  SELECT 1 FROM notifications
  WHERE recipient_id = v_member_id
    AND type = 'engagement_welcome'
    AND source_id = p_engagement_id
);
```

Effort: ~30min for migration + 1 contract test. Fix lands in the helper, not the trigger shim — `NEW.person_id` / `NEW.id` are trigger-only variables and would not compile inside the helper.

---

## 6. Idempotency design pattern

All notification-creating surfaces in this matrix **must** use the same dedup pattern that `approve_selection_application` adopted post-#179 council fix:

```sql
INSERT INTO notifications (recipient_id, type, source_type, source_id, title, body, delivery_mode)
SELECT v_recipient_id, 'TYPE_NAME', 'engagement', v_engagement_id, ...
WHERE NOT EXISTS (
  SELECT 1 FROM notifications
  WHERE recipient_id = v_recipient_id
    AND type = 'TYPE_NAME'
    AND source_id = v_engagement_id
    AND created_at > now() - interval '7 days'  -- or '3 days' for urgent
);
```

The 7-day window is the default established by `v4_notify_expiring_engagements` (rows 7, 7b, 7c). Urgent classes (D-7) use a 3-day window. One-shot transitions (rows 6, 9c) drop the time window entirely — `(recipient_id, type, source_id)` alone is the key.

**Forward-defense convention (aspirational until mechanized — see GAP-182.B).** Any new notification creation point must include the guard. A grep-based linter check that would catch violations:

```bash
grep -rn 'INSERT INTO notifications' supabase/migrations/ | grep -v 'NOT EXISTS' | grep -v '^-' | grep -v '\\-\\-'
```

Until this grep is wired into `npm test` or a CI step, the convention is enforced only by manual code review (sediment from #198 council fix HIGH). Backlog item `GAP-182.B` tracks the mechanization.

---

## 7. Audit log expectations

Every transition row must produce at least one of:
- `admin_audit_log` row (preferred when the transition was admin-initiated)
- `data_anomaly_log` row (when an automation detected an anomaly)
- `mcp_usage_log` row (when an MCP tool drove the transition)

The matrix marks rows 7/7b/7c as ✓ OK because `v4_notify_expiring_engagements` returns a JSON summary (`notifications_d60/d30/d7/total_sent/run_at`) which is the agreed audit-log shape per §9 Q5 (aggregate-per-run, not per-engagement). New cron functions in Gaps 1/2/3 MUST follow the same shape: JSON return + 1 `admin_audit_log` row per cron run (not per engagement). Per-engagement provenance, if ever needed, is reconstructable from the `notifications` table itself filtered by `type` + `source_id` + `created_at`.

---

## 8. Why-pending visibility surface (Issue #182 acceptance criterion)

> "Admin can see why authority is pending and what communication was sent."

Current coverage:

- **Why pending**: `get_pending_agreement_engagements()` (#177) surfaces the queue. Adequate for `agreement_pending` state. Does NOT cover `countersign_pending` (Gap 2) — a separate small RPC `get_pending_countersigns()` is recommended (~30min, mirrors #177 shape).
- **What was sent**: today, `/admin/members/[id]` shows member notifications via the notifications panel, filterable by type. Adequate for retrospective audit. NOT adequate for "snapshot view at queue level" — admin must click into each member separately.

**Proposed minimal surface delta.** Extend `get_pending_agreement_engagements()` response to include `last_notification_at` + `last_notification_type` per engagement (LEFT JOIN to `notifications` filtered by `source_id`). Same for the proposed `get_pending_countersigns()`. This puts both "why pending" and "what was sent" in the same payload that the admin queue already consumes.

Effort: ~1h. Lands as a sibling RPC delta in the Gap 2 follow-up issue (so #177 contract stays stable).

---

## 9. Open questions for PM

Pre-resolved decisions (stated for transparency; PM may revise but no input needed to proceed):

- **Cron frequency.** Daily nudges (Gaps 1, 2); weekly for reengagement (Gap 3). Daily for agreement + countersign because the cost of a missed notification is a stuck member; weekly for reengagement because alumni response cadence is naturally slower.
- **Day-0 storm protection.** Cron 4b filters `WHERE start_date < now() - interval '24 hours'` so day-0 is reserved for the canonical RPC's `selection_termo_due`.
- **Audit log shape.** Aggregate-per-run JSON return + 1 `admin_audit_log` row per cron invocation (matches `v4_notify_expiring_engagements` pattern; see §7).

Genuinely open for PM:

1. **Retroactive scope for special engagement kinds (#160).** When PM decides on Herlon-class historical attestation, does the new nudge cron apply retroactively? If yes, the first non-dry-run cron run would fire for ~16+60 cases — notification storm. Mitigation already in §5 Gap 1 PREREQ: cron ships with `p_dry_run=true` default; PM signs off before flipping. PM still needs to answer: should the dry-run window be 1 run, 1 week, or until #160 closes?
2. **Owner of countersign_pending alert.** GP only? Or also `voluntariado_director` designation? Affects template recipient list. Proposed (matches existing `v4_notify_expiring_engagements` D-7 pattern that cc's Lorena): both.

---

## 10. Implementation sequencing (follow-up issues)

The matrix is the contract; implementation lands in separate issues so each can ship + QA independently. All 3 cron-based gaps can ship in parallel — they share a stylistic pattern (NOT EXISTS dedup + JSON aggregate return + dry-run param) but no technical dependency (distinct `cron.schedule()` job names, distinct notification types, distinct source tables).

1. **Issue (proposed): `lifecycle: implement agreement-pending nudge cron (row 4b)`** — Gap 1 — ~3-4h. Recommended to ship first only as a style template for the others; not a blocker.
2. **Issue (proposed): `lifecycle: implement countersign-pending admin alert (row 5)`** — Gap 2 — ~2h. Independent.
3. **Issue (proposed): `lifecycle: implement reengagement nudge + auto-expire (row 9b)`** — Gap 3 — ~3h. Independent.
4. **Issue (proposed, minor): `lifecycle: add NOT EXISTS guard to _enqueue_engagement_welcome (row 6 / Partial 1)`** — ~30min. Independent. (Row 8 PARTIAL removed at council review — `member_offboarded` type already exists.)

Total estimated effort: ~8.5-9.5h across 4 issues. None require new tables, schema invariants, or MCP tool additions — pure cron + notification type + template work.

---

## 11. Drift watch

**Owner:** `platform-guardian` (smoke check at session boot when any work touches notifications, certs, engagements, or selection RPCs). **Cadence:** quarterly minimum even when no relevant work happens (tracked as `WATCH-182.A` in the backlog log).

Regenerate the §3 matrix from production state via these queries:

```sql
-- 1. Distinct notification types in use
SELECT type, count(*), min(created_at)::date, max(created_at)::date
FROM notifications WHERE created_at > now() - interval '180 days'
GROUP BY type ORDER BY type;

-- 2. Cron jobs touching lifecycle
SELECT jobname, schedule, command FROM cron.job
WHERE command ~* '(notif|renewal|reengage|campaign|agreement|offboard|inactive|digest)';

-- 3. RPCs/triggers that create notifications
SELECT proname FROM pg_proc
WHERE pronamespace='public'::regnamespace AND prosrc ILIKE '%create_notification%';

-- 4. Templates by category
SELECT category, count(*) FROM campaign_templates GROUP BY category;
```

If the queries return rows not represented in §3, this doc is stale — update the matrix in the same PR that introduces the drift, OR open a `WATCH-182.X` backlog item with the diff.

---

## 12. References

- P202 spec: `docs/project-governance/P202_VOLUNTEER_LIFECYCLE_REMEDIATION_SPEC.md` §4
- P202 audit: `docs/audit/P202_VOLUNTEER_LIFECYCLE_SQL_AUDIT.md`
- Issue #179: canonical approval orchestration (PR #198, in QA window at p205 close)
- Issue #180: V4 graph invariants R + S (PR #199, in QA window at p205 close)
- Issue #177: pending agreement visibility queue (PR #197, in QA window)
- Issue #181: certificate hash + IP/UA persistence (PR #184, in QA window)
- Issue #160: special-kinds historical attestation decision (deferred PM team review)
- ADR-0011: V4 authority gate (`can_by_member`)
- ADR-0093: canonical RPC as facade pattern (lives on PR #198 branch only — pending merge; once #198 lands on main this reference becomes resolvable)
