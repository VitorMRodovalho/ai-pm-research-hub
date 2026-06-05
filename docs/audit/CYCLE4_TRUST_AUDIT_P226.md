# Cycle 4 Selection Trust Audit — Handoff A (#292 Workstream 1, #251 read-only evidence)

**Sessão:** p226 (2026-05-23)
**Branch:** `agent/selection-cycle4-trust-audit`
**Scope:** Per #292 Handoff A — read-only SQL evidence pack for Henrique visibility, William dual-track, evaluation assignments, pending-RPC cycle selection, and UI filter hypothesis. **No writes.**
**Gate:** PM approves remediation split before any data/code fix.

## Executive Summary

The PM-reported symptoms in #251 are caused by **two confirmed code bugs** and **one data gap**, plus two reported symptoms that the audit could not reproduce in current state (likely stale UI or perception drift; need PM re-test).

| # | PM Symptom | Audit Finding | Severity | Disposition |
|---|---|---|---|---|
| 1 | "Henrique não aparece em /admin/selection cycle4" | Henrique IS in `selection_applications` + IS in `get_selection_dashboard('cycle4-2026')` payload (admin auth) + no default UI filter hides him | LOW | **Close-candidate** pending PM re-test with browser devtools |
| 2 | "William mostra 1 de 2 evals; Fabricio não vê" | William has 5 evals on leader (rejected) + 3 on researcher (interview_pending). Fabricio submitted 4 evals (2 obj + 2 lead_extra) on 2026-05-21 21:01 UTC, **2.5h BEFORE issue filed** | LOW | **Close-candidate** for William-specific scope; "Fabricio não vê pending" is a separate code bug (item 3+4 below) |
| 3 | "Fabricio não vê pending list" | **CODE BUG #1**: `get_my_pending_evaluations()` body `SELECT * INTO v_cycle FROM selection_cycles WHERE phase = 'evaluating' LIMIT 1;` has **no `ORDER BY`** — non-deterministic when 2+ cycles in `evaluating` phase | HIGH | **Foundation fix** ~30min |
| 4 | Same as #3 (deeper) | **CODE/WORKFLOW BUG #2** (overlaps #260): only **6 of 38 cycle4 apps** have a `peer_review_requested` notification. Dispatcher gate `consent_ai_analysis_at IS NULL OR ai_analysis IS NULL` blocks the other 32 apps. Pending-list relies on this notification → 32 cycle4 apps invisible to evaluators via formal flow | HIGH | **Foundation + Governance**, overlaps #260 Workstream 2 |
| 5 | (Not reported, surfaced by audit) | 19 of 38 cycle4 apps stuck in `screening` despite `objective_done=2` (complete). Includes Henrique + Francisleila (leaders) + 17 researchers. Status advance `screening → objective_cutoff` requires explicit step | MED | **Workflow gap**, audit `compute_pert_cutoff` advance path or PM `finalize_decisions` policy |
| 6 | (Not reported, surfaced by audit) | `selection_committee` for `cycle4-2026` = **0 rows**. Vitor + Fabricio are de-facto evaluators (via admin UI direct entry) but not formally registered | MED | **PM decision**: seed cycle4 committee |

## Live State (2026-05-23)

### Cycles in phase=`evaluating`

```text
cycle3-2026-b2 (id=d28313d4..., created 2026-04-01)
cycle4-2026    (id=08c1e301..., created 2026-05-09)
```

**Both `open` + both `evaluating`.** This is the precondition for code bug #1.

### `selection_applications` rows (#251 Task 1)

| Candidate | App ID | Cycle | Role | Status | linked_application_id | promotion_path | vep_status_raw |
|---|---|---|---|---|---|---|---|
| Henrique Diniz S. Silva | `bcc54dfc…` | cycle4-2026 | leader | **screening** | NULL | NULL | Submitted |
| William Junio (researcher) | `6187b0b2…` | cycle4-2026 | researcher | **interview_pending** | `97a6df7d…` | dual_track | Submitted |
| William Junio (leader) | `97a6df7d…` | cycle4-2026 | leader | **rejected** | `6187b0b2…` | dual_track | OfferNotExtended |

**All three rows present + correctly classified.** William dual-track linkage symmetric.

### Evaluation state (#251 Task 2)

**Henrique (4 evals submitted, all complete for leader):**
- objective by Vitor: 219 (2026-05-21 06:33)
- objective by Fabricio: 235 (2026-05-21 14:49)
- leader_extra by Vitor: 191 (2026-05-21 06:33)
- leader_extra by Fabricio: 210 (2026-05-21 14:49)

**William RESEARCHER (3 evals, complete for researcher):**
- objective by Vitor: 150 (2026-05-14 02:52)
- objective by Fabricio: 140 (2026-05-19 01:04)
- interview by Vitor: 62 (2026-05-13 23:54)

