-- Track Q-A Batch I — orphan recovery: CPMAI + certificates (7 fns)
--
-- Captures live bodies as-of 2026-04-25 for CPMAI course/enrollment/progress
-- + certificate issuance + cert timeline executive view. Bodies preserved
-- verbatim from `pg_get_functiondef` — no behavior change.
--
-- Notes:
-- - exec_cert_timeline uses `has_min_tier(4)` (manager/deputy_manager/+)
--   from a different authority pattern than the legacy operational_role
--   in-IN check. Phase B candidate: pick one source of truth.
-- - issue_certificate calls create_notification via PERFORM — capture
--   verbatim. The 'curator' designation gate co-authorizes with manager/SA.
-- - update_cpmai_progress includes cascading XP awards (module → domain →
--   course completion) and auto-flips enrollment status to 'completed'.

CREATE OR REPLACE FUNCTION public.enroll_in_cpmai_course(p_course_id uuid, p_motivation text DEFAULT NULL::text, p_ai_experience text DEFAULT 'beginner'::text, p_domains_of_interest integer[] DEFAULT '{}'::integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid; v_course record; v_enrollment_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid() AND current_cycle_active = true AND is_active = true;
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error','Must be active member'); END IF;

  SELECT * INTO v_course FROM cpmai_courses WHERE id = p_course_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Course not found'); END IF;
  IF v_course.status NOT IN ('enrollment_open','in_progress') THEN RETURN jsonb_build_object('error','Enrollment not open'); END IF;
  IF v_course.enrollment_deadline IS NOT NULL AND now() > v_course.enrollment_deadline THEN RETURN jsonb_build_object('error','Enrollment deadline passed'); END IF;

  -- Check capacity
  IF v_course.max_capacity IS NOT NULL THEN
    IF (SELECT count(*) FROM cpmai_enrollments WHERE course_id = p_course_id AND status IN ('active','completed')) >= v_course.max_capacity THEN
      RETURN jsonb_build_object('error','Course at capacity');
    END IF;
  END IF;

  -- Check not already enrolled
  IF EXISTS (SELECT 1 FROM cpmai_enrollments WHERE course_id = p_course_id AND member_id = v_member_id AND status != 'withdrawn') THEN
    RETURN jsonb_build_object('error','Already enrolled');
  END IF;

  -- Create enrollment
  INSERT INTO cpmai_enrollments (course_id, member_id, status, motivation, ai_experience, domains_of_interest)
  VALUES (p_course_id, v_member_id, 'active', p_motivation, p_ai_experience, p_domains_of_interest)
  RETURNING id INTO v_enrollment_id;

  -- Create progress rows for all modules
  INSERT INTO cpmai_progress (enrollment_id, module_id, status)
  SELECT v_enrollment_id, m.id, 'not_started'
  FROM cpmai_modules m JOIN cpmai_domains d ON d.id = m.domain_id
  WHERE d.course_id = p_course_id;

  RETURN jsonb_build_object('success', true, 'enrollment_id', v_enrollment_id);
END; $function$;

CREATE OR REPLACE FUNCTION public.exec_cert_timeline(p_months integer DEFAULT 12)
 RETURNS TABLE(cohort_month date, members_in_cohort integer, members_with_tier2 integer, members_with_tier1 integer, pct_with_tier2 numeric, pct_with_tier1 numeric, avg_days_to_tier2 numeric, avg_days_to_tier1 numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.has_min_tier(4) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;

  return query
  select
    v.cohort_month,
    v.members_in_cohort,
    v.members_with_tier2,
    v.members_with_tier1,
    v.pct_with_tier2,
    v.pct_with_tier1,
    v.avg_days_to_tier2,
    v.avg_days_to_tier1
  from public.vw_exec_cert_timeline v
  where v.cohort_month >= (date_trunc('month', now())::date - make_interval(months => greatest(1, least(coalesce(p_months, 12), 60))))
  order by v.cohort_month desc;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_cpmai_admin_dashboard(p_course_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_course_id uuid; v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager')) THEN
    RETURN jsonb_build_object('error','Unauthorized');
  END IF;

  IF p_course_id IS NOT NULL THEN v_course_id := p_course_id;
  ELSE SELECT id INTO v_course_id FROM cpmai_courses ORDER BY created_at DESC LIMIT 1;
  END IF;

  SELECT jsonb_build_object(
    'course', (SELECT row_to_json(c) FROM cpmai_courses c WHERE c.id = v_course_id),
    'enrollment_count', (SELECT count(*) FROM cpmai_enrollments WHERE course_id = v_course_id AND status IN ('active','completed')),
    'completed_count', (SELECT count(*) FROM cpmai_enrollments WHERE course_id = v_course_id AND status = 'completed'),
    'avg_progress_pct', (
      SELECT ROUND(AVG(sub.pct)::numeric, 1) FROM (
        SELECT e.id, COALESCE(count(*) FILTER (WHERE p.status='completed')::numeric / NULLIF(count(*),0) * 100, 0) as pct
        FROM cpmai_enrollments e LEFT JOIN cpmai_progress p ON p.enrollment_id = e.id
        WHERE e.course_id = v_course_id AND e.status = 'active'
        GROUP BY e.id
      ) sub
    ),
    'avg_mock_score', (SELECT ROUND(AVG(ms.score_pct)::numeric,1) FROM cpmai_mock_scores ms JOIN cpmai_enrollments e ON e.id=ms.enrollment_id WHERE e.course_id=v_course_id),
    'enrollments', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',e.id,'member_name',m.name,'status',e.status,'enrolled_at',e.enrolled_at,'completed_at',e.completed_at,'ai_experience',e.ai_experience,
        'progress_pct',COALESCE((SELECT ROUND(count(*) FILTER (WHERE p.status='completed')::numeric / NULLIF(count(*),0)*100,1) FROM cpmai_progress p WHERE p.enrollment_id=e.id),0),
        'mock_best',(SELECT max(ms.score_pct) FROM cpmai_mock_scores ms WHERE ms.enrollment_id=e.id)
      ) ORDER BY e.enrolled_at)
      FROM cpmai_enrollments e JOIN members m ON m.id=e.member_id WHERE e.course_id=v_course_id
    ),'[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END; $function$;

CREATE OR REPLACE FUNCTION public.get_cpmai_leaderboard(p_course_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid; v_course_id uuid; v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;

  IF p_course_id IS NOT NULL THEN v_course_id := p_course_id;
  ELSE SELECT id INTO v_course_id FROM cpmai_courses WHERE status != 'cancelled' ORDER BY created_at DESC LIMIT 1;
  END IF;

  SELECT jsonb_agg(row_data ORDER BY (row_data->>'total_xp')::int DESC) INTO v_result FROM (
    SELECT jsonb_build_object(
      'member_id', m.id, 'name', m.name, 'photo_url', m.photo_url,
      'total_xp', COALESCE((SELECT sum(points) FROM gamification_points gp WHERE gp.member_id = m.id AND gp.category = 'cpmai_prep'), 0),
      'modules_completed', (SELECT count(*) FROM cpmai_progress p JOIN cpmai_enrollments e ON e.id = p.enrollment_id WHERE e.member_id = m.id AND e.course_id = v_course_id AND p.status = 'completed'),
      'best_mock_score', (SELECT max(ms.score_pct) FROM cpmai_mock_scores ms JOIN cpmai_enrollments e ON e.id = ms.enrollment_id WHERE e.member_id = m.id AND e.course_id = v_course_id),
      'enrollment_status', e.status
    ) as row_data
    FROM cpmai_enrollments e JOIN members m ON m.id = e.member_id
    WHERE e.course_id = v_course_id AND e.status IN ('active','completed')
  ) sub;

  RETURN COALESCE(v_result, '[]'::jsonb);
END; $function$;

CREATE OR REPLACE FUNCTION public.issue_certificate(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_cert_id uuid; v_code text; v_member_name text; v_member_id uuid;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager') AND NOT ('curator' = ANY(v_caller.designations))) THEN
    RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  v_member_id := (p_data->>'member_id')::uuid;
  SELECT name INTO v_member_name FROM members WHERE id = v_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Member not found'); END IF;
  v_code := 'CERT-' || extract(year FROM now())::text || '-' || upper(substr(md5(random()::text), 1, 6));
  INSERT INTO certificates (member_id, type, title, description, cycle, period_start, period_end, function_role, language, issued_by, verification_code, issued_at)
  VALUES (v_member_id, COALESCE(p_data->>'type','participation'), p_data->>'title', p_data->>'description',
    COALESCE((p_data->>'cycle')::int, 3), p_data->>'period_start', p_data->>'period_end', p_data->>'function_role',
    COALESCE(p_data->>'language','pt-BR'), v_caller.id, v_code, now())
  RETURNING id INTO v_cert_id;

  -- Notify the recipient member
  PERFORM create_notification(
    v_member_id,
    'certificate_issued',
    'Certificate Issued: ' || COALESCE(p_data->>'title', 'Certificate'),
    'You received a certificate: ' || COALESCE(p_data->>'title', ''),
    '/gamification',
    'certificate',
    v_cert_id
  );

  RETURN jsonb_build_object('success', true, 'certificate_id', v_cert_id, 'verification_code', v_code, 'member_name', v_member_name);
END; $function$;

CREATE OR REPLACE FUNCTION public.submit_cpmai_mock_score(p_course_id uuid, p_score_pct integer, p_total_questions integer DEFAULT NULL::integer, p_correct_answers integer DEFAULT NULL::integer, p_mock_source text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid; v_enrollment_id uuid; v_score_id uuid; v_xp int;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;

  SELECT id INTO v_enrollment_id FROM cpmai_enrollments WHERE course_id = p_course_id AND member_id = v_member_id AND status = 'active';
  IF v_enrollment_id IS NULL THEN RETURN jsonb_build_object('error','Not enrolled'); END IF;

  INSERT INTO cpmai_mock_scores (enrollment_id, score_pct, total_questions, correct_answers, mock_source, notes)
  VALUES (v_enrollment_id, p_score_pct, p_total_questions, p_correct_answers, p_mock_source, p_notes)
  RETURNING id INTO v_score_id;

  -- XP based on score bracket
  v_xp := CASE WHEN p_score_pct >= 90 THEN 20 WHEN p_score_pct >= 75 THEN 15 WHEN p_score_pct >= 60 THEN 10 ELSE 5 END;
  INSERT INTO gamification_points (member_id, points, reason, category, ref_id)
  VALUES (v_member_id, v_xp, 'CPMAI mock exam ' || p_score_pct || '%', 'cpmai_prep', v_score_id);

  RETURN jsonb_build_object('success', true, 'score_id', v_score_id, 'xp_earned', v_xp);
END; $function$;

CREATE OR REPLACE FUNCTION public.update_cpmai_progress(p_module_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid; v_enrollment_id uuid; v_domain_id uuid; v_course_id uuid;
  v_xp int; v_domain_total int; v_domain_done int; v_all_done boolean;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;

  IF p_status NOT IN ('in_progress','completed') THEN RETURN jsonb_build_object('error','Invalid status'); END IF;

  -- Find enrollment via module
  SELECT d.id, d.course_id INTO v_domain_id, v_course_id FROM cpmai_modules m JOIN cpmai_domains d ON d.id = m.domain_id WHERE m.id = p_module_id;
  IF v_domain_id IS NULL THEN RETURN jsonb_build_object('error','Module not found'); END IF;

  SELECT e.id INTO v_enrollment_id FROM cpmai_enrollments e WHERE e.course_id = v_course_id AND e.member_id = v_member_id AND e.status = 'active';
  IF v_enrollment_id IS NULL THEN RETURN jsonb_build_object('error','Not enrolled'); END IF;

  -- Update progress
  UPDATE cpmai_progress SET status = p_status, completed_at = CASE WHEN p_status = 'completed' THEN now() ELSE NULL END
  WHERE enrollment_id = v_enrollment_id AND module_id = p_module_id;

  -- XP for completion
  IF p_status = 'completed' THEN
    SELECT xp_value INTO v_xp FROM cpmai_modules WHERE id = p_module_id;
    INSERT INTO gamification_points (member_id, points, reason, category, ref_id)
    VALUES (v_member_id, COALESCE(v_xp, 5), 'CPMAI module completed', 'cpmai_prep', p_module_id);

    -- Check domain completion
    SELECT count(*) FILTER (WHERE m.is_required), count(*) FILTER (WHERE m.is_required AND p2.status = 'completed')
    INTO v_domain_total, v_domain_done
    FROM cpmai_modules m LEFT JOIN cpmai_progress p2 ON p2.module_id = m.id AND p2.enrollment_id = v_enrollment_id
    WHERE m.domain_id = v_domain_id;

    IF v_domain_total > 0 AND v_domain_done = v_domain_total THEN
      INSERT INTO gamification_points (member_id, points, reason, category, ref_id)
      VALUES (v_member_id, 15, 'CPMAI domain completed', 'cpmai_prep', v_domain_id);
    END IF;

    -- Check all domains completion
    SELECT NOT EXISTS (
      SELECT 1 FROM cpmai_modules m2 JOIN cpmai_domains d2 ON d2.id = m2.domain_id
      LEFT JOIN cpmai_progress p3 ON p3.module_id = m2.id AND p3.enrollment_id = v_enrollment_id
      WHERE d2.course_id = v_course_id AND m2.is_required AND (p3.status IS NULL OR p3.status != 'completed')
    ) INTO v_all_done;

    IF v_all_done THEN
      UPDATE cpmai_enrollments SET status = 'completed', completed_at = now() WHERE id = v_enrollment_id;
      INSERT INTO gamification_points (member_id, points, reason, category, ref_id)
      VALUES (v_member_id, 50, 'CPMAI course completed', 'cpmai_prep', v_course_id);
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'domain_progress_pct', ROUND(COALESCE(v_domain_done,0)::numeric / NULLIF(v_domain_total,0) * 100, 1));
END; $function$;
