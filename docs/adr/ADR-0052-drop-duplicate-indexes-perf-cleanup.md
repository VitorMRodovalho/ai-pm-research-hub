# ADR-0052: DROP 12 duplicate indexes — perf cleanup

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-27 (session p73 EXTENDED++) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migration | `20260514150000_adr_0052_drop_duplicate_indexes_perf_cleanup.sql` |
| Cross-ref | #82 closure (deferred perf items), Supabase advisor `duplicate_index` WARN |
| Closes | 12 of 12 detected duplicate index pairs |

## Context

#82 closure comment listed 5 categories of deferred performance items:
* 70 `auth_rls_initplan` WARN (P1 — RLS pattern fix)
* 108 `multiple_permissive_policies` WARN (P2 — RLS refactor)
* **3 `duplicate_index` WARN (P2 trivial DROP)** ← this ADR
* 118 `unused_index` INFO (P3 batch DROP)
* 146 `unindexed_foreign_keys` INFO (P3)

Direct query of `pg_index` (joined to `pg_class` + `pg_namespace`) found
**12** duplicate index pairs (same table + same column list + same WHERE
predicate). The advisor flag of "3" likely refers to the most-egregious
cases; the remaining 9 still represent storage and write-amplification
waste.

## Decision

DROP 12 redundant indexes via single migration. For each pair, decision
rule:

1. **Constraint-backed wins**: any index with `pg_constraint.conindid`
   pointing to it MUST stay (UNIQUE constraint enforcement). All 8 of
   our pairs include a `*_key` partner — keep those, drop the `idx_*`
   sibling.
2. **Both non-unique + non-constraint**: 4 pairs lack constraint backing.
   Pick by canonical naming convention — keep shorter/more-descriptive
   name, drop the longer/less-canonical sibling.

Pre-flight verification:
```sql
SELECT pg_constraint.conindid FROM pg_constraint
WHERE conindid IN (<12 to-be-dropped index oids>)
-- Result: all NULL → no constraint depends on any of them. Safe to DROP.
```

### Indexes dropped (12)

| Table | Columns | Predicate | Dropped | Kept |
|---|---|---|---|---|
| attendance | event_id | — | `idx_attendance_event_id` | `idx_attendance_event` |
| certificates | verification_code | — | `idx_certs_verification` | `certificates_verification_code_key` (UNIQUE) |
| document_versions | document_id, version_number | — | `idx_document_versions_document` | `document_versions_document_id_version_number_key` (UNIQUE) |
| evm_analyses | analysis_id | — | `idx_evm_analyses_aid` | `evm_analyses_analysis_id_key` (UNIQUE) |
| gamification_points | member_id | — | `idx_points_member` | `idx_gamification_member` |
| knowledge_chunks | asset_id, chunk_index | — | `idx_knowledge_chunks_asset` | `knowledge_chunks_asset_id_chunk_index_key` (UNIQUE) |
| member_activity_sessions | member_id, session_date | — | `idx_activity_sessions_member` | `member_activity_sessions_member_id_session_date_key` (UNIQUE) |
| member_document_signatures | member_id, document_id | `is_current=true` | `idx_member_doc_sigs_current` | `uq_member_doc_sigs_current` (UNIQUE partial) |
| notifications | recipient_id, is_read | `is_read=false` | `idx_notif_unread` | `idx_notif_recipient_unread` |
| risk_simulations | simulation_id | — | `idx_risk_simulations_sid` | `risk_simulations_simulation_id_key` (UNIQUE) |
| tia_analyses | analysis_id | — | `idx_tia_analyses_aid` | `tia_analyses_analysis_id_key` (UNIQUE) |
| wiki_pages | path | — | `idx_wiki_pages_path` | `wiki_pages_path_key` (UNIQUE) |

## Consequences

**Positive**:
* Reclaim disk space (~hundreds of KB to MB depending on row counts —
  negligible at current size, but compounds with growth)
* Eliminate **2x write amplification** for inserts/updates on these tables
  (every row mutation maintained both indexes; now only one)
* Reduce planner consideration overhead (fewer indexes to score per
  query plan)
* Closes the "P2 trivial DROP" item from #82 closure backlog
* Postmig duplicate count: 0 (verified via same query that found 12)

**Neutral**:
* No query plan changes expected — Postgres planner already used only
  one of each pair per query. The kept index has identical column +
  predicate signature.

**Negative**:
* None. Truly redundant indexes by definition.

## Patterns sedimented

1. **Constraint-backed > non-constraint precedence rule**: when choosing
   between duplicate indexes, the one referenced by `pg_constraint.conindid`
   MUST stay. Dropping it would silently break UNIQUE enforcement.
2. **Direct pg_index query > advisor count**: Supabase advisor counts
   may underrepresent actual duplicates. For exhaustive cleanup, query
   `pg_index` JOIN `pg_class` JOIN `pg_namespace` directly with GROUP BY
   `(table, columns, predicate)` HAVING COUNT > 1.
3. **Pre-flight constraint dependency check**: before any DROP INDEX,
   confirm `SELECT conindid FROM pg_constraint WHERE conindid = <oid>`
   returns NULL. Safe to drop only if no constraint depends.

## Rollback

If a query plan unexpectedly degrades after this migration (unlikely,
since the kept index has identical signature):

```sql
-- Re-CREATE any specific dropped index to restore.
-- Example for the most query-frequent (gamification_points):
CREATE INDEX idx_points_member ON public.gamification_points(member_id);
```

Full rollback list available in migration file's commented section.
Rollback re-introduces the duplicate; planner will pick whichever is
cheaper at query time.

## Verification

* [x] All 12 to-be-dropped indexes have NULL constraint dependency
  (pre-flight check passed)
* [x] Migration applied (`20260514150000`)
* [x] Post-migration duplicate count: 0 (verified via direct pg_index
  query)
* [x] Tests preserved 1415 / 1383 / 0 / 32
* [x] Invariants 11/11 = 0
* [x] No frontend/MCP impact (DDL-only migration)

## Remaining #82 deferred perf items (post-ADR-0052)

* [ ] 70 `auth_rls_initplan` WARN — P1 RLS pattern fix `(SELECT auth.uid())`
* [ ] 108 `multiple_permissive_policies` WARN — P2 RLS refactor (largest)
* [ ] 118 `unused_index` INFO — P3 batch DROP (requires usage analysis,
  some may be future-use)
* [ ] 146 `unindexed_foreign_keys` INFO — P3 batch CREATE INDEX

PM may create separate issue for the remaining categories when desired.

## References

* GitHub #82 closure comment (deferred perf items list)
* Supabase advisor: `duplicate_index` WARN class
* `tests/contracts/rpc-migration-coverage.test.mjs` — Track Q-C does
  NOT cover index drops (only function bodies); no contract test impact

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
