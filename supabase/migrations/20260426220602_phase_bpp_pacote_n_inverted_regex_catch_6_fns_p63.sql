-- Phase B'' Pacote N (p63 ext) — 6 fns surfaced via refined regex
-- Discovered during D+F verification audit: original p63 A_admin_broad
-- regex used `operational_role IN (manager...)` pattern which missed
-- the `NOT IN` inverted form (e.g., `IS NOT TRUE AND NOT IN`). Refined
-- audit identified 9 inverted-clean candidates; 6 truly clean (no co_gp,
-- no extras, no scope clause) → this batch.
--
-- 3 deferred from same surface:
--   - finalize_decisions: committee role check (selection committee)
--   - register_event_showcase, remove_event_showcase: tribe_leader
--     without scope (similar A5 pattern)
--
-- Privilege expansion safety check (verified pre-apply):
--   V3 (superadmin OR manager/deputy_manager — no co_gp): 2 members
--   V4 manage_platform: 2 (same — superadmin override)
--   would_gain: [] / would_lose: []

-- ============================================================
-- 1. add_partner_interaction
-- ============================================================
DROP FUNCTION IF EXISTS public.add_partner_interaction(uuid, text, text, text, text, text, date);
CREATE OR REPLACE FUNCTION public.add_partner_interaction(
  p_partner_id uuid, p_interaction_type text, p_summary text,
  p_details text, p_outcome text, p_next_action text, p_follow_up_date date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_interaction_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  INSERT INTO public.partner_interactions (
    partner_id, interaction_type, summary, details, outcome, next_action, follow_up_date, actor_member_id
  ) VALUES (
    p_partner_id, p_interaction_type, p_summary, p_details, p_outcome, p_next_action, p_follow_up_date, v_caller_id
  ) RETURNING id INTO v_interaction_id;

  UPDATE public.partner_entities
  SET
    last_interaction_at = now(),
    next_action = COALESCE(p_next_action, next_action),
    follow_up_date = COALESCE(p_follow_up_date, follow_up_date),
    updated_at = now(),
    notes = COALESCE(notes, '') || E'\n[' || to_char(now(), 'YYYY-MM-DD') || '] ' || p_interaction_type || ': ' || p_summary
  WHERE id = p_partner_id;

  RETURN jsonb_build_object('success', true, 'interaction_id', v_interaction_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.add_partner_interaction(uuid, text, text, text, text, text, date) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.add_partner_interaction(uuid, text, text, text, text, text, date) IS
  'Phase B'' V4 conversion (p63 ext Pacote N): manage_platform via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened.';

-- ============================================================
-- 2. bulk_issue_certificates
-- ============================================================
DROP FUNCTION IF EXISTS public.bulk_issue_certificates(text, text, text, text, text, integer, uuid[]);
CREATE OR REPLACE FUNCTION public.bulk_issue_certificates(
  p_type text, p_title text, p_period_start text, p_period_end text,
  p_language text, p_cycle integer, p_member_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_member record;
  v_count int := 0;
  v_code text;
  v_function_role text;
  v_cert_id uuid;
  v_results jsonb := '[]'::jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized: only GP/Deputy can bulk issue');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: only GP/Deputy can bulk issue');
  END IF;

  IF p_type NOT IN ('participation', 'completion') THEN
    RETURN jsonb_build_object('error', 'Bulk issuance only for participation/completion types');
  END IF;

  IF array_length(p_member_ids, 1) IS NULL OR array_length(p_member_ids, 1) = 0 THEN
    RETURN jsonb_build_object('error', 'No members selected');
  END IF;

  FOR v_member IN
    SELECT m.id, m.name, m.operational_role, m.tribe_id, t.name as tribe_name
    FROM public.members m
    LEFT JOIN public.tribes t ON m.tribe_id = t.id
    WHERE m.id = ANY(p_member_ids)
    AND m.is_active = true
  LOOP
    v_code := 'CERT-' || to_char(now(), 'YYYY') || '-' || upper(substr(md5(random()::text), 1, 6));

    v_function_role := CASE v_member.operational_role
      WHEN 'tribe_leader' THEN 'Líder de Tribo — ' || COALESCE(v_member.tribe_name, '')
      WHEN 'researcher' THEN 'Pesquisador(a) — ' || COALESCE(v_member.tribe_name, '')
      WHEN 'manager' THEN 'Gestor do Projeto'
      WHEN 'deputy_manager' THEN 'Vice-Gestor do Projeto'
      ELSE COALESCE(v_member.operational_role, 'Voluntário(a)') ||
           CASE WHEN v_member.tribe_name IS NOT NULL THEN ' — ' || v_member.tribe_name ELSE '' END
    END;

    INSERT INTO public.certificates (
      member_id, type, title, description, period_start, period_end,
      function_role, language, cycle, verification_code, status,
      issued_by, issued_at
    ) VALUES (
      v_member.id, p_type, p_title, NULL, p_period_start, p_period_end,
      v_function_role, p_language, COALESCE(p_cycle, 3), v_code, 'issued',
      v_caller_id, now()
    ) RETURNING id INTO v_cert_id;

    PERFORM public.create_notification(
      v_member.id, 'certificate_issued',
      'Certificado emitido: ' || p_title,
      'Você recebeu: ' || p_title,
      '/gamification',
      'certificate',
      v_cert_id
    );

    v_count := v_count + 1;
    v_results := v_results || jsonb_build_object(
      'member_id', v_member.id, 'name', v_member.name, 'code', v_code
    );
  END LOOP;

  RETURN jsonb_build_object('issued', v_count, 'certificates', v_results);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.bulk_issue_certificates(text, text, text, text, text, integer, uuid[]) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.bulk_issue_certificates(text, text, text, text, text, integer, uuid[]) IS
  'Phase B'' V4 conversion (p63 ext Pacote N): manage_platform via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened.';

-- ============================================================
-- 3. detect_onboarding_overdue
-- ============================================================
DROP FUNCTION IF EXISTS public.detect_onboarding_overdue();
CREATE OR REPLACE FUNCTION public.detect_onboarding_overdue()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_overdue record;
  v_notified int := 0;
  v_updated int := 0;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: admin only';
  END IF;

  FOR v_overdue IN
    SELECT
      op.id AS progress_id,
      op.application_id,
      op.step_key,
      op.member_id,
      op.sla_deadline,
      sa.applicant_name,
      sa.chapter
    FROM public.onboarding_progress op
    JOIN public.selection_applications sa ON sa.id = op.application_id
    WHERE op.status IN ('pending', 'in_progress')
      AND op.sla_deadline < now()
  LOOP
    UPDATE public.onboarding_progress
    SET status = 'overdue'
    WHERE id = v_overdue.progress_id AND status != 'overdue';

    IF FOUND THEN
      v_updated := v_updated + 1;
    END IF;

    IF v_overdue.member_id IS NOT NULL THEN
      PERFORM public.create_notification(
        v_overdue.member_id,
        'selection_onboarding_overdue',
        'Etapa de Onboarding Atrasada',
        'A etapa "' || v_overdue.step_key || '" está atrasada. Por favor, complete-a o mais breve possível.',
        '/workspace',
        'onboarding_progress',
        v_overdue.progress_id
      );
      v_notified := v_notified + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'steps_marked_overdue', v_updated,
    'notifications_sent', v_notified
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.detect_onboarding_overdue() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.detect_onboarding_overdue() IS
  'Phase B'' V4 conversion (p63 ext Pacote N): manage_platform via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened.';

-- ============================================================
-- 4. get_onboarding_dashboard — search_path KEPT (unqualified refs in subqueries)
-- ============================================================
DROP FUNCTION IF EXISTS public.get_onboarding_dashboard();
CREATE OR REPLACE FUNCTION public.get_onboarding_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public, pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'fully_onboarded', (SELECT count(DISTINCT m.id) FROM members m
        WHERE m.is_active AND m.current_cycle_active
        AND NOT EXISTS (SELECT 1 FROM onboarding_steps s JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = m.id WHERE s.is_required AND op.status != 'completed')
        AND EXISTS (SELECT 1 FROM onboarding_progress op2 WHERE op2.member_id = m.id)),
      'not_started', (SELECT count(DISTINCT m.id) FROM members m
        WHERE m.is_active AND m.current_cycle_active
        AND NOT EXISTS (SELECT 1 FROM onboarding_progress op WHERE op.member_id = m.id AND op.status = 'completed'))
    ),
    'members', (SELECT jsonb_agg(row_to_json(t) ORDER BY t.completed_count ASC, t.name) FROM (
      SELECT m.id, m.name, m.photo_url, m.chapter, m.tribe_id,
        (SELECT count(*) FROM onboarding_progress op WHERE op.member_id = m.id AND op.status = 'completed' AND op.step_key IN (SELECT id FROM onboarding_steps)) AS completed_count,
        (SELECT count(*) FROM onboarding_steps WHERE is_required) AS total_steps,
        (SELECT max(op.updated_at) FROM onboarding_progress op WHERE op.member_id = m.id) AS last_activity
      FROM members m WHERE m.is_active AND m.current_cycle_active
    ) t)
  ) INTO v_result;
  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_onboarding_dashboard() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.get_onboarding_dashboard() IS
  'Phase B'' V4 conversion (p63 ext Pacote N): manage_platform via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path KEPT (body has unqualified refs in subqueries).';

