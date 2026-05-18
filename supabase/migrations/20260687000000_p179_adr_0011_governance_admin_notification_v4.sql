-- p179 ADR-0011 V4 sweep — governance + admin notification surface.
--
-- Carries from p178 council reviews (code-reviewer HIGH backlog):
--   1. approve_change_request: V3 hardcoded `operational_role != 'sponsor' AND
--      COALESCE(v_is_superadmin, false) != true` top-level auth gate.
--      Replaced with `can_by_member(v_member_id, 'participate_in_governance_review')`.
--      Plus seed expansion: participate_in_governance_review for sponsor × sponsor.
--   2. detect_inactive_members: notification recipient query used
--      `operational_role IN ('manager','deputy_manager')`. Replaced with
--      `can_by_member(m.id, 'manage_platform')`.
--   3. detect_stale_events_cron: same recipient query pattern.
--   4. detect_stale_portfolio_items_cron: same recipient query pattern.
--
-- Out of scope this migration:
--   - bulk_mark_excused: already has `can_by_member(v_caller_id, 'manage_event')`
--     as PRIMARY auth gate. The remaining `operational_role IN
--     ('manager','deputy_manager','tribe_leader')` is a data filter on TARGET
--     member's role (deciding if lideranca events apply to them), NOT a
--     caller-auth gate. Carry as separate domain-mapping migration.
--   - review_change_request: already V4-refactored inline in p178 batch 3
--     (commit f53cc2f via 20260686000000).
--
-- Semantic effect:
--   - approve_change_request AUTH GATE: V4 can_by_member(participate_in_governance_review)
--     covers sponsor × sponsor (seeded here), volunteer × {manager, deputy_manager,
--     co_gp}, observer × {curator, reviewer}, chapter_board × liaison, external_reviewer
--     × reviewer. Broader V4 voter pool: 12 members capable, up from 5 V3 sponsors.
--   - approve_change_request QUORUM COUNT: **unchanged from V3** per PM decision
--     2026-05-17. Quorum denominator stays sponsor-only (5 today, CEIL(5×3/5)=3)
--     until governance manual revision authorizes expansion. V4 capable members
--     can VOTE but only sponsor × sponsor engagements count toward quorum.
--   - 3 cron detect fns: notification recipients EXPAND from
--     {manager, deputy_manager} to {manager, deputy_manager, co_gp} via
--     manage_platform seed coverage. co_gp is a legitimate recipient class for
--     platform-wide health alerts.
--
-- Rollback: revert each fn body to prior capture in 20260684000000 / 20260686000000
-- and DELETE FROM engagement_kind_permissions WHERE kind='sponsor' AND role='sponsor'
-- AND action='participate_in_governance_review'.

-- =====================================================================
-- Part 1: Seed expansion — participate_in_governance_review for sponsor × sponsor
-- =====================================================================
-- Scope 'organization' (NOT 'global') per catalog hygiene: every prior
-- participate_in_governance_review seed uses 'organization' (volunteer ×
-- {manager, deputy_manager, co_gp}, observer × {curator, reviewer},
-- chapter_board × liaison, external_reviewer × reviewer). 'global' is
-- reserved for cross-organization use in multi-tenant scenarios. Functionally
-- identical inside can() today, but using 'organization' avoids the precedent
-- of bypassing future org-boundary scope-filter logic.
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description)
SELECT 'sponsor', 'sponsor', 'participate_in_governance_review', 'organization',
       'Chapter presidents and governance representatives (sponsor engagement) can review and approve change requests.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.engagement_kind_permissions
   WHERE kind = 'sponsor' AND role = 'sponsor'
     AND action = 'participate_in_governance_review'
);

