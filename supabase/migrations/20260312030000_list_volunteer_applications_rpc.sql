-- ═══════════════════════════════════════════════════════════════════════════
-- Wave 9: Paginated volunteer applications list RPC
-- Returns row-level data for the /admin/selection frontend.
-- LGPD-sensitive: admin/superadmin only (permission check inside RPC).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.list_volunteer_applications(
  p_cycle    INTEGER DEFAULT NULL,
  p_search   TEXT DEFAULT NULL,
  p_limit    INTEGER DEFAULT 50,
  p_offset   INTEGER DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
BEGIN
  IF NOT (SELECT is_superadmin OR operational_role IN ('manager','deputy_manager','co_gp')
          FROM members WHERE auth_id = auth.uid()) THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  SELECT json_build_object(
    'total', (
      SELECT COUNT(*) FROM volunteer_applications va
      WHERE (p_cycle IS NULL OR va.cycle = p_cycle)
        AND (p_search IS NULL OR p_search = ''
             OR va.first_name ILIKE '%' || p_search || '%'
             OR va.last_name ILIKE '%' || p_search || '%'
             OR va.state ILIKE '%' || p_search || '%'
             OR va.country ILIKE '%' || p_search || '%'
             OR EXISTS (SELECT 1 FROM unnest(va.certifications) c WHERE c ILIKE '%' || p_search || '%'))
    ),
    'rows', (
      SELECT COALESCE(json_agg(row_to_json(r)), '[]'::JSON) FROM (
        SELECT
          va.id,
          va.first_name,
          va.last_name,
          va.membership_status,
          va.certifications,
          va.city,
          va.state,
          va.country,
          va.app_status,
          va.areas_of_interest,
          va.cycle,
          va.snapshot_date,
          va.is_existing_member,
          m.name AS matched_member_name,
          m.operational_role AS matched_member_role
        FROM volunteer_applications va
        LEFT JOIN members m ON m.id = va.member_id
        WHERE (p_cycle IS NULL OR va.cycle = p_cycle)
          AND (p_search IS NULL OR p_search = ''
               OR va.first_name ILIKE '%' || p_search || '%'
               OR va.last_name ILIKE '%' || p_search || '%'
               OR va.state ILIKE '%' || p_search || '%'
               OR va.country ILIKE '%' || p_search || '%'
               OR EXISTS (SELECT 1 FROM unnest(va.certifications) c WHERE c ILIKE '%' || p_search || '%'))
        ORDER BY va.cycle DESC, va.last_name ASC, va.first_name ASC
        LIMIT p_limit OFFSET p_offset
      ) r
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_volunteer_applications(INTEGER, TEXT, INTEGER, INTEGER) TO authenticated;

-- Cross-source analytics helper: platform activity summary
CREATE OR REPLACE FUNCTION public.platform_activity_summary()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
BEGIN
  IF NOT (SELECT is_superadmin OR operational_role IN ('manager','deputy_manager','co_gp')
          FROM members WHERE auth_id = auth.uid()) THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  SELECT json_build_object(
    'members', (SELECT json_build_object(
      'total', COUNT(*),
      'active', COUNT(*) FILTER (WHERE current_cycle_active),
      'with_tribe', COUNT(*) FILTER (WHERE tribe_id IS NOT NULL),
      'with_credly', COUNT(*) FILTER (WHERE credly_url IS NOT NULL AND credly_url != ''),
      'with_photo', COUNT(*) FILTER (WHERE photo_url IS NOT NULL AND photo_url != ''),
      'with_linkedin', COUNT(*) FILTER (WHERE linkedin_url IS NOT NULL AND linkedin_url != '')
    ) FROM members WHERE is_active = TRUE),
    'artifacts', (SELECT json_build_object(
      'total', COUNT(*),
      'published', COUNT(*) FILTER (WHERE status = 'published'),
      'pending', COUNT(*) FILTER (WHERE status = 'review')
    ) FROM artifacts),
    'events', (SELECT json_build_object(
      'total', COUNT(*),
      'this_month', COUNT(*) FILTER (WHERE event_date >= date_trunc('month', CURRENT_DATE)),
      'calendar_imported', COUNT(*) FILTER (WHERE source = 'calendar_import')
    ) FROM events),
    'boards', (SELECT json_build_object(
      'total_boards', (SELECT COUNT(*) FROM project_boards WHERE is_active),
      'total_items', COUNT(*),
      'in_progress', COUNT(*) FILTER (WHERE status = 'in_progress'),
      'done', COUNT(*) FILTER (WHERE status = 'done')
    ) FROM board_items),
    'comms', (SELECT json_build_object(
      'total_entries', COUNT(*),
      'total_reach', COALESCE(SUM(reach), 0),
      'total_engagement', COALESCE(SUM(engagement), 0)
    ) FROM comms_metrics),
    'volunteer_apps', (SELECT json_build_object(
      'total', COUNT(*),
      'matched', COUNT(*) FILTER (WHERE is_existing_member),
      'cycles', COUNT(DISTINCT cycle)
    ) FROM volunteer_applications),
    'monthly_activity', (
      SELECT COALESCE(json_agg(row_to_json(ma)), '[]'::JSON) FROM (
        SELECT m AS month_label,
          COALESCE(e_cnt, 0) AS events,
          COALESCE(a_cnt, 0) AS artifacts,
          COALESCE(b_cnt, 0) AS broadcasts
        FROM generate_series(
          date_trunc('month', CURRENT_DATE) - INTERVAL '5 months',
          date_trunc('month', CURRENT_DATE),
          '1 month'
        ) AS s(m)
        LEFT JOIN (
          SELECT date_trunc('month', event_date) AS mo, COUNT(*) AS e_cnt
          FROM events GROUP BY 1
        ) ev ON ev.mo = s.m
        LEFT JOIN (
          SELECT date_trunc('month', created_at) AS mo, COUNT(*) AS a_cnt
          FROM artifacts GROUP BY 1
        ) ar ON ar.mo = s.m
        LEFT JOIN (
          SELECT date_trunc('month', sent_at) AS mo, COUNT(*) AS b_cnt
          FROM broadcast_log WHERE status = 'sent' GROUP BY 1
        ) bc ON bc.mo = s.m
        ORDER BY m
      ) ma
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.platform_activity_summary() TO authenticated;

COMMIT;
