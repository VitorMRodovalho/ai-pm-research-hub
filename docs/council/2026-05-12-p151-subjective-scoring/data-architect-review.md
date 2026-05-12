# Council review p151 — data-architect lens — ADR-0079

## TL;DR

The schema proposal is structurally sound in its core concept but carries three blocking-class issues that must be resolved before implementation: (1) the `UNIQUE` constraint as written does NOT function as a partial index and will silently fail its stated purpose at scale, (2) the `superseded_by` self-reference has no `ON DELETE` policy, creating a constraint violation path on purge, and (3) the BEFORE trigger purge on consent revocation does NOT reach `video_screening_analysis` rows because that table is separate from `selection_applications` — consent revocation will produce silent data leakage. The pipeline and caching column design are acceptable with targeted changes.

---

## Riscos novos identificados (não estão na spec)

**R-SCHEMA-1 — UNIQUE constraint não é partial index (silently wrong)**

The proposed constraint is:
```sql
CONSTRAINT video_screening_analysis_uniq_active
  UNIQUE (source_screening_id, model, model_version)
```

The spec comment in §10 R7 describes this as `WHERE status != 'superseded'`, but that qualifier is NOT in the DDL. A plain `UNIQUE` constraint enforces uniqueness across ALL rows including superseded ones. This means: when a re-run correctly inserts a new row and marks the prior `status='superseded'`, the second re-run will violate the constraint because two non-superseded rows for the same `(source_screening_id, model, model_version)` cannot exist — but neither can the superseded + new pair if model/version did not change.

The correct implementation requires a partial unique index, not a constraint:
```sql
CREATE UNIQUE INDEX idx_vsa_uniq_active
  ON video_screening_analysis (source_screening_id, model, model_version)
  WHERE status NOT IN ('superseded', 'failed');
```

A plain constraint cannot express `WHERE`; only a `CREATE UNIQUE INDEX` can. Postgres will honor the partial index for uniqueness enforcement. Without this fix, re-scoring is impossible after the first supersede cycle.

**R-SCHEMA-2 — `superseded_by` self-reference: no ON DELETE policy**

The column `superseded_by uuid REFERENCES video_screening_analysis(id)` has no `ON DELETE` clause, which defaults to `ON DELETE NO ACTION` (restrict). If a purge cron attempts to delete `video_screening_analysis` rows for a revoked consent, it will fail with a FK violation if any other row has `superseded_by` pointing to the row being deleted. Standard `ON DELETE SET NULL` is the correct policy here to decouple the audit trail from the purge path:
```sql
superseded_by uuid REFERENCES video_screening_analysis(id) ON DELETE SET NULL
```

This matches the pattern already established in `selection_evaluation_ai_suggestions.superseded_by` in migration `20260516200000_phase_b_pmi_journey_v4.sql` (line 114).

**R-SCHEMA-3 — Consent revoke trigger does NOT purge `video_screening_analysis` (silent LGPD gap)**

The existing trigger `_trg_purge_ai_analysis_on_consent_revocation` is a BEFORE UPDATE trigger on `selection_applications` that NULLifies columns IN the same row (`linkedin_relevant_posts`, `cv_extracted_text`, `ai_pm_focus_tags`, `ai_analysis`). It cannot touch rows in a separate table. The spec says "Revoke trigger 72h purga `video_screening_analysis` rows" but the trigger body as it stands does no such thing — and no migration in the spec list addresses this extension.

This is a genuine LGPD Art. 18 gap. The spec claims compliance by re-using the existing consent mechanism, but `video_screening_analysis` rows are in a different table and will persist through consent revocation unless an explicit DELETE is added to the trigger or a new AFTER trigger on `selection_applications` issues a `DELETE FROM video_screening_analysis WHERE application_id = NEW.id`.

ADR-0079 must not ship without extending `_trg_purge_ai_analysis_on_consent_revocation` (or a companion AFTER trigger) to also `DELETE FROM video_screening_analysis WHERE application_id = NEW.id`. This should be migration 1 in the implementation sequence, not deferred.

**R-SCHEMA-4 — `organization_id` has no DEFAULT and no FK**

The spec DDL shows `organization_id uuid NOT NULL,`. All sibling tables in Phase B (`selection_evaluation_ai_suggestions`, `pmi_video_screenings`, `onboarding_tokens`) use `organization_id uuid NOT NULL DEFAULT auth_org()`. There is no default in the proposed schema. The EF runs as `service_role` and must pass `organization_id` explicitly, which is fragile. Standard pattern: `DEFAULT auth_org()` plus the org-scope RLS policy identical to sibling tables.

**R-SCHEMA-5 — `ai_subjective_score_avg` is a cache column without a declared sync trigger or ADR-0012 invariant**

ADR-0012 Principle 2: every cache column requires a documented trigger of sync AND a testable invariant in `check_schema_invariants()`. The spec describes this column as "computed via trigger AFTER INSERT in vsa" but the trigger is not named, its idempotency under concurrent inserts is not specified, and no invariant `P_subjective_score_avg_consistency` is proposed. The existing precedent for `research_score` (invariant M, migration `20260516760000`) must be replicated here.

**R-SCHEMA-6 — Dual CASCADE pressure on `video_screening_analysis`**