-- ============================================================
-- 5. get_partner_followups
-- ============================================================
DROP FUNCTION IF EXISTS public.get_partner_followups();
CREATE OR REPLACE FUNCTION public.get_partner_followups()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  RETURN jsonb_build_object(
    'overdue', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'partner_id', pe.id, 'partner_name', pe.name,
        'follow_up_date', pe.follow_up_date, 'next_action', pe.next_action,
        'days_overdue', CURRENT_DATE - pe.follow_up_date, 'status', pe.status
      ) ORDER BY pe.follow_up_date ASC), '[]'::jsonb)
      FROM public.partner_entities pe
      WHERE pe.follow_up_date < CURRENT_DATE AND pe.status NOT IN ('inactive', 'churned')
    ),
    'upcoming', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'partner_id', pe.id, 'partner_name', pe.name,
        'follow_up_date', pe.follow_up_date, 'next_action', pe.next_action,
        'days_until', pe.follow_up_date - CURRENT_DATE, 'status', pe.status
      ) ORDER BY pe.follow_up_date ASC), '[]'::jsonb)
      FROM public.partner_entities pe
      WHERE pe.follow_up_date >= CURRENT_DATE AND pe.follow_up_date <= CURRENT_DATE + 14
        AND pe.status NOT IN ('inactive', 'churned')
    ),
    'stale', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'partner_id', pe.id, 'partner_name', pe.name,
        'last_interaction_at', pe.last_interaction_at,
        'days_since', EXTRACT(DAY FROM now() - COALESCE(pe.last_interaction_at, pe.created_at))::int,
        'status', pe.status
      ) ORDER BY COALESCE(pe.last_interaction_at, pe.created_at) ASC), '[]'::jsonb)
      FROM public.partner_entities pe
      WHERE COALESCE(pe.last_interaction_at, pe.created_at) < now() - interval '30 days'
        AND pe.status NOT IN ('inactive', 'churned')
    )
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_partner_followups() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.get_partner_followups() IS
  'Phase B'' V4 conversion (p63 ext Pacote N): manage_platform via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened.';

