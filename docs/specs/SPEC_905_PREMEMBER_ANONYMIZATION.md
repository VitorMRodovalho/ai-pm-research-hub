# SPEC #905 — Pre-member rejected/withdrawn application anonymization (LGPD retention/erasure)

- **Status:** **BUILT + APPLIED, DORMANT** (2026-06-28). Migration `20260805000280` applied to prod; cron registered `active=false`. Go-live (cron activation) is gated on legal-counsel ratifying the retention window — see Go-Live Checklist.
- **Issue:** #905 (surfaced by the #902 sub-gap 2 grounding, PR #904 §8).
- **Branch:** `feat/905-premember-anonymization` (no PR merge without explicit PM "vai" — main auto-deploys).

## Problem

`anonymize_inactive_members` (the 5y LGPD cron) is **member-anchored**: it loops `list_anonymization_candidates` over **member** inactivity and scrubs `selection_applications` PII only `WHERE email = member.email`. Candidates who **never became members** (rejected/withdrawn pre-members) are never reached — their PII (name/email/phone/linkedin/resume/motivation + AI dossier + interview notes + video/voice transcription + PMI membership snapshots) is retained **indefinitely**. Latent LGPD minimization gap (Art. 6 III / Art. 16). Not a breach (RLS denies anon; no exposure), but no scheduled erasure path.

## Grounded state (live, 2026-06-28)