**William LEADER (5 evals, complete for leader; app rejected by VEP):**
- objective by Vitor: 150 (2026-05-13)
- objective by Fabricio: 178 (2026-05-21 21:01)
- leader_extra by Vitor: 60 (2026-05-14)
- leader_extra by Fabricio: 111 (2026-05-21 21:01)
- interview by Vitor: 62 (2026-05-13)

Fabricio's evals for Henrique (14:49) and William leader (21:01) both predate the issue filing (2026-05-21 23:40 UTC).

### Committee membership (#251 Task 3)

**Fabricio Costa (`fabriciorcc@gmail.com`):**
- cycle3-2026: `lead` (2026-03-14)
- cycle3-2026-b2: `evaluator` (2026-04-01)
- **cycle4-2026: NONE** ← data gap

**Cycle 4 committee total: 0 rows.**

### Notification dispatch (cross-ref #260)

For the 38 cycle4 apps:
- `peer_review_requested` notifications: **6 apps notified out of 38** (15.7% coverage)
- Total peer_review notifications ever sent: 12 (all in last 30d, this is the first cycle with any)
- For Henrique, William researcher, William leader: **0 notifications**

Dispatcher `dispatch_peer_review_invitations` requires:
```sql
IF v_app.consent_ai_analysis_at IS NULL OR v_app.ai_analysis IS NULL THEN
  RAISE EXCEPTION 'PEER_PRECONDITION: candidate has no AI analysis;
                   cannot dispatch peer review yet';
END IF;
```

This precondition gate explains the 32-app dispatch gap.

### UI filter logic (`src/pages/admin/selection.astro`)

Filters (defaults in italics):
- `filterRole` *= 'all'* — passes Henrique (role=leader)
- `filterChapter` *= 'all'* — skip
- `filterStatus` *= 'all'* — skip
- `filterVideo` *= 'all'* — skip
- `filterSearch` *= ''* — skip
- `filterHideDecided` *= true* — hides `[approved, rejected, cancelled, withdrawn, converted, waitlist]`. `screening` is **NOT in this list** → Henrique passes
- `filterMyEval` *= 'all'* — skip
- `filterHideShadowVep` *= true* — hides where `extra_flags.is_shadow_vep === true`. Henrique `is_shadow=false` → passes
- `filterInterviewToday` *= false* — skip
- Dual-track collapse only applies when `promotion_path === 'triaged_to_leader' && role_applied === 'researcher'`. Henrique has both NULL → passes

**Conclusion:** No default filter would hide Henrique. `currentCycleId` initial = `allCycles[0].id` (order from `get_selection_cycles`) but `loadDashboard()` called without cycle_code uses RPC default branch `SELECT id FROM selection_cycles ORDER BY created_at DESC LIMIT 1` → cycle4-2026 wins (created 2026-05-09 vs cycle3-2026-b2 2026-04-01). Picker syncs via `picker.value = cycle.id` after dashboard returns.

The only ways Henrique would NOT appear:
- (a) PM manually clicked role-toggle to "researcher" (hides leaders)
- (b) PM had cycle picker on cycle3-2026-b2 (not cycle4-2026)
- (c) Stale browser cache (Henrique row added 2026-05-21 03:07 UTC, ~20h before issue filed — should have refreshed unless browser session was older)
- (d) Search filter accidentally set

None of these are bugs. PM screenshot or devtools state at time of report would confirm.

### Status drift (audit-surfaced)

Cycle 4 status distribution:

| status | count |
|---|---|
| screening | 19 |
| interview_pending | 16 |
| rejected | 2 |
| objective_cutoff | 1 |

Of the 19 in `screening`:
- 2 leaders (Henrique, Francisleila Melo Santos) have `objective_done=2 + leader_extra_done=2` (full eval)
- 17 researchers have `objective_done=2` (full eval for researcher)
- All should advance to `objective_cutoff` or `interview_pending` per PERT cutoff calculation

The advance step requires either (a) `compute_pert_cutoff` cron (Mondays 13:00 UTC per p197c) + manual status update, or (b) PM-driven `finalize_decisions(p_cycle_id, p_decisions)`. Neither is documented as automatic.

## Root-Cause Classification (per #292 Handoff A exit gate)

### CODE FIXES (Foundation lane)

**A. `get_my_pending_evaluations()` cycle non-determinism (HIGH)**
- File: function body in DB (no migration file captures current state per Phase C drift — verify via `_audit_list_public_function_bodies()`)
- Fix: `SELECT * INTO v_cycle FROM public.selection_cycles WHERE phase = 'evaluating' ORDER BY created_at DESC LIMIT 1;`
- Optional: add `p_cycle_id uuid DEFAULT NULL` param to allow evaluator to pick a specific cycle when multiple are open
- ADR: probably none needed (bug fix preserving intent); contract test covering 2+ evaluating cycles
- Effort: XS (~30min)
- Risk: changes Fabricio's pending list NOW from possibly cycle3-2026-b2 → cycle4-2026 (could surface accumulated pending if any). Acceptable; aligns with PM intent.

