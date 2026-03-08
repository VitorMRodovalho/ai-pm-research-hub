-- COMMS_METRICS_V3 rollback

begin;

drop function if exists public.publish_comms_metrics_batch(text, date);
drop policy if exists comms_publish_log_admin_read on public.comms_metrics_publish_log;
drop table if exists public.comms_metrics_publish_log;
alter table public.comms_metrics_daily
  drop column if exists publish_batch_id,
  drop column if exists published_by,
  drop column if exists published_at;

commit;
