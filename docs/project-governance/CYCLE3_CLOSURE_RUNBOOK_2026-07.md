# Ciclo 3 closure runbook (July 2026)

**Issue:** #1003 (EPIC #1002). **Closure meeting:** Thursday **02/07/2026** (the "event" — members keep access
through it). **Related:** #1004 (access turn 09/07, sibling freeze doc), #1008 (16/07 event — keep closure comms
separate), #1020 (handoff protocol), #1021 (VEP coverage), #1022 (exit-state semantics).

> Grounded live 2026-07-01. Member identities + health/personal context stay OFF this committed doc (public repo,
> LGPD Art. 11); the identified lists live in the operator session.

---

## 1. Sequence (order matters)

1. **02/07 — closure meeting** happens; everyone (incl. departing members) keeps access **through the meeting**.
2. **02/07 after meeting — seal attendance** for the closure event (`seal_event_attendance`) so the cycle's
   attendance is frozen before certificates.
3. **After sealing — issue cycle-completion certificates** (§2).
4. **03/07 — execute the researcher (tribe 7) exit → alumni** (§3). **Scheduled** so it does NOT run on the
   02/07 event day (would strip access mid-event). See §3 for the cron.
5. **C4 turn (≈09/07) — leader (tribe 2) non-renewal → alumni + tribe-2 succession** (§4), executed only once a
   successor is named (#1020).
6. **Comms** (§5) — Núcleo/PMI-GO recognition, separate from the 16/07 event.
7. **Reconciliation** — fold into the #1004 post-turn reconciliation (2026-07-09→11).

---

## 2. Cycle-completion certificates — best practice

**Live finding:** the only certificate types ever issued are `volunteer_agreement` (41), `alumni_recognition`
(4, auto on offboard) and `contribution` (1). **No cycle-completion certificate has ever been issued** — so this
establishes the practice for all future cycles.

- **Issue via the platform** (`issue_certificate` + PMI-GO board counter-sign, ADR-0098/0104) **after** attendance
  is sealed. Certificate reflects `function_role` + cycle period.
- **Scope:** the retained/participating C3 cohort. Departing members get their exit cert instead (alumni get the
  auto `alumni_recognition`).
- ⚠️ **Keep it purely Núcleo/PMI-GO — no PDU language, no "AI Community Day"** (same trap as #1008). A
  cycle-completion cert is participation recognition, not a PMI credential.

---

## 3. Researcher (tribe 7) exit → alumni — SCHEDULED

Per the member's own request (capacity: work + graduate studies) and the PM's reply, this is a **full `alumni`
exit, not `observer`** (the "ouvinte"/observer state was governance-rejected — a non-volunteer is unbound by the
term → LGPD/data/IP exposure; see #1022). Return preserved via re-application.

- **Scheduled:** pg_cron **jobid 75** `offboard-antonio-c3-2026-07-03`, `0 12 3 7 *` = **09:00 BRT, 03/07**.
  Guarded: acts only if the member is still `member_status='active'` and `current_date` ∈ [03/07, 06/07], so a
  future yearly fire is a safe no-op. Runs `admin_offboard_member(..., 'alumni', 'personal_workload', ...)` under
  the PM's auth context (transaction-local `request.jwt.claim.sub`); logs to `admin_audit_log`
  (`action='cron.offboard_executed'`).
- **Auto-effect:** `alumni_recognition` cert auto-emitted (return-preserving reason); designations cleared;
  engagements offboarded; `is_active=false` → RLS cuts platform access.
- **Manual tail (NOT done by the cron / RPC):**
  - **Google Drive** access — enqueue revocation so `revoke-drive-drain-hourly` (jobid 64) drains it, or use the
    drive-offboarding tooling (`DRIVE_OFFBOARDING_CASCADE.md` / `approve_drive_revocation`).
  - **WhatsApp group** removal — external, manual.
- **Cleanup:** after 03/07, `SELECT cron.unschedule('offboard-antonio-c3-2026-07-03');` (cosmetic — guards make it
  inert otherwise).
- **Verify 03/07:** member `member_status='alumni'`; `alumni_recognition` cert present; Drive/WhatsApp revoked.

---

## 4. Leader (tribe 2) non-renewal → alumni + succession

- Confirmed non-renewal at cycle end. Because the member **leads a tribe**, do NOT execute until a **successor is
  named** (PM brings the name next week, after new members onboard) — otherwise the tribe is left headless.
  Tracked by **#1020** (responsibility-handoff protocol with pending-successor state).
- **When successor is named:** `admin_offboard_member(p_member_id => <leader>, p_new_status => 'alumni',
  p_reason_category => 'end_of_cycle', p_reassign_to => <successor member_id>)` (auto `alumni_recognition`;
  `p_reassign_to` moves the leader's open `board_items`). Then promote the successor to the tribe-leader track.
- Until #1020 exists, track card/board/task ownership handoff manually.

---

## 5. Comms — best practice

Make both a recap clip **and** recognition art, but **separate from the 16/07 event** (#1008 name/PDU
sensitivity):
- **YouTube:** edited recording / recut of the 02/07 closure meeting.
- **Instagram/LinkedIn:** recognition carousel (tribes + leaders + cycle numbers) + a short clip.
- **Rule:** 100% Núcleo/PMI-GO recognition of volunteers; no "AI Community Day" tie-in, no PDU claim.

---

## 6. Renewal / continuity double-check (feeds #1021)

The volunteer-cert `period_end` is uniform (mostly 2026-12-19) and **masks** real VEP service-end dates
(`selection_applications.service_latest_end_date`). At close, cross-check active researchers/leaders against the
VEP date, not the cert:
- 2 active researchers have VEP service ending **31/07/2026** but their active engagement isn't VEP-linked →
  renewal decision needed.
- 6 active researchers/leaders (incl. 1 leader) have **no** VEP service-end date → radar blind.
This is a data gap (**#1021**), not a per-person exit; no offboarding is driven by it — it flags who to *ask*
about renewal. Identified list in the operator session.

---

## 7. Attendance / continuation signal (context)

Most C3 absences are **excused**, not unexcused — no disciplinary case. Lowest attendance clusters in **tribe 4
(Cultura & Change)** (a tribe-level engagement conversation, not individual offboards). All operational roles hold
an active engagement (0 orphan access — see #1004 §2.3).
