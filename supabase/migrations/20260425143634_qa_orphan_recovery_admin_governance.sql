-- Track Q-A Batch K — orphan recovery: admin governance (8 fns)
--
-- Captures live bodies as-of 2026-04-25 for admin governance / member
-- excuse / change-request stats / publication audit / cycle ranking
-- recalculation / member transition log / changelog reader. Bodies
-- preserved verbatim from `pg_get_functiondef` — no behavior change.
--
-- Phase B drift signals:
-- 1. mark_member_excused uses members.tribe_id directly for tribe leader
--    authority gate (post-ADR-0015 the canonical path is engagements).
--    Captured verbatim — Phase 5 of ADR-0015 will resolve.
-- 2. recalculate_cycle_rankings + import_*_evaluations both implement PERT
--    aggregation independently. Phase B candidate: extract a helper.
-- 3. publish_comms_metrics_batch uses can_manage_comms_metrics() (different
--    authority surface from the rest of the batch's
--    is_superadmin/operational_role checks). Acceptable — function-specific
--    capability gate.

CREATE OR REPLACE FUNCTION public.admin_generate_volunteer_term(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member record;
BEGIN
  SELECT m.* INTO v_member FROM members m
  WHERE m.id = p_member_id AND (m.auth_id = auth.uid() OR EXISTS (
    SELECT 1 FROM members c WHERE c.auth_id = auth.uid() AND (c.is_superadmin OR c.operational_role IN ('manager','deputy_manager'))));
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not found or unauthorized'); END IF;
  RETURN jsonb_build_object('member_id', v_member.id, 'name', v_member.name, 'email', v_member.email,
    'pmi_id', v_member.pmi_id, 'phone', v_member.phone, 'state', v_member.state,
    'country', v_member.country, 'chapter', v_member.chapter, 'generated_at', now());
END; $function$;

CREATE OR REPLACE FUNCTION public.admin_manage_board_member(p_board_id uuid, p_member_id uuid, p_board_role text DEFAULT 'editor'::text, p_action text DEFAULT 'add'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (
    v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager','deputy_manager')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF p_action = 'add' THEN
    INSERT INTO board_members (board_id, member_id, board_role, granted_by)
    VALUES (p_board_id, p_member_id, p_board_role, v_caller.id)
    ON CONFLICT (board_id, member_id) DO UPDATE SET board_role = p_board_role;
  ELSIF p_action = 'remove' THEN
    DELETE FROM board_members WHERE board_id = p_board_id AND member_id = p_member_id;
  ELSIF p_action = 'update' THEN
    UPDATE board_members SET board_role = p_board_role WHERE board_id = p_board_id AND member_id = p_member_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'action', p_action, 'member_id', p_member_id, 'board_role', p_board_role);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_changelog()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_agg(r ORDER BY r->>'released_at' DESC)
  INTO result
  FROM (
    SELECT jsonb_build_object(
      'id', rel.id,
      'version', rel.version,
      'title', rel.title,
      'description', rel.description,
      'release_type', rel.release_type,
      'is_current', rel.is_current,
      'released_at', rel.released_at,
      'stats', rel.stats,
      'items', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', ri.id,
            'title_pt', ri.title_pt,
            'title_en', ri.title_en,
            'title_es', ri.title_es,
            'description_pt', ri.description_pt,
            'description_en', ri.description_en,
            'description_es', ri.description_es,
            'category', ri.category,
            'gc_reference', ri.gc_reference,
            'icon', ri.icon
          ) ORDER BY ri.sort_order
        )
        FROM release_items ri
        WHERE ri.release_id = rel.id AND ri.visible = true
      ), '[]'::jsonb)
    ) as r
    FROM releases rel
  ) sub;

  RETURN COALESCE(result, '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_governance_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (
    v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager','deputy_manager')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  RETURN jsonb_build_object(
    'by_status', (
      SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::jsonb)
      FROM (SELECT status, count(*) as cnt FROM change_requests WHERE status IS NOT NULL GROUP BY status) t
    ),
    'by_type', (
      SELECT COALESCE(jsonb_object_agg(cr_type, cnt), '{}'::jsonb)
      FROM (SELECT cr_type, count(*) as cnt FROM change_requests WHERE cr_type IS NOT NULL GROUP BY cr_type) t
    ),
    'by_impact', (
      SELECT COALESCE(jsonb_object_agg(impact_level, cnt), '{}'::jsonb)
      FROM (SELECT impact_level, count(*) as cnt FROM change_requests WHERE impact_level IS NOT NULL GROUP BY impact_level) t
    ),
    'total', (SELECT count(*) FROM change_requests),
    'pending_review', (SELECT count(*) FROM change_requests WHERE status IN ('submitted', 'under_review')),
    'approved_not_implemented', (SELECT count(*) FROM change_requests WHERE status = 'approved'),
    'implemented', (SELECT count(*) FROM change_requests WHERE status = 'implemented'),
    'withdrawn', (SELECT count(*) FROM change_requests WHERE status = 'withdrawn')
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_member_transitions(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  IF v_caller.id != p_member_id
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND v_caller.is_superadmin IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  RETURN jsonb_build_object('transitions', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', t.id,
      'previous_status', t.previous_status,
      'new_status', t.new_status,
      'previous_tribe_id', t.previous_tribe_id,
      'new_tribe_id', t.new_tribe_id,
      'reason_category', t.reason_category,
      'reason_detail', t.reason_detail,
      'actor_name', m.name,
      'created_at', t.created_at
    ) ORDER BY t.created_at DESC)
    FROM member_status_transitions t
    LEFT JOIN members m ON m.id = t.actor_member_id
    WHERE t.member_id = p_member_id
  ), '[]'::jsonb));
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_member_excused(p_event_id uuid, p_member_id uuid, p_excused boolean DEFAULT true, p_reason text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid; v_caller_role text; v_is_admin boolean; v_caller_tribe int;
BEGIN
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- Admin/GP: always allowed
  IF v_is_admin = true OR v_caller_role IN ('manager', 'deputy_manager') THEN NULL;
  -- Tribe leader: can mark own tribe members
  ELSIF v_caller_role = 'tribe_leader' THEN
    IF NOT EXISTS (
      SELECT 1 FROM members m WHERE m.id = p_member_id AND m.tribe_id = v_caller_tribe
    ) THEN
      RAISE EXCEPTION 'Tribe leaders can only mark excused for their own tribe members';
    END IF;
  ELSE
    RAISE EXCEPTION 'Unauthorized: requires admin, manager, or tribe leader role';
  END IF;

  IF p_excused THEN
    INSERT INTO public.attendance (event_id, member_id, excused, excuse_reason)
    VALUES (p_event_id, p_member_id, true, p_reason)
    ON CONFLICT (event_id, member_id) DO UPDATE SET excused = true, excuse_reason = p_reason, updated_at = now();
  ELSE
    UPDATE public.attendance SET excused = false, excuse_reason = NULL, updated_at = now()
    WHERE event_id = p_event_id AND member_id = p_member_id;
  END IF;

  RETURN json_build_object('success', true, 'excused', p_excused);
END;
$function$;

CREATE OR REPLACE FUNCTION public.publish_comms_metrics_batch(p_source text DEFAULT 'manual_csv'::text, p_metric_date date DEFAULT NULL::date)
 RETURNS TABLE(batch_id text, source text, target_date date, published_rows integer, published_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_source text;
  v_target_date date;
  v_published_rows integer := 0;
  v_batch_id text;
  v_actor_member_id uuid;
  v_now timestamptz;
begin
  if not public.can_manage_comms_metrics() then
    raise exception 'Insufficient privileges to publish comms metrics batch';
  end if;

  v_source := coalesce(nullif(trim(p_source), ''), 'manual_csv');

  select m.id into v_actor_member_id
  from public.members m
  where m.auth_id = auth.uid()
  limit 1;

  if p_metric_date is null then
    select max(c.metric_date) into v_target_date
    from public.comms_metrics_daily c
    where c.source = v_source
      and c.published_at is null;
  else
    v_target_date := p_metric_date;
  end if;

  if v_target_date is null then
    raise exception 'No unpublished rows found for source %', v_source;
  end if;

  v_batch_id := format('comms_pub_%s_%s', v_source, to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'));
  v_now := now();

  update public.comms_metrics_daily
     set published_at = v_now,
         published_by = v_actor_member_id,
         publish_batch_id = v_batch_id,
         payload = coalesce(payload, '{}'::jsonb) || jsonb_build_object(
           'published_via', 'admin_workflow',
           'published_at', v_now,
           'publish_batch_id', v_batch_id,
           'published_by', v_actor_member_id
         )
   where source = v_source
     and metric_date = v_target_date
     and published_at is null;

  get diagnostics v_published_rows = row_count;

  if v_published_rows = 0 then
    raise exception 'No rows were published for source % on %', v_source, v_target_date;
  end if;

  insert into public.comms_metrics_publish_log (
    batch_id, source, target_date, published_rows, published_by, context
  ) values (
    v_batch_id, v_source, v_target_date, v_published_rows, v_actor_member_id,
    jsonb_build_object('published_via', 'rpc_publish_comms_metrics_batch')
  );

  return query
  select v_batch_id, v_source, v_target_date, v_published_rows, v_now;
end;
$function$;

CREATE OR REPLACE FUNCTION public.recalculate_cycle_rankings(p_cycle_id uuid, p_reason text DEFAULT 'manual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_admin boolean;
  v_caller_role text;
  v_researcher_count int;
  v_leader_count int;
  v_snapshot_id uuid;
BEGIN
  -- Auth (admin only)
  SELECT id, is_superadmin, operational_role INTO v_caller_id, v_is_admin, v_caller_role
  FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (v_is_admin = true OR v_caller_role IN ('manager', 'deputy_manager')) THEN
    RAISE EXCEPTION 'Unauthorized: only manager, deputy_manager or superadmin can recalc rankings';
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
