# Issue Registry

**Last updated:** 2026-05-23 (p229 — #116 calendar booking smoke PASS + closed)
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
| #318 | active | Foundation / QA / Governance | all PRs (check-invariants CI ratchet hard-fails until fix) | next-session dispatch (root-cause triage of ARM-9 cron + decision on design intent: demote operational_role independently of member_status or not) | Migration + forward-defense contract test + Herlon cache repair + check_schema_invariants returns 19/19=0 | Close after migration lands, test pass, and live invariants 19/19=0 reconfirmed |
| #221 | active | Foundation / Integration / Governance | #212, #208, #207, AI/video features | Angeline/PM legal ops for later waves | Migration/EF gate, privacy/i18n/UI consent, notification/invariant evidence as scoped | Close only when remaining waves are complete or split into accepted child issues |
| #218 | active | Foundation / Governance | AI/video features | duplicate decision with #221 | Wave 1 evidence exists; Waves 2-5 still pending | Decide parent vs superseded-by-#221 before closing |
| #148 | active | Infra/Security / QA | all merge confidence | #220 | CI heartbeat green on `main` | Close only after CI Validate recovers on main |
| #220 | active | Infra/Security / QA | #148 | none | Local test:browser:guards + build pass with resolvable mock Supabase URL; remote CI pending | Close after CI PR passes and main heartbeat confirms |
| #260 | qa-window | Foundation / Integration / QA / Governance | selection funnel communications, Resend quota safety | production smoke 7d; auto-trigger design for selection_cutoff_approved | All 7 W2 leaves shipped p228 (PRs #305 + #307), Leaf 5 hotfix shipped (PR #313), replay executed live (`updated_count=2`; 15 manual_close), P162 hotfix addendum landed (PR #316). Catalog parity locked. Phase C drift gate enforced. Health signal HEALTHY. | Close after production smoke confirms no recurrence over 7 days |
| #230 | active | Foundation / Governance / QA | volunteer lifecycle reliability after selection approval | PM decision: auto-generate agreement vs manual queue | Herlon-like backlog count, agreement generation/nudge path, idempotent stale alert design | Close after affected backlog is generated/queued/manual-closed and future approved candidates have observable agreement path |

---

## QA Window

| Issue | Registry status | Lane | Blocks | Blocked by | Acceptance evidence | Close rule |
|---|---|---|---|---|---|---|
| #159 | qa-window | Governance | p201 child dispatch | PM stabilization confirmation | Template renders; first p201 child uses template | Close after PM confirms stabilized |
| #216 | qa-window | Frontend | `/profile` trust | production smoke | `/profile` no `ReferenceError`, spec diagnosis corrected | Close after production smoke and doc/comment cleanup |
| #179 | qa-window | Foundation / Governance | #180, #181, #177, #182, #183, #230 | PM decision on spec-vs-implementation split | Spec + SQL audit pack exist; use as lifecycle contract gate for selection reliability sprint | Close spec work only if implementation continues in children |

---

## Spec Trackers

| Issue | Registry status | Lane | Blocks | Blocked by | Acceptance evidence | Close rule |
|---|---|---|---|---|---|---|
| #292 | spec-only | Governance / QA | #260, #251, #116, #179, #230, #229 sequencing | PM/dev adoption of plan | `SELECTION_RELIABILITY_PRIORITIZATION_PLAN.md` accepted and child handoffs dispatched in order | Close after sprint child issues are dispatched or tracker intentionally retained |
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
| Selection reliability Cycle 4 | #292, #251, #298(closed), #260(qa-window), #116(closed), #179, #230, #229, #243, #254 | P0 sequencing program | #251 audit + #298 fix + #260 W2 audit + #260 W2 ALL 7 LEAVES SHIPPED (p228 PRs #305 + #307 + #313 + #316) — #260 is qa-window for 7d production smoke only; replay already executed. #116 calendar webhook smoke PASS + closed p229 (22 real bookings, 92% cycle4 sync rate, idempotency + reschedule-clearance live). Next p230: #318 A3 stop-the-line triage before #179/#230 lifecycle and #229 Phase 2; keep #243/#254 spec/read-only behind #221/#218 |
| Curatorship p197 | #185-#196, #188, #190, #201 | Needs parent status board | Allow max 2 ready leaves concurrently; serialize DB changes |
| Volunteer lifecycle | #177, #179, #180, #181, #182, #183, #205, #213 | Foundation sequence | Start after #221 containment; #179 is the canonical contract gate |
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
7. During the Selection reliability sprint, **#260 Workstream 2 ALL 7 leaves are SHIPPED end-to-end (p228)**: PR #305 (Leaf 1 catalog/helper parity) + PR #307 (Leaves 2 interview_overdue cron + 3 soft AI gate + 4 selection_cutoff_approved foundation + 5 selective replay RPC + 6 operational suppress_all bypass + 7 24h health signal) + PR #313 Leaf 5 hotfix + PR #316 P162 hotfix addendum. Replay executed live (`updated_count=2`; 15 manual_close), so #260 remains `qa-window` for 7d production smoke only. **p229 #116 closed**: live smoke PASS — 22 webhook-synced rows since p95 (2026-05-06), 92% cycle4 sync rate, idempotency + B3 reschedule-clearance both live, most-recent fire 2 days pre-close. P162 #195 carries WATCH-116.A (webhook service_role bypasses `schedule_interview` gate by design; `gate_attempts` audit visibility weaker than RPC path — non-blocking, documented). **NEW STOP-THE-LINE p229: #318 A3 invariant drift** — member Herlon (`c8e76355`) has operational_role='none' while member_status='active'; ARM-9 inactivity cron suspected (fires every 2-7 min today, Herlon updated 18s post-18:07:37 run); blocks all PRs via check-invariants CI ratchet hard-fail; PR #317 (#116 close docs) merged with legitimate --admin bypass per `.claude/rules/bypass-protocol.md` (CI red NOT caused by docs-only PR, tracking issue #318 filed pre-merge, 0/2 W22 bypass budget). **Next p229 dispatch order**: **#318 A3 root-cause triage (stop-the-line, before any new feature work)** → #179/#230 lifecycle → #229 Phase 2. p229 fast-follow carries: A3 design decision (ARM-9 should demote operational_role independently OR flip member_status atomically OR use a separate `arm9_flagged_at` column) + auto-trigger design for selection_cutoff_approved (cron schedule + threshold evaluation) + MCP tool registration for `get_selection_emails_pending_24h` + WATCH-116.A audit-visibility evaluation (if PM wants symmetric webhook logging). p226 carries: cycle4 committee seed (no longer urgent post-Leaf 3 soft gate) + 19 cycle4 screening apps status advance. #298 + #116 CLOSED. #251 close-candidate awaiting PM retest. Do not dispatch #243/#254 implementation until #221/#218 consent blockers are resolved or explicitly decomposed; keep #300 deferred unless PM explicitly escalates a narrow active-data-corruption child.

---

## Related Audit

See `docs/audit/2026-05-21_ISSUES_REGISTRY_AND_PARALLEL_WORK_AUDIT.md` for the initial curator analysis behind this registry.