**B. `dispatch_peer_review_invitations` AI-analysis precondition impact (HIGH, overlaps #260 Workstream 2)**
- 32/38 cycle4 apps unable to receive peer_review_requested due to AI analysis gate
- PM decision needed: is AI analysis a hard precondition (then audit why 32 apps lack consent / analysis), or should the dispatcher allow non-AI fallback (alternative pending signal)?
- Effort: dependent on PM decision
- Cross-ref: #260 Workstream 2 notification routing audit will likely surface same issue
- **Recommendation: bundle with #260 Workstream 2 dispatch** rather than separate issue

### DATA GAPS (Governance lane)

**C. cycle4-2026 selection_committee empty (MED)**
- 0 rows in `selection_committee` for `cycle_id = '08c1e301-9f7b-4d01-a13c-43ac7775c0f7'`
- Vitor + Fabricio are de-facto evaluators via admin UI direct entry
- PM decision: who should be on Cycle 4 committee? At minimum Vitor (lead) + Fabricio (evaluator), but PM may want more peer evaluators
- Fix: `manage_selection_committee(p_cycle_id, 'add', p_member_id, p_role)` MCP tool, no migration needed
- Effort: XS (~5min PM decision + 1-2 RPC calls)
- Note: even after seeding, code bug A still needed for pending list to work correctly

### WORKFLOW GAPS (PM decision)

**D. Status advance `screening → objective_cutoff` for 19 cycle4 apps (MED)**
- 19 candidates with complete objective evals stuck in screening
- May be intentional (PM batch-advances post-PERT-cutoff via `finalize_decisions`) or unintentional gap
- PM decision: should there be cron auto-advance, or keep manual?
- Effort: PM decision + maybe a small cron addition
- Cross-ref: #229 Phase 2 (leader_extra cohort separation) may also surface this when separating bands

### CLOSE-CANDIDATE (no action)

**E. Henrique visibility in /admin/selection (LOW)**
- Henrique IS in DB + IS in dashboard payload + no default UI filter hides him
- Disposition: ask PM for browser devtools snapshot OR re-test now. If still hidden, escalate to UI investigation; if visible, close.

**F. William "1 of 2 evals" report (LOW)**
- William researcher has 3 evals (2 obj + 1 interview, complete); leader has 5 evals (rejected app)
- Fabricio submitted evals 2.5h BEFORE issue filed → PM report may have been from older browser state
- Disposition: close-candidate; if PM disagrees with current state, share screenshot

## Proposed Remediation Issues (per #292 Handoff A: "split a remediation issue if needed")

1. **Issue: Fix `get_my_pending_evaluations()` cycle non-determinism** (Foundation, XS, HIGH)
2. **Issue: Seed cycle4-2026 selection_committee** (Governance, XS, MED) — needs PM decision on members
3. **Bundle with #260 Workstream 2: audit `dispatch_peer_review_invitations` AI-analysis precondition impact** (Foundation, overlaps existing #260 scope, HIGH)
4. **Issue: Audit status advance from `screening` for cycle4 (19 candidates)** (Foundation, MED) — bundle with #229 Phase 2 or separate
5. **Comment on #251: ask PM for browser devtools state on Henrique invisibility** (CLOSE-CANDIDATE pending re-test)

## Handoff to PM

- This audit is the Workstream 1 evidence pack per #292 Handoff A scope.
- No production writes were made during this audit.
- All findings are PII-redacted in the public #251 comment but documented in full in this internal doc.
- Per #292 acceptance criteria: root causes classified into data fix / code fix / PM decision / close-candidate; remediation split proposed.
- Recommended next dispatch (post-PM-review): code bug A (XS, HIGH, unblocks evaluator pending list immediately).

## Cross-references

- #251 — original bug report
- #292 — P0 Selection Reliability Sprint umbrella
- #260 — selection notification routing (overlaps with code bug B)
- #229 — leader_extra Phase 2 (may overlap with status advance audit)
- `get_my_pending_evaluations()` — RPC body inspected via `pg_proc`
- `get_selection_dashboard(text)` — RPC body inspected, dashboard payload tested with admin auth
- `src/pages/admin/selection.astro` — filter logic lines 1230-1290; cycle picker init lines 4283-4340

---

*Audit conducted by Claude under PM direction. Branch: `agent/selection-cycle4-trust-audit`. Sessão: p226. No writes performed. All evidence read-only via Supabase MCP `execute_sql` as service_role + simulated PM auth context.*
