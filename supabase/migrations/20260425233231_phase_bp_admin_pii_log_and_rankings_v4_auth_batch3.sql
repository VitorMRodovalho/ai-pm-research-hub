-- Track Q Phase B' — V4 auth migration (batch 3)
--
-- Migrates 2 admin functions from p52 Q-A captures from legacy V3 authority
-- (`is_superadmin OR manager OR deputy_manager`) to V4
-- `can_by_member('manage_platform')`. Same pattern as batch 1+2.
--
-- Privilege expansion: zero in current production (same safety check
-- result as previous batches: legacy=2, v4=2, no gain/lose).
--
-- Functions migrated:
--   1. get_pii_access_log_admin — admin reader of PII access audit log.
--      Critical to keep narrow (admin only). manage_platform fits.
--   2. recalculate_cycle_rankings — selection cycle ranking recalc + audit
--      snapshot. Admin only.
--
-- Bodies otherwise verbatim from p52 Q-A captures.

CREATE OR REPLACE FUNCTION public.get_pii_access_log_admin(p_target_member_id uuid DEFAULT NULL::uuid, p_accessor_id uuid DEFAULT NULL::uuid, p_days integer DEFAULT 30, p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: admin only');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', pl.id,
    'accessor', jsonb_build_object('id', a.id, 'name', a.name, 'role', a.operational_role),
    'target', jsonb_build_object('id', t.id, 'name', t.name, 'chapter', t.chapter),
    'fields_accessed', pl.fields_accessed,
    'context', pl.context,
    'reason', pl.reason,
    'accessed_at', pl.accessed_at
  ) ORDER BY pl.accessed_at DESC), '[]'::jsonb)
  INTO v_result
  FROM pii_access_log pl
  JOIN members a ON a.id = pl.accessor_id
  JOIN members t ON t.id = pl.target_member_id
  WHERE pl.accessed_at >= now() - (p_days || ' days')::interval
    AND (p_target_member_id IS NULL OR pl.target_member_id = p_target_member_id)
    AND (p_accessor_id IS NULL OR pl.accessor_id = p_accessor_id)
  LIMIT p_limit;

  RETURN jsonb_build_object('log', v_result, 'filters', jsonb_build_object('days', p_days, 'target', p_target_member_id, 'accessor', p_accessor_id));
END;
$function$;

CREATE OR REPLACE FUNCTION public.recalculate_cycle_rankings(p_cycle_id uuid, p_reason text DEFAULT 'manual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_researcher_count int;
  v_leader_count int;
  v_snapshot_id uuid;
BEGIN
  -- Auth (admin only)
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission for ranking recalc';
  END IF;

  -- Reset ranks
  UPDATE selection_applications
  SET rank_researcher = NULL, rank_leader = NULL
  WHERE cycle_id = p_cycle_id;

  -- Ranking 1: researcher track (Standard Competition Ranking via RANK())
  -- Includes: role_applied='researcher' OR promotion_path='direct_researcher'
  -- Excludes: promoted to leader AND leader app already approved/converted (they're not researchers anymore)
  WITH ranked AS (
    SELECT a.id,
      RANK() OVER (
        ORDER BY a.research_score DESC NULLS LAST, a.applicant_name ASC
      ) as rnk
    FROM selection_applications a
    WHERE a.cycle_id = p_cycle_id
      AND a.role_applied = 'researcher'
      AND a.research_score IS NOT NULL
      AND a.status NOT IN ('withdrawn','rejected','cancelled','merged')
      AND NOT EXISTS (
        -- Exclude if linked leader app is approved/converted
        SELECT 1 FROM selection_applications la
        WHERE la.id = a.linked_application_id
          AND la.role_applied = 'leader'
          AND la.status IN ('approved','converted')
      )
  )
  UPDATE selection_applications a
  SET rank_researcher = r.rnk
  FROM ranked r WHERE a.id = r.id;

  GET DIAGNOSTICS v_researcher_count = ROW_COUNT;

  -- Ranking 2: leader track
  WITH ranked AS (
    SELECT a.id,
      RANK() OVER (
        ORDER BY a.leader_score DESC NULLS LAST, a.applicant_name ASC
      ) as rnk
    FROM selection_applications a
    WHERE a.cycle_id = p_cycle_id
      AND (a.role_applied = 'leader' OR a.promotion_path = 'triaged_to_leader')
      AND a.leader_score IS NOT NULL
      AND a.status NOT IN ('withdrawn','rejected','cancelled','merged')
  )
  UPDATE selection_applications a
  SET rank_leader = r.rnk
  FROM ranked r WHERE a.id = r.id;

  GET DIAGNOSTICS v_leader_count = ROW_COUNT;

  -- Audit snapshot
  INSERT INTO selection_ranking_snapshots (cycle_id, triggered_by, reason, rankings, formula_version)
  SELECT p_cycle_id, v_caller_id, p_reason,
    jsonb_agg(jsonb_build_object(
      'application_id', id,
      'applicant_name', applicant_name,
      'role_applied', role_applied,
      'promotion_path', promotion_path,
      'research_score', research_score,
      'leader_score', leader_score,
      'rank_researcher', rank_researcher,
      'rank_leader', rank_leader,
      'status', status
    )),
    'v1.0-cr047'
  FROM selection_applications
  WHERE cycle_id = p_cycle_id
  RETURNING id INTO v_snapshot_id;

  RETURN jsonb_build_object(
    'success', true,
    'cycle_id', p_cycle_id,
    'researcher_ranked', v_researcher_count,
    'leader_ranked', v_leader_count,
    'snapshot_id', v_snapshot_id,
    'formula_version', 'v1.0-cr047',
    'formula', jsonb_build_object(
      'research_score', 'objective_pert + interview_pert',
      'leader_score', 'research_score * 0.7 + leader_extra_pert * 0.3',
      'tiebreaker', 'RANK() OVER (..., applicant_name ASC) — Standard Competition Ranking ISO 80000-2'
    )
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
