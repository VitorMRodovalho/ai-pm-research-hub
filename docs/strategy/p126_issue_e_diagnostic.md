# Issue E Diagnostic — Live Data Reveals Issue B Symptom, Not Separate

**Date:** 2026-05-09
**Sessão:** p126
**Status:** Diagnosed; fix DEFERRED to E3 full scope (next session p127+)
**Data source:** Live Supabase query 2026-05-09

## Original handoff p125 framing (PARTIALLY WRONG)

> Issue E: 10 interview_status≠none com 0 score (legacy bypass?)

The handoff implied:
- 10 rows existed
- score = 0 (not NULL)
- "legacy" — historical bypass from prior cycles

## Live data reveals different reality

Query: `SELECT id, applicant_name, status, interview_status, objective_score_avg, cycle_id FROM selection_applications WHERE interview_status != 'none' AND (objective_score_avg = 1 OR objective_score_avg IS NULL) ORDER BY cycle_decision_date DESC NULLS FIRST LIMIT 20;`

**Findings:**
- **10 rows in CURRENT Cycle 3 batch 2** (`cycle_id = d28313d4-569a-4c58-9eae-7e84c5da29b1`, `cycle_code = 'cycle3-2026-b2'`)
- **Score is NULL, not 0** — handoff inferred wrong
- Status: `'submitted'` — NOT advanced through proper sequence
- Interview status: `'scheduled'` — booking happened
- Some have `final_score` populated (e.g., 209.00, 212.00, 144.00); others NULL

**Affected candidates (10):**
1. Maria Araújo — final_score=209
2. Marcio Pimenta — final_score=212
3. Flavio Oliveira — final_score=NULL
4. Luciana Carpes Pranke — final_score=144
5. Luíse Quintana — final_score=NULL
6. CRISTIANO NUNES — final_score=114
7. Danilo Nascimento — final_score=115
8. William Junio — final_score=NULL
9. Bruna Lima Zomer — final_score=NULL
10. Bruna Soares — final_score=NULL

## Diagnosis: Issue E is manifestation of Issue B

**Issue B (P1) original framing**: "booking workflow disparado fora dos 3 gates do `schedule_interview`"

**These 10 rows ARE the evidence**:
- Booking happened (`interview_status='scheduled'`) before objective_score_avg was computed (NULL)
- 5/10 also have `final_score` populated despite no objective average (suggests partial scoring path) — points to scoring formula edge case
- Status remained 'submitted' instead of advancing through `screening → objective_eval → objective_cutoff → interview_pending → interview_scheduled`

**Root cause hypothesis (to verify in E3 full scope p127+):**
1. Some candidate hit `/interview-booking/<token>` UI path that issued a token without proper gate check
2. OR `schedule_interview` RPC has a bypass code path (manual trigger by admin? legacy email link?)
3. OR `final_score` was assigned by a non-standard path that didn't update objective_score_avg

## Recommended remediation (DEFERRED — for E3 full scope)

### Step 1 — Audit the booking issuance path
```sql
-- Find when these 10 booking tokens were issued
SELECT 
  sa.id, sa.applicant_name, sa.interview_status,
  ibt.created_at AS token_issued_at,
  ibt.issued_by_member_id, ibt.expires_at
FROM selection_applications sa
LEFT JOIN interview_booking_tokens ibt ON ibt.application_id = sa.id
WHERE sa.id IN (
  'afe6e6ea-a4bd-41a6-ab06-e2b0996a1732',
  '9b3502e6-dd3a-466d-9424-3b30f779f3fc',
  'c9b935c3-96a6-45d9-849e-4f4d22848514',
  '39bfd8cf-d20e-409b-bede-ab5cc5d8a063',
  '4943a94e-655b-4e5d-9ee0-09789a789a8c',
  '3ea1e179-4bc6-4066-baf0-b48a4cd01356',
  'd05ddb44-3dea-4d9e-946e-485215122373',
  '97a6df7d-44e8-4788-8429-c55154e384ed',
  'ca505e71-99db-436e-a8a6-7447acd4d3e8',
  'bdb5037c-0b97-493d-b0a8-06b8b6c9ceec'
);
```

### Step 2 — Check gate_attempts_log
```sql
-- E3 RPC alignment: schedule_interview should fail if 3 gates not met (objective_eval done)
-- Query: are there bypass attempts logged?
SELECT * FROM gate_attempts_log
WHERE rpc_name = 'schedule_interview'
  AND application_id = ANY(ARRAY[
    'afe6e6ea-a4bd-41a6-ab06-e2b0996a1732'::uuid,
    -- ... other 9 IDs
  ])
ORDER BY attempted_at DESC;
```

### Step 3 — PM decision: re-schedule vs let proceed
- These 10 candidates believe they have a confirmed interview slot
- Cancelling now = reputational damage + LGPD Art. 20 challenge vector ("decision rolled back arbitrarily")
- Letting proceed = process integrity gap, but candidates already invested
- **Recommended**: let proceed for these 10; tighten gate going forward; document as Cycle 3 b2 known exception in selection committee notes

### Step 4 — Code fix in `schedule_interview` RPC
Add gate enforcement: `IF v_app.objective_score_avg IS NULL THEN RAISE EXCEPTION 'Cannot schedule before objective evaluation complete'`. Currently missing or has bypass path.

## Why DEFERRED to E3 full scope

p126 reduced scope explicitly excludes Issue B fix per PM Opção C decision. Issue E being symptom of Issue B confirms the deferral is correct — fixing Issue E without fixing Issue B root cause would be cosmetic.

E3 full scope p127+ should:
1. Audit gate_attempts_log to identify exact bypass code path
2. Patch `schedule_interview` RPC to enforce gate
3. PM decision on remediation for these 10 active candidates
4. Cron + Apps Script Calendar webhook + chapter VP coordination (separate scope, governance-heavy)

## Tracking item

**ISS-p126-E**: Issue E manifestation of Issue B; 10 cycle3-2026-b2 candidates have interview_status='scheduled' without objective_score_avg. **Owner**: PM (Vitor) — selection committee notes + Vitor decides remediation. **Deadline**: before any of the 10 are decisioned final (cycle_decision_date currently NULL for all).
