---
issue: 159
title: gov - p201 parallel agent operating model
lane: Governance
priority: P1
effort: S (mostly done; needs PM ratification)
status: done
opened: 2026-05-19
github: https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/159
---

# p201 Session Brief - Issue #159: Parallel Agent Operating Model

## Why this brief exists

This issue is the meta-governance work that legitimises every other p201
session. Without an accepted operating model, parallel agents have no
shared definition of lanes, gates, or handoff format. Most of the work
already shipped in `docs/project-governance/P201_PARALLEL_AGENT_ROADMAP.md`
(commit `9c4a01db`). What is left is PM ratification + minor process
fixtures (issue template, label hygiene, sprint closure routine link).

## Context to read first

- `docs/project-governance/P201_PARALLEL_AGENT_ROADMAP.md` (canonical proposal)
- `docs/project-governance/PROJECT_GOVERNANCE_RUNBOOK.md` (current governance)
- `docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md`
- `AGENTS.md` and `.claude/agents/platform-guardian.md`

## Lane and gates

- Lane: Governance (no app behaviour change)
- Can touch: `docs/`, `.github/ISSUE_TEMPLATE/`, `AGENTS.md`, label config
- Can't touch: source code, SQL, MCP, Cloudflare
- Mandatory gates: PM signoff before adopting any rule that changes how
  other lanes work; no force-push or label deletion without PM go-ahead

## In scope

1. PM ratification of the lane model, mandatory handoff format, and merge
   gates in `P201_PARALLEL_AGENT_ROADMAP.md` §3-§5.
2. GitHub issue template that requires lane + acceptance criteria fields.
3. Label audit: ensure every lane has matching labels
   (`mcp-server`, `infrastructure`, `governance`, `data-integrity`, `ux`,
   `audit`, `documentation` already exist; verify coverage for Foundation
   and Frontend lanes; add if missing).
4. Sprint closure routine update so the parallel-agent model is referenced
   in `SPRINT_IMPLEMENTATION_PRACTICES.md`.
5. Definition-of-done checklist (5-8 bullets) printed in the issue template.

## Out of scope

- Implementing any of the issues #160-#166 (each has its own session).
- Reorganising the council or sub-agent definitions in `.claude/agents/`.
- Rewriting `AGENTS.md` beyond a small reference paragraph.

## Files likely to touch

- `docs/project-governance/P201_PARALLEL_AGENT_ROADMAP.md` (status -> Adopted)
- `docs/project-governance/PROJECT_GOVERNANCE_RUNBOOK.md` (reference link)
- `docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md` (link parallel model)
- `.github/ISSUE_TEMPLATE/` (new task template with lane field) - check if dir exists
- `AGENTS.md` (one-paragraph reference to the operating model)

## Recommended approach

1. Read the roadmap doc and verify nothing has drifted since 2026-05-19.
2. Open a PR that flips the doc's `Status:` to `Adopted` plus the small
   process fixtures above.
3. Reference this PR from every subsequent parallel-agent session brief.
4. Avoid creating new abstractions; keep the model as-is unless PM wants
   to amend.

## Validation

- `git diff` shows only docs / issue template changes.
- All listed P1/P2 issues already use labels declared in the roadmap.
- `gh issue list --label "governance"` shows #159 plus the other
  governance-relevant issues, none orphaned.

## Rollback

- Revert PR. No DB/RPC/Worker/EF artifacts to undo.
- Issue template rollback: delete file under `.github/ISSUE_TEMPLATE/`.

## Cross-references

- `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md` (audit that opened this)
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` (operational backlog format)

## Handoff (fill on completion)

```md
## Handoff

Issue: #159
Branch: agent/issue-159 (worktree em /home/vitormrodovalho/projects/ai-pm-issue-159)
Escopo: PM ratification + 5 process fixtures conforme brief §In scope. Docs-only, zero source/SQL/MCP.
Arquivos:
  - docs/project-governance/P201_PARALLEL_AGENT_ROADMAP.md (Status Proposto → Adopted + mapping Lane→Label + promotion rule PM addendum)
  - .github/ISSUE_TEMPLATE/parallel_agent_task.yml (novo template: lane dropdown + acceptance + DoD 6-bullet + handoff format ref)
  - docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md (nova seção "Execução Paralela por Agente (p201)" linkando roadmap)
  - AGENTS.md (parágrafo "Parallel-agent operating model (p201)" referenciando roadmap; tabela "Agent team structure" preservada)
  - docs/project-governance/PROJECT_GOVERNANCE_RUNBOOK.md (item 9 em "Para começar a trabalhar" linkando roadmap)
Validação:
  - git diff: 4 docs modificados + 1 issue template novo = scope adherence brief §Lane and gates
  - Roadmap §3-§5 verificado intacto (6 lanes / 9 handoff fields / 6 gate tipos)
  - gh issue list --label governance: #166/#165/#161/#160/#159/#157/#156/#132/#106/#97/#90 todas labeladas; #148 (CI Monitor) único orphan e não é parallel-agent
  - Build/test/lint NÃO executados — mudanças docs-only sem código tocado
Riscos:
  - Baixo. Documentação não muda comportamento de aplicação. Risco residual: promotion rule de labels pode ficar dormente se ninguém revisitar pós-1 sprint — gerenciado pelo PM via observação de friction triage.
Rollback:
  - Revert PR. Sem DDL/Worker/EF artifacts pra desfazer.
  - Issue template rollback: rm .github/ISSUE_TEMPLATE/parallel_agent_task.yml
Docs:
  - Roadmap p201 promovido a Adopted; template novo; SPRINT_IMPLEMENTATION_PRACTICES + AGENTS + RUNBOOK linkam roadmap.
  - Backlog log NÃO atualizado nesta sessão (nenhum GAP/OPP novo identificado; brief executado integralmente conforme escopo).
Próximo passo:
  - PR open via agent/issue-159 → main com este Handoff no description.
  - Pós-merge: cada session brief subsequente (#160-#166) referencia o roadmap Adopted via link.
  - Pós-1 sprint: PM avalia promotion rule de labels (lane:* dedicado se ambiguidade atrapalhar triagem).
```
