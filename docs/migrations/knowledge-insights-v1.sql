-- KNOWLEDGE_INSIGHTS_V1
-- Purpose: establish friction/insight mining foundation for roadmap prioritization.

create table if not exists public.knowledge_insights (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('youtube','drive','linkedin','manual','meeting_notes')),
  asset_id uuid references public.knowledge_assets(id) on delete set null,
  chunk_id uuid references public.knowledge_chunks(id) on delete set null,
  insight_type text not null check (insight_type in ('friction','request','idea','risk','opportunity','decision')),
  taxonomy_area text not null check (taxonomy_area in ('product','process','data','adoption','governance','skills','comms','operations','other')),
  title text not null,
  summary text not null,
  evidence_quote text,
  evidence_url text,
  sentiment_score numeric(5,4),
  impact_score integer not null default 3 check (impact_score between 1 and 5),
  urgency_score integer not null default 3 check (urgency_score between 1 and 5),
  confidence_score numeric(5,4) check (confidence_score is null or (confidence_score >= 0 and confidence_score <= 1)),
  status text not null default 'open' check (status in ('open','triaged','planned','done','dismissed')),
  detected_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.members(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_knowledge_insights_type_status
  on public.knowledge_insights (insight_type, status, detected_at desc);

create index if not exists idx_knowledge_insights_taxonomy
  on public.knowledge_insights (taxonomy_area, status, impact_score desc, urgency_score desc);

create index if not exists idx_knowledge_insights_asset
  on public.knowledge_insights (asset_id, chunk_id);

create index if not exists idx_knowledge_insights_metadata
  on public.knowledge_insights using gin (metadata);

alter table public.knowledge_insights enable row level security;

drop policy if exists knowledge_insights_read on public.knowledge_insights;
create policy knowledge_insights_read
on public.knowledge_insights
for select
to authenticated
using (true);

drop policy if exists knowledge_insights_manage on public.knowledge_insights;
create policy knowledge_insights_manage
on public.knowledge_insights
for all
to authenticated
using (public.can_manage_knowledge())
with check (public.can_manage_knowledge());

create or replace function public.set_knowledge_insights_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_knowledge_insights_updated_at on public.knowledge_insights;
create trigger trg_knowledge_insights_updated_at
before update on public.knowledge_insights
for each row execute function public.set_knowledge_insights_updated_at();

create or replace function public.knowledge_insights_overview(
  p_status text default 'open',
  p_days integer default 30
)
returns table (
  taxonomy_area text,
  insight_type text,
  items integer,
  avg_impact numeric,
  avg_urgency numeric,
  max_detected_at timestamptz
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    i.taxonomy_area,
    i.insight_type,
    count(*)::integer as items,
    round(avg(i.impact_score)::numeric, 2) as avg_impact,
    round(avg(i.urgency_score)::numeric, 2) as avg_urgency,
    max(i.detected_at) as max_detected_at
  from public.knowledge_insights i
  where (p_status is null or i.status = p_status)
    and i.detected_at >= now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 365)))
  group by i.taxonomy_area, i.insight_type
  order by items desc, avg_impact desc, avg_urgency desc;
$$;

revoke all on function public.knowledge_insights_overview(text, integer) from public;
grant execute on function public.knowledge_insights_overview(text, integer) to authenticated;

create or replace function public.knowledge_insights_backlog_candidates(
  p_status text default 'open',
  p_limit integer default 25
)
returns table (
  insight_id uuid,
  title text,
  taxonomy_area text,
  insight_type text,
  status text,
  impact_score integer,
  urgency_score integer,
  priority_score integer,
  confidence_score numeric,
  detected_at timestamptz,
  evidence_url text
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    i.id as insight_id,
    i.title,
    i.taxonomy_area,
    i.insight_type,
    i.status,
    i.impact_score,
    i.urgency_score,
    (i.impact_score * i.urgency_score) as priority_score,
    i.confidence_score,
    i.detected_at,
    i.evidence_url
  from public.knowledge_insights i
  where (p_status is null or i.status = p_status)
  order by priority_score desc, coalesce(i.confidence_score, 0) desc, i.detected_at desc
  limit greatest(1, least(coalesce(p_limit, 25), 200));
$$;

revoke all on function public.knowledge_insights_backlog_candidates(text, integer) from public;
grant execute on function public.knowledge_insights_backlog_candidates(text, integer) to authenticated;
