# ADR-0056: auth_rls_initplan perf fix — batch 4 (Class E can_by_member subquery)

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-27 (session p73 EXTENDED++++++) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migration | `20260514190000_adr_0056_auth_rls_initplan_batch_4.sql` |
| Cross-ref | ADR-0053 + 0054 + 0055 (prior batches) |
| Closes | 7 of 70 flagged policies (cumulative ADR-0053..0056: 49/70 ~70%) |

## Context

Continuation of the auth_rls_initplan series. Class E pattern wraps inner
`auth.uid()` inside an already-wrapped subquery passed to `can_by_member`:

```sql
-- Before:
can_by_member((SELECT m.id FROM members m WHERE m.auth_id = auth.uid()), 'action')
-- After:
can_by_member((SELECT m.id FROM members m WHERE m.auth_id = (SELECT auth.uid())), 'action')
```

This creates **2-layer InitPlan caching**:
1. Outer `(SELECT m.id ...)` cached as InitPlan, invokes can_by_member once
   per query with the resolved member id
2. Inner `(SELECT auth.uid())` cached as InitPlan, evaluates auth.uid()
   once

Both layers contribute to the per-row → per-query reduction (the outer
prevents repeated member lookups; the inner prevents repeated auth.uid()
evaluations within the lookup).

## Decision

Ship 7 simple Class E policies (subset of ~10 total — remaining 3 are
multi-clause approval_chains/signoffs cluster, deferred to ADR-0057):

| Table | Policy | Cmd | Action |
|---|---|---|---|
| board_item_event_links | board_item_event_links_write_manage_event | ALL | manage_event |
| initiative_kinds | initiative_kinds_delete_admin | DELETE | write |
| initiative_kinds | initiative_kinds_update_admin | UPDATE | write |
| initiative_kinds | initiative_kinds_write_admin | INSERT | write |
| initiative_member_progress | imp_insert_write | INSERT | write |
| pending_manual_version_approvals | pending_mva_select_manage_platform | SELECT | manage_platform |
| tribe_kpi_contributions | tribe_kpi_contrib_write_manage_platform | ALL | manage_platform |

All `authenticated` role. All preserve original V4 action semantics
(`manage_event`, `write`, `manage_platform`).

## Consequences

**Positive**:
* Cumulative ADR-0053..0056: **49/70 policies wrapped (~70% of P1 scope)**
* 2-layer InitPlan caching for V4 `can_by_member` gate composition
* Tables with V4 admin gate (`initiative_kinds`, `tribe_kpi_contributions`,
  `pending_manual_version_approvals`) get InitPlan benefit on hot paths
* Class E partial closure (7 of ~10); remaining 3 are approval cluster

**Neutral**:
* No semantic change. V4 action semantics preserved.

**Negative**:
* None.

## Pattern sedimented (additive)

25. **2-layer InitPlan caching for V4 gate composition**: when a V4 helper
    (`can_by_member`, `rls_can`, etc.) is passed a subquery resolving to
    the caller's member id, BOTH the outer subquery AND the inner
    `auth.uid()` benefit from `(SELECT ...)` wrapping. The two layers
    compose: outer caches member-id resolution; inner caches auth.uid().

## Remaining #82 perf items (post-ADR-0056)

* [ ] **21** `auth_rls_initplan` WARN (was 70; -42 batches 1-3; -7 batch 4 = -49 cumulative)
  * Class E remaining: approval_chains (3) + approval_signoffs (2) (~5 policies, EXISTS+can_by_member multi-clause)
  * Class F: multi-clause OR helper compositions (~12 policies — document_comments, document_versions, comms_*, hub_resources, etc.)
  * Class G: misc (auth.role/jwt patterns, broadcast_log, comms_metrics_admin_read, member_doc_sigs_read_self_or_admin, webinars_update_v2, member_offboarding_records.update_authorized, etc.)
* [ ] 108 `multiple_permissive_policies` WARN (P2 RLS refactor)
* ~~3 `duplicate_index` WARN~~ ✅ DONE ADR-0052
* [ ] 118 `unused_index` INFO (P3)
* [ ] 146 `unindexed_foreign_keys` INFO (P3)

## Verification

* [x] Migration applied (`20260514190000`)
* [x] 7/7 policies show OK/OK
* [x] Tests preserved 1415 / 1383 / 0 / 32
* [x] Invariants 11/11 = 0
* [x] Role grants preserved (7× authenticated)
* [x] V4 action semantics preserved (manage_event, write, manage_platform)

## References

* ADR-0053 (batch 1) + ADR-0054 (batch 2) + ADR-0055 (batch 3)
* ADR-0007 (V4 can_by_member authority)
* GitHub #82 closure (deferred perf list)

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
