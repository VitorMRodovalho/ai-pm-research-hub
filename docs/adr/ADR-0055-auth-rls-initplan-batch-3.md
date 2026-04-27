# ADR-0055: auth_rls_initplan perf fix — batch 3 (Class D superadmin EXISTS)

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-27 (session p73 EXTENDED+++++) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migration | `20260514180000_adr_0055_auth_rls_initplan_batch_3.sql` |
| Cross-ref | ADR-0053 (batch 1) + ADR-0054 (batch 2), #82 closure |
| Closes | 17 of 70 flagged policies (cumulative ADR-0053+0054+0055: 42/70 ~60%) |

## Context

Continuation of ADR-0053+0054. Class D pattern (superadmin EXISTS subqueries)
is the largest cohesive cluster — 17 policies follow the canonical idiom:

```sql
EXISTS (SELECT 1 FROM members
        WHERE auth_id = auth.uid() AND is_superadmin = true)
```

Wrap inner `auth.uid()` to enable InitPlan caching at the inner subquery level:

```sql
EXISTS (SELECT 1 FROM members
        WHERE auth_id = (SELECT auth.uid()) AND is_superadmin = true)
```

## Decision

17 policies, single-class batch:

### 16 simple superadmin EXISTS policies

Tables: `admin_audit_log`, `board_items`, `certificates`, `chapter_registry`,
`chapters`, `cycles`, `email_webhook_events`, `gamification_points`,
`member_offboarding_records`, `organizations`, `privacy_policy_versions`,
`project_boards`, `publication_series`, `release_items`, `site_config`,
`volunteer_applications`. (16 distinct policies)

Mix of role grants (`authenticated` for most, `public` for `cycles_admin_write`
+ `publication_series_superadmin_all`). Mix of cmd: most are `ALL` with both
USING + WITH CHECK; `admin_audit_log`, `email_webhook_events`,
`offboarding_records_delete_superadmin`, `volunteer_applications` are
single-clause.

### 1 complex multi-OR EXISTS policy

`member_offboarding_records.offboarding_records_select_authorized` has 4
OR branches (3× EXISTS with auth.uid() + 1× rls_can helper). All `auth.uid()`
references wrapped:

```sql
EXISTS (… auth.uid() … superadmin)
OR EXISTS (… member_id match … auth.uid())
OR EXISTS (… offboarded_by match … auth.uid())
OR rls_can('manage_member')
```

Each EXISTS clause gets its own `(SELECT auth.uid())` wrap (3 instances total).
The `rls_can()` helper is V4 idiom and stays unchanged.

## Consequences

**Positive**:
* Cumulative ADR-0053+0054+0055: **42/70 policies wrapped (~60% of P1 scope)**
* Class D fully closed (largest cohesive cluster done)
* All 16 superadmin-gated tables now use InitPlan
* `member_offboarding_records` (PII-sensitive) gets perf boost on hot SELECT path

**Neutral**:
* No semantic change — same 4 OR branches in offboarding_records, just inner
  auth.uid() wrapped per-clause

**Negative**:
* None.

## Patterns sedimented (additive)

23. **Multi-OR per-clause auth.uid() wrap**: when policies have multiple OR
    branches each containing `auth.uid()`, each branch gets its own
    `(SELECT auth.uid())` wrap independently. Postgres' InitPlan caching
    deduplicates identical subqueries across the same query, so per-branch
    wrapping doesn't multiply the cost.

24. **Cohesive cluster batching**: the 16 superadmin EXISTS policies share
    nearly-identical structure. Shipping them together preserves a clean
    "class D fully closed" narrative + verification simpler (one regex, all
    pass). Mixed-pattern batches harder to verify at-a-glance.

## Remaining #82 perf items (post-ADR-0055)

* [ ] **28** `auth_rls_initplan` WARN (was 70; -25 batches 1+2; -17 batch 3 = -42 cumulative)
  * Class E candidates: can_by_member/rls_can with subquery member-id (~10 policies)
  * Class F candidates: multi-clause OR helper compositions (~12 policies)
  * Class G candidates: misc (auth.role()/auth.jwt() patterns, edge cases)
* [ ] 108 `multiple_permissive_policies` WARN (P2 RLS refactor)
* ~~3 `duplicate_index` WARN~~ ✅ DONE ADR-0052
* [ ] 118 `unused_index` INFO (P3)
* [ ] 146 `unindexed_foreign_keys` INFO (P3)

## Verification

* [x] Migration applied (`20260514180000`)
* [x] 17/17 policies show OK/OK (qual + with_check use SELECT wrapper)
* [x] Complex offboarding_records 3-EXISTS policy verified (all auth.uid wrapped)
* [x] Tests preserved 1415 / 1383 / 0 / 32
* [x] Invariants 11/11 = 0
* [x] PostgREST schema reload via NOTIFY pgrst
* [x] Role grants preserved (15× authenticated, 2× public)

## References

* ADR-0053 (batch 1) + ADR-0054 (batch 2)
* GitHub #82 closure (deferred perf list)
* Supabase advisor: `auth_rls_initplan` WARN class

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
