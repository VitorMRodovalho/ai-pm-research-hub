-- Jornadas de onboarding, fatia B: a autodeclaração não fecha etapa que tem fato.
--
-- Decisão do GP (20/11/2026): quem decide se uma etapa fecha por clique ou por fato é o catálogo,
-- numa coluna, e não uma lista copiada em cada função. As quatro etapas com fato são o Termo
-- (certificado), o aceite do VEP (status do VEP), "Conheça sua tribo" (presença numa reunião da
-- tribo, #2718) e a primeira reunião (presença). A exceção é o GP marcar, com justificativa escrita,
-- por admin_complete_onboarding_step; a pessoa não marca.
--
-- Corpos de partida: as capturas mais recentes, conferidas por md5 contra o vivo em 20/11
-- (complete_onboarding_step 5faa98d1, update_pmi_onboarding_step b395ee00, get_my_onboarding
-- d63f009d, consume_onboarding_token 9cc865f8).
-- Guard: tests/contracts/jornadas-fatia-b-fato-fecha.test.mjs.

ALTER TABLE public.onboarding_steps
  ADD COLUMN closed_by text NOT NULL DEFAULT 'member'
  CONSTRAINT onboarding_steps_closed_by_check CHECK (closed_by IN ('member', 'fact'));

COMMENT ON COLUMN public.onboarding_steps.closed_by IS
  'member: a pessoa marca (clique). fact: só um fato fecha (certificado, VEP, presença); a exceção é admin_complete_onboarding_step.';

UPDATE public.onboarding_steps SET closed_by = 'fact'
WHERE id IN ('volunteer_term', 'vep_acceptance', 'meet_tribe', 'first_meeting');

CREATE OR REPLACE FUNCTION public.complete_onboarding_step(p_step_id text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_role text;
BEGIN
  SELECT id, operational_role INTO v_member_id, v_member_role FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  IF NOT EXISTS (
    SELECT 1 FROM onboarding_steps s
    WHERE s.id = p_step_id
      AND public.onboarding_step_applies(s.applies_to_role, v_member_role)
  ) THEN
    RETURN jsonb_build_object('error', 'Invalid step'); END IF;
  -- Jornadas fatia B: etapa que fecha por fato (onboarding_steps.closed_by) não fecha por clique.
  IF EXISTS (SELECT 1 FROM onboarding_steps s WHERE s.id = p_step_id AND s.closed_by = 'fact') THEN
    RETURN jsonb_build_object('error', 'step_closed_by_fact', 'step_id', p_step_id);
  END IF;
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at, metadata, updated_at)
  VALUES (v_member_id, p_step_id, 'completed', now(), p_metadata, now())
  ON CONFLICT (member_id, step_key) DO UPDATE SET
    status = 'completed', completed_at = now(),
    metadata = COALESCE(p_metadata, onboarding_progress.metadata), updated_at = now();
  RETURN jsonb_build_object('success', true, 'step_id', p_step_id);
END; $function$;

CREATE OR REPLACE FUNCTION public.update_pmi_onboarding_step(p_token text, p_step_key text, p_status text DEFAULT 'completed'::text, p_evidence_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_step record;
  v_total int;
  v_completed int;
  v_all_done boolean;
BEGIN
  -- 1. Validate token + scope
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'profile_completion' = ANY(scopes);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing profile_completion scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type % does not support PMI onboarding step update', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;

  -- 2. Validate status
  IF p_status NOT IN ('completed', 'skipped', 'in_progress') THEN
    RAISE EXCEPTION 'Invalid status: must be completed, skipped, or in_progress';
  END IF;

  -- 2b. Jornadas fatia B: etapa que fecha por fato (onboarding_steps.closed_by) não fecha pelo portal.
  IF EXISTS (SELECT 1 FROM public.onboarding_steps s WHERE s.id = p_step_key AND s.closed_by = 'fact') THEN
    RAISE EXCEPTION 'Step % closes by fact, not by self-declaration', p_step_key
      USING ERRCODE = 'check_violation';
  END IF;

  -- 3. Verify step exists for this application
  SELECT * INTO v_step
  FROM public.onboarding_progress
  WHERE application_id = v_application_id AND step_key = p_step_key;
  IF v_step IS NULL THEN
    RAISE EXCEPTION 'Onboarding step not found for application';
  END IF;

  -- 4. Update step
  UPDATE public.onboarding_progress
  SET status = p_status,
      completed_at = CASE WHEN p_status IN ('completed', 'skipped') THEN now() ELSE NULL END,
      evidence_url = COALESCE(p_evidence_url, evidence_url)
  WHERE application_id = v_application_id AND step_key = p_step_key;

  -- 5. Check if all steps are done
  SELECT COUNT(*) INTO v_total FROM public.onboarding_progress WHERE application_id = v_application_id;
  SELECT COUNT(*) INTO v_completed FROM public.onboarding_progress
    WHERE application_id = v_application_id AND status IN ('completed', 'skipped');

  v_all_done := (v_completed = v_total AND v_total > 0);

  -- Note: R8 wrapper does NOT auto-activate member or update application.status.
  -- The candidate via token only marks their own click steps; the exception for a
  -- fact step is admin_complete_onboarding_step (GP, with a written reason).

  RETURN jsonb_build_object(
    'success', true,
    'step_key', p_step_key,
    'new_status', p_status,
    'all_done', v_all_done,
    'completed_steps', v_completed,
    'total_steps', v_total
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_role text;
  v_has_req_agreement_engagement boolean;
  v_result jsonb;
BEGIN
  SELECT id, operational_role INTO v_member_id, v_member_role
  FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  -- #322 close-review: mirror the approve_selection_application forward guard here.
  SELECT EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.members m ON m.id = v_member_id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    WHERE e.person_id = m.person_id
      AND e.status = 'active'
      AND ek.requires_agreement = true
  ) INTO v_has_req_agreement_engagement;

  -- Auto-generate progress rows (guarded: volunteer_term only with an active
  -- requires_agreement engagement; #1103: only steps that apply to this member's role)
  INSERT INTO onboarding_progress (member_id, step_key, status)
  SELECT v_member_id, s.id, 'pending'
  FROM onboarding_steps s
  WHERE NOT EXISTS (SELECT 1 FROM onboarding_progress op WHERE op.member_id = v_member_id AND op.step_key = s.id)
    AND NOT (s.id = 'volunteer_term' AND NOT v_has_req_agreement_engagement)
    AND public.onboarding_step_applies(s.applies_to_role, v_member_role);

  SELECT jsonb_build_object(
    'member_id', v_member_id,
    'total_steps', (SELECT count(*) FROM onboarding_steps s
      WHERE s.is_required AND public.onboarding_step_applies(s.applies_to_role, v_member_role)),
    'completed_steps', (SELECT count(*) FROM onboarding_progress
      WHERE member_id = v_member_id AND status IN ('completed', 'skipped')
        AND step_key IN (SELECT id FROM onboarding_steps s
          WHERE public.onboarding_step_applies(s.applies_to_role, v_member_role))),
    'all_complete', (NOT EXISTS (
      SELECT 1 FROM onboarding_steps s
      JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = v_member_id
      WHERE s.is_required AND op.status NOT IN ('completed', 'skipped')
        AND public.onboarding_step_applies(s.applies_to_role, v_member_role)
    )),
    'steps', (SELECT jsonb_agg(row_to_json(t) ORDER BY t.step_order) FROM (
      SELECT s.id AS step_id, s.step_order, s.label_pt, s.label_en, s.label_es,
        s.description_pt, s.description_en, s.description_es, s.icon, s.is_required, s.closed_by,
        COALESCE(op.status, 'pending') AS status, op.completed_at, op.metadata
      FROM onboarding_steps s
      LEFT JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = v_member_id
      WHERE public.onboarding_step_applies(s.applies_to_role, v_member_role)
      ORDER BY s.step_order
    ) t)
  ) INTO v_result;
  RETURN v_result;
END; $function$;

CREATE OR REPLACE FUNCTION public.consume_onboarding_token(p_token text)
 RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_app selection_applications%ROWTYPE;
  v_cycle selection_cycles%ROWTYPE;
  v_progress jsonb;
  v_video_screenings jsonb;
  v_step_catalog jsonb;
  v_member_id uuid;
  v_member_auth_id uuid;
  v_primary_email text;
  v_result jsonb;
BEGIN
  UPDATE onboarding_tokens
     SET consumed_at = COALESCE(consumed_at, now()),
         last_accessed_at = now(),
         access_count = access_count + 1
   WHERE token = p_token
     AND expires_at > now()
  RETURNING * INTO v_token_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired token'
      USING ERRCODE = 'invalid_authorization_specification';
  END IF;

  IF v_token_row.source_type = 'pmi_application' THEN
    SELECT * INTO v_app
    FROM selection_applications
    WHERE id = v_token_row.source_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Token references missing application';
    END IF;

    SELECT * INTO v_cycle
    FROM selection_cycles
    WHERE id = v_app.cycle_id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'step_key', op.step_key,
      'status', op.status,
      'completed_at', op.completed_at,
      'evidence_url', op.evidence_url,
      'notes', op.notes,
      'sla_deadline', op.sla_deadline
    ) ORDER BY op.created_at), '[]'::jsonb)
    INTO v_progress
    FROM onboarding_progress op
    WHERE op.application_id = v_app.id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'pillar', vs.pillar,
      'question_index', vs.question_index,
      'status', vs.status,
      'uploaded_at', vs.uploaded_at
    ) ORDER BY vs.question_index, vs.created_at), '[]'::jsonb)
    INTO v_video_screenings
    FROM pmi_video_screenings vs
    WHERE vs.application_id = v_app.id;

    -- #2273 defeito A — o CATALOGO, que e onde os rotulos sempre estiveram.
    -- Vai inteiro, sem filtrar por papel: quem decide quais passos a pessoa tem e
    -- `onboarding_progress`, ja semeado. Filtrar aqui duplicaria a regra de elegibilidade em
    -- dois lugares, e a copia e que envelhece.
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'key', os.id,
      'step_order', os.step_order,
      'icon', os.icon,
      'is_required', os.is_required,
      'applies_to_role', os.applies_to_role,
      'closed_by', os.closed_by,
      'label', jsonb_build_object(
        'pt-BR', os.label_pt, 'en-US', os.label_en, 'es-LATAM', os.label_es
      ),
      'description', jsonb_build_object(
        'pt-BR', os.description_pt, 'en-US', os.description_en, 'es-LATAM', os.description_es
      )
    ) ORDER BY os.step_order), '[]'::jsonb)
    INTO v_step_catalog
    FROM onboarding_steps os;

    -- #2273 defeito B — o estado de conta, para o portal poder dizer COM QUAL e-mail entrar.
    v_member_id := public._portal_member_for_application(v_app.id);
    IF v_member_id IS NOT NULL THEN
      SELECT m.auth_id,
             COALESCE(
               (SELECT me.email::text FROM public.member_emails me
                 WHERE me.member_id = m.id AND me.is_primary IS TRUE LIMIT 1),
               m.email
             )
        INTO v_member_auth_id, v_primary_email
      FROM public.members m WHERE m.id = v_member_id;
    END IF;

    v_result := jsonb_build_object(
      'source_type', 'pmi_application',
      'scopes', v_token_row.scopes,
      'application', jsonb_build_object(
        'id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'email', v_app.email,
        'phone', v_app.phone,
        'linkedin_url', v_app.linkedin_url,
        'credly_url', v_app.credly_url,
        'role_applied', v_app.role_applied,
        'cycle_id', v_app.cycle_id,
        'has_consent', v_app.consent_ai_analysis_at IS NOT NULL
                       AND v_app.consent_ai_analysis_revoked_at IS NULL,
        'has_revoked', v_app.consent_ai_analysis_revoked_at IS NOT NULL,
        'has_voice_biometric_consent', v_app.consent_voice_biometric_at IS NOT NULL
                       AND v_app.consent_voice_biometric_revoked_at IS NULL,
        'has_voice_biometric_revoked', v_app.consent_voice_biometric_revoked_at IS NOT NULL,
        'status', v_app.status
      ),
      'cycle', jsonb_build_object(
        'id', v_cycle.id,
        'cycle_code', v_cycle.cycle_code,
        'title', v_cycle.title,
        'phase', v_cycle.phase,
        'onboarding_steps', v_cycle.onboarding_steps
      ),
      'step_catalog', v_step_catalog,
      -- #2393 A2: a vaga da candidatura, para o portal mostrar o período e os passos da trilha no lugar do ciclo.
      'opening', (SELECT jsonb_build_object(
                    'opportunity_id', vo.opportunity_id, 'title', vo.title,
                    'start_date', vo.start_date, 'end_date', vo.end_date,
                    'evaluation_track', vo.evaluation_track, 'video_invite_by', vo.video_invite_by,
                    -- o prazo do resultado do piloto, contado da emissão deste token (a mesma regra do prazo do link)
                    'result_by', CASE WHEN vo.evaluation_track = 'line_pilot'
                                      THEN (v_token_row.issued_at + public._prazo_do_resultado_do_piloto())::date END)
                  FROM public.vep_opportunities vo WHERE vo.opportunity_id = v_app.vep_opportunity_id),
      'account_state', jsonb_build_object(
        'member_exists',     v_member_id IS NOT NULL,
        'has_account',       v_member_auth_id IS NOT NULL,
        'masked_email',      public._mask_email(v_primary_email),
        'can_request_setup', v_member_id IS NOT NULL
                             AND v_member_auth_id IS NULL
                             AND v_app.status = 'approved'
      ),
      'onboarding_progress', v_progress,
      'video_screenings', v_video_screenings,
      'token_metadata', jsonb_build_object(
        'access_count', v_token_row.access_count,
        'expires_at', v_token_row.expires_at,
        'first_access', v_token_row.consumed_at = v_token_row.last_accessed_at
      )
    );

  ELSIF v_token_row.source_type IN ('initiative_invitation', 'direct_assignment') THEN
    v_result := jsonb_build_object(
      'source_type', v_token_row.source_type,
      'scopes', v_token_row.scopes,
      'pending_implementation', true,
      'message', 'Esse fluxo ainda não está ativo. Aguarde comunicação.'
    );

  ELSE
    RAISE EXCEPTION 'Unknown source_type: %', v_token_row.source_type;
  END IF;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_complete_onboarding_step(p_member_id uuid, p_step_key text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_role text;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: manage_platform required' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_note IS NULL OR length(btrim(p_note)) < 3 THEN
    RAISE EXCEPTION 'A written reason is required' USING ERRCODE = 'check_violation';
  END IF;
  SELECT operational_role INTO v_role FROM members WHERE id = p_member_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM onboarding_steps s
                 WHERE s.id = p_step_key AND public.onboarding_step_applies(s.applies_to_role, v_role)) THEN
    RAISE EXCEPTION 'Step % does not apply to this member', p_step_key USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at, metadata, updated_at)
  VALUES (p_member_id, p_step_key, 'completed', now(),
          jsonb_build_object('closed_by', 'gp', 'gp_member_id', v_caller_id, 'gp_note', btrim(p_note), 'gp_at', now()),
          now())
  ON CONFLICT (member_id, step_key) DO UPDATE SET
    status = 'completed', completed_at = now(),
    metadata = COALESCE(onboarding_progress.metadata, '{}'::jsonb)
      || jsonb_build_object('closed_by', 'gp', 'gp_member_id', v_caller_id, 'gp_note', btrim(p_note), 'gp_at', now()),
    updated_at = now();

  RETURN jsonb_build_object('success', true, 'member_id', p_member_id, 'step_key', p_step_key);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_complete_onboarding_step(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_complete_onboarding_step(uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