-- =====================================================================
-- Part 2: approve_change_request — top-level auth via can_by_member
-- =====================================================================
CREATE OR REPLACE FUNCTION public.approve_change_request(p_cr_id uuid, p_action text, p_comment text DEFAULT NULL::text, p_ip inet DEFAULT NULL::inet, p_user_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_name text;
  v_cr record;
  v_hash text;
  v_total_sponsors int;
  v_total_approvals int;
  v_quorum_needed int;
  v_quorum_met boolean;
BEGIN
  SELECT id, name
  INTO v_member_id, v_member_name
  FROM members WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- p179 ADR-0011 V4 refactor: top-level authority via V4 can_by_member.
  -- Covers sponsor × sponsor (seeded p179), volunteer × {co_gp, deputy_manager,
  -- manager}, observer × {curator, reviewer}, chapter_board × liaison,
  -- external_reviewer × reviewer. Superadmin auto-passes via can() chain.
  IF NOT can_by_member(v_member_id, 'participate_in_governance_review') THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  IF p_action NOT IN ('approved', 'rejected', 'abstained') THEN
    RETURN jsonb_build_object('error', 'invalid_action');
  END IF;

  SELECT * INTO v_cr FROM change_requests WHERE id = p_cr_id;
  IF v_cr IS NULL THEN
    RETURN jsonb_build_object('error', 'cr_not_found');
  END IF;

  IF v_cr.status NOT IN ('submitted', 'proposed', 'under_review', 'open', 'pending_review', 'in_review') THEN
    RETURN jsonb_build_object('error', 'cr_not_approvable', 'status', v_cr.status);
  END IF;

  v_hash := encode(sha256(convert_to(
    p_cr_id::text || v_member_id::text || p_action || now()::text || 'nucleo-ia-governance-salt', 'UTF8'
  )), 'hex');

  INSERT INTO cr_approvals (cr_id, member_id, action, comment, signature_hash, signed_ip, signed_user_agent)
  VALUES (p_cr_id, v_member_id, p_action, p_comment, v_hash, p_ip, p_user_agent)
  ON CONFLICT (cr_id, member_id)
  DO UPDATE SET action = EXCLUDED.action, comment = EXCLUDED.comment,
    signature_hash = EXCLUDED.signature_hash, signed_ip = EXCLUDED.signed_ip,
    signed_user_agent = EXCLUDED.signed_user_agent, created_at = now();

  UPDATE change_requests
  SET approved_by_members = (
    SELECT array_agg(DISTINCT member_id) FROM cr_approvals WHERE cr_id = p_cr_id AND action = 'approved'
  ),
  status = CASE
    WHEN status IN ('submitted', 'open', 'pending_review') THEN 'under_review'
    ELSE status
  END
  WHERE id = p_cr_id;

  -- p179 PM decision (2026-05-17): quorum count remains V3 sponsor-only until
  -- the governance manual revision formally authorizes expansion to the
  -- broader V4 voter pool (curators/reviewers/etc.). Auth gate is V4
  -- (can_by_member above) — V4 capable members can vote, but only sponsor ×
  -- sponsor engagements count toward quorum denominator. When manual v3
  -- revision lands, swap to `can_by_member(m.id, 'participate_in_governance_review')`.
  SELECT count(*) INTO v_total_sponsors
  FROM members m
  WHERE m.is_active = true
    AND m.operational_role = 'sponsor';
  SELECT count(*) INTO v_total_approvals FROM cr_approvals WHERE cr_id = p_cr_id AND action = 'approved';

  v_quorum_needed := GREATEST(CEIL(v_total_sponsors::numeric * 3 / 5), 1);
  v_quorum_met := v_total_approvals >= v_quorum_needed;

  IF v_quorum_met THEN
    UPDATE change_requests SET status = 'approved', approved_at = now()
    WHERE id = p_cr_id AND status != 'approved';

    INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (v_member_id, 'cr_approved_quorum', 'change_request', p_cr_id,
      jsonb_build_object('cr_number', v_cr.cr_number, 'approvals', v_total_approvals, 'quorum', v_quorum_needed));

    -- p179 ADR-0011 V4: notify everyone with governance review capability + platform admins.
    INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT m.id, 'governance_cr_approved',
      v_cr.cr_number || ' aprovado por quorum!',
      v_cr.title || ' aprovado com ' || v_total_approvals || '/' || v_quorum_needed || ' votos.',
      '/governance', 'change_request', p_cr_id
    FROM members m
    WHERE m.is_active = true
      AND (can_by_member(m.id, 'participate_in_governance_review')
           OR can_by_member(m.id, 'manage_platform'));
  ELSE
    -- p179 ADR-0011 V4: notify other governance reviewers about the vote.
    INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT m.id, 'governance_cr_vote',
      v_cr.cr_number || ': ' || v_member_name || ' votou ' || p_action,
      v_cr.title, '/governance', 'change_request', p_cr_id
    FROM members m
    WHERE m.is_active = true
      AND m.id != v_member_id
      AND can_by_member(m.id, 'participate_in_governance_review');
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'action', p_action, 'signature_hash', v_hash,
    'approvals', v_total_approvals, 'quorum_needed', v_quorum_needed,
    'quorum_met', v_quorum_met,
    'cr_status', CASE WHEN v_quorum_met THEN 'approved' ELSE 'under_review' END
  );
