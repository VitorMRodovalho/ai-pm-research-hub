-- Credly/Gamification sanitize pack (v1)
-- Date: 2026-03-08
-- Purpose: fix legacy Credly points, remove duplicates and prevent manual-vs-Credly double counting.
-- Run in maintenance window.

begin;

-- 0) Backup impacted rows (idempotent table + per-run snapshot)
create table if not exists public._bak_gp_credly_sanitize_v1 (
  run_at timestamptz not null,
  id uuid not null,
  member_id uuid,
  reason text,
  points int,
  category text,
  created_at timestamptz,
  payload jsonb
);

insert into public._bak_gp_credly_sanitize_v1 (run_at, id, member_id, reason, points, category, created_at, payload)
select
  now(),
  gp.id,
  gp.member_id,
  gp.reason,
  gp.points,
  gp.category,
  gp.created_at,
  to_jsonb(gp)
from public.gamification_points gp
where gp.reason ilike 'Credly:%'
   or (gp.category = 'course' and gp.reason ilike 'Curso:%');

-- 1) Normalize legacy Credly points according to keyword tiers
with scored as (
  select
    id,
    case
      -- PMI mini trail exceptions must win over generic Tier 1/2 keyword matches
      when lower(reason) ~ '(generative ai overview.*project managers|data landscape.*genai.*project managers|prompt engineering.*project managers|practical application.*gen ai.*project managers|citizen developer.*cdba|introduction.*cognitive.*cpmai|ai in infrastructure.*construction|ai in agile delivery)'
        then 15
      -- Tier 1 (+50)
      when lower(reason) ~ '(project management professional|\bpmp\b|\bcpmai\b|pmi-cpmai|cognitive project management|\bpmi-acp\b|\bpmi-cp\b|\bpgmp\b|\bpfmp\b|\bpmi-rmp\b|\bpmi-sp\b)'
        then 50
      -- Tier 2 (+25)
      when lower(reason) ~ '(\bcapm\b|pmi-pbsm|disciplined agile|professional scrum master|\bpsm\b|\bpspo\b|\bsafe\b|scaled agile|\bcsm\b|certified scrum|prosci|change management|finops|aws certified|azure|google cloud certified|data analyst|data engineer|data scientist|itil|togaf|cobit|business intelligence|scrum foundation|sfpc)'
        then 25
      -- Tier 3 (+15)
      when lower(reason) ~ '(artificial intelligence|machine learning|deep learning|generative ai|gen ai|genai|prompt engineering|data science|data landscape|business intelligence|cognitive|project management|agile|scrum)'
        then 15
      else null
    end as expected_points
  from public.gamification_points
  where reason ilike 'Credly:%'
)
update public.gamification_points gp
set points = s.expected_points
from scored s
where gp.id = s.id
  and s.expected_points is not null
  and gp.points is distinct from s.expected_points;

-- 2) Deduplicate Credly rows per member+reason (case-insensitive), keep oldest row (app behavior parity)
with ranked as (
  select
    id,
    row_number() over (
      partition by member_id, lower(trim(reason))
      order by created_at asc nulls first, id asc
    ) as rn
  from public.gamification_points
  where reason ilike 'Credly:%'
)
delete from public.gamification_points gp
using ranked r
where gp.id = r.id
  and r.rn > 1;

-- 3) Remove manual course points already covered by matching Credly trail badges
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
), manual_to_delete as (
  select distinct m.id
  from public.gamification_points m
  join trail_map tm on m.reason ilike ('Curso: ' || tm.code || '%')
  join public.gamification_points c
    on c.member_id = m.member_id
   and c.reason ilike 'Credly:%'
   and lower(c.reason) like tm.credly_pattern
  where m.category = 'course'
)
delete from public.gamification_points gp
using manual_to_delete d
where gp.id = d.id;

-- 4) Repair missing/null tier/points inside members.credly_badges JSON when points or tier can be inferred
with fixed as (
  select
    m.id,
    jsonb_agg(
      case
        when (b ? 'tier') and (b->>'tier') is null and (b ? 'points') and (b->>'points') ~ '^[0-9]+$' then
          jsonb_set(b, '{tier}', to_jsonb(case (b->>'points')::int when 50 then 1 when 25 then 2 when 15 then 3 else 4 end), true)
        when not (b ? 'tier') and (b ? 'points') and (b->>'points') ~ '^[0-9]+$' then
          jsonb_set(b, '{tier}', to_jsonb(case (b->>'points')::int when 50 then 1 when 25 then 2 when 15 then 3 else 4 end), true)
        when ((not (b ? 'points')) or (b->>'points') is null) and (b ? 'tier') and (b->>'tier') ~ '^[0-9]+$' then
          jsonb_set(b, '{points}', to_jsonb(case (b->>'tier')::int when 1 then 50 when 2 then 25 when 3 then 15 else 10 end), true)
        else b
      end
      order by ord
    ) as badges
  from public.members m
  cross join lateral jsonb_array_elements(coalesce(m.credly_badges, '[]'::jsonb)) with ordinality as e(b, ord)
  group by m.id
)
update public.members m
set credly_badges = f.badges,
    credly_verified_at = now()
from fixed f
where m.id = f.id
  and m.credly_badges is distinct from f.badges;

commit;

-- Optional hardening index (run separately if desired after verifying no duplicates remain):
-- create unique index if not exists uq_gp_credly_member_reason_ci
--   on public.gamification_points (member_id, lower(trim(reason)))
--   where reason ilike 'Credly:%';
