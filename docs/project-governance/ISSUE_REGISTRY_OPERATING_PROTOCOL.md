# Issue Registry Operating Protocol

**Status:** Adopted draft  
**Last updated:** 2026-05-21  
**Purpose:** make `ISSUE_REGISTRY.md` the operational dispatch layer between PM, curator, Claude Code, Codex, and any other parallel agent.

This protocol complements `P201_PARALLEL_AGENT_ROADMAP.md`. The roadmap defines lanes, handoff, and merge gates. The registry defines what is safe to dispatch now.

---

## 1. Operating Rhythm

Run a registry pass at these moments:

1. Before assigning work to Claude Code or another implementation agent.
2. After a PR merges or a production hotfix lands.
3. When CI, compliance, auth, MCP, or data-integrity issues appear.
4. Before opening a new workstream that touches more than one lane.
5. At the end of each work session if issue status changed.

Do not wait for sprint closure to update the registry. The registry is a dispatch board, not a retrospective artifact.

---

## 2. Status Definitions

Use exactly one status per issue.

| Status | Meaning | Allowed work |
|---|---|---|
| `active` | Work may proceed now, but it is not necessarily a leaf. | Diagnosis, decomposition, implementation only if scoped enough. |
| `ready-leaf` | Narrow task ready for one agent/worktree. | Implementation by Claude Code/dev. |
| `qa-window` | Implementation appears complete; issue remains open for stabilization. | Smoke, evidence collection, close decision. No refactor unless smoke fails. |
| `blocked` | Do not implement until blocker clears. | Clarification, spec, dependency tracking only. |
| `spec-only` | Planning surface, ADR, or parent tracker. | Docs, ADRs, child issue creation. No app behavior change. |
| `defer` | Valid but outside current wave. | Revisit only during planning. |
| `close-candidate` | Likely done; needs curator comment, PM signoff, or final smoke. | Evidence check and close recommendation. |

Promotion rule:

- `active` becomes `ready-leaf` only when scope, files, lane, acceptance evidence, and blocker state are clear.
- `ready-leaf` becomes `active` again if implementation reveals cross-lane scope or unclear architecture.
- `qa-window` becomes `close-candidate` after the required smoke/evidence passes.
- Any issue touching legal basis, biometric/voice/video AI, PII, RLS, auth, CI red state, or production data drift may be promoted to Stop-The-Line.

---

## 3. Dispatch Rules

Only dispatch implementation work from `ready-leaf`.

Before assigning a `ready-leaf`, the curator must confirm:

1. One primary lane is named.
2. Files/directories in scope are explicit.
3. Out-of-scope boundaries are explicit.
4. Acceptance evidence is testable.
5. Merge gate from p201 §5 is known.
6. No Stop-The-Line issue blocks the work.
7. No active agent is already touching the same files or migration surface.

Parallelism limits while CI or compliance is unstable:

| Lane | Max active implementation branches | Rule |
|---|---:|---|
| Foundation | 1 | Serialize migrations/RPC/RLS. |
| Frontend | 1-2 | Only if file ownership does not overlap. |
| MCP/AI | 0-1 | Pause new AI/video work while LGPD/consent gates are unresolved. |
| Governance | 2 | Safe for docs, specs, registry, ADRs. |
| Infra/Security | 1 | One CI/auth/Cloudflare fix at a time. |
| QA | 1 | Tests/smoke only; avoid rewriting app behavior. |

---

## 4. Curator Pass Checklist

For each open issue reviewed, record one of these outcomes:

- **Keep:** status remains correct.
- **Promote:** issue is now dispatchable or higher risk.
- **Demote:** issue is broader or more blocked than it appeared.
- **Split:** parent issue needs ready-leaf children.
- **Close candidate:** evidence suggests issue can close.
- **Comment needed:** GitHub issue needs curator context.

Minimum registry fields:

| Field | Required? | Notes |
|---|---|---|
| Issue | Yes | GitHub number. |
| Registry status | Yes | One of the approved statuses. |
| Lane | Yes | Use p201 lane names. |
| Blocks | Yes | Use `none` when empty. |
| Blocked by | Yes | Issue number, external decision, or `none`. |
| Acceptance evidence | Yes | Test, smoke, log, query, screenshot, or docs artifact. |
| Close rule | Yes | What must be true to close. |

---

## 5. Handoff To Claude Code

When handing work to Claude Code/dev, provide this block:

```md
Issue:
Registry status: ready-leaf
Lane:
Branch/worktree:
In scope:
Out of scope:
Acceptance evidence:
Required gate:
Known blockers:
Do not touch:
Handoff expected:
```

Rules:

- Do not hand off parent trackers as implementation tasks.
- Do not assign a branch that mixes Foundation + Frontend unless the registry explicitly documents the exception.
- Do not let Claude Code close an issue based only on local intuition. Require the registry close rule.
- If a dev agent discovers new scope, it must stop and report back; the curator updates the registry before more implementation.

---

## 6. Close Rules

An issue can close only when its registry close rule is satisfied.

Common close rules:

- **Bug:** reproduction path fixed + regression test or smoke evidence.
- **CI:** local reproduction fixed + remote CI green + main heartbeat recovered.
- **Docs:** source updated + rendered page/source link verified + no count drift.
- **MCP:** `tools/list` or discovery endpoint verified + smoke call + docs/matrix updated.
- **SQL/RPC:** migration applied or ready + rollback documented + `check_schema_invariants()` clean + RPC smoke.
- **QA window:** production smoke passed for the affected route/workflow.
- **Spec-only:** child ready-leaf issues created or PM explicitly decides to retain parent tracker.

If evidence is missing, use `close-candidate`, not closed.

---

## 7. Issue Registry Hygiene

Keep `ISSUE_REGISTRY.md` small enough to operate.

Recommended sections:

1. Stop-The-Line
2. QA Window
3. Spec Trackers
4. Ready Or Near-Ready Leaves
5. Program Clusters
6. Dispatch Rules

Archive stale detail into audit docs. The registry should answer: “what can safely move now?”

Update `Last updated` when:

- a status changes;
- a new issue is added;
- a close rule changes;
- a blocker is added/removed;
- evidence moves from pending to validated.

---

## 8. Decision Log Pattern

When a registry decision changes execution order, comment on the GitHub issue with:

```md
Curator registry update:

- Status:
- Lane:
- Blocks / blocked by:
- Acceptance evidence:
- Close rule:
- Dispatch decision:
```

Use this especially for:

- `qa-window` issues kept open after merge;
- `blocked` issues that developers may otherwise pick up;
- Stop-The-Line issues;
- parent trackers being split into leaves.

---

## 9. Current Operating Stance

As of 2026-05-21:

- Claude Code/dev owns implementation leaves.
- Codex/curator owns registry, issue context, handoffs, evidence review, and governance docs unless explicitly asked to implement.
- #221 remains a compliance blocker for new AI/video work until resolved or decomposed.
- #234 is a post-deploy observation issue: do not over-audit MCP refresh before the updated OAuth metadata is deployed and observed.
- #224 is implementation-ready, but should stay with the dev lane if Claude Code is already assigned.