END;
$function$;

-- =====================================================================
-- Part 3: detect_inactive_members — V4 recipient query
-- =====================================================================
CREATE OR REPLACE FUNCTION public.detect_inactive_members(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_threshold int;
  v_candidates jsonb := '[]'::jsonb;
  v_count int := 0;
  v_notified int := 0;
  v_cron_context boolean;
BEGIN
  -- Cron-context auth bypass (ADR-0028 pattern)
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

  IF NOT v_cron_context AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF NOT v_cron_context THEN
    PERFORM 1 FROM public.members
    WHERE auth_id = auth.uid()
      AND public.can_by_member(id, 'manage_member');
    IF NOT FOUND THEN RAISE EXCEPTION 'Unauthorized: requires manage_member'; END IF;
  END IF;

  SELECT COALESCE((value::text)::int, 180) INTO v_threshold
  FROM public.site_config WHERE key = 'inactivity_threshold_days';
  v_threshold := COALESCE(v_threshold, 180);

  WITH inactive AS (
    SELECT
      m.id AS member_id,
      m.name,
      m.email,
      m.tribe_id,
      m.chapter,
      m.created_at AS member_created_at,
      (SELECT MAX(a.checked_in_at) FROM public.attendance a
        WHERE a.member_id = m.id AND a.present = true) AS last_attendance_at,
      m.updated_at AS last_member_update_at
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.is_active = true
      AND m.anonymized_at IS NULL
      AND m.name <> 'VP Desenvolvimento Profissional (PMI-GO)'
      -- Exclude very recent joins (need at least threshold days history)
      AND m.created_at < (now() - make_interval(days => v_threshold))
      -- Either no attendance ever, OR last attendance older than threshold
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.member_id = m.id AND a.present = true
          AND a.checked_in_at > (now() - make_interval(days => v_threshold))
      )
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'member_id', member_id,
    'name', name,
    'chapter', chapter,
    'tribe_id', tribe_id,
    'last_attendance_at', last_attendance_at,
    'days_since_last_attendance',
      CASE WHEN last_attendance_at IS NULL
        THEN EXTRACT(DAY FROM now() - member_created_at)::int
        ELSE EXTRACT(DAY FROM now() - last_attendance_at)::int
      END
  )), '[]'::jsonb), COALESCE(COUNT(*), 0)
  INTO v_candidates, v_count
  FROM inactive;

  -- p179 ADR-0011 V4: notify admins via manage_platform capability
  -- (replaces operational_role IN ('manager','deputy_manager')).
  IF NOT p_dry_run AND v_count > 0 THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT mgr.id,
           'arm9_inactivity_alert',
           v_count || ' membro(s) sem atividade há mais de ' || v_threshold || ' dias',
           'Considerar transição para status inactive. Lista disponível em /admin/members?filter=inactive_candidates',
           '/admin/members?filter=inactive_candidates',
           'arm9_inactivity_detection',
           NULL
    FROM public.members mgr
    WHERE mgr.is_active = true
      AND can_by_member(mgr.id, 'manage_platform');
    GET DIAGNOSTICS v_notified = ROW_COUNT;

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'arm9.inactivity_detection_run', NULL, NULL,
      jsonb_build_object('threshold_days', v_threshold, 'candidates_count', v_count, 'managers_notified', v_notified),
      jsonb_build_object('dry_run', false, 'source', 'cron_or_manual')
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'threshold_days', v_threshold,
    'candidates_count', v_count,
    'candidates', v_candidates,
    'managers_notified', v_notified,
    'dry_run', p_dry_run
  );
