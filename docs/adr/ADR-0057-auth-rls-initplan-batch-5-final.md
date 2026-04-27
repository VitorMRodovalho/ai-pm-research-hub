# ADR-0057: auth_rls_initplan perf fix — batch 5 FINAL (closes 100% of #82 P1)

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-27 (session p74) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migration | `20260514200000_adr_0057_auth_rls_initplan_batch_5_final.sql` |
| Cross-ref | ADR-0053 + 0054 + 0055 + 0056 (prior batches) |
| Closes | 27 of 27 remaining flagged policies — **auth_rls_initplan = 0** |

## Context

Final batch of the `auth_rls_initplan` series. After ADR-0056 the advisor
re-baselined and surfaced **27 remaining policies** (handoff p74 estimated
21; the +6 delta consists of policies that the advisor hadn't surfaced
under prior runs because they were obscured by other lints). All 27
follow the same mechanical wrap pattern established in ADR-0053..0056:

* `auth.uid()` → `(SELECT auth.uid())`
* `auth.role()` → `(SELECT auth.role())`

Three sub-classes were folded into a single batch (vs the per-class
batching of 0053-0056) because the transformation is purely textual,
verification is mechanical (regex word-boundary scan), and the rollback
unit is one migration. Single-shot batching trades verification surface
area (one big migration) for atomicity and reduced ADR sprawl.

### Class breakdown of the 27

| Class | Count | Tables |
|---|---|---|
| Class E remaining (multi-clause helper composition) | 5 | approval_chains × 3, approval_signoffs × 2 |
| Class F (OR-composed helper subqueries) | 14 | document_versions × 3, document_comments × 3, document_comment_edits, hub_resources, member_document_signatures, member_offboarding_records, comms_media_items, comms_metrics_daily, webinars, pii_access_log |
| Class G (misc patterns: `auth.role()`, sender match, simple EXISTS, INSERT WITH CHECK with multiple guards) | 8 | tribe_deliverables, broadcast_log, campaign_sends, chapter_needs, z_archive.presentations, z_archive.member_role_changes × 2, z_archive.comms_token_alerts |

## Decision

Ship one migration `20260514200000` covering all 27 policies via the
DROP+CREATE idiom. Each rewritten policy preserves:

* Same `polcmd` (SELECT/INSERT/UPDATE/DELETE/ALL)
* Same `polpermissive` (PERMISSIVE)
* Same `polroles` (`{}` for unrestricted role list, or `{authenticated}`)
* Same logical USING / WITH CHECK content — only `auth.uid()` and
  `auth.role()` calls swapped for `(SELECT ...)` form

Verification confirmed via word-boundary regex `(?<!SELECT )\mauth\.uid\(\)`
and `(?<!SELECT )\mauth\.role\(\)` against `pg_get_expr(polqual)` and
`pg_get_expr(polwithcheck)` — 27/27 policies flagged 0 unwrapped calls
post-migration.

## Consequences

**Positive**:
* **auth_rls_initplan WARN count: 27 → 0 (100% closure of #82 P1)**
* Cumulative ADR-0053..0057: 76 policies wrapped across 5 batches (13+12+17+7+27)
* InitPlan caching now applies uniformly across the whole RLS surface
* z_archive policies wrapped too (small benefit but eliminates lint noise)

**Neutral**:
* No ACL/role/permissive change. V4 action semantics preserved.
* No new patterns sedimented beyond the ones already captured in
  0053-0056 — this batch validates that the transform generalizes.

**Negative**:
* Single large migration is harder to read in code review than per-class
  splits. Mitigated by per-table section headers in the SQL file.

## Pattern sedimented (additive)

26. **Final-batch pattern: collapse residual classes into one migration
    once the transform is mechanical.** Rationale: when 4 prior batches
    have proven the textual transform safe across multiple class
    archetypes (single-clause, multi-OR, helper composition, 2-layer
    nesting), the final residual batch can fold all remaining classes
    into one shipped unit. Trade-off: cognitive load of reading one big
    migration vs. extending the ADR series further. Choose the former
    when the safety surface is exhausted.

## Remaining #82 perf items (post-ADR-0057)

* ~~70 `auth_rls_initplan` WARN~~ ✅ **DONE 100%** (this ADR)
* ~~12 `duplicate_index` WARN~~ ✅ DONE ADR-0052
* [ ] **133** `multiple_permissive_policies` WARN (P2 RLS refactor — largest remaining class)
* [ ] **204** `unused_index` INFO (P3 — needs usage analysis before drop)
* [ ] **157** `unindexed_foreign_keys` INFO (P3 — batch CREATE INDEX candidate)

## Verification

* [x] Migration applied (`20260514200000`)
* [x] All 27 policies show OK/OK on regex word-boundary scan
* [x] Advisor returns `auth_rls_initplan: 0` post-migration
* [x] Tests preserved 1415 / 1383 / 0 / 32
* [x] Invariants 11/11 = 0
* [x] Role grants preserved (no policy lost its TO clause)
* [x] V4 action semantics preserved (`can_by_member`, `rls_can`,
  `rls_is_superadmin` unchanged)

## References

* ADR-0053 (batch 1) + ADR-0054 (batch 2) + ADR-0055 (batch 3) + ADR-0056 (batch 4)
* ADR-0007 (V4 can_by_member authority)
* GitHub #82 closure (deferred perf list)
* Supabase docs: <https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select>

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
