-- Credly/Gamification audit pack (v1)
-- Date: 2026-03-08
-- Purpose: measure legacy inconsistencies before/after sanitize script.

-- 1) Credly rows by points distribution
select points, count(*) as qty
from public.gamification_points
where reason ilike 'Credly:%'
group by points
order by points;

-- 2) Potential legacy mismatches where title strongly indicates Tier 1, but points != 50
select reason, points, count(*) as qty
from public.gamification_points
where reason ilike 'Credly:%'
  and (
    lower(reason) like '%project management professional%'
    or lower(reason) like '%pmp%'
    or lower(reason) like '%cpmai%'
    or lower(reason) like '%pmi-cpmai%'
  )
  and lower(reason) not like '%introduction to cognitive project management in ai%'
  and points <> 50
group by reason, points
order by qty desc, reason;

-- 3) Tier 2 spot-check mismatches (known from backlog)
select reason, points, count(*) as qty
from public.gamification_points
where reason ilike 'Credly:%'
  and (
    lower(reason) like '%business intelligence%'
    or lower(reason) like '%scrum foundation%'
    or lower(reason) like '%sfpc%'
  )
  and points <> 25
group by reason, points
order by qty desc, reason;

-- 4) Duplicate Credly entries by member+reason (case-insensitive)
select
  member_id,
  lower(trim(reason)) as reason_norm,
  count(*) as qty,
  min(created_at) as first_seen,
  max(created_at) as last_seen
from public.gamification_points
where reason ilike 'Credly:%'
group by member_id, lower(trim(reason))
having count(*) > 1
order by qty desc, member_id
limit 200;

-- 5) Double counting risk: manual course points + matching Credly trail badge
with trail_map as (
  select * from (values
    ('GENAI_OVERVIEW',  '%generative ai overview%project managers%'),
    ('DATA_LANDSCAPE',  '%data landscape%genai%project managers%'),
    ('PROMPT_ENG',      '%prompt engineering%project managers%'),
    ('PRACTICAL_GENAI', '%practical application%gen ai%project managers%'),
    ('CDBA_INTRO',      '%citizen developer%cdba%'),
    ('CPMAI_INTRO',     '%introduction%cognitive%cpmai%'),
    ('AI_INFRA',        '%ai in infrastructure%construction%'),
    ('AI_AGILE',        '%ai in agile delivery%')
  ) as t(code, credly_pattern)
)
select
  m.member_id,
  m.reason as manual_reason,
  c.reason as credly_reason,
  m.points as manual_points,
  c.points as credly_points
from public.gamification_points m
join trail_map tm on m.reason ilike ('Curso: ' || tm.code || '%')
join public.gamification_points c
  on c.member_id = m.member_id
 and c.reason ilike 'Credly:%'
 and lower(c.reason) like tm.credly_pattern
where m.category = 'course'
order by m.member_id, m.reason
limit 300;

-- 6) members.credly_badges JSON entries with null tier
select count(*) as null_tier_badges
from public.members m
cross join lateral jsonb_array_elements(coalesce(m.credly_badges, '[]'::jsonb)) as b
where b ? 'tier' and (b->>'tier') is null;

-- 7) members.credly_badges JSON entries without tier key
select count(*) as missing_tier_key_badges
from public.members m
cross join lateral jsonb_array_elements(coalesce(m.credly_badges, '[]'::jsonb)) as b
where not (b ? 'tier');