| metric | value |
|---|---|
| terminal rows (`status IN ('rejected','withdrawn')`) | 46 (rejected 45 + withdrawn 1) |
| terminal **without a member** by email | 35 |
| **candidate pool** (no member, excluding the #935 VEP cohort) | **29** |
| excluded — VEP-expired + cutoff-approved (→ #935 re-apply track) | 6 |
| excluded — email matches a member | 11 |
| **eligible TODAY** under 5y / 2y / 1y window | **0 / 0 / 0** (all anchors 2026-03-19 → 2026-06-28) |

Zero rows are eligible under any reasonable window → the build is **risk-free**; the cron is dormant until legal sets the window (no row would be touched anyway).

## Design (migration `20260805000280`)

1. **`selection_applications.anonymized_at timestamptz`** — erasure marker (member-anchored path does not set it).
2. **`list_premember_anonymization_candidates(p_years, p_years_withdrawn)`** — SECDEF, privacy-minimal output (ids/dates/booleans only, **no PII**). Predicate: `anonymized_at IS NULL` ∧ terminal status ∧ no-member (primary `members.email` + `member_emails` table + `members.secondary_emails` array, all `trim(lower())`) ∧ **not** the #935 VEP cohort ∧ retention window elapsed. Anchor = `COALESCE(cycle_decision_date, created_at)`.
3. **`anonymize_premember_applications(p_dry_run, p_years, p_years_withdrawn, p_limit)`** — SECDEF, dry-run default, per-application loop with `EXCEPTION` isolation. Erasure policy:
   - **DELETE** pure candidate-derived children: `pmi_video_screenings` (voice/video transcription + Drive/YouTube links = biometric-adjacent), `ai_analysis_runs`, `ai_processing_log`, `ai_score_validations`, `selection_evaluation_ai_suggestions`, `selection_membership_snapshots`, `selection_application_service_history`, `selection_topic_views`, `selection_dispatch_url_log`, `onboarding_progress`.
   - **SCRUB free-text, KEEP structured scores**: `selection_evaluations` (notes/criterion_notes), `selection_interviews` (notes/theme/calendar_event_id), `gate_attempts` (payload/reason), `selection_evaluation_anomalies` (payload).
   - **Mother row**: scrub all direct identifiers + free-text + AI (incl. triage + scraped LinkedIn) + external VEP ids + voice evidence. KEEP scores/ranks/pert/cohort_n + demographic bands + coarse geo + cycle_id + status + tags (categorical) + referral_source/referrer_member_id + consent ledger fields. Delete the résumé binary from storage. Audit to `admin_audit_log` (ids/anchors/counts only, **no PII**).
4. **Grants**: service_role only (REVOKE anon/authenticated/PUBLIC) — mirrors `anonymize_inactive_members`.
5. **Cron** `lgpd-anonymize-premember-monthly` (`15 4 1 * *`) registered **dormant** (`active=false`).
6. **`get_lgpd_cron_health`** extended: `pending_premember_anonymization` counter + `premember_anonymization` block (registered/active/pending) + dormant-aware health (behavior-neutral vs the original 3-job logic while dormant).

## Council review (2026-06-28) — incorporated

Parallel review by legal-counsel + security-engineer + data-architect. All "apply-safe, gate activation" verdicts. Findings folded in **before** apply:

- **BLOCKER (data-architect):** `selection_dispatch_url_log.resolved_url` is `NOT NULL` → `SET NULL` would fail at runtime. **Moved to DELETE.**
- **Erasure completeness (security):** added `linkedin_relevant_posts`, `ai_pm_focus_tags`, `chapter_affiliation`, `conversion_reason`, `interview_reschedule_reason`, `ai_triage_score/confidence/at/model` to the mother-row scrub (all are purged by the consent-revocation trigger — parity restored); added `onboarding_progress` DELETE (withdrawn-mid-onboarding edge).
- **Candidate-set (data-architect):** dropped `updated_at` from the anchor (the `pmi-vep-sync` worker bumps it on rejected rows → would silently extend the window); added `trim()`; extended the no-member guard to `member_emails` + `members.secondary_emails`.
- **`tags`:** verified the only value in the pool is `convert_to_researcher` (categorical) → **kept**, avoiding over-scrub.

## Residual classification (legal)

After scrubbing identifiers + free-text, the row retains scores + demographic bands (gender/age_band/industry/sector/seniority) + coarse geo + cycle_id. In a small cohort this may be **k=1** → it is **PSEUDONYMIZED** (restricted to service_role), **not anonymized** under Art. 5 III. Acceptable for cohort/equity analytics under Art. 16 III, **but** classify it as pseudonymized in the RoPA and obtain legal sign-off on k-anonymity before activating the cron.

## GO-LIVE CHECKLIST (cron activation — legal parecer R1–R5)

- [ ] **R1** Ratify retention windows. Legal recommendation: **rejected 2y / withdrawn 1y**. Set them on the cron command (`p_years`, `p_years_withdrawn`). The function already supports the bifurcation.
- [ ] **R2** Time-bound the #935 exclusion to the active cycle (+grace) so those 6 don't stay excluded forever once cycle5 closes without re-application.
- [ ] **R3** Map + purge the **external video binaries** (Google Drive / YouTube referenced by `pmi_video_screenings`) — not reachable from SQL; needs an EF or manual runbook. Capture the links during a dry-run before erasure.
- [ ] **R4** Confirm the **legal basis (Art. 11 I)** for voice/video collection on the candidacy form (biometric = sensitive; legitimate-interest is not available). Independent of #905 but flagged.
- [ ] **R5** RoPA entries (pre-member selection activity + pseudonymized residual + external-binary purge) + record the dormant cron with a **max activation deadline** (legal suggestion: 2026-09-30) so the gap is "governance-in-progress," not "indefinite."
- [ ] Activate: set windows on the cron command + `SELECT cron.alter_job(<jobid>, active := true)`.

## Follow-ups (separate issues)

- **Cross-cutting child-table PII gap** (affects the **member** path too): `ai_calibration_runs.sample_payload` retains `applicant_name` for historical runs; the member-anchored `anonymize_inactive_members` also leaves `pmi_video_screenings` / `ai_analysis_runs` / evaluation notes un-erased. Unify the two erasure paths around a shared helper.
- **Invariant-905** in `check_schema_invariants()`: 0 rows where terminal + pre-member + past-window + `anonymized_at IS NULL` — only meaningful once the cron is active (defer to go-live).

## Validation (live, post-apply)

- Dry-run `p_years=0` → `processed = 29` (candidate-set correct, #935 + no-member guards work). `p_years=5/1` → 0 (no row past window).
- Cron jobid 71, `active=false`, `15 4 1 * *`.
- Grants: `authenticated`=no EXECUTE, `service_role`=EXECUTE.
- Bookkeeping: tracking row `20260805000280` (has_body), phantom `20260628201554` reverted. Contract tests `rpc-migration-coverage` (22/22), `security-lgpd` + `schema-invariants` (80/80) green. `npx astro build` clean.
