# Decision — #579 governance-body hardening (build + ship)

**Date:** 2026-06-08
**Type:** PM-decision (build) + council-on-draft
**Outcome:** Shipped. PR #595 squash-merged to `main` (`0e2a83b0`), EF `nucleo-mcp` deployed, migration `20260805000133` live. 0 `--admin`. #579 CLOSED.

## Options presented (session "go")
Head of the PM-agreed hardening/follow-up sequence (from the #580 handoff). Grounded BEFORE presenting:
1. **#579** governance-body hardening — grounded REAL: `get_governance_document_reader` had a live `anon=X` grant; **21/42 (50%)** locked `document_versions` contain nested `<ul>/<ol>` that the shipped `get_governance_document_body` MCP tool flattened/garbled; **0** bodies use `data:`/external-img URIs (→ that sub-item scoped out).
2. #592 a11y expand-button (LOW, frontend polish).
3. #591 #577 follow-up (drill-down breakdown; toggle-persistence half PostHog-gated).
4. #587 batch link N+1 (issue says "not urgent").

## Recommendation (PL/CTO) + rationale
**#579**, scoped to: nested-list md fidelity + REVOKE anon + live E2E + toolBlock sentinel; **drop** the data:-URI item (0 rows in prod). Rationale: grounding promoted it from "polish" to a **live correctness fix** (50% of governance bodies served garbled to the LLM/MCP consumer by a tool shipped the prior day) + a confirmed-live security-hygiene REVOKE (same #485/#564/#567 sediment class); self-contained for a clean session (migration + EF + tests + deploy). **PM chose #579.**

## Build
- **`governance-html.mjs`**: replaced the non-greedy `listItemsToMd` (couldn't balance nested lists) with a balanced, recursive converter (`findListClose` / `splitTopLevelLi` / `splitItemContent` / `renderList` / `replaceTopLevelLists`). Nested lists indent CommonMark-correct (parent marker width per level). Rendered blocks stashed into NUL-delimited tokens so the whitespace-collapsing pass can't flatten indentation. Multi-`<p>` items → marker line + indented continuation lines; bare text either side of a nested list keeps word spacing. `sanitizeGovernanceHtml` strips HTML comments (prompt-injection channel) — **each removal looped to a fixpoint** (reveal-safe).
- **migration `20260805000133`**: `REVOKE EXECUTE … FROM anon` (+ PUBLIC) on the reader RPC. Root cause: the defining migration revoked PUBLIC but Supabase `ALTER DEFAULT PRIVILEGES` grants `anon` directly → residual.
- **test (`459-…`)**: `toolBlock()` bounds by next generic `mcp.tool(` + success-path tail sentinel; 35 → 44 tests.

## Council-on-draft (pre-apply) — Workflow `wf_bb67c6fd-6d4`
4 reviewers (code-reviewer, senior-software-engineer, security-engineer, ai-engineer): **4/4 GO_W_FIXES, 0 NO_GO, 0 blocker.** Folded: multi-`<p>` merge (MEDIUM), text-both-sides no-space join, HTML-comment strip, toolBlock tail-sentinel, migration NOTIFY note. Documented-not-changed (degenerate/impossible-in-TipTap): empty-`<li>` bare marker, unbalanced-list graceful degradation, greedy unquoted-handler over-strip.

## CodeQL fix-forward (3 iterations, NOT bypassed)
CodeQL flagged `js/incomplete-multi-character-sanitization` (HIGH). Restructuring `sanitizeGovernanceHtml` surfaced the pre-existing single-pass script/style/handler removals (latent incomplete-sanitization). Learned: CodeQL recognizes a **single-replace** `do { p=s; s=s.replace(re) } while (s!==p)` as complete, but NOT a multi-replace chain inside one loop → looped each removal individually. All checks green after.

## Verification (live)
- Build exit 0 · full DB-aware suite **3687/3687, 0 fail**.
- Converter proven on the real R2 manual "Índice" body + adversarial stress (5000 items 8ms, 200-level 16ms, no ReDoS/loop/throw; malformed → graceful flat text).
- Migration E2E: anon **denied** (`insufficient_privilege`); impersonated active member still gets the full 41KB body; ACL now `{postgres, authenticated, service_role}`.
- EF smoke: `/health` 308+4, `initialize` 200, `tools/list` 308.

## Refs
Issue #579 · PR #595 · #459 (parent) · `governance-html.mjs` · `20260805000133_p579_governance_reader_revoke_anon.sql`
