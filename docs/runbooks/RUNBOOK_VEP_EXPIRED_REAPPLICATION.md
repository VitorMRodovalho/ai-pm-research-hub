# Runbook — VEP-expired candidate re-application (#902 sub-gap 2)

**Audience:** GP / coordenação.  **Status:** active.  **Spec:** `docs/specs/SPEC_902_SUBGAP2_VEP_REAPPLICATION.md`.

When an **approved-then-VEP-expired** candidate exists (passed objective screening + got the interview
invitation, but their VEP application/offer expired on the PMI portal and the `pmi-vep-sync` worker flipped
them `→ rejected`), this runbook is the **manual GP path** to bring them back. There is **no auto-approval**
— member-lifecycle decisions are GP-only (ADR-0067 D1, LGPD Art. 18). The prior score is **context for the
GP**, never an inherited approval.

> **Grounded reality (2026-06-26):** the live cohort is **7** (4 OfferNotExtended, 2 Expired, 1 Withdrawn),
> all pre-member. **Only 1 of the 7 ever interviewed** — `cutoff_approved_email_sent_at` means "passed the
> objective gate + was invited to interview", **not** admission. So most re-applicants are *resuming an
> incomplete evaluation*, not collecting a prior verdict.

---

## 1. Bucket rules (ratified PM 2026-06-26) — apply BEFORE contacting anyone

| `vep_status_raw` | Meaning | Action |
|---|---|---|
| `Expired` / `OfferExpired` | Pure deadline lapse (administrative) | **Eligible** for the re-apply invite + GP fast-track context. |
| `OfferNotExtended` | PMI/VEP **actively** chose not to extend | **Case-by-case GP review** first — may encode a PMI-side eligibility judgment. No auto-invite. |
| `Withdrawn` | Candidate **opted out** | **Excluded** — no invite, no carried benefit. A re-application is a brand-new candidacy. |

---

## 2. Identify the cohort (read-only, aggregate)

```sql
SELECT vep_status_raw, status, count(*) AS n,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM selection_evaluations e
         WHERE e.application_id = a.id AND e.evaluation_type='interview')) AS interviewed
FROM selection_applications a
WHERE a.cutoff_approved_email_sent_at IS NOT NULL
  AND a.vep_status_raw IN ('Expired','OfferExpired','OfferNotExtended','Withdrawn')
  AND a.status IN ('rejected','withdrawn')
GROUP BY 1,2 ORDER BY n DESC;
```

For an individual case, pull the GP context (manage_member): `get_application_returning_context(p_application_id)`
and `get_application_score_breakdown(p_application_id)` — these surface prior-cycle participation + the prior
score so the GP can decide with full context.

---

## 3. Manual re-application (when a NEXT cycle exists)

> There is **no automated re-approval RPC in Fase 1** (that is Fase 2, unbuilt). Re-anchoring is the policy:
> the candidate **resumes the pipeline in the new cycle and is re-evaluated against that cycle's own cutoff**.
> The prior score is shown to the GP as context — it does NOT pre-decide admission.

1. **Confirm a fresh, current VEP application exists.** For these pre-member candidates the only valid
   "current PMI membership" signal is a **new VEP application with `vep_status_raw='Active'`** (the stale
   terminal value on the old row is NOT a currency signal; `members.pmi_id_verified` is an import-seeded
   stale cache — do **not** gate on it). A genuine re-application via VEP produces this.
2. **Bring the candidate into the new cycle.** Either they re-apply through VEP (worker ingests a net-new
   row), or a GP moves the source row with `admin_move_application_to_cycle(p_application_id, p_target_cycle_id, p_reason)`
   (manage_platform; target cycle must be `open`; this clears rankings — then run `recalculate_cycle_rankings`).
3. **Resume evaluation in the new cycle.** For the (rare) candidate who already interviewed, the GP has the
   prior interview on record; for the majority who did not, they continue at the interview stage. Score is
   re-anchored against the new cycle's `compute_pert_cutoff`.
4. **GP makes a fresh decision.** The approval is `approve_selection_application` under the GP's own
   `manage_platform` authority (a human click). The prior score informs, it does not bind.
5. **Audit.** The approval writes `data_anomaly_log 'selection_approval_canonical'`. Note in the application /
   audit that this is a VEP-expired re-application of a prior-cycle source.

---

## 4. The re-apply invite email (DORMANT machinery — how to activate)

Fase 1 shipped the comms **dormant** (no cron, RPC defaults to dry-run). Objects:

- Column `selection_applications.vep_expired_reapply_email_sent_at` (single-fire stamp).
- Template `campaign_templates` slug `selection_vep_expired_reapply_invite` (trilingual; conditional copy
  that never promises approval; LGPD Art. 9 + Art. 18 footer). **DRAFT — review/adjust copy before activating.**
- RPC `process_pending_vep_expired_reapply_invites(p_dry_run boolean DEFAULT true, p_reapply_url text DEFAULT NULL)`.
- SLA grace `sla_policies 'reapply_invite_grace'` (default `2 days`).

**Dry-run (safe, lists who WOULD be invited, sends nothing):**

```sql
SELECT public.process_pending_vep_expired_reapply_invites();          -- defaults: dry_run=true
SELECT public.process_pending_vep_expired_reapply_invites(true, NULL); -- explicit dry-run
```

**Activation (only once a next cycle + its application URL exist):**

```sql
-- one-off send (service_role):
SELECT public.process_pending_vep_expired_reapply_invites(false, 'https://nucleoia.vitormr.dev/<next-cycle-apply-url>');

-- OR schedule daily (avoid the 14:00/15:00/16:00 selection-cron cluster):
SELECT cron.schedule('vep-expired-reapply-invite-daily', '0 18 * * *',
  $$ SELECT public.process_pending_vep_expired_reapply_invites(false, 'https://nucleoia.vitormr.dev/<next-cycle-apply-url>') $$);
```

- The filter only targets **Expired/OfferExpired + rejected + cutoff-approved + not-yet-invited**, past the
  grace window. Withdrawn and OfferNotExtended are excluded by construction.
- Single-fire: a candidate is invited at most once (`vep_expired_reapply_email_sent_at`).
- **Do not activate** without a real `reapply_url` — a NULL/empty URL forces dry-run as a safety latch.

---

## 5. What is explicitly NOT in scope (deferred to Fase 2 + ADR)

- **Auto-approve / score-transfer RPC** (`reapprove_from_prior_cycle`) — needs PM ratification of the eligible
  sub-bucket + the re-anchoring rule + a `_compute_pert_cutoff_core` exclusion patch. See spec §4b.
- **Including OfferNotExtended in a fast-track** — needs a documented legal basis (Art. 7, IX + LIA) and an ADR.
- **A membership-currency gate** — vacuously satisfied by a genuine VEP re-application; any future gate must be
  notify/alert only (never auto-block), to preserve member-lifecycle = GP-only.

---

## 6. Cross-refs

- `memory/reference_vep_sync_terminal_flip_and_deadline_902.md` (the silent worker flip mechanics).
- `memory/selection_interview_invite_resend_runbook.md` (cutoff-approval + interview-invite dispatch).
- `docs/specs/SPEC_D7_VEP_OFFER_REMINDER.md` (the structural analog this comms mirrors).
- ADR-0067 (human-in-the-loop for selection decisions) · ADR-0028 (cron-aware comms gate).
