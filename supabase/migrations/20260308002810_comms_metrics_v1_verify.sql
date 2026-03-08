-- COMMS_METRICS_V1 verification + smoke test
-- Validates objects and permissions, then seeds deterministic smoke rows.

begin;

do $$
declare
  v_exists boolean;
  v_rls boolean;
  v_count integer;
  v_grant_count integer;
  v_payload record;
begin
  -- table exists and RLS enabled
  select true, c.relrowsecurity
    into v_exists, v_rls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'comms_metrics_daily'
  limit 1;

  if coalesce(v_exists, false) is false then
    raise exception 'comms_metrics_daily does not exist';
  end if;
  if coalesce(v_rls, false) is false then
    raise exception 'RLS is not enabled on comms_metrics_daily';
  end if;

  -- expected indexes
  select count(*)
    into v_count
  from pg_indexes
  where schemaname = 'public'
    and tablename = 'comms_metrics_daily'
    and indexname in (
      'uq_comms_metrics_daily_key',
      'idx_comms_metrics_daily_metric_date',
      'idx_comms_metrics_daily_channel'
    );
  if v_count < 3 then
    raise exception 'Missing expected indexes on comms_metrics_daily. Found: %', v_count;
  end if;

  -- expected policies
  select count(*)
    into v_count
  from pg_policies
  where schemaname = 'public'
    and tablename = 'comms_metrics_daily'
    and policyname in (
      'comms_metrics_admin_read',
      'comms_metrics_admin_insert',
      'comms_metrics_admin_update',
      'comms_metrics_admin_delete'
    );
  if v_count < 4 then
    raise exception 'Missing expected RLS policies on comms_metrics_daily. Found: %', v_count;
  end if;

  -- function exists + grant to authenticated
  select count(*)
    into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'comms_metrics_latest';
  if v_count = 0 then
    raise exception 'Function public.comms_metrics_latest() does not exist';
  end if;

  select count(*)
    into v_grant_count
  from information_schema.routine_privileges rp
  where rp.routine_schema = 'public'
    and rp.routine_name = 'comms_metrics_latest'
    and rp.grantee = 'authenticated'
    and rp.privilege_type = 'EXECUTE';
  if v_grant_count = 0 then
    raise exception 'EXECUTE grant missing for authenticated on public.comms_metrics_latest()';
  end if;

  -- deterministic smoke rows for today
  insert into public.comms_metrics_daily (
    metric_date, channel, audience, reach, engagement_rate, leads, source, payload
  )
  values
    (current_date, 'linkedin', 1000, 650, 0.0725, 20, 'manual_smoke', '{"seed":"comms_metrics_v1_verify"}'::jsonb),
    (current_date, 'newsletter', 700, 480, 0.1150, 14, 'manual_smoke', '{"seed":"comms_metrics_v1_verify"}'::jsonb)
  on conflict (metric_date, channel, source)
  do update set
    audience = excluded.audience,
    reach = excluded.reach,
    engagement_rate = excluded.engagement_rate,
    leads = excluded.leads,
    payload = excluded.payload;

  select *
    into v_payload
  from public.comms_metrics_latest();

  if v_payload.metric_date is null then
    raise exception 'comms_metrics_latest() returned null metric_date';
  end if;
  if coalesce(v_payload.rows_count, 0) <= 0 then
    raise exception 'comms_metrics_latest() returned zero rows_count';
  end if;

  raise notice 'COMMS_METRICS_V1 verify OK: date=%, audience=%, reach=%, engagement=%, leads=%, rows=%',
    v_payload.metric_date, v_payload.audience, v_payload.reach, v_payload.engagement, v_payload.leads, v_payload.rows_count;
end
$$;

commit;
