# Cycle 4 Video Screening Reconciliation — Read-Only Audit (p236)

**Issue:** #254 (program: reconcile Cycle 4 video screenings and complete AI-assisted video review workflow)
**Scope:** Workstream 1 only (read-only audit) — implementation workstreams remain blocked pending PM call on the recommended child split below.
**Filed:** 2026-05-23 (p236, post-#221/#218 decomposition that unblocked spec/audit work)
**Methodology:** SQL queries against live Supabase (`ldrfrvwhxsmgaabwmaik`); attempted Drive enumeration of folder `1m7ds6GM9aD8sdvImMsU4jp2AnXgsm4m7` from Claude-attached OAuth identity — access denied (folder owned in a context this identity cannot enumerate; the 5 known `drive_file_id` values returned `Requested entity was not found` on `get_file_metadata` from the same identity).

---

## TL;DR (executive summary)

- **Cycle 4 has 38 applications.** 20 have `pmi_video_screenings` rows (5 per application = 100 rows total). 18 have none.
- **Only 1 candidate uploaded videos**: Eduardo Luz (`e780d8a9-55e0-4a6c-9370-4acc24a9619d`, `eduardoluz.pm@gmail.com`, status=`interview_pending`, role=`researcher`). The other 19 video-row apps are 100% `opted_out` (5 pillars each = 95 rows).
- **5 Drive files** are tracked in DB for Eduardo (one per pillar: background, communication, proactivity, teamwork, culture_alignment), all pointing to folder `1m7ds6GM9aD8sdvImMsU4jp2AnXgsm4m7`.
- **PM observation** of "6 files in the Drive folder" cannot be verified from this audit's identity — the 6th file (if real) is not registered in `pmi_video_screenings` and would need PM Drive admin to enumerate. Most likely candidates: an "intro" video before the 5 pillars, a retry/duplicate that was later replaced, or a stale test upload.
- **Transcription state**: 1 of Eduardo's 5 (the `background` pillar) was transcribed pre-block on 2026-05-19 15:17 (via OpenAI Whisper). The other 4 stayed `uploaded` (no transcription) — correctly blocked first by Whisper 429 quota, then formally by the p207 helper gate (`analyze_application_video_async` consent check).
- **1 AI suggestion** exists for Eduardo's background pillar (`suggestion_id=90b556be-6050-4419-a8d9-5e4457ed9d66`, model `claude-haiku-4-5-20251001`, prompt `p197d_d1_v1`, `suggested_weighted_subtotal=8`, `consumed_at=NULL` → not yet validated by committee evaluation).
- **Consent gap**: 0 of the 107 total `selection_applications` rows have `consent_voice_biometric_at` populated — UI not yet shipped (tracked under sibling **#331**). Eduardo's 1 already-transcribed row is the LGPD Art. 11 retroactive scope tracked under sibling **#332**.
- **Data drift finding**: All 5 of Eduardo's video file names use the prefix `cycle3-2026-b2__opp64967__…` even though his application's `cycle_id` resolves to `cycle4-2026`. Upload-time cycle label looks stale relative to the canonical `selection_applications.cycle_id` (his app `created_at=2026-04-15` predated `cycle4` open date `2026-05-15`, and his upload times `2026-05-07` predated cycle4 open too). Not a blocker; flag for the Drive reconciliation workstream.

---

## 1. Data sources

- `selection_applications` filtered to `cycle_id = '08c1e301-9f7b-4d01-a13c-43ac7775c0f7'` (Cycle 4 — `cycle4-2026`, open 2026-05-15 → 2026-06-30, phase `evaluating`)
- `pmi_video_screenings` for those applications
- `selection_evaluation_ai_suggestions` filtered to `evaluation_type='video'` for those applications
- `ai_processing_log` (sampling; not the canonical join column)
- Google Drive folder `1m7ds6GM9aD8sdvImMsU4jp2AnXgsm4m7` — **enumeration failed from this audit's OAuth identity** (folder + individual files both return `Requested entity was not found`)

---

## 2. Cycle 4 landscape

| Metric | Value |
|---|---|
| Total Cycle 4 applications | 38 |
| Apps with `consent_ai_analysis_at` populated | 24 |
| Apps with `consent_voice_biometric_at` populated | **0** |
| Apps with `consent_voice_biometric_revoked_at` populated | 0 |
| Apps with at least one `pmi_video_screenings` row | 20 |
| Apps with NO `pmi_video_screenings` row | 18 |
| Total `pmi_video_screenings` rows (5 pillars × 20 apps) | 100 |
| Rows with `status='uploaded'` (5 — all Eduardo) | 5 |
| Rows with `status='opted_out'` (95 — 19 other apps × 5 pillars each) | 95 |
| Rows with `transcription IS NOT NULL` | **1** (Eduardo / background pillar) |
| Rows with `drive_file_id IS NOT NULL` | 5 (all Eduardo) |
| Rows with `drive_file_id IS NULL` | 95 (all opted_out) |
| Distinct `drive_folder_id` values | 1 (`1m7ds6GM9aD8sdvImMsU4jp2AnXgsm4m7`) |
| Total video-evaluation AI suggestions | 1 |

Status breakdown is a perfect dichotomy: `uploaded` (5) or `opted_out` (95). No intermediate states (no `transcribing`, `failed`, `pending`, etc.) currently in cycle4. The single transcribed row is `status='uploaded'` with `transcription IS NOT NULL` — there is no separate `status='transcribed'` value used for cycle4.

---

## 3. Candidate audit: Eduardo Luz

**Application:** `e780d8a9-55e0-4a6c-9370-4acc24a9619d` · `eduardoluz.pm@gmail.com` · `status=interview_pending` · `role_applied=researcher` · `vep_application_id=288274` · `vep_opportunity_id=64967` · `created_at=2026-04-15 22:41:34+00` · `consent_ai_analysis_at=NOT NULL` · `consent_voice_biometric_at=NULL` · `is_returning_member=false` · `linked_application_id=NULL`

All 5 of Eduardo's `pmi_video_screenings` rows, ordered by pillar:

| Screening ID | Pillar | Q# | Drive File ID | Drive File Name | Status | Transcribed | Uploaded At |
|---|---|---|---|---|---|---|---|
| `6afb7e26` | background | 1 | `14bA9rCezVD0Usko-S28ZtJnXd63MwsO6` | `cycle3-2026-b2__opp64967__e780d8a9-eduardo-luz__researcher__p1-background__20260507-2103.mp4` | uploaded | ✅ YES (OpenAI Whisper, 2026-05-19 15:17:47) | 2026-05-07 21:03:46 |
| `225b726e` | communication | 2 | `1Y5ba-Hx-VijzIEHqRXqaI-fk0CbwWs0K` | `__p2-communication__20260507-2123.mp4` | uploaded | ❌ NO | 2026-05-07 21:23:57 |
| `0608202b` | proactivity | 3 | `1St4hHVMxG-VYF7pPOPkYhtIldAPlyRUm` | `__p3-proactivity__20260507-2128.mp4` | uploaded | ❌ NO | 2026-05-07 21:28:50 |
| `467b814b` | teamwork | 4 | `1Tac8KxLyhipPIxi20wC5OTM6y0ARNRT9` | `__p4-teamwork__20260507-2037.quickt` | uploaded | ❌ NO | 2026-05-07 20:38:21 |
| `a2b632b3` | culture_alignment | 5 | `1c6axkZHI9FeI1Q_8MrlOmtZDZMj9_BNJ` | `__p5-culture_alignment__20260507-2036.quickt` | uploaded | ❌ NO | 2026-05-07 20:37:31 |

Coverage: all 5 canonical pillars present, 1 distinct file per pillar, all under the same folder ID. No duplicates, no orphans on the DB side, no retries (`retry_count=0` for all 5). 2 files have `.quickt` extension (QuickTime container; iOS/macOS native capture); 3 have `.mp4`.

Eduardo's AI suggestion (the only video suggestion in cycle4):

| Field | Value |
|---|---|
| Suggestion ID | `90b556be-6050-4419-a8d9-5e4457ed9d66` |
| `evaluation_type` | `video` |
| `model_provider` / `model_name` | `anthropic` / `claude-haiku-4-5-20251001` |
| `prompt_version` | `p197d_d1_v1` |
| `generated_at` | 2026-05-19 15:19:44 (≈2 min after the background pillar transcription completed) |
| `suggested_weighted_subtotal` | 8 |
| Pillars scored | only `background` (consistent — only 1 of 5 was transcribed) |
| `consumed_at` | NULL (no committee evaluation has validated this suggestion) |
| `used_in_evaluation_id` | NULL |
| `superseded_by` | NULL |

The suggestion is dormant — no human committee member has reviewed or validated it. Per ADR-0067 (AI-augmented selection Art. 20 safeguards), suggestions are non-binding and must remain so until a human evaluator validates.

---

## 4. Drive folder reconciliation

**Folder:** `1m7ds6GM9aD8sdvImMsU4jp2AnXgsm4m7`
**PM observation:** "folder contains 6 files"
**DB reconciliation:** 5 known files (all Eduardo's, one per pillar)
**Variance:** 1 file unaccounted for

This audit's identity cannot enumerate the folder (Drive API responds `Requested entity was not found` to both `search_files` with `parentId =` clause and `get_file_metadata` for each known `drive_file_id` — likely because the folder is owned by a service account or admin Google identity outside this OAuth scope). Therefore the 6th file's identity and metadata must come from PM Drive admin access.

**Hypothesis ranking for the 6th file** (most → least likely, none can be confirmed without admin Drive access):

1. **Intro video** — many self-recorded screening UIs have a 0th "intro/orientation" question that's filmed but not pillar-scored. If so, it's not registered in `pmi_video_screenings` by design.
2. **Retry/duplicate** — a candidate may have uploaded a take, then re-uploaded a better take; the DB row was updated in place (pointing to the new `drive_file_id`) while the old file lingered in Drive untracked.
3. **Stale test upload** — pre-cycle4 manual test by an admin (the file name might or might not match the `cycle3-2026-b2__opp64967__e780d8a9-eduardo-luz` pattern).
4. **Orphan from another candidate** — a different Cycle 4 candidate uploaded a file but the `pmi_video_screenings` row was never created/updated (would indicate a broken upload-confirmation path; concerning if true).

The Drive reconciliation workstream (workstream 3 of #254) is the canonical home for resolving this. Until it ships, the variance is documented but not fixed.

---

## 5. Opt-out cohort (19 apps × 5 pillars = 95 rows)

19 other Cycle 4 applicants have video screening rows; ALL of them are `status='opted_out'` for ALL 5 pillars (no partial uploads). Distribution by `app_status`:

| App Status | N applicants | Notes |
|---|---|---|
| `screening` | 13 | Earlier funnel stage; opt-out may shift to upload later |
| `interview_pending` | 5 | Already at interview stage with no videos uploaded — video step bypassed |
| `rejected` | 1 (William Junio, leader track) | Same candidate has a separate `interview_pending` researcher application |

All 19 have `consent_ai_analysis_at` populated except one (Flavio Oliveira, `has_ai_consent=false`).

**Note on `opted_out` semantics**: every applicant who reaches the video screening step appears to get 5 pre-seeded rows (one per pillar) initialized to `status='opted_out'`; the status flips to `uploaded` if/when the candidate uploads. This is consistent with #254's observation that the `/admin/selection` timeline conflates "uploaded video" and "opt-out" through the legacy `video_screening_done` boolean — both render as "OK ou opt-out" in the UI even though they're semantically distinct states. **This is workstream 2 of #254** (UI semantics fix using `video_agg.status_agg` instead of the boolean).

---

## 6. Consent gap

| Consent | Cycle 4 count | All-apps count |
|---|---|---|
| `consent_ai_analysis_at IS NOT NULL` | 24 / 38 | 25 / 107 |
| `consent_voice_biometric_at IS NOT NULL` | **0 / 38** | **0 / 107** |
| `consent_voice_biometric_revoked_at IS NOT NULL` | 0 / 38 | 0 / 107 |

The voice biometric consent gap (0/107) is fully tracked under sibling **#331** (W2 UI capture + `privacy.s4.openaiWhisper` i18n disclosure). The retroactive-notification scope for Eduardo's 1 already-transcribed row is tracked under sibling **#332** (W3). Until #331 ships, the SQL helper gate (`analyze_application_video_async`) + BEFORE trigger (`trg_pmi_video_screening_voice_consent`) hold the line — Eduardo's 4 untranscribed rows cannot be auto-processed; ad-hoc requests would also be rejected.

---

## 7. Data drift findings

### 7.1 Cycle label drift in upload file names

All 5 of Eduardo's Drive file names use the prefix `cycle3-2026-b2__opp64967__e780d8a9-eduardo-luz__researcher__pX-*__YYYYMMDD-HHMM.{mp4,quickt}`.

His current `selection_applications.cycle_id` resolves to `cycle4-2026` (open 2026-05-15 → 2026-06-30). Upload times are 2026-05-07 — before cycle4 opened. App `created_at=2026-04-15` — also before cycle4 opened.

Possible explanations:
- He was originally a `cycle3-2026-b2` candidate (open 2026-03-28 → 2026-05-31), uploaded videos during that window, and was later **moved/migrated to cycle4** without renaming the Drive files. But `linked_application_id` is `NULL` and `is_returning_member=false` — no formal cross-cycle linkage recorded.
- Upload-time UI code may have had stale cycle hardcoding (selected the most-recent open cycle at upload time rather than the candidate's actual application cycle_id).
- The `opp64967` opportunity ID matches his current `vep_opportunity_id=64967` — so VEP-side mapping is consistent across the cycle label change.

This is not blocking for the current funnel (Eduardo is in `interview_pending`), but it weakens any future audit query that joins by file-name prefix. Recommend the Drive reconciliation workstream normalize this convention OR document an explicit allowlist.

### 7.2 EF JS-layer gate absence

`supabase/functions/analyze-application-video/index.ts` line 263 still calls `whisperTranscribe(...)` without an explicit JS-layer `consent_voice_biometric_at IS NOT NULL` check before the OpenAI API invocation. The SQL helper gate is the sole pre-Whisper moat (plus Whisper 429 quota as an organic block). Defense-in-depth would add a JS-layer guard above the SQL helper. Not in scope for #254 itself; carries as a separate WATCH item.

---

## 8. Acceptance criteria status (#254 body)

| Criterion | Status |
|---|---|
| Audit report explains every file in the referenced Drive folder | **Partial** — 5 of 6 documented via DB join; the 6th requires PM Drive admin access to identify |
| `/admin/selection` no longer conflates uploaded video and opt-out in timeline | **Not started** — workstream 2 (UI fix) is not part of this audit; recommend child issue |
| Admin can identify missing/orphan/duplicate/unmapped videos without inspecting Drive manually | **Not started** — workstream 3 (Drive reconciliation tooling) is not part of this audit; recommend child issue |
| Missing AI analysis has explicit reason (no file / no consent / failed / pending / completed) | **Partial** — this audit documents the explicit reasons for cycle4 (1 transcribed pre-block, 4 blocked by p207 gate, 95 opted_out, 18 no-rows); UI surface to display reasons is not yet built |
| AI video suggestions are non-binding and require committee validation | **Holding** — current behavior is already non-binding (`consumed_at=NULL` on the 1 suggestion; no consumption pathway has run automatically) |
| Regression/contract test covers uploaded vs opt-out vs partial states | **Not started** — falls under workstream 2 (UI semantics fix) |

---

## 9. Recommended child issue split (PROPOSAL — not yet filed)

Per #254's suggested 5-workstream lane split. **None of these are filed yet** — this audit holds at the proposal stage so PM can confirm scope/sequencing before creation. Numbers are placeholders pending PM approval.

| Proposed child | Lane | Status | Blocks | Acceptance |
|---|---|---|---|---|
| **D1** — Cycle 4 video screening audit (this doc) | QA / Foundation | ✅ shipped p236 (this audit) | future workstreams 2-5 | This document |
| **D2** — `/admin/selection` timeline + detail UI: use `video_agg.status_agg` instead of `video_screening_done` boolean; render distinct states (`Vídeo enviado`, `Opt-out registrado`, `Parcial`, `Não realizado`, `Análise IA pendente/falhou/concluída`) | Frontend / UX | ready-leaf after PM approval | None | Timeline labels distinct; contract test for state matrix |
| **D3** — Drive reconciliation admin tool/report + flag orphan files + safe linking flow | Integration / Foundation | ready-leaf after PM approval | None | Admin can identify the 6th file + safe-link unmapped Drive files to applications |
| **D4** — Consent-aware video reprocess path (re-enable transcription per-row WHEN consent newly given) | MCP-AI / Foundation | blocked on **#331** (UI consent capture) | #331 close | Reprocess only fires when both `consent_ai_analysis_at` AND `consent_voice_biometric_at` are set; emits explicit "blocked: no consent" state otherwise |
| **D5** — AI suggestion lineage + human-in-the-loop scoring policy: define whether video suggestions feed `interview`, `leader_extra`, dedicated `video`, or subjective-scoring table; preserve `ai_suggestion_id → used_in_evaluation_id` lineage | Governance / Foundation | spec-only (depends on #243 calibration spec) | #243 child split | Scoring policy ADR + lineage trigger + test that no AI score affects official result without committee validation |

**Sequencing recommendation**:
- D2 + D3 can ship in parallel (Frontend vs Integration; no DB schema conflicts)
- D4 blocked on #331 — fine; UI consent must precede reprocess unblock
- D5 blocked on #243 — fine; calibration framework should define scoring policy before video lineage is set

---

## 10. Carries / open questions for PM

1. **Identify the 6th Drive file** in folder `1m7ds6GM9aD8sdvImMsU4jp2AnXgsm4m7` (PM admin access required — this audit's identity can't enumerate). Once identified, D3 child can be scoped properly.
2. **Cycle label drift** in Eduardo's Drive file names (`cycle3-2026-b2` prefix vs `cycle4-2026` app `cycle_id`) — accept as benign data drift OR include rename/migration in D3 scope.
3. **EF JS-layer consent gate** above SQL helper — defense-in-depth WATCH (carry from p236 disposition of #221/#218). File as standalone if PM wants tracked separately from D4.
4. **Pillar / question-index intent**: this audit assumes the canonical 5 pillars are `background (1), communication (2), proactivity (3), teamwork (4), culture_alignment (5)`. If new pillars are planned for future cycles, the 5-pre-seeded-rows-per-app contract may need to flex.
5. **Eduardo's 1 transcribed-but-unconsented row**: tracked under #332 — confirm the retroactive-notification scope matches PM expectation (1 candidate, 1 pillar, ~6KB transcription text, no consumed AI scoring).
6. **D5 dependency on #243**: confirm sequencing — if PM wants D5 to ship as standalone scoring-policy child without waiting for the broader #243 framework, scope adjust required.

---

## 11. Live state pins (verifiable post-publication)

- HEAD commit at audit time: `5d01dbab` (PR #336 merge — p236 disposition close)
- Invariants 19/19 = 0 violations at audit time
- `selection_cycles.id` for `cycle4-2026` = `08c1e301-9f7b-4d01-a13c-43ac7775c0f7`
- `selection_applications.id` for Eduardo Luz = `e780d8a9-55e0-4a6c-9370-4acc24a9619d`
- Eduardo's 5 `pmi_video_screenings.id`: `6afb7e26` (background), `225b726e` (communication), `0608202b` (proactivity), `467b814b` (teamwork), `a2b632b3` (culture_alignment)
- AI suggestion: `90b556be-6050-4419-a8d9-5e4457ed9d66` (claude-haiku-4-5-20251001, p197d_d1_v1)
- Wave 1 LGPD engineering moat: migrations `20260731000000` (#218 emergency block — orphan local file on stale branch) + `20260801000000-002` (#221 p207 drop-trigger + columns + helper gate, all in main)
- Decomposition siblings: **#331** (W2 UI consent capture + i18n) / **#332** (W3 retroactive notification + Art. 18 §IV) / **#333** (W4 invariant U) / **#334** (W5 Angeline legal-ops) / **#335** (ADR-0094)

---

Assisted-By: Claude (Anthropic)
