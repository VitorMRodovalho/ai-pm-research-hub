# Issues Registry + Parallel Work Audit

**Date:** 2026-05-21  
**Scope:** open GitHub issues, resolved-but-open QA windows, early code hotspot scan  
**Repo:** `VitorMRodovalho/ai-pm-research-hub`  
**Mode:** curatorship and stabilization. No app behavior changed.
**GitHub comments posted:** #159, #216, #224, #212, #148, #218, #221, #220.

---

## Executive Summary

The backlog is not just "too many issues"; it is mixing four different kinds of work in the same queue:

1. **Live stabilization blockers**: CI is failing on `main`, `/profile` has had recurring production runtime failures, and the Whisper/LGPD issue is a P0 compliance blocker.
2. **Resolved but intentionally open QA windows**: several issues are effectively done but remain open under the PM stabilization rule.
3. **Architecture/spec trackers**: #212, #166, #204, #97, #92 are planning surfaces, not implementation tasks.
4. **Implementation leaves**: narrow fixes like #217, #211, #205, #194, #193, #192.

The current parallel-agent model in `P201_PARALLEL_AGENT_ROADMAP.md` is directionally correct, but it needs an **issue registry layer** that marks each issue as one of: `active`, `qa-window`, `blocked`, `spec-only`, `ready-leaf`, `defer`, or `close-candidate`.

Without that registry, adding more Claude/Codex/Cursor instances increases throughput but also increases duplicate work, merge friction, and "fix one side, break another" regressions.

---

## Current Open Backlog Snapshot

`gh issue list --state open --limit 200` returned roughly 60 open issues.

### P0 / Stop-the-line

| Issue | Status | Curator read |
|---|---|---|
| #221 | Active P0 | Canonical forward issue for Whisper Art. 11 remediation: drop/block trigger path, add explicit voice biometric consent, update EF/RPC gate, legal/audit chain. |
| #218 | Partially resolved, keep open | Wave 1 emergency block was applied and PR created. Remaining Waves 2-5 are consent UI, privacy/i18n, retroactive notification, invariant, Angeline/ANPD determination. This should either become the parent tracker or be closed in favor of #221 after explicit comment. |
| #148 | Active P0/P1 | CI Validate has been failing on `main` since 2026-05-18. All other merge/process improvements are weakened while this is open. |
| #220 | Active P1 under #148 | Detailed root-cause investigation for `browser_guards`: L1 workerd DNS strict + L2 brittle Supabase auth-failure assumption. This is the real work item behind #148. |

### Resolved But Not Closed

| Issue | Evidence | Proposed action |
|---|---|---|
| #159 | PR #167 merged via squash on 2026-05-20; issue comment says QA window open. | Mark `qa-window`; close after PM confirms template render and first p201 child issue uses it. |
| #216 | PR #223 opened/merged path appears to have corrected diagnosis: missing client-side import of `t`, not TS annotation minify. Issue reopened per QA window. | Mark `qa-window`; update misleading spec filename/comment after merge stabilization; close only after `/profile` production smoke. |
| #179 | Specs and SQL audit pack created; reopened per PM QA rule. | Mark `qa-window` or split: close spec artifact task if no implementation landed; keep lifecycle implementation in child issues. |
| #218 | Wave 1 applied live; remaining waves still open. | Not close-candidate until UI/privacy/notification/invariant decisions are split or completed. |

### Spec / Architecture Trackers

| Issue | Curator read | Required boundary |
|---|---|---|
| #212 | Large spec tracker for initiative collaboration hub. PR #214 produced research, architecture, ADR-0094 draft, and sub-issue bodies. Council found blockers and spawned #217/#218/#221 class work. | Keep as `spec-only` until PM signoff. No implementation should be claimed directly under #212. |
| #166 | Semantic layer roadmap. | Architecture lane only until ADR decisions exist. |
| #204 | Gemini + Drive/Calendar governance umbrella. | Do not mix vendor/model evaluation with Drive permission lifecycle implementation. |
| #97 | External speaker lifecycle. | Depends on consent/legal patterns from #212/#221. |
| #92 | Calendar integration architecture. | Needs identity/email resolution contract (#205/#210) before implementation. |

### Clusters Needing Triage

