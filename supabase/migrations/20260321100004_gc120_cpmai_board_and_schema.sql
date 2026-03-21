-- GC-120: CPMAI Prep Course — Design Board + DB Schema
-- Phase 1: BoardEngine board for course design (14 cards)
-- Phase 2: 7 cpmai_* tables + RLS deny-all + seed (1 course, 5 ECO v8 domains)
-- Applied via execute_sql; this file records changes for git history.

-- Board: 75df916d-cc19-4d42-a58d-6017eb710a24 (CPMAI Prep Course — Design)
-- Course: a1b2c3d4-e5f6-7890-abcd-ef1234567890 (Preparatório CPMAI — Ciclo 3)
-- 5 domains: ECO v8 weights (15+26+26+16+17 = 100%)

-- Tables created:
-- cpmai_courses, cpmai_domains, cpmai_modules, cpmai_enrollments,
-- cpmai_progress, cpmai_mock_scores, cpmai_sessions
-- All with RLS deny-all (rpc_only_deny_all policy)

NOTIFY pgrst, 'reload schema';
