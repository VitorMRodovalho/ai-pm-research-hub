-- 1) Table exists
select table_schema, table_name
from information_schema.tables
where table_schema = 'public'
  and table_name = 'home_schedule';

-- 2) Singleton row available
select id, kickoff_at, selection_deadline_at, recurring_weekday, recurring_start_brt, recurring_end_brt, platform_label
from public.home_schedule
where id = 1;

-- 3) RLS policies
select schemaname, tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename = 'home_schedule'
order by policyname;
