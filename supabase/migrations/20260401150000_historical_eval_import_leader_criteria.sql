-- Historical evaluation import for Ciclo 3 2026 (kickoff)
-- ========================================================
-- Phase 1: 93 objective evaluations (Fabricio + Vitor) + 29 interviews imported
-- Phase 2: 24 leader_extra evaluations + conversion linkage for 5 dual applicants
--
-- Scale conversions applied:
-- - Objective: 0-5 → 0-10 (x2), certification stays 0-2
-- - Interview: communication 1-4 → 0-10, others 1-3 → 0-10
-- - All scores recalculated with platform weights (not original planilha weights)
--
-- Dual applicants linked via converted_from/converted_to (no merge — preserves audit trail)
-- Each application retains its vep_opportunity_id (64967=researcher, 64966=leader)

-- Leader extra criteria for kickoff cycle
-- (Applied via execute_sql, documented here for migration history)

-- Helper RPC for historical imports (created via execute_sql)
-- import_historical_evaluations(jsonb) — researcher objective + interview
-- import_leader_evaluations(jsonb) — leader_extra objective + interview
