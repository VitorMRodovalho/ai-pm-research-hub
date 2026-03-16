-- Fix: exec_chapter_roi — replace reference to archived member_chapter_affiliations
-- table with members.chapter data via analytics_member_scope.
-- The member_chapter_affiliations table was moved to z_archive (W132) with 0 rows.
-- Members already have chapter info (PMI-GO, PMI-CE, etc.) on the members table.

CREATE OR REPLACE FUNCTION public.exec_chapter_roi(
  p_cycle_code text DEFAULT NULL::text,
  p_tribe_id integer DEFAULT NULL::integer,
  p_chapter text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $function$
declare
  v_result jsonb;
begin
  if not public.can_read_internal_analytics() then
    raise exception 'Internal analytics access required';
  end if;

  with scoped as (
    select * from public.analytics_member_scope(p_cycle_code, p_tribe_id, p_chapter)
  ),
  affiliation_scope as (
    select distinct
      s.member_id,
      s.chapter as chapter_code,
      s.first_cycle_start,
      s.cycle_start,
      s.is_current
    from scoped s
    where s.chapter is not null and trim(s.chapter) <> ''
  )
  select jsonb_build_object(
    'cycle_code', (select max(cycle_code) from scoped),
    'cycle_label', (select max(cycle_label) from scoped),
    'attribution_window', jsonb_build_object('before_days', 30, 'after_days', 90),
    'chapters', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.attributed_conversions desc, r.chapter_code)
      from (
        select
          chapter_code,
          count(*)::integer as affiliated_members,
          count(*) filter (where is_current)::integer as current_active_affiliates,
          count(*) filter (
            where first_cycle_start is not null
              and first_cycle_start >= cycle_start - interval '30 days'
              and first_cycle_start < cycle_start + interval '90 days'
          )::integer as attributed_conversions
        from affiliation_scope
        group by chapter_code
      ) r
    ), '[]'::jsonb)
  ) into v_result;

  return coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'attribution_window', jsonb_build_object('before_days', 30, 'after_days', 90),
    'chapters', '[]'::jsonb
  ));
end;
$function$;
