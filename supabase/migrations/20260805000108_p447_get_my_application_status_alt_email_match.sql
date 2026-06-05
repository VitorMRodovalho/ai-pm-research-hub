-- #447 — get_my_application_status: match the candidate's application by PRIMARY email OR any member_emails alternate.
-- Before: matched only members.email (primary) -> applications whose canonical email is a reconciled ALTERNATE
--         (post-#445 member_emails) were invisible in the candidate's own self-view (live case: Paulo / app 6259ced2).
-- After:  WHERE a.email IN (caller's primary UNION caller's member_emails alternates).
-- Safe (no leak): member_emails.email is globally UNIQUE and no email maps to >1 member (verified live 2026-06-04),
--                 so the UNION cannot surface another person's application.
-- Body-only CREATE OR REPLACE (same signature, no new params).
-- Rollback: re-apply the pre-#447 body (single-equality WHERE lower(trim(a.email)) = lower(trim(v_caller.email))).

CREATE OR REPLACE FUNCTION public.get_my_application_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_apps jsonb;
BEGIN
  SELECT id, email, name INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::jsonb) INTO v_apps
  FROM (
    SELECT
      a.id AS application_id,
      a.cycle_id,
      sc.cycle_code,
      sc.title AS cycle_title,
      sc.phase,
      sc.status AS cycle_status,
      sc.close_date,
      a.role_applied,
      a.promotion_path,
      a.status,
      a.cycle_decision_date,
      a.created_at,
      a.updated_at,
      -- Surface candidato-editable fields so they know what's on file
      a.linkedin_url,
      a.resume_url,
      a.credly_url,
      a.motivation_letter IS NOT NULL AS has_motivation,
      a.consent_ai_analysis_at IS NOT NULL AS ai_consent_granted,
      -- During evaluating phase: show submitted count without identities
      CASE
        WHEN sc.phase = 'evaluating' THEN (
          SELECT COUNT(*)::int FROM public.selection_evaluations e
          WHERE e.application_id = a.id AND e.submitted_at IS NOT NULL
        )
        ELSE NULL
      END AS submitted_evaluations_count,
      -- Status final flag
      a.status = ANY(ARRAY['approved','converted','rejected','objective_cutoff','withdrawn','cancelled']) AS is_final
    FROM public.selection_applications a
    JOIN public.selection_cycles sc ON sc.id = a.cycle_id
    -- #447: match the caller's PRIMARY email OR any of their member_emails alternates.
    -- member_emails.email is globally UNIQUE and no email maps to >1 member, so the UNION
    -- cannot surface another person's application.
    WHERE lower(trim(a.email)) IN (
      SELECT lower(trim(m.email::text))  FROM public.members m        WHERE m.id = v_caller.id         AND m.email IS NOT NULL
      UNION
      SELECT lower(trim(me.email::text)) FROM public.member_emails me WHERE me.member_id = v_caller.id AND me.email IS NOT NULL
    )
  ) r;

  RETURN jsonb_build_object(
    'member_id', v_caller.id,
    'email', v_caller.email,
    'applications', v_apps,
    'count', jsonb_array_length(v_apps)
  );
END; $function$;
