-- Credly/Gamification hardening pack (v1)
-- Date: 2026-03-08
-- Purpose: prevent future duplicate Credly inserts at DB level.

-- 1) Safety pre-check: this must return zero rows before creating the unique index.
select
  member_id,
  lower(trim(reason)) as reason_norm,
  count(*) as qty
from public.gamification_points
where reason ilike 'Credly:%'
group by member_id, lower(trim(reason))
having count(*) > 1
order by qty desc, member_id
limit 100;

-- 2) Enforce uniqueness only for Credly reason rows.
-- Use CONCURRENTLY to reduce lock impact in production.
create unique index concurrently if not exists uq_gp_credly_member_reason_ci
  on public.gamification_points (member_id, lower(trim(reason)))
  where reason ilike 'Credly:%';

-- 3) Post-check: ensure index exists
select
  schemaname,
  tablename,
  indexname,
  indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'gamification_points'
  and indexname = 'uq_gp_credly_member_reason_ci';
