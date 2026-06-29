-- Onda 2 — FU-2 Slice A: chapter-scope the cross-chapter member-PII leak (legal A1, LIVE).
--
-- Finding (grounded 2026-06-28): a non-GP partner-chapter director holds `view_pii` at organization
-- scope (e.g. Francisca, PMI-CE: can_by_member view_pii=true, manage_platform=false), so the member-
-- directory PII RPCs returned PII (email/phone/pmi_id) of ANY chapter — violating LGPD minimization
-- (Art.6,III) + finalidade. Council decision #2: partner-chapter leaders see only their OWN chapter;
-- the SEDE (contracting chapter, PMI-GO) + GP see all. This migration TIGHTENS (reduces) exposure —
-- safe without the FU-4 federated-data annex (which gates EXPANDING/sharing, not restricting).
--
-- Mechanism (V4 Path-3 formalized): helper `caller_chapter_scope()` returns NULL for GP
-- (manage_platform/manage_member), superadmin, or sede callers (= unrestricted), else the caller's
-- own chapter. Each PII RPC applies it as a row filter (lists) or a target-chapter check (single
-- target: suppress PII or deny). Own-record access is always allowed. NO seed change, NO new scope
-- value — the action stays org-scoped; the DATA is scoped in the RPC (data-architect Caminho B).
--
-- Slice A = the 6 raw member-PII RPCs (PM-approved). Remaining VCD analytics aggregates + the other
-- PII RPCs are tracked follow-on slices (#952). Cross-ref: ADR-0105 (eixo de visibilidade),
-- docs/reference/V4_AUTHORITY_MODEL.md (Caminho 3), handoff pt6 FU-2.

-- ── Helper: caller's chapter restriction (NULL = unrestricted) ──
CREATE OR REPLACE FUNCTION public.caller_chapter_scope()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
  v_chapter text;
  v_superadmin boolean;
BEGIN
  SELECT id, chapter, COALESCE(is_superadmin, false)
    INTO v_id, v_chapter, v_superadmin
  FROM public.members WHERE auth_id = auth.uid();
  IF v_id IS NULL THEN
    RETURN NULL;  -- no member record: PII RPCs gate (view_pii) denies before scope matters
  END IF;
  -- GP-tier (manage_platform / manage_member), superadmin, or SEDE (contracting chapter, PMI-GO)
  -- see ALL chapters → NULL = unrestricted.
  IF v_superadmin
     OR public.can_by_member(v_id, 'manage_platform')
     OR public.can_by_member(v_id, 'manage_member')
     OR EXISTS (
          SELECT 1 FROM public.chapter_registry cr
          WHERE cr.is_contracting_chapter AND v_chapter = 'PMI-' || cr.chapter_code
        )
  THEN
    RETURN NULL;
  END IF;
  -- Otherwise restrict cross-chapter PII to the caller's own chapter.
  RETURN v_chapter;
END;
$function$;
REVOKE ALL ON FUNCTION public.caller_chapter_scope() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.caller_chapter_scope() FROM anon;
GRANT EXECUTE ON FUNCTION public.caller_chapter_scope() TO authenticated, service_role;

-- ── get_person: suppress PII for out-of-chapter targets (keeps public fields) ──
CREATE OR REPLACE FUNCTION public.get_person(p_person_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_target_person_id uuid;
  v_can_pii boolean;
  v_person record;
  v_scope text;
BEGIN
  SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT id INTO v_caller_person_id FROM public.persons WHERE legacy_member_id = v_caller_member_id;

  IF p_person_id IS NULL THEN
    v_target_person_id := v_caller_person_id;
  ELSE
    v_target_person_id := p_person_id;
  END IF;

  IF v_target_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  IF v_target_person_id = v_caller_person_id THEN
    v_can_pii := true;
  ELSE
    SELECT public.can(v_caller_person_id, 'view_pii', NULL, NULL) INTO v_can_pii;
  END IF;

  SELECT * INTO v_person FROM public.persons WHERE id = v_target_person_id;
  IF v_person IS NULL THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  -- FU-2 Slice A: chapter-scope — a non-GP/non-sede caller sees PII only for own-chapter people.
  IF v_can_pii AND v_target_person_id <> v_caller_person_id THEN
    v_scope := public.caller_chapter_scope();
    IF v_scope IS NOT NULL
       AND (SELECT m.chapter FROM public.members m WHERE m.id = v_person.legacy_member_id) IS DISTINCT FROM v_scope THEN
      v_can_pii := false;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'id', v_person.id,
    'name', v_person.name,
    'photo_url', v_person.photo_url,
    'linkedin_url', v_person.linkedin_url,
    'city', v_person.city,
    'state', v_person.state,
    'country', v_person.country,
    'credly_url', v_person.credly_url,
    'credly_badges', COALESCE(v_person.credly_badges, '[]'::jsonb),
    'consent_status', v_person.consent_status,
    'email', CASE WHEN v_can_pii THEN v_person.email ELSE NULL END,
    'phone', CASE WHEN v_can_pii AND v_person.share_whatsapp THEN v_person.phone ELSE NULL END,
    'address', CASE WHEN v_can_pii AND v_person.share_address THEN v_person.address ELSE NULL END,
    'birth_date', CASE WHEN v_can_pii AND v_person.share_birth_date THEN v_person.birth_date::text ELSE NULL END,
    'pmi_id', CASE WHEN v_can_pii THEN v_person.pmi_id ELSE NULL END,
    'legacy_member_id', v_person.legacy_member_id
  );
END;
$function$;

-- ── member_list_emails: deny cross-chapter for non-GP/non-sede callers ──
CREATE OR REPLACE FUNCTION public.member_list_emails(p_member_id uuid)
 RETURNS TABLE(id uuid, member_id uuid, email citext, is_primary boolean, kind text, added_at timestamp with time zone, organization_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_is_service_role boolean := false;
  v_allowed boolean := false;
  v_scope text;
  v_target_chapter text;
BEGIN
  -- #684: role-GUC discriminator (current_user is always the SECDEF owner under SECDEF).
  v_is_service_role := NOT public._request_is_rest_caller();

  IF NOT v_is_service_role THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF v_caller.id IS NULL THEN
      RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF v_caller.id = p_member_id OR public.can_by_member(v_caller.id, 'manage_member') OR public.can_by_member(v_caller.id, 'view_pii') THEN
      v_allowed := true;
    END IF;

    IF NOT v_allowed THEN
      RAISE EXCEPTION 'Unauthorized to view member emails';
    END IF;

    -- FU-2 Slice A: chapter-scope — a non-GP/non-sede caller may list emails only for own-chapter members.
    IF v_caller.id <> p_member_id THEN
      v_scope := public.caller_chapter_scope();
      IF v_scope IS NOT NULL THEN
        SELECT chapter INTO v_target_chapter FROM public.members WHERE id = p_member_id;
        IF v_target_chapter IS DISTINCT FROM v_scope THEN
          RAISE EXCEPTION 'Unauthorized: cross-chapter member emails';
        END IF;
      END IF;
    END IF;
  END IF;

  RETURN QUERY
  SELECT me.id, me.member_id, me.email, me.is_primary, me.kind, me.added_at, me.organization_id
  FROM public.member_emails me
  WHERE me.member_id = p_member_id;
END;
$function$;

-- ── admin_list_members_with_pii: filter rows by chapter scope (lists) ──
CREATE OR REPLACE FUNCTION public.admin_list_members_with_pii(p_tribe_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_accessed_ids uuid[];
  v_scope text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RAISE EXCEPTION 'Access denied: requires view_pii permission (LGPD-sensitive data)';
  END IF;

  -- FU-2 Slice A: chapter-scope — non-GP/non-sede callers see only their own chapter's members.
  v_scope := public.caller_chapter_scope();

  SELECT array_agg(m.id) INTO v_accessed_ids
  FROM public.members m
  WHERE (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
    AND (v_scope IS NULL OR m.chapter = v_scope)
    AND m.id <> v_caller_id;

  PERFORM public.log_pii_access_batch(
    v_accessed_ids,
    ARRAY['name','email','phone','role','designations']::text[],
    'admin_list_members_with_pii',
    CASE WHEN p_tribe_id IS NOT NULL THEN 'filtered by tribe ' || p_tribe_id ELSE 'all members' END
  );

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'name', m.name,
    'email', m.email,
    'phone', m.phone,
    'tribe_id', m.tribe_id,
    'operational_role', m.operational_role,
    'designations', m.designations,
    'is_active', m.is_active,
    'cycle_active', m.current_cycle_active
  ) ORDER BY m.name), '[]'::jsonb) INTO v_result
  FROM public.members m
  WHERE (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
    AND (v_scope IS NULL OR m.chapter = v_scope);

  RETURN v_result;
END;
$function$;

-- ── admin_get_member_details: deny cross-chapter (before logging) ──
CREATE OR REPLACE FUNCTION public.admin_get_member_details(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_scope text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RAISE EXCEPTION 'Access denied: requires view_pii permission (LGPD-sensitive data)';
  END IF;

  -- FU-2 Slice A: chapter-scope — non-GP/non-sede callers may not read out-of-chapter member details.
  v_scope := public.caller_chapter_scope();
  IF v_scope IS NOT NULL
     AND p_member_id <> v_caller_id
     AND (SELECT chapter FROM public.members WHERE id = p_member_id) IS DISTINCT FROM v_scope THEN
    RAISE EXCEPTION 'Access denied: cross-chapter member details';
  END IF;

  PERFORM public.log_pii_access(
    p_member_id,
    ARRAY['name','email','phone','photo_url','role','designations','is_active','cycles']::text[],
    'admin_get_member_details',
    NULL
  );

  SELECT jsonb_build_object(
    'id', m.id,
    'name', m.name,
    'email', m.email,
    'phone', m.phone,
    'photo_url', m.photo_url,
    'tribe_id', m.tribe_id,
    'operational_role', m.operational_role,
    'designations', m.designations,
    'is_superadmin', m.is_superadmin,
    'is_active', m.is_active,
    'cycle_active', m.current_cycle_active,
    'cycles', m.cycles,
    'created_at', m.created_at
  ) INTO v_result
  FROM public.members m
  WHERE m.id = p_member_id;

  RETURN v_result;
END;
$function$;

-- ── get_member_attendance_hours: deny cross-chapter (non-own) ──
CREATE OR REPLACE FUNCTION public.get_member_attendance_hours(p_member_id uuid, p_cycle_code text DEFAULT 'cycle_3'::text)
 RETURNS TABLE(total_hours numeric, total_events integer, avg_hours_per_event numeric, current_streak integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_start date;
  v_streak int := 0;
  v_rec record;
  v_target_tribe int;
  v_scope text;
BEGIN
  SELECT id INTO v_caller_id
  FROM public.members WHERE auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT (v_caller_id = p_member_id OR public.can_by_member(v_caller_id, 'view_pii')) THEN
    RAISE EXCEPTION 'Unauthorized: can only view own attendance or requires view_pii permission';
  END IF;

  -- FU-2 Slice A: chapter-scope — non-GP/non-sede callers may not read out-of-chapter attendance.
  IF v_caller_id <> p_member_id THEN
    v_scope := public.caller_chapter_scope();
    IF v_scope IS NOT NULL
       AND (SELECT chapter FROM public.members WHERE id = p_member_id) IS DISTINCT FROM v_scope THEN
      RAISE EXCEPTION 'Unauthorized: cross-chapter attendance';
    END IF;
  END IF;

  SELECT cycle_start INTO v_cycle_start
  FROM public.cycles WHERE cycle_code = p_cycle_code;

  IF v_cycle_start IS NULL THEN
    RETURN QUERY SELECT 0::numeric, 0::int, 0::numeric, 0::int;
    RETURN;
  END IF;

  SELECT tribe_id INTO v_target_tribe FROM public.members WHERE id = p_member_id;

  FOR v_rec IN
    SELECT e.id,
           EXISTS(SELECT 1 FROM public.attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id AND a.present) AS was_present
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND e.date <= current_date
      AND (e.initiative_id IS NULL
           OR i.legacy_tribe_id = v_target_tribe)
    ORDER BY e.date DESC
  LOOP
    IF v_rec.was_present THEN
      v_streak := v_streak + 1;
    ELSE
      EXIT;
    END IF;
  END LOOP;

  RETURN QUERY
  SELECT
    COALESCE(SUM(e.duration_minutes / 60.0), 0)::numeric          AS total_hours,
    COUNT(DISTINCT a.event_id)::int                                AS total_events,
    CASE WHEN COUNT(DISTINCT a.event_id) > 0
      THEN (COALESCE(SUM(e.duration_minutes / 60.0), 0) / COUNT(DISTINCT a.event_id))::numeric
      ELSE 0::numeric
    END                                                            AS avg_hours_per_event,
    v_streak                                                       AS current_streak
  FROM public.attendance a
  JOIN public.events e ON e.id = a.event_id
  WHERE a.member_id = p_member_id AND a.present;
END;
$function$;

-- ── get_member_cycle_xp: deny cross-chapter (non-own) ──
CREATE OR REPLACE FUNCTION public.get_member_cycle_xp(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cycle_start_date date;
  v_rank int;
  v_total int;
  result json;
  v_caller_id uuid;
  v_scope text;
begin
  -- XP gate: SECDEF + authenticated-grant allowed enumerating any member's XP/rank by id.
  select id into v_caller_id from public.members where auth_id = auth.uid() and is_active = true;
  if v_caller_id is null then
    raise exception 'Not authenticated' using errcode = 'insufficient_privilege';
  end if;
  if p_member_id <> v_caller_id and not public.can_by_member(v_caller_id, 'view_pii') then
    raise exception 'Unauthorized' using errcode = 'insufficient_privilege';
  end if;

  -- FU-2 Slice A: chapter-scope — non-GP/non-sede callers may not read out-of-chapter XP.
  if p_member_id <> v_caller_id then
    v_scope := public.caller_chapter_scope();
    if v_scope is not null
       and (select chapter from public.members where id = p_member_id) is distinct from v_scope then
      raise exception 'Unauthorized' using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Cycle window comes solely from the current cycle (the prior hardcoded literal fallback was removed).
  select cycle_start into cycle_start_date
  from public.cycles where is_current = true limit 1;

  -- M5 (#419 D1): rank by THIS cycle's XP (matches the displayed cycle_points), with a
  -- deterministic member_id tiebreak. Previously ranked on lifetime SUM(points), which
  -- contradicted the cycle_points shown and reshuffled ties non-deterministically.
  WITH ranked AS (
    SELECT member_id,
           COALESCE(SUM(points) FILTER (WHERE created_at >= cycle_start_date), 0) as cycle_pts,
           ROW_NUMBER() OVER (
             ORDER BY COALESCE(SUM(points) FILTER (WHERE created_at >= cycle_start_date), 0) DESC,
                      member_id
           ) as pos
    FROM public.gamification_points
    GROUP BY member_id
  )
  SELECT pos, (SELECT COUNT(DISTINCT member_id) FROM public.gamification_points)
  INTO v_rank, v_total
  FROM ranked WHERE member_id = p_member_id;

  select json_build_object(
    'lifetime_points', coalesce(sum(points), 0)::int,
    'cycle_points', coalesce(sum(points) filter (where created_at >= cycle_start_date), 0)::int,
    'cycle_attendance', coalesce(sum(points) filter (where category = 'attendance' and created_at >= cycle_start_date), 0)::int,
    'cycle_learning', coalesce(sum(points) filter (where category in ('trail', 'course', 'knowledge_ai_pm') and created_at >= cycle_start_date), 0)::int,
    'cycle_certs', coalesce(sum(points) filter (where category in ('cert_pmi_senior', 'cert_cpmai', 'cert_pmi_mid', 'cert_pmi_practitioner', 'cert_pmi_entry') and created_at >= cycle_start_date), 0)::int,
    'cycle_courses', coalesce(sum(points) filter (where category in ('trail', 'course', 'knowledge_ai_pm') and created_at >= cycle_start_date), 0)::int,
    'cycle_artifacts', coalesce(sum(points) filter (where category = 'artifact' and created_at >= cycle_start_date), 0)::int,
    'cycle_showcase', coalesce(sum(points) filter (where category = 'showcase' and created_at >= cycle_start_date), 0)::int,
    'cycle_bonus', coalesce(sum(points) filter (where category not in ('attendance','trail','course','knowledge_ai_pm','cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry','artifact','badge','specialization','showcase') and created_at >= cycle_start_date), 0)::int,
    'cycle_code', (select cycle_code from public.cycles where is_current = true limit 1),
    'cycle_label', (select cycle_label from public.cycles where is_current = true limit 1),
    'rank_position', coalesce(v_rank, 0),
    'total_ranked', coalesce(v_total, 0)
  ) into result
  from public.gamification_points
  where member_id = p_member_id;

  return coalesce(result, '{}');
end;
$function$;
