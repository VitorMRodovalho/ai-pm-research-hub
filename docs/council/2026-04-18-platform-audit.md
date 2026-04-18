# Platform Audit — Council Tier 3 Sweep

**Date:** 2026-04-18 (D-10 pre-CBGPL)
**Scope:** Post ADR-0015 Phase 5 A2 (10 RPCs refactored). 4 parallel council agents dispatched: data-architect, security-engineer, ai-engineer, product-leader. legal-counsel deferred (IP docs are .docx, require conversion).
**Duration:** ~7 min parallel
**Participants:** 4 council agents + PM (Vitor) integrator

---

## Executive Summary

### Consolidated P0/P1 findings (must-act items)

| # | Severity | Finding | Agent | Owner |
|---|---|---|---|---|
| 1 | **P0** | `artifacts` table orphan with 7 active RPC readers (e.g. `vw_exec_funnel`) — Eixo B8-class silent stale data | data-architect | senior-software-engineer |
| 2 | **P0** | Zero automated persona coverage tests (12 personas, 0 tested end-to-end) | ai-engineer | senior-software-engineer |
| 3 | **P1** | `can()` + `can_by_member()` missing `SET search_path` — SECURITY DEFINER privilege escalation vector | security-engineer | security-engineer |
| 4 | **P1** | OAuth `redirect_uri` not allowlist-validated (`/src/pages/oauth/exchange.ts:60`) — open redirect / auth code interception | security-engineer | security-engineer |
| 5 | **P1** | 4 cache columns without sync trigger (ADR-0012 violation): `current_cycle_active`, `cpmai_certified`, `credly_badges`, `cycles` | data-architect | data-architect |
| 6 | **P1** | `members` table: 151K seq scans / 71 rows → RLS path re-scanning (O(n²) risk at scale) | data-architect | data-architect |
| 7 | **P1** | `get_comms_dashboard` + `get_research_pipeline` MCP tools missing `canV4` gate | ai-engineer | ai-engineer |
| 8 | **P1** | `nucleo-guide` prompt bug: `isComms = isLeader` and `isLiaison = isSponsor` conflate distinct roles | ai-engineer | ai-engineer |
| 9 | **P1** | `docs/council/decisions/` directory doesn't exist — Tier 3 output has nowhere to land | ai-engineer | PM |
| 10 | **P1** | Phase 5 A6 scope 5× larger than documented: **46 RPCs** (not 9), + `cycle_tribe_dim` MV + 5 views + `members_select_tribe_leader` policy break on DROP COLUMN | data-architect | data-architect |

### Consolidated P2 findings (should-act near-term)

- `active_members` view uses `SELECT *` — structural land mine for any new PII column in `members`
- `admin_audit_log` allows arbitrary `action` string on INSERT — audit integrity issue
- Curator persona has no MCP write tool (read-only workflow)
- Alumni + observer + candidate personas: near-zero dedicated tools/prompts
- Stale inline comment `index.ts:394`: "Register 68 tools (54R+14W)" vs actual 76 (61R+15W)
- `campaign_recipients.external_email` plaintext (no encryption counterpart like `phone_encrypted`)
- Multiple zero-scan indexes (dead weight)
- `vw_exec_funnel.members_with_published_artifact` = stale metric (reads frozen `artifacts` table)

---

## Product-Leader Recommendation (prioritization)

### Pre-CBGPL (D-10, 28/Abr)
1. **DEFER Phase 5 A3-A6** — finalizing 46 RPC refactors in D-10 introduces regression risk for demo. Current state (A1+A2 done, 10 RPCs refactored, V4 semantics propagated via `get_my_member_record`) is stable.
2. **Smoke test P0 flows** (attendance, gamification, roster, initiative pages) with real data 1 day before demo (27/Abr dry-run).
3. **Fix P1-security items before next deploy** (search_path + redirect_uri allowlist) — they don't block demo but open attack surface is higher now.
4. **Communicate with 5 PMI presidents** by 22/Abr (6 days before CBGPL, not on the day).
5. **Decide apply_migration MCP bug** (P2 open) — if only affects dev flow, keep deferred; if affects any demo path, P0.

### Post-CBGPL (30 days)
1. LIM abstract submission (1st week of May) — opportunity closing
2. CPMAI launch (communication by 5/Mai, public by 15/Mai)
3. Phase 5 A3-A6 completion (target 10/Mai, 3-5 sessions)
4. Council decision log population (start with retrospective of Tier 3 audit items → A/B/C decisions)

### Optionality impact (Trentim A/B/C)
- **A (PMI internal spinoff)**: CBGPL plants seed with presidents. Trentim 29/Abr meeting should include direct "next concrete step for Path A" question.
- **B (consulting)**: LIM + CPMAI + whitepaper pipeline. Each week of LIM delay closes submission window.
- **C (community-led)**: Already active via CBGPL expansion. No net-new decision required.

**Closure risk**: Not submitting LIM → closes B partially. Starting multi-chapter technical onboarding before validating interest → closes A. Launching CPMAI without formal IP agreement with Herlon/Pedro → ambiguity risk (flag for legal-counsel).

---

## Phase 5 A6 Pre-Drop Checklist (Updated)

Data-architect flagged the original scope of 9 writers + 4 triggers + 1 index was **incomplete**. Full list before `ALTER TABLE members DROP COLUMN tribe_id`:

