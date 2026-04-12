---
name: guardian
description: Invoca o Refactor Guardian para auditar o estado do Domain Model V4 refactor. Use no início e fim de qualquer sessão que tocar o refactor.
user_invocable: true
---

Invoke the Refactor Guardian agent to audit the current state of the Domain Model V4 refactor.

The guardian will:

1. Read `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` to determine the current phase
2. Verify refactor invariants (npm test baseline, astro build, MCP smoke, stable features, migrations have org_id post-Phase 1)
3. Check ADR integrity — no Accepted ADRs edited without a new ADR
4. Inventory code changes since `pre-v4-baseline` tag via `git diff --name-only`
5. For each Accepted ADR, grep for evidence of acceptance criteria fulfilled
6. Propose a diff to update `DOMAIN_MODEL_V4_MASTER.md` (do not edit directly)
7. Report drift between ADRs and code
8. Recommend: can we proceed to next phase, or blockers remain?

Output format is a structured report defined in `.claude/agents/refactor-guardian.md`.

Usage: invoke the agent via the Agent tool with subagent_type `general-purpose` and point it at `.claude/agents/refactor-guardian.md` for instructions. Pass the user's current goal (starting a session / ending a session / smoke check) as context.

The guardian NEVER edits files — it only reads, greps, and proposes diffs. It NEVER runs deploy or destructive commands. It prioritizes blocking over silently proceeding if any invariant is unclear.
