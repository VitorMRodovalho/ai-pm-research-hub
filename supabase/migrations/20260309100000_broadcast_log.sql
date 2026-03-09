-- ═══════════════════════════════════════════════════════════════════════════
-- WAVE 3: Broadcast de Email — Tabela de log + RLS
-- Date: 2026-03-09
-- Purpose: Store broadcast history for tribe leader → tribe communications
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.broadcast_log (
  id uuid primary key default gen_random_uuid(),
  tribe_id integer not null references public.tribes(id),
  sender_id uuid not null references public.members(id),
  subject text not null,
  body text not null,
  recipient_count integer not null default 0,
  status text not null default 'sent' check (status in ('sent', 'failed', 'partial')),
  error_detail text,
  sent_at timestamptz not null default now()
);

create index if not exists idx_broadcast_log_tribe on public.broadcast_log(tribe_id, sent_at desc);
create index if not exists idx_broadcast_log_sender on public.broadcast_log(sender_id);

comment on table public.broadcast_log
  is 'Audit log for tribe broadcast emails. Each row = one broadcast dispatched by a leader or admin.';

alter table public.broadcast_log enable row level security;

-- Policy: Sender can read their own broadcasts
drop policy if exists "broadcast_log_read_sender" on public.broadcast_log;
create policy "broadcast_log_read_sender" on public.broadcast_log
  for select to authenticated
  using (
    sender_id = (
      select m.id from public.members m where m.auth_id = auth.uid() limit 1
    )
  );

-- Policy: Tribe leader can read broadcasts of their tribe
drop policy if exists "broadcast_log_read_tribe_leader" on public.broadcast_log;
create policy "broadcast_log_read_tribe_leader" on public.broadcast_log
  for select to authenticated
  using (
    tribe_id = (
      select m.tribe_id from public.members m
      where m.auth_id = auth.uid()
        and m.operational_role = 'tribe_leader'
      limit 1
    )
  );

-- Policy: Admin (tier >= 4) can read all broadcasts
drop policy if exists "broadcast_log_read_admin" on public.broadcast_log;
create policy "broadcast_log_read_admin" on public.broadcast_log
  for select to authenticated
  using (public.has_min_tier(4));

-- Insert is done via service_role (Edge Function), which bypasses RLS
-- No insert policy needed for authenticated users

-- Rate limit helper: count broadcasts today for a tribe
create or replace function public.broadcast_count_today(p_tribe_id integer)
returns integer
language sql
security definer
stable
as $$
  select count(*)::integer
  from public.broadcast_log
  where tribe_id = p_tribe_id
    and sent_at >= current_date
    and status = 'sent';
$$;

commit;
