-- ADR-0052: DROP 12 duplicate indexes (perf cleanup, #82 deferred items)
--
-- Background: Supabase advisor flagged 3 `duplicate_index` WARNs in #82
-- closure comments as P2 trivial DROPs. Direct query of pg_index found 12
-- redundant pairs (same table + same columns + same predicate). Advisor
-- likely flags only most-egregious cases.
--
-- Decision rule: keep constraint-backed (`*_key`, `uq_*`) indexes — they
-- enforce UNIQUE constraints and dropping would break invariants. Drop
-- redundant `idx_*` siblings that have identical column lists + predicates.
-- For non-unique pairs (no constraint), drop the less canonically-named one.
--
-- Verification (pre-migration):
--   * SELECT pg_constraint.conindid → all 12 to-be-dropped have NULL
--     (no constraint depends on them)
--   * Each pair has identical columns_def + predicate (same query plan
--     would use either)
--
-- Risk: very low. Postgres planner uses any available index; with
-- duplicate indexes present, only one is consulted per query anyway.
-- Removing the redundant one frees:
--   * disk space (~hundreds of KB to MB depending on index size)
--   * write amplification (each row insert/update no longer maintains 2x)
--   * planner consideration overhead
--
-- Rollback: see commented section at bottom (re-CREATE INDEX with same
-- definition; copy from supabase/migrations/* archaeology).

-- Pair 1: attendance.event_id (both non-unique; canonical name `idx_attendance_event`)
DROP INDEX IF EXISTS public.idx_attendance_event_id;

-- Pair 2: certificates.verification_code (UNIQUE constraint owns the canonical key)
DROP INDEX IF EXISTS public.idx_certs_verification;

-- Pair 3: document_versions(document_id, version_number) (UNIQUE constraint)
DROP INDEX IF EXISTS public.idx_document_versions_document;

-- Pair 4: evm_analyses.analysis_id (UNIQUE constraint)
DROP INDEX IF EXISTS public.idx_evm_analyses_aid;

-- Pair 5: gamification_points.member_id (both non-unique; canonical `idx_gamification_member`)
DROP INDEX IF EXISTS public.idx_points_member;

-- Pair 6: knowledge_chunks(asset_id, chunk_index) (UNIQUE constraint)
DROP INDEX IF EXISTS public.idx_knowledge_chunks_asset;

-- Pair 7: member_activity_sessions(member_id, session_date) (UNIQUE constraint)
DROP INDEX IF EXISTS public.idx_activity_sessions_member;

-- Pair 8: member_document_signatures(member_id, document_id) WHERE is_current=true
-- (uq_* prefix indicates intentional unique constraint enforcement)
DROP INDEX IF EXISTS public.idx_member_doc_sigs_current;

-- Pair 9: notifications(recipient_id, is_read) WHERE is_read=false
-- Both non-unique partial indexes. Keep `idx_notif_recipient_unread` (more descriptive).
DROP INDEX IF EXISTS public.idx_notif_unread;

-- Pair 10: risk_simulations.simulation_id (UNIQUE constraint)
DROP INDEX IF EXISTS public.idx_risk_simulations_sid;

-- Pair 11: tia_analyses.analysis_id (UNIQUE constraint)
DROP INDEX IF EXISTS public.idx_tia_analyses_aid;

-- Pair 12: wiki_pages.path (UNIQUE constraint)
DROP INDEX IF EXISTS public.idx_wiki_pages_path;

-- =====================================================================
-- Rollback (commented). To restore, re-CREATE each index with same
-- definition. Originals can be archaeologized from supabase/migrations/.
-- Functionally equivalent indexes already exist (the ones kept), so
-- rollback is only needed if a query plan unexpectedly degrades.
-- =====================================================================
-- CREATE INDEX idx_attendance_event_id ON public.attendance(event_id);
-- CREATE INDEX idx_certs_verification ON public.certificates(verification_code);
-- CREATE INDEX idx_document_versions_document ON public.document_versions(document_id, version_number);
-- CREATE INDEX idx_evm_analyses_aid ON public.evm_analyses(analysis_id);
-- CREATE INDEX idx_points_member ON public.gamification_points(member_id);
-- CREATE INDEX idx_knowledge_chunks_asset ON public.knowledge_chunks(asset_id, chunk_index);
-- CREATE INDEX idx_activity_sessions_member ON public.member_activity_sessions(member_id, session_date);
-- CREATE INDEX idx_member_doc_sigs_current ON public.member_document_signatures(member_id, document_id) WHERE is_current = true;
-- CREATE INDEX idx_notif_unread ON public.notifications(recipient_id, is_read) WHERE is_read = false;
-- CREATE INDEX idx_risk_simulations_sid ON public.risk_simulations(simulation_id);
-- CREATE INDEX idx_tia_analyses_aid ON public.tia_analyses(analysis_id);
-- CREATE INDEX idx_wiki_pages_path ON public.wiki_pages(path);