-- ============================================================
-- 6. get_partner_interactions
-- ============================================================
DROP FUNCTION IF EXISTS public.get_partner_interactions(uuid);
CREATE OR REPLACE FUNCTION public.get_partner_interactions(p_partner_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', pi.id,
      'interaction_type', pi.interaction_type,
      'summary', pi.summary,
      'details', pi.details,
      'outcome', pi.outcome,
      'next_action', pi.next_action,
      'follow_up_date', pi.follow_up_date,
      'actor_name', m.name,
      'created_at', pi.created_at
    ) ORDER BY pi.created_at DESC
  ) INTO v_result
  FROM public.partner_interactions pi
  LEFT JOIN public.members m ON m.id = pi.actor_member_id
  WHERE pi.partner_id = p_partner_id;

  RETURN jsonb_build_object(
    'interactions', COALESCE(v_result, '[]'::jsonb),
    'total', (SELECT count(*) FROM public.partner_interactions WHERE partner_id = p_partner_id)
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_partner_interactions(uuid) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.get_partner_interactions(uuid) IS
  'Phase B'' V4 conversion (p63 ext Pacote N): manage_platform via can_by_member. Was V3 (superadmin OR manager/deputy_manager). search_path hardened.';

NOTIFY pgrst, 'reload schema';