END $function$;

-- =====================================================================
-- Part 4: detect_stale_events_cron — V4 recipient query
-- =====================================================================
CREATE OR REPLACE FUNCTION public.detect_stale_events_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer := 0;
  v_inserted integer := 0;
BEGIN
  -- 24-48h window (gives líder 1 day to react before falling into wider monitoring)
  SELECT count(*) INTO v_count
  FROM events e
  WHERE e.date BETWEEN CURRENT_DATE - 2 AND CURRENT_DATE - 1
    AND NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id);

  IF v_count > 0 THEN
    -- p179 ADR-0011 V4: notify admins via manage_platform capability
    -- (replaces operational_role IN ('manager','deputy_manager')).
    INSERT INTO notifications (recipient_id, type, title, body, delivery_mode, created_at)
    SELECT m.id,
           'event_stale_no_attendance',
           format('%s evento(s) sem attendance marcado', v_count),
           format('%s evento(s) passado(s) há mais de 24h não tem nenhuma marcação de presença. Cancele se a reunião não aconteceu OU marque presença em /attendance.', v_count),
           'digest_weekly',
           now()
    FROM members m
    WHERE m.is_active = true
      AND can_by_member(m.id, 'manage_platform');
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'stale_count', v_count,
    'notifications_inserted', v_inserted,
    'window_hours', 48,
    'run_at', now()
  );
END $function$;

-- =====================================================================
-- Part 5: detect_stale_portfolio_items_cron — V4 recipient query
-- =====================================================================
CREATE OR REPLACE FUNCTION public.detect_stale_portfolio_items_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer := 0;
  v_inserted integer := 0;
  v_stale_threshold interval := '60 days';
BEGIN
  SELECT count(*) INTO v_count
  FROM board_items bi
  WHERE bi.is_portfolio_item = true
    AND bi.status NOT IN ('done', 'archived')
    AND bi.updated_at < now() - v_stale_threshold;

  -- Only insert reminder if there is something stale (smart-skip empty digest per ADR-0022)
  IF v_count > 0 THEN
    -- p179 ADR-0011 V4: notify admins via manage_platform capability
    -- (replaces operational_role IN ('manager','deputy_manager')).
    INSERT INTO notifications (recipient_id, type, title, body, delivery_mode, created_at)
    SELECT m.id,
           'portfolio_stale_reminder',
           format('%s portfolio item(s) precisam de update', v_count),
           format('%s itens marcados is_portfolio_item=true sem update há mais de 60 dias. Revise via /admin/portfolio.', v_count),
           'digest_weekly',
           now()
    FROM members m
    WHERE m.is_active = true
      AND can_by_member(m.id, 'manage_platform');

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'stale_count', v_count,
    'notifications_inserted', v_inserted,
    'threshold_days', 60,
    'run_at', now()
  );
END $function$;

-- =====================================================================
-- Schema reload (PostgREST surface affected for approve_change_request signature)
-- =====================================================================
-- NOTIFY pgrst, 'reload schema' — invoked separately via execute_sql post-apply.