| Cluster | Issues | Curator read |
|---|---|---|
| Curatorship p197 | #185-#196, #188, #190, #201 | This is a program, not independent bugs. Needs one parent spec/status board and 2-3 ready leaves max at a time. |
| Volunteer lifecycle | #177, #179, #180, #181, #182, #183, #205, #213 | Foundation-heavy. Should be sequenced behind #179 canonical approval contract and #181 agreement evidence. |
| MCP/AI | #162, #163, #170, #183, #188, #206-#208 | High regression risk because MCP touches RPC contracts and sensitive data. Require contract matrix before new tools beyond P0 fixes. |
| Attendance/calendar | #104, #107, #116, #156, #157, #172, #210 | Symptoms of missing semantic cohort/cadence model. Treat as one stabilization wave, not ad hoc UI fixes. |
| Drive/identity/collaboration | #110, #204, #205, #209, #211, #212 | Needs explicit source-of-truth decision: engagement lifecycle drives Drive permission state. |

---

## Early Code Hotspot Scan

This was not a full security audit. It was a targeted scan to confirm the backlog maps to real code surfaces.

### Security / LGPD / AI Processing

Evidence found:

- `supabase/functions/analyze-application-video/index.ts` explicitly transcribes via OpenAI Whisper and writes back to `pmi_video_screenings`.
- `supabase/functions/nucleo-mcp/index.ts` exposes `analyze_application_video`, with a `view_pii` JS-layer gate and RPC call.
- `docs/council/2026-05-20-p207-tier3-strategic-review-212.md` documents the Whisper Art. 11 issue and recommends the block + explicit consent path.
- `docs/reference/MCP_TOOL_MATRIX.md` includes `analyze_application_video`, which means the MCP contract matrix must be updated after any consent/gate change.

Curator decision:

- No new AI/video/meeting transcript feature should proceed until #221 is closed or explicitly decomposed into completed child gates.
- Any future AI provider call should have: provider name, purpose, consent source, revocation behavior, audit log, and retention behavior.

### Frontend Runtime Stability

Evidence found:

- `src/pages/profile.astro` has a large processed `<script>` block and prior inline comments about runtime `ReferenceError` traps.
- #216's latest comment corrected the root cause: client script used `t(...)` without importing/defining it in browser scope.
- Additional inline `onclick` usage exists in `src/pages/help.astro`, `src/pages/publications.astro`, and `src/pages/gamification.astro`, which conflicts with sprint implementation guidance discouraging vanilla inline events.

Curator decision:

- Add a forward-defense issue: audit processed Astro scripts for browser-scope unresolved identifiers and inline event handlers.
- Do not refactor all inline scripts in one PR. Start with routes that are production-critical: `/profile`, `/gamification`, `/publications`, `/help`.

### Permissions / Navigation

Evidence found:

- `src/lib/navigation.config.ts` is the central source for visibility, `minTier`, `allowedDesignations`, and `lgpdSensitive`.
- `src/lib/permissions.ts` has both `hasPermission(...)` and the V4 `canFor(...)` replacement.
- Many page/component call sites still use `hasPermission(...)`; issue #161 is the correct audit surface for sensitive UI gates.

Curator decision:

- Keep #161 as an audit issue, not a mass replacement issue.
- Convert only sensitive or scoped decisions to `canFor(...)` where there is an actual initiative/tribe/resource scope.

### Admin Selection JSON Import

Evidence found:

- `/admin/selection` has a p151 consolidated JSON import flow that calls `/api/admin/import-pmi-vep-json`.
- The API route proxies the request to the `pmi-vep-sync` worker `/ingest`; its own comment says the worker records invocation history in `cron_run_log`.
- The frontend render path only shows `N erro(s) — ver detalhes no cron_run_log do worker` when `d.errors.length > 0`; it does not render the actual `errors` array, run id, worker status, or a direct lookup path.

Possible bug:

- If PM uploads a JSON and sees a generic cron/log warning, the import may be partially succeeding while hiding row-level worker errors. This is a UX/observability bug even if the worker behavior is correct.
- Candidate issue: #224 `admin-selection-json-cron-error` — reproduce with the failing JSON, capture dry-run/apply response, show actual worker errors inline, and include a `cron_run_log` correlation id or timestamp.

Curator decision:

- Treat this as a `ready-leaf` Frontend/Integration/QA issue once a sample failing JSON or response payload is available. It should not be bundled with broader selection lifecycle work.

### CI / QA