1. **46 RPCs** reference `m.tribe_id` / `mb.tribe_id` / `members.tribe_id` (not 9). 10 done in A2. 36 remaining. Full list from data-architect analysis includes: get_tribe_event_roster, admin_get_tribe_allocations, send_attendance_reminders, mark_member_present, get_public_impact_data, get_pending_countersign, bulk_issue_certificates, get_public_leaderboard, exec_cycle_report, get_attendance_summary, get_board_members, calc_attendance_pct, detect_operational_alerts, mark_member_excused, get_attendance_grid, send_attendance_reminders_cron, update_onboarding_step, get_org_chart, admin_detect_data_anomalies, and ~25 others.
2. **`cycle_tribe_dim` materialized view** references `m.tribe_id` in current_tribes CTE — MUST rewrite to use `initiatives.legacy_tribe_id` before drop
3. **5 views break on drop**: `impact_hours_summary`, `members_public_safe`, `public_members`, `recurring_event_groups`, `active_members` all expose `tribe_id` from members directly
4. **`members_select_tribe_leader` RLS policy** (`/20260427030000_v4_phase4_1_rls_legacy_policies.sql:255-259`)
5. **4 triggers on `members`** (trg_a/b_sync, trg_refresh_dim, trg_sync_member_status)
6. **1 index `idx_members_tribe_active`** (auto-dropped by DROP COLUMN)

**Safe execution order**: (1) rewrite 36 remaining readers, (2) rewrite `cycle_tribe_dim` MV, (3) rewrite 5 views, (4) drop policy, (5) drop 4 triggers, (6) drop index, (7) DROP COLUMN.

Given scope 5× larger than initially estimated: **revise A3-A6 estimate from 3-5 sessions to 5-8 sessions**.

---

## New Invariants Proposed (data-architect)

| ID | Check | Severity | Covered in Phase 5 A6? |
|---|---|---|---|
| G_current_cycle_active_consistency | `members.current_cycle_active` must have matching `member_cycle_history` row | high | No — independent work |
| H_cpmai_certified_consistency | `members.cpmai_certified` must match certificates.credential_type='cpmai' | medium | No — independent work |
| I_artifacts_frozen | `COUNT(*) FROM artifacts WHERE created_at > '2026-04-13' = 0` | high | No — separate action needed |
| J_member_tribe_engagement_consistency | Pre-drop contract: tribe_id in members matches active volunteer engagement's initiative | high | **Yes — add before A6 drop** |

---

## Actionable Items Ranked

### This week (pre-CBGPL)
1. **[P1-security]** New migration: `ALTER FUNCTION public.can(...) SET search_path = 'public', 'pg_temp';` + same for `can_by_member()`
2. **[P1-security]** Validate OAuth `redirect_uri` against DCR-registered URI in `/src/pages/oauth/exchange.ts` and `/src/pages/oauth/token.ts`
3. **[P1-ai]** Add `canV4` gate to `get_comms_dashboard` + `get_research_pipeline` in `nucleo-mcp/index.ts`
4. **[P1-ai]** Fix `nucleo-guide` prompt: `isComms`, `isLiaison`, `isChapterBoard` must use distinct `canV4` actions, not aliases
5. **[P1-governance]** `mkdir docs/council/decisions/` — prevent first Tier 3 output bouncing

### Post-CBGPL (May)
6. **[P0-data]** Triage `artifacts` orphan — either resurrect with initiative_id or drop 7 readers + vw_exec_funnel metric
7. **[P0-tests]** Persona coverage test matrix — 12 personas × MCP end-to-end (target: automated in CI)
8. **[P1-data]** Cache column sync triggers for `current_cycle_active`, `cpmai_certified`, `credly_badges`, `cycles`
9. **[P1-data]** Phase 5 A3 — 36 remaining readers (5-8 sessions target)
10. **[P2-perf]** Investigate members seq-scan hotspot (151K scans / 71 rows) — likely RLS per-row re-scan

---

## Decision log entries (draft)

Per council README Phase 2 goal: populate `docs/council/decisions/` with 3-5 entries. Suggested first entries (from today's sweep):

1. `2026-04-18-defer-phase-5-pre-cbgpl.md` — Status: Accepted. Council: product-leader (recommend), data-architect (supports due to 5× scope increase).
2. `2026-04-18-p1-security-sweep.md` — Status: Proposed. Council: security-engineer (identified).
3. `2026-04-18-artifacts-orphan-triage.md` — Status: Proposed. Council: data-architect (identified).

---

## What didn't get reviewed this session

- **Legal-counsel IP doc review** — 5 docx files in `/home/vitormrodovalho/Downloads/A/` require conversion before review. Deferred.
- **ux-leader friction audit critical journeys** — already exercised during A2 C2 validation; no new sweep needed in same session.
- **accountability-advisor PMI governance** — to be invoked when Parte 3 (IP ratification workflow) is designed.

---

## Next session

Per PM directive, Parte 3 (IP ratification on-platform workflow planning) was planned but deferred due to context budget. Recommended structure:
- ux-leader + product-leader: workflow design (email → cadastro → DocuSign-like comments → curadores → líderes ciência → PMI-GO president approval → demais presidentes ciência)
- data-architect: schema (approval_chains, document_versions, signatures)
- legal-counsel: validate final text of 4 gov docs (v3) with Roberto's 2 pontos (software=direito autoral + conflito periódicos + INPI/Bib Nacional)
- accountability-advisor: define minimal audit trail

Document outcome should land in `docs/council/2026-04-18-ip-ratification-planning.md`.

---

## Appendix — Raw agent outputs

(Preserved in session log `memory/project_session_18apr_p28_phase5_a2.md` for reference.)
