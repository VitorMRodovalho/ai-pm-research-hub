-- COMMS_METRICS_V2 rollback

begin;

drop function if exists public.comms_metrics_latest_by_channel(integer);
drop policy if exists comms_ingestion_admin_update on public.comms_metrics_ingestion_log;
drop policy if exists comms_ingestion_admin_insert on public.comms_metrics_ingestion_log;
drop policy if exists comms_ingestion_admin_read on public.comms_metrics_ingestion_log;
drop table if exists public.comms_metrics_ingestion_log;
drop function if exists public.can_manage_comms_metrics();

commit;
