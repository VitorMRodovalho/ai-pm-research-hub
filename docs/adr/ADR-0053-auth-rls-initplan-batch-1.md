# ADR-0053: auth_rls_initplan perf fix — batch 1 (#82 P1 deferred)

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-27 (session p73 EXTENDED+++) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migration | `20260514160000_adr_0053_auth_rls_initplan_batch_1.sql` |
| Cross-ref | #82 closure (deferred perf items), Supabase advisor `auth_rls_initplan` WARN |
| Closes | 13 of 70 flagged policies (batch 1; remaining batches as ADR-0054+) |

## Context

#82 closure listed 70 `auth_rls_initplan` WARNs as P1 deferred perf items.
The Supabase advisor's docs explain:

> Postgres planner caches `(SELECT auth.uid())` as an InitPlan, evaluating
> it ONCE per query. Bare `auth.uid()` is re-evaluated PER ROW. For RLS
> policies on tables with non-trivial row counts, this is a measurable
> per-query cost.

Fix is mechanical:

```sql
-- Before:
USING (auth.uid() = user_id)

-- After:
USING ((SELECT auth.uid()) = user_id)
```

Semantically identical. Postgres rewrites stored as `( SELECT auth.uid() AS uid)`
(adds alias). This rewrite preserves the InitPlan caching benefit.

## Decision

Ship batch 1 of the 70-policy fix: 13 simple `(auth.uid() = column)`
patterns across 7 tables. Each policy is DROP'd + re-CREATE'd with
the wrapped expression.

Rationale for batch-by-batch approach:
* Single-migration with 70 DROP/CREATE pairs is high-risk (any syntax
  error rolls back ALL policy changes; partial application leaves
  permission state ambiguous)
* Different policy patterns (subqueries, OR clauses, EXISTS) need
  surgical care — better to verify each pattern class separately
* Batch 1 selects the simplest, lowest-risk patterns to validate
  the approach + sediment confidence

### Batch 1 scope (13 policies, 7 tables)

| Table | Policy | Cmd | Old expr | New expr |
|---|---|---|---|---|
| analysis_results | Users can insert own analyses | INSERT | `(auth.uid() = user_id)` | `((SELECT auth.uid()) = user_id)` |
| analysis_results | Users can view own analyses | SELECT | same | same |
| comparison_results | Users can insert own comparisons | INSERT | same | same |
| comparison_results | Users can view own comparisons | SELECT | same | same |
| evm_analyses | Users can insert own EVM analyses | INSERT | same | same |
| evm_analyses | Users can view own EVM analyses | SELECT | same | same |
| member_activity_sessions | Members can insert own sessions | INSERT | `(member_id = (SELECT id FROM members WHERE auth_id = auth.uid()))` | wraps inner auth.uid() in (SELECT) |
| risk_simulations | Users can insert own risk simulations | INSERT | `(auth.uid() = user_id)` | `((SELECT auth.uid()) = user_id)` |
| risk_simulations | Users can view own risk simulations | SELECT | same | same |
| tia_analyses | Users can insert own TIA analyses | INSERT | same | same |
| tia_analyses | Users can view own TIA analyses | SELECT | same | same |
| user_profiles | Users can update own profile | UPDATE | `(auth.uid() = id)` | `((SELECT auth.uid()) = id)` |
| user_profiles | Users can view own profile | SELECT | same | same |

All policies are PERMISSIVE; no policy semantics changed. PostgREST
schema reload via `NOTIFY pgrst` to refresh policy cache.

### Out of scope (deferred to ADR-0054+)

* Policies with EXISTS containing `auth.uid()` (need careful subquery analysis)
* Policies mixing `auth.uid()` and `rls_can()` / `rls_is_*()` helpers (composition risk)
* Policies on tables under V4 admin gate (`rls_can()` may already provide initplan-like caching internally — verify before rewriting)
* `auth.role()` and `auth.jwt()` patterns (separate batch, smaller surface)

Roughly 57 remaining flagged policies. Estimate 4-5 future batches:
* Batch 2: standard helper-call policies (`rls_is_*` superadmin checks)
* Batch 3: complex multi-clause OR/AND policies on critical tables
  (members, board_items, project_boards) — needs council review
* Batch 4: subquery-bearing policies (chapters, document_*)
* Batch 5: `auth.role()` / `auth.jwt()` patterns

## Consequences

**Positive**:
* InitPlan caching enabled for 13 high-traffic user-owned record policies
* Per-query overhead reduced (proportional to row count scanned)
* Closes 13 of 70 advisor `auth_rls_initplan` WARNs
* Establishes pattern + safety review for future batches

**Neutral**:
* No semantic change. Policy enforcement identical pre/post.
* Postgres stored format adds ` AS uid` alias automatically (cosmetic only)

**Negative**:
* None. Pure perf optimization.

## Patterns sedimented

1. **InitPlan wrap pattern**: `auth.uid()` → `(SELECT auth.uid())` for
   any RLS policy expression. Evaluates once per query (InitPlan cache)
   instead of per row. Postgres stored format becomes
   `( SELECT auth.uid() AS uid)`.
2. **Batch-by-batch RLS rewrite**: ship in focused batches by pattern
   class (simple equality / helper-call / multi-clause / subquery).
   Each batch validates the pattern before scaling.
3. **Verify with regex permissive on alias**: when checking pg_policies
   text post-migration, the regex `\(\s*SELECT\s+auth\.uid\(\)` matches
   without trailing `\)` to accommodate Postgres' inserted ` AS uid`.

## Rollback

```sql
-- Per-policy rollback (re-CREATE with bare auth.uid()):
DROP POLICY "Users can insert own analyses" ON public.analysis_results;
CREATE POLICY "Users can insert own analyses" ON public.analysis_results
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);
-- ... (repeat per policy)
```

Rollback re-introduces the per-row evaluation cost. Only needed if a
specific policy unexpectedly fails (none observed in batch 1).

## Verification

* [x] Migration applied (`20260514160000`)
* [x] 13/13 policies show OK/OK status (qual + with_check use SELECT wrapper)
* [x] Tests preserved 1415 / 1383 / 0 / 32
* [x] Invariants 11/11 = 0
* [x] PostgREST schema reload via NOTIFY pgrst

## Remaining #82 perf items (post-ADR-0053 batch 1)

* [ ] 57 `auth_rls_initplan` WARN — batches 2-5 (ADR-0054+)
* [ ] 108 `multiple_permissive_policies` WARN (P2 RLS refactor)
* ~~3 `duplicate_index` WARN~~ ✅ DONE ADR-0052 (12 dropped)
* [ ] 118 `unused_index` INFO (P3 batch DROP)
* [ ] 146 `unindexed_foreign_keys` INFO (P3 batch CREATE)

## References

* GitHub #82 closure comment (deferred perf items)
* Supabase advisor: `auth_rls_initplan` WARN class
* https://supabase.com/docs/guides/database/postgres/row-level-security#rls-performance-recommendations
* `tests/contracts/track-r-auth-org-acl.test.mjs` — RLS policy contract test

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
