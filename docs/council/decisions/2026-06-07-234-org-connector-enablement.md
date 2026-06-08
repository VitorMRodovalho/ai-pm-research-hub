# Decision — #234 MCP connector: Option B (org/team connector) enablement + scope of the platform-side work

**Date**: 2026-06-07
**Decider**: PM (Vitor) — Option B recorded 2026-06-06 (#234 comment); platform-scope decisions this session by PL/CTO under the working agreement
**Domain**: MCP / connector distribution (#234)
**Status**: DECISION standing (Option B) · platform-side work SHIPPED this session · residual = PM/admin UI action + member smoke

## Context

#234 = "stabilize MCP connector refresh and evaluate official Claude listing." Two workstreams: **A** (short-term
stabilization of OAuth refresh) and **B** (medium-term distribution path). Decision was already taken by the PM on
2026-06-06 in the issue comment: **Option B — publish as an org/team connector**; Option C (public Claude Connectors
Directory) explicitly **not** chosen.

This session ("go", clean post-`/clear`) treated #234 as **build-ready** (per the working agreement: items past
decision don't need another decision round). The job: finish everything the platform side can deliver and hand the
PM a tight, evidenced residual.

## Grounding (live, 2026-06-07 — before any conclusion)

- Open issues **61**; schema invariants **0**; `7192b01e` (refresh-scope hotfix) confirmed **in `main`**.
- OAuth metadata **live**: `grant_types_supported=[authorization_code, refresh_token]`,
  `scopes_supported=[mcp:tools, offline_access]` on **both** well-known endpoints.
- Runtime `/mcp` **308**, `/semantic` **4** (v0.2.0); deployed `/docs/mcp` renders manifest total **312** (= 308+4) —
  the stale "293" the issue cited is gone.
- Refresh **code path** read first-hand + adversarially reviewed (security-engineer): proxy auto-refresh + token
  endpoint KV store are **real**; 30-day KV TTL. Verdict: `complete_with_caveats`.

## Platform-side decisions taken this session (PL/CTO)

1. **No Worker deploy / no code change in this PR.** `/docs/mcp` already shows the current count (criterion #4 MET
   live), and the PM framed Workstream A as done ("ops/admin, not a code change"). Keeping it docs-only minimizes risk.
2. **Refresh-rotation hardening → tracked follow-up, not this PR.** The security-engineer surfaced a MEDIUM-labelled
   robustness gap (proxy KV re-store gated on `if (data.refresh_token)`, missing the `|| oldToken` fallback that
   `oauth/token.ts:81` already has). First-hand assessment: **defensive-only** — Supabase echoes a new refresh token
   on every successful rotation, so the realistic 7-day path is unaffected. It deserves its own focused Worker-deploy
   PR + OAuth smoke, not bundling into a docs PR. Counter-rec to "fix it now" was declined on scope-discipline grounds.
3. **De-pin MCP tool counts (28 live-facing instances)** across READMEs ×3, AGENTS.md, SECURITY.md, SKILL.md,
   MCP_SETUP_GUIDE.md → `300+` / "full catalog" + a "query live" pointer. Ends the recurring per-session count-drift
   sediment. Historical records (changelog, council snapshots, audit archives) left untouched.
4. **Build the enablement package** `docs/MCP_ORG_CONNECTOR_ENABLEMENT.md` — connector metadata, PM org-settings
   steps, member OAuth smoke checklist, live Workstream-A evidence, acceptance-criteria status, and an Option-C
   (Directory) deferred stub.

## Acceptance criteria outcome

4 **MET** (OAuth metadata, docs relogin model, `/docs/mcp` count, decision recorded) · 1 **observational**
(7-day continuity — PM observes after the org reconnect) · 1 **N/A** (Directory submission checklist — Option C not
chosen). No platform/code criterion remains open.

## Residual (PM-only — issue stays OPEN as the Option-B tracker)

1. Add the server in Claude.ai **org connector settings** (metadata in the enablement doc §1/§3).
2. One non-admin **member OAuth smoke** (enablement doc §4).
3. Observe **7-day** continuity; then close #234.

## Follow-ups (backlog)

- Refresh-rotation hardening (own Worker-deploy PR) — filed this session as **#580**.
- `/mcp`→`/mcp/full` rename (#280) stays blocked on gate G19.

## Refs

- Enablement package: `docs/MCP_ORG_CONNECTOR_ENABLEMENT.md`
- Working agreement: `memory/working_agreement_decision_process_2026_06_07.md`
- Prior MCP decision: `docs/council/decisions/2026-06-07-mcp-wave2-get-operational-status.md`