Both FKs in `video_screening_analysis` are `ON DELETE CASCADE`: `application_id → selection_applications` and `source_screening_id → pmi_video_screenings`. The `pmi_video_screenings.application_id` is also `ON DELETE CASCADE` to `selection_applications`. This creates a two-hop cascade with redundant paths. The `application_id` FK cascade is redundant since `pmi_video_screenings` already cascades. Consider whether single deletion path via `source_screening_id` is sufficient.

---

## Recomendações por decisão aberta

**D-TRIGGER (Cron A vs Trigger B vs Hybrid C)**

Recommend **A (cron polling)** with one amendment: the polling query needs a compound index to be efficient. Add:
```sql
CREATE INDEX idx_vsa_source_completed
  ON video_screening_analysis(source_screening_id)
  WHERE status = 'completed';
```

The existing `idx_video_screenings_status_pending` on `pmi_video_screenings` covers `status IN ('uploaded', 'transcribing', 'failed')` but NOT `transcribed` — add `'transcribed'` to that partial index.

**D-RUBRIC (hardcoded vs `pillar_rubrics` table)**

Recommend **B (table)** but with schema notes: `pillar_rubrics` must have `organization_id NOT NULL` + RLS, an `is_active boolean NOT NULL DEFAULT true` for soft versioning, and `prompt_hash text NOT NULL` to enable EF cache invalidation detection. The EF should read the active rubric per invocation (not cached at EF boot).

**D-RETRY-CAP (max retries)**

Recommend **A (3)**. Add a separate `failed_permanent` status value or a `CHECK (retry_count <= 3)` constraint to prevent runaway retries.

**D-SUPERSEDE (re-run behavior)**

Recommend **A (insert + mark prior superseded)**. Confirm the UNIQUE partial index fix (R-SCHEMA-1) is in place before implementing.

---

## Ajustes propostos ao schema/pipeline

1. **Migration 1 MUST include**: extension of `_trg_purge_ai_analysis_on_consent_revocation` to delete from `video_screening_analysis` (R-SCHEMA-3). NOT OPTIONAL.

2. **Migration 1 DDL corrections**:
   - `ON DELETE SET NULL` to `superseded_by` (R-SCHEMA-2)
   - `DEFAULT auth_org()` to `organization_id` (R-SCHEMA-4)
   - Remove `CONSTRAINT video_screening_analysis_uniq_active UNIQUE (...)`; replace with partial unique index (R-SCHEMA-1)
   - Add `CREATE UNIQUE INDEX idx_vsa_uniq_active ON video_screening_analysis (source_screening_id, model, model_version) WHERE status NOT IN ('superseded','failed')`

3. **Migration 2 MUST include** (per ADR-0012 Principle 2): trigger function for `ai_subjective_score_avg` sync (AFTER INSERT OR UPDATE OR DELETE on `video_screening_analysis` WHERE `status='completed'`) PLUS invariant `P_subjective_score_avg_consistency` in `check_schema_invariants()`.

4. **Additional indexes for cron path**: add `'transcribed'` to `idx_video_screenings_status_pending`, add `idx_vsa_source_completed` on `video_screening_analysis(source_screening_id) WHERE status='completed'`.

5. **`check_length(reasoning) <= 500` CHECK constraint** — prefer EF-side truncation + `reasoning_truncated boolean DEFAULT false` column over hard CHECK that produces failed row.

6. **`pillar_rubrics` FK integrity**: `ai_processing_log` should record `pillar_rubric_id` (active row ID at time of call) for analytics queries.

---

## ADR readiness — verdict

**BLOCK — safe-with-mandatory-changes before any migration applies to prod.**

Blocking items (must fix in spec + migration DDL before ACCEPTED status):

1. R-SCHEMA-1: Partial unique index, not constraint — re-scoring mechanically broken without this.
2. R-SCHEMA-3: Explicit purge of `video_screening_analysis` rows on consent revocation — LGPD Art. 18 compliance claim is false otherwise.
3. R-SCHEMA-2: `ON DELETE SET NULL` on `superseded_by` — cascade purge FK violation risk.
4. R-SCHEMA-5: ADR-0012 invariant `P_subjective_score_avg_consistency` + named trigger.

Non-blocking but recommended before p152 implementation:

- R-SCHEMA-4: `DEFAULT auth_org()` on `organization_id`
- Additional indexes for cron hot path
- `reasoning_truncated` column over hard CHECK constraint
- Cron polling index covering `status='transcribed'` in `pmi_video_screenings`

The architectural direction is correct and the pattern re-use from ADR-0074 is sound. The blocking items are mechanical DDL fixes, not conceptual problems.

---

Relevant files referenced:
- `docs/specs/p150-b-full-subjective-scoring-spec.md`
- `docs/adr/ADR-0079-subjective-scoring-via-video-transcription.md`
- `supabase/migrations/20260516200000_phase_b_pmi_journey_v4.sql` (`pmi_video_screenings` DDL and RLS pattern, lines 155-215)
- `supabase/migrations/20260514300000_adr_0059_w1_selection_applications_linkedin_ai_analysis_fields.sql` (lines 35-58, `_trg_purge_ai_analysis_on_consent_revocation` body)
- `supabase/migrations/20260516760000_p107_140_arm_onda1_invariant_12_score_consistency_sync_trigger.sql` (precedent for invariant M + sync trigger on score cache column)
- `docs/adr/ADR-0012-schema-consolidation-principles.md` (Principles 2 and 6)
