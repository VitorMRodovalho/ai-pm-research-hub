-- p277 / #419 (ADR-0100) — metric 2 continuation: get_cycle_report org-level active_member converge.
--
-- WHAT: get_cycle_report computed its org-level active-member count + by-role breakdown with
--   is_active-ONLY (= 53), the +1 real drift vs the canonical is_active AND current_cycle_active
--   (= 52, audit D5). Converges both to the canonical v_active_members view (53 → 52).
--     - members.active            : count(*) FILTER (WHERE is_active)  → count(*) FROM v_active_members
--     - members.by_role base      : FROM members WHERE is_active       → FROM v_active_members
--   LEFT ALONE (different metric): tribes[].member_count is tribe-scoped roster (= #419 step 4),
--   and observers/alumni are member_status lifecycle buckets. impact_hours already inherits the
--   canonical via get_homepage_stats (metric 1).
--
--   v_active_members gains an operational_role column (append-only) so the by-role breakdown can
--   group on it from the canonical set.
--
-- WHY: ADR-0100 §2.2/§2.3 single canonical active-member set; continuation of metric 2 (the view +
--   3 RPCs shipped in migration 062). get_cycle_report keeps SET search_path TO '' (fully-qualified).
--
-- ROLLBACK: re-CREATE get_cycle_report with is_active-only counts; CREATE OR REPLACE VIEW
--   v_active_members without operational_role.

-- ── extend the canonical view (append-only column) ──────────────────────────
CREATE OR REPLACE VIEW public.v_active_members AS
  SELECT id, organization_id, chapter, tribe_id, person_id, operational_role
  FROM public.members
  WHERE is_active = true AND current_cycle_active = true;
-- (CREATE OR REPLACE VIEW preserves the migration-062 grants: REVOKE anon/PUBLIC + GRANT authenticated/service_role)

-- ── converge get_cycle_report org-level active counts ───────────────────────
CREATE OR REPLACE FUNCTION public.get_cycle_report(p_cycle integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_result := jsonb_build_object(
    'cycle', p_cycle,
    'generated_at', now(),
    'members', (SELECT jsonb_build_object(
      'total', count(*),
      'active', (SELECT count(*) FROM public.v_active_members),
      'observers', count(*) FILTER (WHERE member_status = 'observer'),
      'alumni', count(*) FILTER (WHERE member_status = 'alumni'),
      'by_role', (SELECT coalesce(jsonb_object_agg(operational_role, cnt), '{}') FROM (SELECT operational_role, count(*) as cnt FROM public.v_active_members GROUP BY operational_role) r)
    ) FROM public.members),
    'tribes', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'name', t.name,
      'member_count', (SELECT count(*) FROM public.members WHERE tribe_id = t.id AND is_active),
      'board_progress', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE bi.status = 'done') / count(*)) END FROM public.project_boards pb JOIN public.initiatives i ON i.id = pb.initiative_id JOIN public.board_items bi ON bi.board_id = pb.id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived')
    ) ORDER BY t.id), '[]') FROM public.tribes t WHERE t.is_active),
    'events', (SELECT jsonb_build_object(
      'total', count(*),
      'total_impact_hours', (SELECT * FROM public.get_homepage_stats())->'impact_hours'
    ) FROM public.events WHERE date >= '2026-01-01'),
    'boards', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', pb.id, 'title', pb.board_name,
      'total_items', (SELECT count(*) FROM public.board_items WHERE board_id = pb.id AND status != 'archived'),
      'done_items', (SELECT count(*) FROM public.board_items WHERE board_id = pb.id AND status = 'done'),
      'progress', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE status = 'done') / count(*)) END FROM public.board_items WHERE board_id = pb.id AND status != 'archived')
    )), '[]') FROM public.project_boards pb WHERE pb.is_active),
    'kpis', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'name', k.kpi_label_pt, 'name_en', k.kpi_label_en,
      'target', k.target_value, 'current', k.current_value,
      'pct', CASE WHEN k.target_value > 0 THEN round(100.0 * k.current_value / k.target_value) ELSE 0 END
    )), '[]') FROM public.annual_kpi_targets k WHERE k.year = 2026),
    'platform', jsonb_build_object(
      'releases_count', (SELECT count(*) FROM public.releases),
      'governance_entries', 125,
      'zero_cost', true,
      'stack', 'Astro 5 + React 19 + Tailwind 4 + Supabase + Cloudflare Pages'
    )
  );
  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
