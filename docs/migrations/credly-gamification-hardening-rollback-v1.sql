-- Credly/Gamification hardening rollback (v1)
-- Date: 2026-03-08
-- Purpose: rollback unique-index protection if needed.

drop index concurrently if exists public.uq_gp_credly_member_reason_ci;

select
  indexname
from pg_indexes
where schemaname = 'public'
  and tablename = 'gamification_points'
  and indexname = 'uq_gp_credly_member_reason_ci';
