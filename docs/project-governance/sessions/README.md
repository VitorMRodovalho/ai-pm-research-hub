# p201 Parallel Agent Session Briefs

**Created:** 2026-05-19
**Source roadmap:** `../P201_PARALLEL_AGENT_ROADMAP.md`
**Source audit:** `../../audit/P201_MCP_ARCHITECTURE_AUDIT.md`

Each brief in this directory is **self-contained**: a fresh session or
agent in a separate worktree should be able to start from the brief
alone without first reading the audit or roadmap. The briefs follow the
mandatory handoff format defined in §4 of `P201_PARALLEL_AGENT_ROADMAP.md`.

## How to use a brief

1. Pick a brief from the table below whose `status` is `ready` or
   `partial-done`.
2. Create a worktree on a feature branch:
   ```bash
   git worktree add ../ai-pm-issue-<N> -b agent/issue-<N>
   cd ../ai-pm-issue-<N>
   ```
3. Read the brief end-to-end. Confirm `Lane and gates` constraints.
4. Implement only `In scope`. If you discover `Out of scope` work that
   blocks completion, open a new issue rather than expanding the brief.
5. Run the `Validation` steps before opening the PR.
6. Fill the `Handoff` block at the bottom of the brief and append it to
   the PR description.

## Briefs

| Brief | Issue | Lane | Priority | Status | Notes |
|---|---|---|---|---|---|
| [p201_issue_159_governance_operating_model.md](p201_issue_159_governance_operating_model.md) | [#159](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/159) | Governance | P1 | done | Adopted 2026-05-19 (p202) — PM ratified + 5 process fixtures shipped |
| [p201_issue_160_herlon_authority_state.md](p201_issue_160_herlon_authority_state.md) | [#160](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/160) | Foundation + Governance | P1 | ready | Decision A/B/C required before SQL |
| [p201_issue_161_ui_gates_audit.md](p201_issue_161_ui_gates_audit.md) | [#161](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/161) | Frontend + Foundation | P1 | partial-done | Curatorship hotfix shipped; full inventory remains |
| [p201_issue_162_mcp_293_contract_matrix.md](p201_issue_162_mcp_293_contract_matrix.md) | [#162](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/162) | MCP/AI | P1 | done | Resolved 2026-05-19 (p202) — scripts/audit-mcp-tool-matrix.mjs + 293-row matrix MD+JSON; runtime drift=0; spot-check 3/3 PASS |
| [p201_issue_163_cloudflare_bic_mcp_oauth.md](p201_issue_163_cloudflare_bic_mcp_oauth.md) | [#163](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/163) | Infra/Security | P1 | done | Resolved 2026-05-19 (p202) — Rule 1 skip-BIC + Rule 2 rate limit live; 4-path smoke + 120-req burst test PASS |
| [p201_issue_164_local_supabase_qa.md](p201_issue_164_local_supabase_qa.md) | [#164](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/164) | Infra/Security + QA | P1 | done | Resolved 2026-05-19 (p202) — Path C: split baseline RPCs to 20260723000000_*after_schema + docs/operations/LOCAL_QA.md runbook; audit #39 closed |
| [p201_issue_165_release_backfill.md](p201_issue_165_release_backfill.md) | [#165](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/165) | Governance | P1 (docs) | partial-done | Minimal backfill shipped; richer reconstruction remains |
| [p201_issue_166_semantic_layer_roadmap.md](p201_issue_166_semantic_layer_roadmap.md) | [#166](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/166) | Foundation + Governance | P2 | done | Resolved 2026-05-19 (p202) — roadmap Adopted + 5 ADRs scaffolded (0088-0092 Proposed); zero schema/RPC; GC-147 + audit #29/#34/#38 closed |

## Suggested execution order (low coupling first)

1. **#159** - ratify operating model (unblocks everything else)
2. Parallel after #159 ratified:
   - **#162** (MCP matrix) - independent, upstream for #166
   - **#163** (Cloudflare BIC) - independent infra
   - **#164** (local QA) - independent infra
   - **#165** (release backfill) - independent docs
3. **#160** (Herlon) - needs PM decision; can run before or after the
   above
4. **#161** (UI gates audit) - benefits from #160 path being decided
   (Herlon UX path C touches the same surfaces)
5. **#166** (semantic layer) - depends on #162 output

## Coupling and conflicts

- #160 and #161 touch overlapping UI surfaces; coordinate sequencing
  to avoid merge conflicts in `*Nav*.astro` and engagement card
  components.
- #162 and #166 both touch `docs/audit/P162_GAP_OPPORTUNITY_LOG.md`
  closure entries - merge in order.
- #163 has zero code coupling but does require a synced Cloudflare
  account session.
- #164 is independent unless #162 audit catches a new migration drift
  that needs local reproduction.

## Mandatory gates (recap from §5 of the roadmap)

| Change type | Minimum gate |
|---|---|
| SQL/RPC/RLS | `check_schema_invariants()`, RPC smoke, migration + rollback, `NOTIFY pgrst` when signature changes |
| Frontend | lint on file, `npm run build`, route smoke when route changes |
| i18n | three dictionaries updated |
| MCP | `tools/list` + `/health`, tool smoke, no new failures in `mcp_usage_log` |
| Cloudflare | Security Events before/after, Ray ID, rule documented |
| Docs | links valid, no count drift against canonical pins |

## Handoff format

Every PR must include this block in its description:

```md
## Handoff
Issue:
Branch:
Escopo:
Arquivos:
Validacao:
Riscos:
Rollback:
Docs:
Proximo passo:
```

## Post-p201 task briefs

The p201 program ratified the parallel-agent operating model. Subsequent sessions
file task briefs into this same directory using the prefix `p<session>_issue_<N>_<slug>.md`
and the same self-contained format. They are NOT part of the p201 closure checklist
but reuse the lane + gates + handoff conventions defined in
`../P201_PARALLEL_AGENT_ROADMAP.md`.

| Brief | Issue | Lane | Priority | Status | Notes |
|---|---|---|---|---|---|
| [p207_issue_216_profile_ts_annotation_minify.md](p207_issue_216_profile_ts_annotation_minify.md) | [#216](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/216) | Frontend | P1 | ready | 3rd recurrence of TS-annotation × Vite minify trap; ~22 module-level annotations to strip in profile.astro + EN/ES variants + forward-defense backlog entry |

## Closing the program

The p201 program is done when:

1. All P1 issues are merged or have a deliberate carry decision recorded.
2. MCP contract matrix exists and is reexecutable.
3. Persona smoke covers Roberto, Sarah, Marcos, Herlon.
4. Cloudflare MCP bootstrap is validated without 1010.
5. Local QA strategy is documented (and `supabase start` either works or
   is explicitly not required).
6. Docs have no count drift against canonical pins.
7. Release/governance backfill is accepted.

See `../P201_PARALLEL_AGENT_ROADMAP.md` §8 for the canonical definition.
