-- COMMS_METRICS_V1 rollback

begin;

revoke execute on function public.comms_metrics_latest() from authenticated;
drop function if exists public.comms_metrics_latest();

drop trigger if exists trg_comms_metrics_updated_at on public.comms_metrics_daily;
drop function if exists public.set_comms_metrics_updated_at();

drop policy if exists comms_metrics_admin_read on public.comms_metrics_daily;
drop policy if exists comms_metrics_admin_insert on public.comms_metrics_daily;
drop policy if exists comms_metrics_admin_update on public.comms_metrics_daily;
drop policy if exists comms_metrics_admin_delete on public.comms_metrics_daily;

drop table if exists public.comms_metrics_daily;

commit;