Evidence found:

- #148 is a long-running CI monitor issue with repeated failures.
- #220 provides a refined root cause: `mock.supabase.co` DNS behavior plus brittle browser guard assumptions.

Curator decision:

- Stabilizing CI is a prerequisite for parallel work. Until #220/#148 close, merges should be treated as elevated-risk even when local checks pass.

---

## Recommended Issue Registry Fields

Every open issue should receive a lightweight registry status:

| Field | Values |
|---|---|
| `registry_status` | `active`, `qa-window`, `blocked`, `spec-only`, `ready-leaf`, `defer`, `close-candidate` |
| `lane` | Foundation, Frontend, MCP/AI, Governance, Infra/Security, QA |
| `merge_boundary` | files/directories the agent may touch |
| `blocks` | issue numbers blocked by this issue |
| `blocked_by` | issue numbers or external decisions |
| `acceptance_evidence` | build/test/smoke/log/query required to close |
| `close_rule` | what must be true before closing |

This can live as a Markdown table first. It does not need custom GitHub labels on day one.

---

## Parallel Work Model Recommendation

The current p201 rule is correct: one issue, one branch/worktree, one lane.

What is missing is a **dispatch rule**:

1. Only `ready-leaf` issues may be assigned to implementation agents.
2. `spec-only` issues may only produce docs/ADR/sub-issues, not code.
3. `qa-window` issues are read-only unless the smoke fails.
4. `active P0` issues can preempt all other work.
5. Any issue touching two lanes must be split unless the second lane is docs-only.

Suggested maximum concurrent work while CI is red:

| Lane | Max active implementation branches | Notes |
|---|---:|---|
| Foundation | 1 | DB/RPC/RLS changes serialize. |
| Frontend | 1 | Only leaf fixes with no DB dependency. |
| MCP/AI | 0-1 | Pause new tools until #162/#221 stabilize. |
| Governance | 2 | Safe for registry/spec/docs work. |
| Infra/Security | 1 | #220/#148 should own this lane first. |
| QA | 1 | Browser guards and contract tests only. |

After CI is green, increase Frontend and Governance first. Keep Foundation serialized unless migrations are unrelated and explicitly reviewed.

---

## First Stabilization Wave

### Wave 0: Registry and stop-the-line cleanup

1. Mark #159 and #216 as `qa-window`.
2. Decide whether #218 remains parent or is superseded by #221.
3. Treat #148/#220 as the only Infra/Security implementation task until green.
4. Freeze #212 implementation until PM signs off on the revised ADR/sub-issue set.
5. Create an issue registry table from this audit and update it once per work session.

### Wave 1: Compliance and CI

1. Close #221 or split it into consent DB gate, EF/MCP gate, privacy/i18n UI, notification, invariant.
2. Close #220 and confirm CI green without `--admin` bypass.
3. Add forward-defense tests for `/profile` runtime import regressions.

### Wave 2: Lifecycle foundation

1. Execute #179 canonical approval contract only after #221 P0 is contained.
2. Sequence #180/#181/#177/#182 behind #179.
3. Keep #183 blocked until lifecycle contracts are stable.

### Wave 3: Product growth

1. Use #212 only as parent spec.
2. Spawn/claim G1-G4 leaf issues separately.
3. Keep Drive permission sync and external identity in Foundation/Integration lanes, not mixed with metadata UI.

---

## Immediate Close / Comment Candidates

| Issue | Suggested curator comment |
|---|---|
| #159 | "QA window: PR #167 merged; close after template render + first p201 child confirms template use." |
| #216 | "QA window: diagnosis revised to missing browser import of `t`; close after prod `/profile` smoke and spec doc correction." |
| #218 | "Wave 1 complete, remaining waves either tracked here or superseded by #221. PM decision needed to avoid duplicate P0 trackers." |
| #212 | "Spec tracker only. PR #214 deliverables produced; no implementation until PM signs off on revised blockers/sub-issues." |
| #148 | "Parent CI monitor. Active implementation should happen in #220; close only when main CI heartbeat recovers." |

---

## Next Action

Create a canonical registry file, for example:

`docs/project-governance/ISSUE_REGISTRY.md`

Seed it with the P0/P1 issues above and update it as issues are closed, split, or promoted. This should become the dispatch board for Claude Code, Codex, Cursor, and any other parallel agent.
