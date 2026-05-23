# Issue Registry

**Last updated:** 2026-05-23 (p232 — #229 Phase 2 closed: leader_extra cohort visibility in 3 read RPCs + MCP descriptions + frontend 2-band chip; next #321 (Gap A phantom rows))
**Purpose:** dispatch board for parallel agents. This registry complements GitHub labels by adding execution status, lane, blockers, and close rules.

**Operating protocol:** `docs/project-governance/ISSUE_REGISTRY_OPERATING_PROTOCOL.md`

Status values:

- `active` — work may proceed now.
- `qa-window` — implementation appears complete; keep open for stabilization smoke only.
- `blocked` — do not implement until blocker clears.
- `spec-only` — planning/ADR/sub-issues only; no app behavior changes.
- `ready-leaf` — narrow implementation issue ready for one agent/worktree.
- `defer` — valid but not current-wave work.
- `close-candidate` — likely closable after curator comment/signoff.

---

## Stop-The-Line

| Issue | Registry status | Lane | Blocks | Blocked by | Acceptance evidence | Close rule |
|---|---|---|---|---|---|---|
| #221 | active | Foundation / Integration / Governance | #212, #208, #207, AI/video features | Angeline/PM legal ops for later waves | Migration/EF gate, privacy/i18n/UI consent, notification/invariant evidence as scoped | Close only when remaining waves are complete or split into accepted child issues |
| #218 | active | Foundation / Governance | AI/video features | duplicate decision with #221 | Wave 1 evidence exists; Waves 2-5 still pending | Decide parent vs superseded-by-#221 before closing |
| #148 | active | Infra/Security / QA | all merge confidence | #220 | CI heartbeat green on `main` | Close only after CI Validate recovers on main |
| #220 | active | Infra/Security / QA | #148 | none | Local test:browser:guards + build pass with resolvable mock Supabase URL; remote CI pending | Close after CI PR passes and main heartbeat confirms |
| #260 | qa-window | Foundation / Integration / QA / Governance | selection funnel communications, Resend quota safety | production smoke 7d; auto-trigger design for selection_cutoff_approved | All 7 W2 leaves shipped p228 (PRs #305 + #307), Leaf 5 hotfix shipped (PR #313), replay executed live (`updated_count=2`; 15 manual_close), P162 hotfix addendum landed (PR #316). Catalog parity locked. Phase C drift gate enforced. Health signal HEALTHY. | Close after production smoke confirms no recurrence over 7 days |
| #230 | umbrella | Foundation / Governance / QA | volunteer lifecycle reliability after selection approval | #321 + #322 + #323 children to ship | p230 audit refuted original Herlon-specific premise (his engagements don't require agreement; A3 fixed by #318/#320). Reframed into 3 narrow children covering actual gaps: #321 phantom onboarding rows, #322 classification leftovers + forward guard, #323 catalog config (`study_group_*` requires_agreement+null template) | Close when all 3 children ship; do NOT mint a Herlon term |

---

## QA Window

| Issue | Registry status | Lane | Blocks | Blocked by | Acceptance evidence | Close rule |
|---|---|---|---|---|---|---|
| #159 | qa-window | Governance | p201 child dispatch | PM stabilization confirmation | Template renders; first p201 child uses template | Close after PM confirms stabilized |
| #216 | qa-window | Frontend | `/profile` trust | production smoke | `/profile` no `ReferenceError`, spec diagnosis corrected | Close after production smoke and doc/comment cleanup |
| #179(closed) | closed | Foundation / Governance | none | none | 5/5 ACs met live p230 — canonical `approve_selection_application` exists; `admin_update_application` + `finalize_decisions` delegate (RAISE on failure); invariants R/S/A3 green; contract test `canonical-approval-orchestration.test.mjs`. Implementation continues under #230 children (#321/#322/#323) + existing lifecycle issues #180/#181/#177/#182/#183 → registry close rule satisfied | Closed 2026-05-23 (p230); no re-open unless concrete canonical RPC failure proves the partial AC-4 split is incorrect |
| #229(closed) | closed | Foundation / MCP-AI / Frontend | none | none | Phase 2 shipped p232 — migration `20260805000017` extends 3 read RPCs: `get_pert_cutoff_summary` accepts `leader_extra_pert_score` + dual-track math, `get_application_score_breakdown` returns `leader_extra_cutoff` block, `get_selection_dashboard.cycle` exposes sibling `leader_extra_cutoff`. MCP v2.79.1 surfaces `leader_extra_pert_score` in score_column z.enum + descriptions clarify dual-dim. Frontend `/admin/selection` has 2-band chip (objective + leader cutoff). Contract tests +12 (`p232-229-phase2-leader-extra-visibility.test.mjs`). Live smoke 3/3 — get_pert_cutoff_summary leader_extra returns method=disabled (cohort_n=6 < 10) expected, get_application_score_breakdown returns leader_extra_cutoff + top-level leader_extra_pert_score, get_selection_dashboard.cycle has both blocks. Backfill not needed (cron `recompute-pert-cutoffs-weekly` already calls both dimensions per p219 Phase 1) | Closed 2026-05-23 (p232); no re-open unless concrete read-surface gap surfaces in production |

---

## Spec Trackers

| Issue | Registry status | Lane | Blocks | Blocked by | Acceptance evidence | Close rule |
|---|---|---|---|---|---|---|
| #292 | spec-only | Governance / QA | #260, #251, #116(closed), #179(closed), #229(closed), #230(umbrella) + #321/#322/#323 sequencing | PM/dev adoption of plan | `SELECTION_RELIABILITY_PRIORITIZATION_PLAN.md` accepted and child handoffs dispatched in order | Close after sprint child issues are dispatched or tracker intentionally retained |
| #300 | spec-only | Governance / Foundation / MCP-AI | external_reviewer onboarding refactor | PM triage; do not preempt #292 unless escalated as active P0 | 10-gap umbrella decomposed into child issues with lanes and blockers | Keep deferred during Selection reliability sprint unless PM explicitly escalates a narrow stop-the-line child |
| #212 | spec-only | Governance / Architecture | #211, #209, Drive/external-member work | #221 and PM signoff | ADR-0094, architecture doc, sub-issue set accepted | Close only after child issues spawned or tracker intentionally retained |
| #254 | spec-only | QA / Foundation / Integration / Frontend / MCP-AI / Governance | Cycle 4 video screening trust, AI-assisted video review workflow | production read-only audit, #221/#218 consent stance | Drive folder files reconciled to `pmi_video_screenings`, AI processing/suggestion state, and human validation path; child issues split by lane | Close only after audit evidence and child implementation issues are accepted or tracker intentionally retained |
| #243 | spec-only | Governance / MCP-AI / Frontend / QA | selection AI-assist calibration children | calibration profile contract and child split | Spec/ADR defines versioned calibration profile, context completeness warnings, evidence guardrails, AI lineage, and LGPD/HITL stance | Close only after child issues are accepted or tracker intentionally retained |
| #166 | spec-only | Foundation / Governance | semantic-layer implementation | ADR decisions | roadmap/ADR accepted | Close after roadmap decomposes into leaves |
| #204 | spec-only | Governance / Integration | Gemini/Drive/Calendar work | #212/#209 boundaries | integration governance direction accepted | Close after split into vendor eval, Drive lifecycle, calendar governance leaves |
| #97 | spec-only | Governance / Foundation | speaker lifecycle | consent/legal pattern from #221/#212 | accepted external speaker lifecycle spec | Close after child issues exist |
| #92 | spec-only | Integration / Foundation | calendar sync implementation | #205/#210 identity/email contract | accepted calendar integration architecture | Close after child issues exist |

---

## Ready Or Near-Ready Leaves

| Issue | Registry status | Lane | Blocks | Blocked by | Acceptance evidence | Close rule |
|---|---|---|---|---|---|---|
| #211 | blocked | Frontend | #212 G3 | #212 PM signoff if broader scope applies | metadata UI smoke | Do not start until scope is confirmed standalone vs #212 child |
| #194 | ready-leaf | QA | curatorship p197 confidence | p197 test fixtures | contract tests for review flow pass | Close after tests land |
| #193 | ready-leaf | Foundation | curatorship status consistency | none | migration/audit confirms phantom states removed | Close after migration + rollback docs |
| #192 | ready-leaf | Foundation | curatorship review integrity | none | DB constraint/RPC test: one curator review per round | Close after test + migration evidence |
| #321 | ready-leaf | Foundation / Governance / Data-integrity | #230 umbrella close | none | AFTER INSERT trigger on certificates of type=volunteer_agreement marks matching onboarding_progress row completed; backfill 30 phantom rows; contract test (forward-defense + DB-gated); live smoke 0 phantom | Close after trigger + backfill + test + smoke confirms 0 phantom rows |
| #322 | ready-leaf | Foundation / Governance / Data-integrity | #230 umbrella close | #321 (sync trigger first to clean Gap A before classifying remainder) | PII-redacted audit of 4 active + 7 inactive rows; PM per-row decision; forward guard in `approve_selection_application` (do NOT seed vol_term unless engagement kind requires_agreement); offboarding extension auto-completes/marks obsolete; contract test | Close after audit + guard + offboarding extension + 0 active members with pending vol_term and no requires_agreement engagement |
| #323 | ready-leaf | Foundation / Governance / Data-integrity | #230 umbrella close | PM decision per kind: assign template OR flip requires_agreement=false | Migration applies PM decision for `study_group_owner` + `study_group_participant`; catalog invariant test extended (requires_agreement=true ⇒ agreement_template IS NOT NULL OR slug IN allowlist); live smoke 0 catalog inconsistencies | Close after migration + invariant test + smoke confirms no offending catalog rows |


## Close Candidates / QA Evidence Needed

| Issue | Registry status | Lane | Blocks | Blocked by | Acceptance evidence | Close rule |
|---|---|---|---|---|---|---|
| #251 | close-candidate | QA / Foundation | none | PM browser retest / devtools evidence if still reported | p226 audit did not reproduce Henrique invisibility or William 1/2 state; #298 spawned for real pending-list bug | Close after PM retest confirms current state or split a narrow UI/cache issue |
| #217 | close-candidate | Foundation / QA | none | final curator/PM close comment | Migration `20260802000007` + contract test show `/initiative/` and not `/iniciativas/` | Close after posting evidence summary to issue |
| #227 | close-candidate | Foundation / QA | none | PM browser smoke for CV button | Storage policy uses `rls_can('view_pii')`; forward-defense test exists | Close after `/admin/selection` CV signed URL smoke confirms no 400 |


---

## Program Clusters

| Cluster | Issues | Registry stance | Dispatch rule |
|---|---|---|---|
| Selection reliability Cycle 4 | #292, #251, #298(closed), #260(qa-window), #116(closed), #318(closed), #179(closed), #229(closed), #230(umbrella) + #321/#322/#323 children, #243, #254 | P0 sequencing program | #251 audit + #298 fix + #260 W2 ALL 7 LEAVES SHIPPED + replay live (p228) — qa-window for 7d production smoke only. #116 calendar webhook smoke PASS + closed p229. #318 A3 invariant fixed p230 (PR #320). **p230 close #179 + reframe #230**: #179 closed as IMPLEMENTED (5/5 ACs met live; canonical RPC + delegating legacy paths + invariants R/S/A3 + contract test). #230 reframed into umbrella with 3 ready-leaf children — #321 phantom-row sync trigger, #322 classification leftovers + forward guard, #323 catalog config. **p232 #229 Phase 2 closed**: leader_extra cohort visibility in 3 read RPCs (get_pert_cutoff_summary dual-track CHECK + math; get_application_score_breakdown adds leader_extra_cutoff block; get_selection_dashboard.cycle exposes sibling block); MCP v2.79.1 with `leader_extra_pert_score` in z.enum + dual-dim descriptions; frontend `/admin/selection` 2-band chip; +12 contract tests; live smoke 3/3 PASS (method=disabled expected — cohort_n=6 < 10). Next p232+ dispatch order: **#321 (Gap A phantom rows sync trigger first to unblock #322 audit isolation)**, then #322 (Gap B classification + forward guard), then #323 (Gap C catalog config); keep #243/#254 spec/read-only behind #221/#218 |
| Curatorship p197 | #185-#196, #188, #190, #201 | Needs parent status board | Allow max 2 ready leaves concurrently; serialize DB changes |
| Volunteer lifecycle | #177, #179(closed), #180, #181, #182, #183, #205, #213, #230(umbrella) + #321/#322/#323 | Foundation sequence | Start after #221 containment; #179 closed as IMPLEMENTED p230 (canonical contract gate shipped); #230 reframed into umbrella with 3 ready-leaf children — #321 sync trigger first, then #322 classification + guard, then #323 catalog config |
| MCP/AI | #162, #163, #170, #183, #188, #206-#208 | High-risk | Pause new tools until #162 contract matrix and #221 consent gates are stable |
| Attendance/calendar | #104, #107, #116, #156, #157, #172, #210 | Stabilization wave | Treat as one semantic cohort/cadence program |
| Drive/identity/collaboration | #110, #204, #205, #209, #211, #212, #254 | Architecture first | Drive permission lifecycle must follow engagement source-of-truth decision; video file reconciliation must start with read-only evidence |

---

## Dispatch Rules

1. Assign implementation agents only to `ready-leaf` issues.
2. `spec-only` issues may produce docs, ADRs, and child issues only.
3. `qa-window` issues are read-only unless smoke fails.
4. Foundation migrations serialize unless explicitly proven independent.
5. MCP/AI work must name data touched, consent basis, RPC/tool contract, and smoke evidence.
6. Any branch touching multiple lanes needs a documented exception or a split.
7. During the Selection reliability sprint, **#260 Workstream 2 ALL 7 leaves are SHIPPED end-to-end (p228)**: PR #305 (Leaf 1 catalog/helper parity) + PR #307 (Leaves 2 interview_overdue cron + 3 soft AI gate + 4 selection_cutoff_approved foundation + 5 selective replay RPC + 6 operational suppress_all bypass + 7 24h health signal) + PR #313 Leaf 5 hotfix + PR #316 P162 hotfix addendum. Replay executed live (`updated_count=2`; 15 manual_close), so #260 remains `qa-window` for 7d production smoke only. **p229 #116 closed**: live smoke PASS — 22 webhook-synced rows since p95 (2026-05-06), 92% cycle4 sync rate, idempotency + B3 reschedule-clearance both live, most-recent fire 2 days pre-close. P162 #195 carries WATCH-116.A (webhook service_role bypasses `schedule_interview` gate by design; `gate_attempts` audit visibility weaker than RPC path — non-blocking, documented). **#318 A3 invariant drift fixed p230**: PR #320 added `chk_a3_active_role_not_none`, repaired Herlon via canonical V4 ladder, and restored check-invariants to 19/19=0 with no bypass. **p230 #179 closed as IMPLEMENTED**: 5/5 ACs met live (canonical `approve_selection_application` exists; `admin_update_application` + `finalize_decisions` delegate with RAISE on failure; invariants R/S/A3 green; `canonical-approval-orchestration.test.mjs` covers contract); implementation continues under children. **p230 #230 reframed as umbrella**: live audit refuted Herlon-specific premise (his engagements don't require agreement); 16→4 pending_agreement (none `volunteer` kind); spawned 3 ready-leaf children #321 (phantom row sync trigger, ~30 rows) + #322 (classification leftovers + forward guard, 4 active + 7 inactive) + #323 (catalog config: `study_group_*` requires_agreement=true with null template). Do NOT mint Herlon term. **p232 #229 Phase 2 closed**: leader_extra cohort visibility completed via migration `20260805000017` (3 read RPCs extended) + MCP v2.79.1 (`score_column` z.enum adds `leader_extra_pert_score` + descriptions clarify dual-dim) + frontend `/admin/selection` 2-band chip + 12 new contract tests; live smoke 3/3 PASS; method=disabled expected because cohort_n=6 < 10 threshold (will turn dynamic once 10+ leader-track approvals exist historically). **Next p232+ dispatch order**: #321 (Gap A phantom rows sync trigger), then #322 (Gap B classification + forward guard), then #323 (Gap C catalog config). p230 fast-follow carries: auto-trigger design for selection_cutoff_approved (cron schedule + threshold evaluation) + MCP tool registration for `get_selection_emails_pending_24h` + WATCH-116.A audit-visibility evaluation (if PM wants symmetric webhook logging). p226 carries: cycle4 committee seed (no longer urgent post-Leaf 3 soft gate) + 19 cycle4 screening apps status advance. #298 + #116 + #318 + #179 + #229 CLOSED. #251 close-candidate awaiting PM retest. Do not dispatch #243/#254 implementation until #221/#218 consent blockers are resolved or explicitly decomposed; keep #300 deferred unless PM explicitly escalates a narrow active-data-corruption child.

---

## Related Audit

See `docs/audit/2026-05-21_ISSUES_REGISTRY_AND_PARALLEL_WORK_AUDIT.md` for the initial curator analysis behind this registry.
