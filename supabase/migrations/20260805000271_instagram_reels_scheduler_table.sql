-- Instagram Reels scheduler — durable queue of scheduled organic posts.
-- The Content Publishing API has NO future-time field (it publishes on call), so the
-- platform owns scheduling: rows land here with a future scheduled_at, and the
-- publish-scheduled cron/EF drains due rows through the existing publish-instagram fn.
-- Mirrors comms_metrics_ingestion_log conventions (admin gate = can_manage_comms_metrics).
--
-- NOTE (apply order): apply this migration (table + bucket) FIRST. The cron that drains
-- it lives in the NEXT migration and must be applied ONLY after publish-scheduled is
-- deployed + dry-run validated (else the cron POSTs to a non-existent function).

begin;

-- 1) the scheduled-posts queue
create table if not exists public.comms_scheduled_posts (
  id uuid primary key default gen_random_uuid(),
  channel text not null default 'instagram',
  media_type text not null check (media_type in ('IMAGE', 'CAROUSEL', 'REELS', 'STORIES')),
  payload jsonb not null,              -- full publish-instagram body (video_url, caption, share_to_feed, children...)
  scheduled_at timestamptz not null,
  status text not null default 'pending'
    check (status in ('pending', 'publishing', 'published', 'failed', 'canceled')),
  attempts integer not null default 0,
  external_id text,                    -- IG media id once published
  permalink text,
  error text,
  label text,                          -- human label, e.g. 'reel:vitor_projetos'
  created_at timestamptz not null default now(),
  published_at timestamptz
);

-- drain query is (status, scheduled_at) — index it
create index if not exists idx_comms_scheduled_due
  on public.comms_scheduled_posts (status, scheduled_at);

comment on table public.comms_scheduled_posts is
  'Durable queue of scheduled organic social posts. Drained by the publish-scheduled EF (cron) through publish-instagram. No PII.';

-- 2) RLS — admin-only (Tier 4 / manager) read+write; the EF runs as service role (bypasses RLS).
alter table public.comms_scheduled_posts enable row level security;

drop policy if exists comms_scheduled_admin_read on public.comms_scheduled_posts;
create policy comms_scheduled_admin_read
  on public.comms_scheduled_posts
  for select to authenticated
  using (public.can_manage_comms_metrics());

drop policy if exists comms_scheduled_admin_insert on public.comms_scheduled_posts;
create policy comms_scheduled_admin_insert
  on public.comms_scheduled_posts
  for insert to authenticated
  with check (public.can_manage_comms_metrics());

drop policy if exists comms_scheduled_admin_update on public.comms_scheduled_posts;
create policy comms_scheduled_admin_update
  on public.comms_scheduled_posts
  for update to authenticated
  using (public.can_manage_comms_metrics())
  with check (public.can_manage_comms_metrics());

drop policy if exists comms_scheduled_admin_delete on public.comms_scheduled_posts;
create policy comms_scheduled_admin_delete
  on public.comms_scheduled_posts
  for delete to authenticated
  using (public.can_manage_comms_metrics());

-- 3) the comms-media bucket was image-only (jpeg/png/webp, 5MB). Reels need MP4 + headroom
--    (largest Short ≈ 25MB). Add video/mp4 and raise the limit to 50MB.
update storage.buckets
  set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'video/mp4'],
      file_size_limit = 52428800
  where id = 'comms-media';

commit;
