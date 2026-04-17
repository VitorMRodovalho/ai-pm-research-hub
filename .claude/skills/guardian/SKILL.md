---
name: guardian
description: Invoca o Platform Guardian (pós-V4) para auditar invariantes estruturais da plataforma, detectar drift entre docs e código, verificar cobertura ADR de mudanças recentes, e propor novos itens de backlog. Use no início/fim de sessão que toque SQL/RPC/MCP ou como smoke check periódico. Para referência histórica do refactor V4 (concluído 2026-04-13), veja `.claude/agents/refactor-guardian.md`.
user_invocable: true
---

Invoke the **Platform Guardian** agent (`.claude/agents/platform-guardian.md`) to audit the current state of the platform.

The guardian will:

1. **Live DB invariants** — run `check_schema_invariants()` via Supabase MCP. 8 invariants, expected 0 violations each. Any ≠ 0 blocks.
2. **Build & tests baseline** — report commands the human should run (guardian doesn't run deploy/destructive commands)
3. **ADR-0011 compliance** — grep recent migrations for hardcoded role lists in SECURITY DEFINER RPCs (should use `can()`/`can_by_member()`)
4. **ADR-0012 compliance** — new cache columns without sync triggers → flag
5. **Docs drift** — CLAUDE.md metrics vs real (MCP tool count, EF count, test count, version)
6. **ADR coverage** — recent migrations lacking backing ADR for structural changes → flag
7. **Backlog inventory** — propose new items for `memory/project_issue_gap_opportunity_log.md`
8. **Memory freshness** — check `MEMORY.md` index reflects latest session

Output format is a structured report defined in `.claude/agents/platform-guardian.md`.

Usage: invoke the agent via the Agent tool with subagent_type `general-purpose` (or any subagent capable of Read/Glob/Grep/Bash) and point it at `.claude/agents/platform-guardian.md` for instructions. Pass the user's current goal (starting a session / ending a session / smoke check) as context.

The guardian NEVER edits files — it only reads, greps, and proposes diffs. It NEVER runs deploy or destructive commands. It prioritizes blocking over silently proceeding if any invariant is unclear.

## Legacy / historical

For the V4 refactor in-progress period (2026-04-11 → 2026-04-13), the predecessor was `.claude/agents/refactor-guardian.md`. That agent covered specific phase-gating invariants for ADRs 0004-0009 during the 7-phase refactor. Kept as historical reference. Do NOT invoke refactor-guardian for new work — use platform-guardian.
