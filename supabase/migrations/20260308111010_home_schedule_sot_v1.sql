-- Home Schedule Source of Truth (S-HOME-SCHEDULE-SOT)
-- Single-row table consumed by homepage runtime to avoid date hardcodes.

create table if not exists public.home_schedule (
  id smallint primary key default 1 check (id = 1),
  kickoff_at timestamptz not null,
  selection_deadline_at timestamptz not null,
  recurring_weekday smallint not null check (recurring_weekday between 0 and 6),
  recurring_start_brt time not null,
  recurring_end_brt time not null,
  platform_label text not null default 'Google Meet',
  updated_at timestamptz not null default now()
);

insert into public.home_schedule (
  id,
  kickoff_at,
  selection_deadline_at,
  recurring_weekday,
  recurring_start_brt,
  recurring_end_brt,
  platform_label
)
values (
  1,
  '2026-03-12T22:30:00Z',
  '2026-03-09T15:00:00Z',
  4,
  '19:30',
  '20:30',
  'Google Meet'
)
on conflict (id) do update
set
  kickoff_at = excluded.kickoff_at,
  selection_deadline_at = excluded.selection_deadline_at,
  recurring_weekday = excluded.recurring_weekday,
  recurring_start_brt = excluded.recurring_start_brt,
  recurring_end_brt = excluded.recurring_end_brt,
  platform_label = excluded.platform_label,
  updated_at = now();

alter table public.home_schedule enable row level security;

drop policy if exists home_schedule_read on public.home_schedule;
create policy home_schedule_read
on public.home_schedule
for select
using (true);

drop policy if exists home_schedule_manage on public.home_schedule;
create policy home_schedule_manage
on public.home_schedule
for all
to authenticated
using (has_min_tier(4))
with check (has_min_tier(4));
