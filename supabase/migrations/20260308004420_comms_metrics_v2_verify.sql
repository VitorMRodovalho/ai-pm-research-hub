-- COMMS_METRICS_V2 verification
-- Run after applying V2 migration and one smoke sync execution.

begin;

do $$
declare
  v_exists boolean;
  v_rls boolean;
  v_count integer;
  v_grant_count integer;
  v_smoke_count integer;
  v_payload record;
begin
  -- table exists and RLS enabled
  select true, c.relrowsecurity
    into v_exists, v_rls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'comms_metrics_ingestion_log'
  limit 1;

  if coalesce(v_exists, false) is false then
    raise exception 'comms_metrics_ingestion_log does not exist';
  end if;
  if coalesce(v_rls, false) is false then
    raise exception 'RLS is not enabled on comms_metrics_ingestion_log';
  end if;

  -- expected policies
  select count(*)
    into v_count
  from pg_policies
  where schemaname = 'public'
    and tablename = 'comms_metrics_ingestion_log'
    and policyname in (
      'comms_ingestion_admin_read',
      'comms_ingestion_admin_insert',
      'comms_ingestion_admin_update'
    );
  if v_count < 3 then
    raise exception 'Missing expected policies on comms_metrics_ingestion_log. Found: %', v_count;
  end if;

  -- expected functions
  select count(*)
    into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'can_manage_comms_metrics',
      'comms_metrics_latest_by_channel'
    );
  if v_count < 2 then
    raise exception 'Missing expected V2 functions. Found: %', v_count;
  end if;

  -- execute grants on functions for authenticated
  select count(*)
    into v_grant_count
  from information_schema.routine_privileges rp
  where rp.routine_schema = 'public'
    and rp.routine_name in (
      'can_manage_comms_metrics',
      'comms_metrics_latest_by_channel'
    )
    and rp.grantee = 'authenticated'
    and rp.privilege_type = 'EXECUTE';
  if v_grant_count < 2 then
    raise exception 'Missing EXECUTE grants for authenticated on V2 functions. Found: %', v_grant_count;
  end if;

  -- smoke evidence from function run
  select count(*)
    into v_smoke_count
  from public.comms_metrics_ingestion_log
  where triggered_by = 'manual_smoke'
    and status = 'success';
  if v_smoke_count = 0 then
    raise exception 'No successful manual_smoke run found in comms_metrics_ingestion_log';
  end if;

  select *
    into v_payload
  from public.comms_metrics_latest_by_channel(7)
  limit 1;

  raise notice 'COMMS_METRICS_V2 verify OK: smoke_runs=% latest_date=% channel=%',
    v_smoke_count, v_payload.metric_date, v_payload.channel;
end
$$;

commit;
