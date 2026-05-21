# Issue Registry

**Last updated:** 2026-05-21  
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

---

## QA Window

| Issue | Registry status | Lane | Blocks | Blocked by | Acceptance evidence | Close rule |
|---|---|---|---|---|---|---|
| #159 | qa-window | Governance | p201 child dispatch | PM stabilization confirmation | Template renders; first p201 child uses template | Close after PM confirms stabilized |
| #216 | qa-window | Frontend | `/profile` trust | production smoke | `/profile` no `ReferenceError`, spec diagnosis corrected | Close after production smoke and doc/comment cleanup |
| #179 | qa-window | Foundation / Governance | #180, #181, #177, #182, #183 | PM decision on spec-vs-implementation split | Spec + SQL audit pack exist | Close spec work only if implementation continues in children |

---

## Spec Trackers

| Issue | Registry status | Lane | Blocks | Blocked by | Acceptance evidence | Close rule |
|---|---|---|---|---|---|---|
| #212 | spec-only | Governance / Architecture | #211, #209, Drive/external-member work | #221 and PM signoff | ADR-0094, architecture doc, sub-issue set accepted | Close only after child issues spawned or tracker intentionally retained |
| #166 | spec-only | Foundation / Governance | semantic-layer implementation | ADR decisions | roadmap/ADR accepted | Close after roadmap decomposes into leaves |
| #204 | spec-only | Governance / Integration | Gemini/Drive/Calendar work | #212/#209 boundaries | integration governance direction accepted | Close after split into vendor eval, Drive lifecycle, calendar governance leaves |
| #97 | spec-only | Governance / Foundation | speaker lifecycle | consent/legal pattern from #221/#212 | accepted external speaker lifecycle spec | Close after child issues exist |
| #92 | spec-only | Integration / Foundation | calendar sync implementation | #205/#210 identity/email contract | accepted calendar integration architecture | Close after child issues exist |

---

## Ready Or Near-Ready Leaves

| Issue | Registry status | Lane | Blocks | Blocked by | Acceptance evidence | Close rule |
|---|---|---|---|---|---|---|
| #217 | ready-leaf | Frontend / Integration | #212 v1 | none | welcome email link smoke: `/initiative/` not `/iniciativas/` | Close after route/link smoke |
| #205 | ready-leaf | Foundation | #210, #212 G1/G2 | none | migration + `resolve_member_by_email` RPC smoke | Close after contract tests and docs |
| #224 | ready-leaf | Frontend / Integration / QA | VEP JSON import confidence | reproducible sample JSON from PM | `/admin/selection` JSON dry-run/apply shows actual worker errors inline, plus `cron_run_log` lookup path or run id | File issue, reproduce with failing JSON, then close after UI/error contract smoke |
| #211 | blocked | Frontend | #212 G3 | #212 PM signoff if broader scope applies | metadata UI smoke | Do not start until scope is confirmed standalone vs #212 child |
| #194 | ready-leaf | QA | curatorship p197 confidence | p197 test fixtures | contract tests for review flow pass | Close after tests land |
| #193 | ready-leaf | Foundation | curatorship status consistency | none | migration/audit confirms phantom states removed | Close after migration + rollback docs |
| #192 | ready-leaf | Foundation | curatorship review integrity | none | DB constraint/RPC test: one curator review per round | Close after test + migration evidence |

---

## Program Clusters

| Cluster | Issues | Registry stance | Dispatch rule |
|---|---|---|---|
| Curatorship p197 | #185-#196, #188, #190, #201 | Needs parent status board | Allow max 2 ready leaves concurrently; serialize DB changes |
| Volunteer lifecycle | #177, #179, #180, #181, #182, #183, #205, #213 | Foundation sequence | Start after #221 containment; #179 is the canonical contract gate |
| MCP/AI | #162, #163, #170, #183, #188, #206-#208 | High-risk | Pause new tools until #162 contract matrix and #221 consent gates are stable |
| Attendance/calendar | #104, #107, #116, #156, #157, #172, #210 | Stabilization wave | Treat as one semantic cohort/cadence program |
| Drive/identity/collaboration | #110, #204, #205, #209, #211, #212 | Architecture first | Drive permission lifecycle must follow engagement source-of-truth decision |

---

## Dispatch Rules

1. Assign implementation agents only to `ready-leaf` issues.
2. `spec-only` issues may produce docs, ADRs, and child issues only.
3. `qa-window` issues are read-only unless smoke fails.
4. Foundation migrations serialize unless explicitly proven independent.
5. MCP/AI work must name data touched, consent basis, RPC/tool contract, and smoke evidence.
6. Any branch touching multiple lanes needs a documented exception or a split.

---

## Related Audit

See `docs/audit/2026-05-21_ISSUES_REGISTRY_AND_PARALLEL_WORK_AUDIT.md` for the initial curator analysis behind this registry.
