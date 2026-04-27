# ADR-0054: auth_rls_initplan perf fix — batch 2 (#82 P1)

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-27 (session p73 EXTENDED++++) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migration | `20260514170000_adr_0054_auth_rls_initplan_batch_2.sql` |
| Cross-ref | ADR-0053 (batch 1), #82 closure deferred perf items |
| Closes | 12 of 70 flagged policies (cumulative ADR-0053+0054: 25/70) |

## Context

Continuation of ADR-0053. Same `(SELECT auth.uid())` InitPlan wrap.

## Decision

12 policies across 8 tables, 3 pattern classes:

### Class A continuation (4 policies, members table)

Simple `(auth_id = auth.uid())` direct equality. All `authenticated` role.

* `Members can update own notification preferences` (UPDATE)
* `member_update_own_profile` (UPDATE)
* `members_select_own` (SELECT)
* `members_update_own` (UPDATE)

### Class B (2 policies, IS NOT NULL existence check)

Pattern `(auth.uid() IS NOT NULL)` → `((SELECT auth.uid()) IS NOT NULL)`.
Used on tables where ANY authenticated user is allowed to insert.

* `change_requests."Auth create CRs"` (INSERT, role=public)
* `webinar_lifecycle_events.wle_insert` (INSERT, role=authenticated)

### Class C (6 policies, member-id IN/= subquery)

Pattern: `member_id [= | IN] (SELECT id FROM members WHERE auth_id = auth.uid())`.
Inner `auth.uid()` wrapped to enable InitPlan caching at the inner subquery level.

* `notification_preferences.notifpref_own` (ALL)
* `notifications.notif_select_own` (SELECT)
* `course_progress."Auth update progress"` (ALL — both qual + with_check)
* `tribe_selections."Auth insert selection"` (INSERT)
* `tribe_selections."Auth update selection"` (UPDATE)
* `member_document_signatures.member_doc_sigs_insert_self_or_rpc` (INSERT)

## Consequences

**Positive**:
* Cumulative ADR-0053+0054: 25/70 policies wrapped (~36% of P1 scope)
* `members` table fully covered (high-traffic — lookups by auth_id are hot path)
* All Class B policies covered (IS NOT NULL idiom — easy class)

**Neutral**:
* Pattern is now well-validated; future batches can scale faster
* Mix of `public` and `authenticated` role grants preserved

**Negative**:
* None. Pure perf optimization.

## Patterns sedimented (additive to ADR-0053's #18-20)

21. **Inner-subquery auth.uid() wrap**: even when the outer policy clause
    is already in a `(SELECT ... WHERE auth_id = auth.uid())` subquery,
    the inner `auth.uid()` reference itself benefits from `(SELECT auth.uid())`
    wrapping. The two SELECT layers compose: outer subquery executes once,
    inner wraps the auth.uid() InitPlan within that.

22. **Pattern class B (IS NOT NULL)**: simplest existence check pattern.
    Often appears in INSERT policies for "any logged-in user can insert".
    Mechanical wrap.

## Remaining #82 perf items (post-ADR-0054)

* [ ] **45** `auth_rls_initplan` WARN (was 70; -13 batch 1; -12 batch 2 = -25 cumulative)
  * Class D candidates: superadmin EXISTS subqueries (~15 policies)
  * Class E candidates: can_by_member/rls_can with subquery member-id (~10 policies)
  * Class F candidates: multi-clause OR helper compositions (~12 policies)
  * Class G candidates: auth.role()/auth.jwt() patterns (~5 policies)
* [ ] 108 `multiple_permissive_policies` WARN (P2 RLS refactor)
* ~~3 `duplicate_index` WARN~~ ✅ DONE ADR-0052 (12 dropped)
* [ ] 118 `unused_index` INFO (P3)
* [ ] 146 `unindexed_foreign_keys` INFO (P3)

## Verification

* [x] Migration applied (`20260514170000`)
* [x] 12/12 policies show OK/OK
* [x] Tests preserved 1415 / 1383 / 0 / 32
* [x] Invariants 11/11 = 0
* [x] PostgREST schema reload via NOTIFY pgrst
* [x] Role grants preserved (4× authenticated members, 1× public CR, 1× authenticated webinar, etc.)

## References

* ADR-0053 (batch 1)
* GitHub #82 closure (deferred perf list)
* Supabase advisor: `auth_rls_initplan` WARN class

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
