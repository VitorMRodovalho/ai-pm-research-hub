# p126 E3 Reduced Scope Synthesis — PM as Product Lead

**Date:** 2026-05-09
**Sessão:** p126 (continuation post E2 ship)
**Predecessor:** p126 E2 commit 193f560
**Successor:** Wave 4 = PM accepts → commit + push → handoff p127 (clean restart for E3 full scope)

## Why reduced scope (PM Decision Opção C)

Full E3 scope includes:
- Issue A: Calendar webhook deploy (Apps Script auth chain) — **DEFERRED** (operational, requires Google Workspace coordination)
- Issue B: schedule_interview gate fix — **DEFERRED** (10 active candidates affected; remediation requires PM decision)
- Issue C: is_returning_member fix — **APPLIED** (backfill SQL only; RPC patch deferred)
- Issue D: end_date backfill — **DELEGATED** (worker E2 setEngagementEndDateSource handles; Hotfix Wave 0 already covers 36/94)
- Issue E: 10 interview-no-score audit — **DIAGNOSED** (manifestation of Issue B; documented; remediation deferred)
- Decision 4 cycle freeze EF logic — **APPLIED**
- Decision 9 cron deploy — **DEFERRED** (chapter VP coordination async)

**Reduced scope rationale**: ship non-deploy items now (low-risk, immediate value); defer deploy-dependent items to clean E3 full scope session p127+ when chapter VP coordination async unblocks.

## Items APPLIED (this session)

### 1. Issue C is_returning_member backfill (Migration 8)
- File: `supabase/migrations/20260518080000_p126_e3_returning_member_engagement_backfill.sql`
- SQL UPDATE flagging active-engagement returning candidates as `is_returning_member=true`
- Predicate: matched member has `engagements.status='active' AND kind LIKE 'volunteer%'`
- Catches João Coelho's case (cycle 2 cohort active 2026-03-05) + any similar
- Audit log entry registered in `admin_audit_log`
- **NOT applied**: import_vep_applications RPC body patch (deferred — risk noted in handoff)

### 2. ai_processing_log.prompt_version column (Migration 9)
- File: `supabase/migrations/20260518090000_p126_e3_ai_processing_log_prompt_version.sql`
- ALTER TABLE ADD COLUMN with default `'v1-cycle3'`
- Audit trail for Decision 4 cycle freeze (LGPD Art. 8 §6)
- ai-engineer Wave 2 E2 BLOCKER pré-Cycle 4 — closed

### 3. pmi-ai-triage EF cycle freeze logic
- File: `supabase/functions/pmi-ai-triage/index.ts`
- Added `cycle_id` to `SELECT_COLS` + `AppRow` interface
- New `resolvePromptVersion(sb, cycleId)` function with `CYCLES_FROZEN_V1` Set
- Logs `prompt_version` on every `ai_processing_log` INSERT
- COMMENT documents Decisions 3, 4, P3 (profile_about_me + is_open_to_volunteer NEVER em prompt)
- V2 enriched prompt deploy: scaffold present, actual implementation deferred to Cycle 4 launch (Decision S12)

### 4. Issue E diagnostic
- File: `docs/strategy/p126_issue_e_diagnostic.md`
- Documented 10 affected candidates (all in cycle3-2026-b2)
- Confirmed Issue E = symptom of Issue B (booking gate bypass), not separate
- 4-step remediation plan prepared for E3 full scope p127+
- PM decision needed on whether to re-schedule or let proceed

## Items DEFERRED to E3 full scope (next session)

| Item | Reason for deferral | Tracking |
|---|---|---|
| Issue A — Calendar webhook deploy | Apps Script auth chain + Google Workspace coordination | T-3 + handoff p127 |
| Issue B — schedule_interview gate fix | Affects 10 active candidates; needs gate_attempts_log audit + PM decision | ISS-p126-E |
| Issue D — end_date backfill | Worker E2 `setEngagementEndDateSource` handles + Hotfix Wave 0 covers 36/94 | Auto via /ingest re-run pós deploy |
| Cron compliance D-60/D-30/D-7 | Chapter VP coordination (Decision 9 dry-run staging) | T-3 + chapter VP outreach via Ivan |
| import_vep_applications RPC patch (Issue C body) | Drift risk if /ingest re-runs antes do RPC patch | Add to E3 full scope p127 first migration |

## Compile/test status

- **TypeScript** (worker): clean (`npx tsc --noEmit` zero errors after E2)
- **Deno EF**: not formally tested in this session; pmi-ai-triage edits are minimal (4 small additions to existing structure); production deploy will smoke
- **Migration application**: NOT applied to prod (apply gate per ADR-0076 Princípio 11)

## Files touched this iteration

| File | Wave 1 / Wave 3 (this iteration) |
|---|---|
| `supabase/migrations/20260518080000_p126_e3_returning_member_engagement_backfill.sql` | NEW |
| `supabase/migrations/20260518090000_p126_e3_ai_processing_log_prompt_version.sql` | NEW |
| `supabase/functions/pmi-ai-triage/index.ts` | MODIFIED (cycle_id + prompt_version + Decision 4 logic) |
| `docs/strategy/p126_issue_e_diagnostic.md` | NEW (diagnostic, no code) |
| `docs/council/p126_e3_reduced_synthesis.md` | NEW (this synth) |

## Approval status

- Wave 1 PM drafts complete (no Wave 2 council review for reduced scope — minimal surface)
- TypeScript compiles clean
- E3 reduced scope ready for commit + push

**Wave 2 council deferred**: reduced scope is ~150 lines of net-new logic (vs E1's 2818 lines + E2's 727 lines). Council parallel review for that scope = diminishing returns. Full E3 next session WILL have Wave 2 (4 agents per p125 mapping).

## Handoff to p127

After this commit + push, sessão p126 closes. p127 starts CLEAN with:
- ADR-0076 status `Proposed` (still pending Ivan async sign-off)
- E1+E2+E3-reduced shipped to GitHub
- E3 full scope (Issue A + Issue B + cron + RPC patch) as next entregável
- E4a CSV waiting on age_band audit (T-5, Ivan deadline 30/Jun/2026)

Next session boot prompt updated em `memory/next_session_prompt.md`.
