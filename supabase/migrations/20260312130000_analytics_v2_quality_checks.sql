-- ═══════════════════════════════════════════════════════════════════════════
-- Analytics V2 quality checks
-- Date: 2026-03-12
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.exec_analytics_v2_quality(
  p_cycle_code text default null,
  p_tribe_id integer default null,
  p_chapter text default null
)
returns jsonb
language plpgsql
security definer
stable
as $$
declare
  v_funnel jsonb;
  v_impact jsonb;
  v_roi jsonb;
  v_stages jsonb;
  v_total integer := 0;
  v_onboarding integer := 0;
  v_allocated integer := 0;
  v_published integer := 0;
  v_before integer := 30;
  v_after integer := 90;
  v_issues text[] := '{}';
  v_warnings text[] := '{}';
begin
  if not public.can_read_internal_analytics() then
    raise exception 'Internal analytics access required';
  end if;

  v_funnel := public.exec_funnel_v2(p_cycle_code, p_tribe_id, p_chapter);
  v_impact := public.exec_impact_hours_v2(p_cycle_code, p_tribe_id, p_chapter);
  v_roi := public.exec_chapter_roi(p_cycle_code, p_tribe_id, p_chapter);
  v_stages := coalesce(v_funnel -> 'stages', '{}'::jsonb);

  v_total := coalesce((v_stages ->> 'total_members')::integer, 0);
  v_onboarding := coalesce((v_stages ->> 'members_with_full_core_trail')::integer, 0);
  v_allocated := coalesce((v_stages ->> 'members_allocated_to_tribe')::integer, 0);
  v_published := coalesce((v_stages ->> 'members_with_published_artifact')::integer, 0);

  if v_total < 0 or v_onboarding < 0 or v_allocated < 0 or v_published < 0 then
    v_issues := array_append(v_issues, 'negative_stage_values');
  end if;

  if v_onboarding > v_total then
    v_issues := array_append(v_issues, 'onboarding_exceeds_total');
  end if;
  if v_allocated > v_total then
    v_issues := array_append(v_issues, 'allocated_exceeds_total');
  end if;
  if v_published > v_total then
    v_issues := array_append(v_issues, 'published_exceeds_total');
  end if;

  if v_published > v_allocated and v_allocated > 0 then
    v_warnings := array_append(v_warnings, 'published_exceeds_allocated');
  end if;

  if coalesce((v_impact ->> 'total_impact_hours')::numeric, 0) < 0 then
    v_issues := array_append(v_issues, 'negative_impact_hours');
  end if;

  if coalesce((v_impact ->> 'percent_of_target')::numeric, 0) > 200 then
    v_warnings := array_append(v_warnings, 'impact_percent_above_200');
  end if;

  if coalesce((v_roi -> 'attribution_window' ->> 'before_days')::integer, v_before) <> v_before
     or coalesce((v_roi -> 'attribution_window' ->> 'after_days')::integer, v_after) <> v_after then
    v_warnings := array_append(v_warnings, 'unexpected_roi_window');
  end if;

  return jsonb_build_object(
    'ok', coalesce(array_length(v_issues, 1), 0) = 0,
    'filters', jsonb_build_object(
      'cycle_code', p_cycle_code,
      'tribe_id', p_tribe_id,
      'chapter', p_chapter
    ),
    'attribution_window', jsonb_build_object(
      'before_days', v_before,
      'after_days', v_after
    ),
    'issues', to_jsonb(v_issues),
    'warnings', to_jsonb(v_warnings),
    'snapshot', jsonb_build_object(
      'funnel_stages', v_stages,
      'impact_total_hours', coalesce((v_impact ->> 'total_impact_hours')::numeric, 0),
      'impact_percent_of_target', coalesce((v_impact ->> 'percent_of_target')::numeric, 0),
      'roi_chapters_count', coalesce(jsonb_array_length(v_roi -> 'chapters'), 0)
    )
  );
end;
$$;

grant execute on function public.exec_analytics_v2_quality(text, integer, text) to authenticated;

commit;
