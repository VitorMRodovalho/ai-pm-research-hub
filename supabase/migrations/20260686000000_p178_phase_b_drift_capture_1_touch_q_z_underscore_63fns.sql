-- p178 Phase B drift capture — 1-touch bucket Q-Z + underscore-prefix (63 fns).
--
-- **FINAL 1-touch batch — closes Phase B 1-touch drift recovery.** Cumulative
-- across p176 + p178: 225/225 fns captured (100%) under Q-C/Phase-C charter.
--
-- Each fn below is currently in the 1-touch bucket of
-- `RPC_BODY_DRIFT_ALLOWLIST_P175.txt` — captured by exactly one prior migration
-- whose body has since drifted from live.
--
-- Bodies pulled via pg_get_functiondef() — live IS canonical at the time of
-- capture. After apply, these fns are clean per Phase C body-hash drift contract
-- and removed from allowlist. BODY_DRIFT_BASELINE_SIZE 63→0. Allowlist file
-- becomes header-only.
--
-- Rollback: not needed — capturing live state. To revert a single fn, restore
-- its prior CREATE OR REPLACE FUNCTION body from the migration in `latest_file`.

CREATE OR REPLACE FUNCTION public._audit_list_public_tables()
 RETURNS TABLE(table_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT c.relname::text
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind IN ('r', 'p')  -- regular + partitioned (root only — partitions filtered by lacking pg_inherits parent)
    AND NOT EXISTS (
      -- Exclude partitions (children of partitioned tables)
      SELECT 1 FROM pg_catalog.pg_inherits i WHERE i.inhrelid = c.oid
    )
  ORDER BY c.relname;
$function$
;

CREATE OR REPLACE FUNCTION public._audit_preview_gate_eligibles_drift()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_doc_type text;
  v_gate jsonb;
  v_gate_kind text;
  v_cache_count int;
  v_live_count int;
  v_results jsonb := '[]'::jsonb;
BEGIN
  FOREACH v_doc_type IN ARRAY public._cacheable_preview_doc_types()
  LOOP
    FOR v_gate IN SELECT * FROM jsonb_array_elements(public.resolve_default_gates(v_doc_type))
    LOOP
      v_gate_kind := v_gate->>'kind';
      -- Skip submitter_acceptance — not cacheable
      IF v_gate_kind = 'submitter_acceptance' THEN CONTINUE; END IF;

      -- Cache count
      SELECT count(*) INTO v_cache_count
      FROM public.preview_gate_eligibles_cache c
      JOIN public.members m ON m.id = c.member_id
      WHERE c.doc_type = v_doc_type
        AND m.is_active = true
        AND v_gate_kind = ANY(c.eligible_gates);

      -- Live count
      SELECT count(*) INTO v_live_count
      FROM public.members m
      WHERE m.is_active = true
        AND public._can_sign_gate(m.id, NULL, v_gate_kind, v_doc_type, NULL);

      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'doc_type', v_doc_type,
        'gate_kind', v_gate_kind,
        'cache_count', v_cache_count,
        'live_count', v_live_count,
        'mismatch', v_cache_count <> v_live_count
      ));
    END LOOP;
  END LOOP;

  RETURN v_results;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._auto_stage_alumni_on_cycle_open()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_alumni record;
  v_count integer := 0;
BEGIN
  -- Only trigger when is_current flips false → true
  IF (OLD.is_current IS DISTINCT FROM NEW.is_current) AND NEW.is_current = true THEN
    FOR v_alumni IN
      SELECT DISTINCT m.id AS member_id
      FROM public.members m
      JOIN public.member_offboarding_records r ON r.member_id = m.id
      WHERE m.member_status = 'alumni'
        AND m.anonymized_at IS NULL
        AND r.return_interest = true
        AND NOT EXISTS (
          SELECT 1 FROM public.re_engagement_pipeline p
          WHERE p.member_id = m.id AND p.cycle_code = NEW.cycle_code
            AND p.state IN ('staged','invited','accepted')
        )
    LOOP
      PERFORM public.stage_alumni_for_re_engagement(v_alumni.member_id, NEW.cycle_code, 'cron_new_cycle');
      v_count := v_count + 1;
    END LOOP;

    IF v_count > 0 THEN
      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
      VALUES (
        NULL, 're_engagement.auto_staged_on_cycle_open', 'cycle', NULL,
        jsonb_build_object('cycle_code', NEW.cycle_code, 'staged_count', v_count),
        jsonb_build_object('source', 'trg_auto_stage_alumni_on_cycle_open')
      );
    END IF;
  END IF;
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION public._block_self_evaluation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_evaluator_email text;
  v_applicant_email text;
BEGIN
  SELECT email INTO v_evaluator_email FROM members WHERE id = NEW.evaluator_id;
  SELECT email INTO v_applicant_email FROM selection_applications WHERE id = NEW.application_id;

  IF v_evaluator_email IS NOT NULL
     AND v_applicant_email IS NOT NULL
     AND lower(trim(v_evaluator_email)) = lower(trim(v_applicant_email)) THEN
    RAISE EXCEPTION 'Conflict of interest: evaluator (%) cannot evaluate their own application (%)',
      v_evaluator_email, v_applicant_email
      USING HINT = 'Self-evaluation is not allowed. Another committee member must evaluate this candidacy.';
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._enqueue_engagement_welcome(p_engagement_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_eng record;
  v_member_id uuid;
  v_initiative_title text;
  v_initiative_kind text;
  v_subject text;
  v_body text;
  v_link text;
BEGIN
  SELECT e.*, p.id AS person_id_resolved
  INTO v_eng
  FROM public.engagements e
  LEFT JOIN public.persons p ON p.id = e.person_id
  WHERE e.id = p_engagement_id;

  IF NOT FOUND THEN RETURN; END IF;

  -- Resolve member_id from person_id (guard: skip se nao ha member linked)
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.person_id = v_eng.person_id
  LIMIT 1;

  IF v_member_id IS NULL THEN RETURN; END IF;

  -- Resolve initiative metadata
  SELECT i.title, i.kind INTO v_initiative_title, v_initiative_kind
  FROM public.initiatives i WHERE i.id = v_eng.initiative_id;

  v_link := '/iniciativas/' || COALESCE(v_eng.initiative_id::text, '');

  -- Per-kind subject + body. Legal: NUNCA bundle com cessao de direitos.
  CASE v_eng.kind
    WHEN 'speaker' THEN
      v_subject := 'Bem-vindo(a) como speaker em ' || COALESCE(v_initiative_title, 'iniciativa');
      v_body := 'Sua participacao como speaker foi registrada. ' ||
                'Antes da preparacao do material, voce recebera o Termo de Speaker ' ||
                'em etapa dedicada para leitura e assinatura. Duvidas sobre direitos ' ||
                'autorais? Contate a coordenacao do Nucleo IA Hub.';
    WHEN 'volunteer' THEN
      v_subject := 'Bem-vindo(a) ao ' || COALESCE(v_initiative_title, 'Nucleo IA Hub');
      v_body := 'Sua participacao como voluntario(a) foi registrada. ' ||
                'Em breve voce recebera o Termo de Voluntariado para assinatura. ' ||
                'Acesse a iniciativa para ver agenda e proximos passos.';
    WHEN 'study_group_owner' THEN
      v_subject := 'Voce e owner de ' || COALESCE(v_initiative_title, 'study group');
      v_body := 'Voce foi confirmado(a) como owner deste grupo de estudo. ' ||
                'Voce pode convocar participantes, agendar reunioes e emitir certificados ' ||
                'ao final. Use o painel da iniciativa para gerenciar.';
    WHEN 'study_group_participant' THEN
      v_subject := 'Bem-vindo(a) ao grupo ' || COALESCE(v_initiative_title, 'de estudo');
      v_body := 'Sua participacao no grupo de estudo foi registrada. ' ||
                'Acesse o cronograma e materiais na pagina da iniciativa.';
    WHEN 'observer' THEN
      v_subject := 'Voce esta listado como observer em ' || COALESCE(v_initiative_title, 'iniciativa');
      v_body := 'Sua participacao como observador foi registrada. ' ||
                'Voce tem acesso de leitura aos materiais e reunioes da iniciativa.';
    WHEN 'committee_coordinator', 'committee_member' THEN
      v_subject := 'Bem-vindo(a) ao comite ' || COALESCE(v_initiative_title, '');
      v_body := 'Sua participacao no comite foi registrada. ' ||
                'Acesse o painel para ver responsabilidades e agenda.';
    WHEN 'workgroup_coordinator', 'workgroup_member' THEN
      v_subject := 'Bem-vindo(a) ao workgroup ' || COALESCE(v_initiative_title, '');
      v_body := 'Sua participacao no workgroup foi registrada. ' ||
                'Acesse o painel para ver tarefas e proximos passos.';
    ELSE
      -- Default: skip welcome para kinds nao-mapeados (guard clause)
      RETURN;
  END CASE;

  -- Enqueue notification (delivery_mode='transactional_immediate' = welcome eh time-sensitive)
  INSERT INTO public.notifications (
    recipient_id, type, title, body, link, source_type, source_id, delivery_mode
  ) VALUES (
    v_member_id,
    'engagement_welcome',
    v_subject,
    v_body,
    v_link,
    'engagement',
    p_engagement_id,
    'transactional_immediate'
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public._get_peer_review_eligibility(p_application_id uuid)
 RETURNS TABLE(peer_member_id uuid, peer_name text, peer_email text, load_count integer, last_invited_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_app record;
BEGIN
  SELECT cycle_id, email INTO v_app
  FROM public.selection_applications
  WHERE id = p_application_id;

  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found: %', p_application_id;
  END IF;

  RETURN QUERY
  SELECT
    m.id AS peer_member_id,
    m.name AS peer_name,
    m.email AS peer_email,
    -- load_count = submitted evals + pending invitations (not yet evaluated)
    (
      SELECT count(*)::int
      FROM public.selection_evaluations e
      JOIN public.selection_applications sa ON sa.id = e.application_id
      WHERE e.evaluator_id = m.id AND sa.cycle_id = v_app.cycle_id
    )
    +
    (
      SELECT count(*)::int
      FROM public.notifications n
      JOIN public.selection_applications sa ON sa.id = n.source_id
      WHERE n.type = 'peer_review_requested'
        AND n.recipient_id = m.id
        AND sa.cycle_id = v_app.cycle_id
        AND NOT EXISTS (
          SELECT 1 FROM public.selection_evaluations e2
          WHERE e2.application_id = n.source_id AND e2.evaluator_id = m.id
        )
    ) AS load_count,
    -- last_invited_at: most recent peer_review_requested notification in cycle
    (
      SELECT max(n.created_at)
      FROM public.notifications n
      JOIN public.selection_applications sa ON sa.id = n.source_id
      WHERE n.type = 'peer_review_requested'
        AND n.recipient_id = m.id
        AND sa.cycle_id = v_app.cycle_id
    ) AS last_invited_at
  FROM public.selection_committee sc
  JOIN public.members m ON m.id = sc.member_id
  WHERE sc.cycle_id = v_app.cycle_id
    AND sc.role IN ('evaluator', 'lead')
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.type = 'peer_review_requested'
        AND n.recipient_id = m.id
        AND n.source_id = p_application_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations e
      WHERE e.application_id = p_application_id
        AND e.evaluator_id = m.id
    )
    AND m.email != v_app.email
  ORDER BY load_count ASC, last_invited_at ASC NULLS FIRST, m.name ASC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._get_vault_secret(p_name text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_secret text;
BEGIN
  -- Service role only — Edge Functions usam service_role key
  IF current_user NOT IN ('service_role', 'postgres', 'supabase_admin') THEN
    RETURN NULL;
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = p_name
  LIMIT 1;

  RETURN v_secret;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._grant_auto_xp(p_slug text, p_recipient_id uuid, p_ref_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_rule gamification_rules%ROWTYPE;
  v_org_id uuid;
BEGIN
  IF p_recipient_id IS NULL THEN
    RETURN; -- silently skip if no recipient (NULL assignee/author)
  END IF;

  SELECT organization_id INTO v_org_id FROM members WHERE id = p_recipient_id;
  IF v_org_id IS NULL THEN
    RETURN; -- recipient member not found
  END IF;

  SELECT * INTO v_rule
  FROM gamification_rules
  WHERE slug = p_slug
    AND organization_id = v_org_id
    AND active = true
    AND effective_from <= now()
  ORDER BY effective_from DESC LIMIT 1;
  IF v_rule.slug IS NULL THEN
    RETURN; -- rule disabled or missing
  END IF;

  -- Idempotency: skip if already paid for this ref_id + category
  IF EXISTS (
    SELECT 1 FROM gamification_points
    WHERE ref_id = p_ref_id AND category = p_slug AND member_id = p_recipient_id
  ) THEN
    RETURN;
  END IF;

  INSERT INTO gamification_points (member_id, points, reason, category, ref_id, organization_id)
  VALUES (p_recipient_id, v_rule.base_points, p_reason, v_rule.slug, p_ref_id, v_org_id);
END;
$function$
;

CREATE OR REPLACE FUNCTION public._log_gate_attempt(p_application_id uuid, p_rpc_name text, p_caller_id uuid, p_gate_passed boolean, p_gate_failed_code text, p_gate_failed_reason text, p_bypass_requested boolean, p_bypass_granted boolean, p_payload jsonb, p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.gate_attempts (
    application_id, rpc_name, caller_id, gate_passed,
    gate_failed_code, gate_failed_reason,
    bypass_requested, bypass_granted, payload, organization_id
  ) VALUES (
    p_application_id, p_rpc_name, p_caller_id, p_gate_passed,
    p_gate_failed_code, p_gate_failed_reason,
    p_bypass_requested, p_bypass_granted, p_payload, p_organization_id
  );
EXCEPTION WHEN OTHERS THEN
  -- Audit failure must never block business logic
  RAISE WARNING '_log_gate_attempt failed: %', SQLERRM;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._offboarding_create_stub()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_inferred_category text;
  v_reason_text       text;
  v_chapter           text;
  v_cycle_code        text;
BEGIN
  IF NEW.member_status NOT IN ('alumni','observer','inactive') THEN
    RETURN NEW;
  END IF;

  IF EXISTS (SELECT 1 FROM public.member_offboarding_records WHERE member_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  v_reason_text := COALESCE(NEW.status_change_reason, '');
  v_inferred_category := NULL;
  IF v_reason_text ~ '^[a-z_]+:\s' THEN
    v_inferred_category := SPLIT_PART(v_reason_text, ':', 1);
    IF NOT EXISTS (SELECT 1 FROM public.offboard_reason_categories WHERE code = v_inferred_category) THEN
      v_inferred_category := NULL;
    END IF;
  END IF;

  v_chapter := NEW.chapter;
  SELECT cycle_code INTO v_cycle_code
  FROM public.cycles WHERE is_current = true ORDER BY cycle_start DESC LIMIT 1;

  INSERT INTO public.member_offboarding_records (
    member_id, offboarded_at, offboarded_by,
    reason_category_code, reason_detail,
    tribe_id_at_offboard, chapter_at_offboard, cycle_code_at_offboard
  ) VALUES (
    NEW.id, COALESCE(NEW.offboarded_at, now()), NEW.offboarded_by,
    v_inferred_category, NULLIF(TRIM(v_reason_text), ''),
    NEW.tribe_id, v_chapter, v_cycle_code
  );

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._sync_interview_to_event(p_interview_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_interview record;
  v_app       record;
  v_event_id  uuid;
  v_event_status text;
  v_event_date date;
  v_event_time time;
  v_interviewer_ids uuid[];
BEGIN
  SELECT * INTO v_interview FROM public.selection_interviews WHERE id = p_interview_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT a.*, c.cycle_code AS cycle_code
    INTO v_app
    FROM public.selection_applications a
    LEFT JOIN public.selection_cycles c ON c.id = a.cycle_id
   WHERE a.id = v_interview.application_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  v_event_status := CASE v_interview.status
    WHEN 'completed'   THEN 'completed'
    WHEN 'cancelled'   THEN 'cancelled'
    WHEN 'noshow'      THEN 'cancelled'
    WHEN 'rescheduled' THEN 'cancelled'
    ELSE 'scheduled'
  END;

  IF v_interview.scheduled_at IS NOT NULL THEN
    v_event_date := (v_interview.scheduled_at AT TIME ZONE 'America/Sao_Paulo')::date;
    v_event_time := (v_interview.scheduled_at AT TIME ZONE 'America/Sao_Paulo')::time;
  END IF;

  IF v_interview.calendar_event_id IS NOT NULL AND v_interview.calendar_event_id <> '' THEN
    SELECT id INTO v_event_id
      FROM public.events
     WHERE calendar_event_id = v_interview.calendar_event_id
       AND type = 'entrevista'
     LIMIT 1;
  END IF;

  IF v_event_id IS NULL AND v_event_date IS NOT NULL THEN
    SELECT id INTO v_event_id
      FROM public.events
     WHERE selection_application_id = v_interview.application_id
       AND type = 'entrevista'
       AND date  = v_event_date
       AND (
         time_start IS NULL
         OR ABS(EXTRACT(EPOCH FROM (time_start - v_event_time))) <= 300
       )
     ORDER BY (time_start IS NULL) ASC, ABS(EXTRACT(EPOCH FROM (COALESCE(time_start, v_event_time) - v_event_time))) ASC
     LIMIT 1;
  END IF;

  v_interviewer_ids := NULLIF(v_interview.interviewer_ids, ARRAY[]::uuid[]);

  IF v_event_id IS NOT NULL THEN
    UPDATE public.events
       SET status                   = v_event_status,
           date                     = COALESCE(v_event_date, date),
           time_start               = COALESCE(v_event_time, time_start),
           duration_minutes         = COALESCE(v_interview.duration_minutes, duration_minutes),
           invited_member_ids       = COALESCE(v_interviewer_ids, invited_member_ids),
           selection_application_id = COALESCE(selection_application_id, v_interview.application_id),
           calendar_event_id        = COALESCE(calendar_event_id, NULLIF(v_interview.calendar_event_id, '')),
           updated_at               = now()
     WHERE id = v_event_id;
    RETURN v_event_id;
  END IF;

  IF v_interview.scheduled_at IS NULL THEN
    RETURN NULL;
  END IF;
  IF v_interview.notes IS NOT NULL AND v_interview.notes ILIKE '%[Espelhado%' THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.events (
    type, title, date, time_start, duration_minutes, status,
    audience_level, visibility, nature, source,
    calendar_event_id, invited_member_ids, selection_application_id,
    organization_id, created_at, updated_at
  ) VALUES (
    'entrevista',
    'Entrevista — ' || COALESCE(v_app.applicant_name, 'Candidato')
      || COALESCE(' (' || v_app.cycle_code || ')', ''),
    v_event_date,
    v_event_time,
    COALESCE(v_interview.duration_minutes, 30),
    v_event_status,
    'leadership',
    'leadership',
    'entrevista_selecao',
    'selection_portal',
    NULLIF(v_interview.calendar_event_id, ''),
    v_interviewer_ids,
    v_interview.application_id,
    v_interview.organization_id,
    now(), now()
  )
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._sync_member_initiative_from_engagement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  -- Only fire when an active engagement with initiative scope appears
  IF NEW.status IS DISTINCT FROM 'active' OR NEW.initiative_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Resolve member via person_id (V4 canonical link)
  SELECT id INTO v_member_id
  FROM public.members
  WHERE person_id = NEW.person_id
    AND initiative_id IS NULL
  LIMIT 1;

  IF v_member_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Set member.initiative_id only when currently NULL (never overwrite existing primary tribe)
  UPDATE public.members
  SET initiative_id = NEW.initiative_id, updated_at = now()
  WHERE id = v_member_id AND initiative_id IS NULL;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._trg_compute_evaluation_anomalies_on_phase_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_app record;
  v_stddev numeric;
  v_mean numeric;
  v_count int;
BEGIN
  -- Only fire on transition to 'evaluations_closed'
  IF NEW.phase IS DISTINCT FROM OLD.phase
     AND NEW.phase = 'evaluations_closed'
     AND OLD.phase = 'evaluating' THEN

    FOR v_app IN
      SELECT id FROM selection_applications WHERE cycle_id = NEW.id
    LOOP
      SELECT
        stddev(weighted_subtotal),
        avg(weighted_subtotal),
        count(*)
      INTO v_stddev, v_mean, v_count
      FROM selection_evaluations
      WHERE application_id = v_app.id AND submitted_at IS NOT NULL;

      -- Threshold: stddev > 1.5 with at least 2 evaluators
      IF v_count >= 2 AND v_stddev > 1.5 THEN
        INSERT INTO selection_evaluation_anomalies
          (application_id, cycle_id, alert_type, payload)
        VALUES (
          v_app.id, NEW.id, 'high_variance',
          jsonb_build_object(
            'stddev', v_stddev,
            'mean', v_mean,
            'evaluator_count', v_count,
            'threshold', 1.5,
            'detected_at_phase_change', now()
          )
        );
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._trg_engagement_welcome_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Only fire for active engagements
  IF NEW.status = 'active' THEN
    PERFORM public._enqueue_engagement_welcome(NEW.id);
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._trg_refresh_preview_gate_eligibles_on_engagement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_person_id uuid;
  v_member_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_person_id := OLD.person_id;
  ELSE
    v_person_id := NEW.person_id;
  END IF;

  IF v_person_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  -- Refresh all members linked to this person (typically 1, sometimes more)
  FOR v_member_id IN
    SELECT m.id FROM public.members m WHERE m.person_id = v_person_id
  LOOP
    PERFORM public._refresh_preview_gate_eligibles_for_member(v_member_id);
  END LOOP;

  RETURN COALESCE(NEW, OLD);
END;
$function$
;

CREATE OR REPLACE FUNCTION public._trg_sync_interview_to_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  BEGIN
    PERFORM public._sync_interview_to_event(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
      VALUES (
        'interview_event_sync_error',
        'warning',
        'Failed to sync selection_interview to events row',
        jsonb_build_object(
          'interview_id', NEW.id,
          'application_id', NEW.application_id,
          'error', SQLERRM,
          'sqlstate', SQLSTATE
        )
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._tribe_broadcast_urgent_rate_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor_count integer;
  v_week_start timestamptz := date_trunc('week', now());
BEGIN
  -- Only enforce for tribe_broadcast type with immediate delivery
  IF NEW.type != 'tribe_broadcast' THEN RETURN NEW; END IF;
  IF NEW.delivery_mode != 'transactional_immediate' THEN RETURN NEW; END IF;
  IF NEW.actor_id IS NULL THEN RETURN NEW; END IF;

  -- Count this actor's prior urgent broadcasts in current ISO week
  SELECT count(DISTINCT digest_batch_id)
  INTO v_actor_count
  FROM public.notifications
  WHERE type = 'tribe_broadcast'
    AND delivery_mode = 'transactional_immediate'
    AND actor_id = NEW.actor_id
    AND created_at >= v_week_start
    AND id != NEW.id;

  -- Rate limit: 1 urgent broadcast batch per week per actor
  -- (digest_batch_id allows N notifications in same broadcast count as 1)
  IF v_actor_count >= 1 THEN
    RAISE EXCEPTION 'rate_limit_exceeded: tribe_broadcast urgent limited to 1/week/leader (current: %, week_start: %). Use delivery_mode=digest_weekly for non-urgent broadcast.',
      v_actor_count, v_week_start
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._validate_gates_shape(p_gates jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    -- gates é jsonb array não-vazio
    jsonb_typeof(p_gates) = 'array'
    AND jsonb_array_length(p_gates) > 0
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_gates) g
      WHERE NOT (
        -- cada elemento é jsonb object
        jsonb_typeof(g) = 'object'
        -- required keys presentes
        AND g ? 'kind' AND g ? 'order' AND g ? 'threshold'
        -- kind é string no allowlist
        AND (g->>'kind') IN (
          'curator','leader','leader_awareness','submitter_acceptance',
          'chapter_witness','president_go','president_others',
          'volunteers_in_role_active','member_ratification','external_signer'
        )
        -- order é integer >= 1
        AND jsonb_typeof(g->'order') = 'number'
        AND (g->>'order')::int >= 1
        -- threshold é integer >= 0 OU string 'all'
        AND (
          (jsonb_typeof(g->'threshold') = 'number' AND (g->>'threshold')::int >= 0)
          OR (jsonb_typeof(g->'threshold') = 'string' AND g->>'threshold' = 'all')
        )
      )
    );
$function$
;

CREATE OR REPLACE FUNCTION public.record_ai_validation(p_application_id uuid, p_ai_purpose text, p_validation_action text, p_ai_score numeric DEFAULT NULL::numeric, p_ai_verdict text DEFAULT NULL::text, p_ai_model text DEFAULT NULL::text, p_override_score numeric DEFAULT NULL::numeric, p_comment text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_app record; v_committee record; v_id uuid;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RETURN jsonb_build_object('error', 'Application not found'); END IF;
  SELECT * INTO v_committee FROM public.selection_committee WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;
  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'view_pii'::text) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: not a committee member or admin');
  END IF;
  IF p_ai_purpose NOT IN ('sonnet_triage', 'gemini_qualitative') THEN RETURN jsonb_build_object('error', 'invalid ai_purpose'); END IF;
  IF p_validation_action NOT IN ('agree', 'disagree', 'override') THEN RETURN jsonb_build_object('error', 'invalid validation_action'); END IF;
  IF p_validation_action = 'override' AND p_ai_purpose <> 'sonnet_triage' THEN RETURN jsonb_build_object('error', 'override only valid for sonnet_triage'); END IF;
  IF p_validation_action = 'override' AND (p_override_score IS NULL OR p_override_score < 0 OR p_override_score > 10) THEN RETURN jsonb_build_object('error', 'override_score (0-10) required when action=override'); END IF;
  IF p_validation_action <> 'override' AND p_override_score IS NOT NULL THEN RETURN jsonb_build_object('error', 'override_score only allowed when action=override'); END IF;

  INSERT INTO public.ai_score_validations (application_id, validator_id, ai_purpose, ai_model, ai_score, ai_verdict, validation_action, override_score, comment, validated_at)
  VALUES (p_application_id, v_caller.id, p_ai_purpose, p_ai_model, p_ai_score, p_ai_verdict, p_validation_action, p_override_score, NULLIF(trim(COALESCE(p_comment, '')), ''), now())
  ON CONFLICT (application_id, validator_id, ai_purpose) DO UPDATE SET
    ai_model = EXCLUDED.ai_model, ai_score = EXCLUDED.ai_score, ai_verdict = EXCLUDED.ai_verdict,
    validation_action = EXCLUDED.validation_action, override_score = EXCLUDED.override_score,
    comment = EXCLUDED.comment, validated_at = now()
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'id', v_id, 'application_id', p_application_id, 'ai_purpose', p_ai_purpose, 'validation_action', p_validation_action, 'override_score', p_override_score, 'validated_at', now());
END; $function$
;

CREATE OR REPLACE FUNCTION public.record_member_activity(p_page text DEFAULT '/'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member_id uuid;
  v_today date := CURRENT_DATE;
BEGIN
  SELECT id INTO v_member_id
  FROM public.members
  WHERE auth_id = auth.uid() AND is_active = true;
  
  IF v_member_id IS NULL THEN RETURN; END IF;

  -- Update member's last_seen_at + rolling pages (last 5)
  UPDATE public.members SET
    last_seen_at = now(),
    last_active_pages = (
      SELECT array_agg(p) FROM (
        SELECT unnest(
          ARRAY[p_page] || COALESCE(last_active_pages, '{}')
        ) AS p LIMIT 5
      ) sub
    )
  WHERE id = v_member_id;

  -- Upsert daily session
  INSERT INTO public.member_activity_sessions (member_id, session_date, pages_visited, first_page, last_page)
  VALUES (v_member_id, v_today, 1, p_page, p_page)
  ON CONFLICT (member_id, session_date) DO UPDATE SET
    pages_visited = member_activity_sessions.pages_visited + 1,
    last_page = p_page,
    updated_at = now();

  -- Update total_sessions count
  UPDATE public.members SET
    total_sessions = (
      SELECT count(DISTINCT session_date) 
      FROM public.member_activity_sessions 
      WHERE member_id = v_member_id
    )
  WHERE id = v_member_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.record_offboarding_interview(p_member_id uuid, p_exit_interview_full_text text DEFAULT NULL::text, p_exit_interview_source text DEFAULT NULL::text, p_return_interest boolean DEFAULT NULL::boolean, p_return_window_suggestion text DEFAULT NULL::text, p_lessons_learned text DEFAULT NULL::text, p_recommendation_for_future text DEFAULT NULL::text, p_referred_by_tribe_leader boolean DEFAULT NULL::boolean, p_attachment_urls text[] DEFAULT NULL::text[], p_reason_category_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_record_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member action';
  END IF;

  IF p_exit_interview_source IS NOT NULL
     AND p_exit_interview_source NOT IN ('whatsapp','email','verbal','google_form','other') THEN
    RAISE EXCEPTION 'Invalid exit_interview_source: must be whatsapp|email|verbal|google_form|other';
  END IF;

  IF p_reason_category_code IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.offboard_reason_categories WHERE code = p_reason_category_code) THEN
    RAISE EXCEPTION 'Invalid reason_category_code: not in offboard_reason_categories';
  END IF;

  UPDATE public.member_offboarding_records SET
    exit_interview_full_text   = COALESCE(p_exit_interview_full_text, exit_interview_full_text),
    exit_interview_source      = COALESCE(p_exit_interview_source, exit_interview_source),
    return_interest            = COALESCE(p_return_interest, return_interest),
    return_window_suggestion   = COALESCE(p_return_window_suggestion, return_window_suggestion),
    lessons_learned            = COALESCE(p_lessons_learned, lessons_learned),
    recommendation_for_future  = COALESCE(p_recommendation_for_future, recommendation_for_future),
    referred_by_tribe_leader   = COALESCE(p_referred_by_tribe_leader, referred_by_tribe_leader),
    attachment_urls            = COALESCE(p_attachment_urls, attachment_urls),
    reason_category_code       = COALESCE(p_reason_category_code, reason_category_code),
    updated_at                 = now()
  WHERE member_id = p_member_id
  RETURNING id INTO v_record_id;

  IF v_record_id IS NULL THEN
    RAISE EXCEPTION 'Offboarding record not found for member_id %', p_member_id;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'offboarding.interview_updated', 'member', p_member_id,
    jsonb_build_object(
      'record_id', v_record_id,
      'fields_set', jsonb_build_object(
        'exit_interview_full_text', p_exit_interview_full_text IS NOT NULL,
        'exit_interview_source',    p_exit_interview_source IS NOT NULL,
        'return_interest',          p_return_interest IS NOT NULL,
        'return_window_suggestion', p_return_window_suggestion IS NOT NULL,
        'lessons_learned',          p_lessons_learned IS NOT NULL,
        'recommendation_for_future',p_recommendation_for_future IS NOT NULL,
        'referred_by_tribe_leader', p_referred_by_tribe_leader IS NOT NULL,
        'attachment_urls',          p_attachment_urls IS NOT NULL,
        'reason_category_code',     p_reason_category_code IS NOT NULL
      )
    ));

  RETURN jsonb_build_object('updated', true, 'record_id', v_record_id, 'member_id', p_member_id);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.register_card_drive_file(p_board_item_id uuid, p_drive_file_id text, p_drive_file_url text, p_filename text, p_mime_type text DEFAULT NULL::text, p_size_bytes bigint DEFAULT NULL::bigint, p_uploaded_via text DEFAULT 'platform'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_new_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF p_uploaded_via NOT IN ('platform', 'drive_native_synced') THEN
    RETURN jsonb_build_object('error', 'Invalid uploaded_via — must be platform or drive_native_synced');
  END IF;

  INSERT INTO public.board_item_files (
    board_item_id, drive_file_id, drive_file_url, filename, mime_type,
    size_bytes, uploaded_by, uploaded_via
  ) VALUES (
    p_board_item_id, p_drive_file_id, p_drive_file_url, p_filename,
    p_mime_type, p_size_bytes, v_caller_id, p_uploaded_via
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'success', true,
    'file_id', v_new_id,
    'drive_file_id', p_drive_file_id
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.register_decision(p_event_id uuid, p_title text, p_description text DEFAULT NULL::text, p_related_card_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action_id uuid;
  v_event record;
  v_full_text text;
  v_card_id uuid;
  v_links_created int := 0;
  v_card_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  SELECT id INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
    RETURN jsonb_build_object('error', 'title_required');
  END IF;

  v_full_text := trim(p_title) ||
    CASE WHEN p_description IS NOT NULL AND length(trim(p_description)) > 0
      THEN E'\n\n' || trim(p_description)
      ELSE ''
    END;

  -- Decision is an action item with kind='decision' (status auto='completed')
  INSERT INTO public.meeting_action_items (
    event_id, description, kind, status, created_by
  ) VALUES (
    p_event_id, v_full_text, 'decision', 'completed', v_caller_id
  )
  RETURNING id INTO v_action_id;

  -- Mark resolved with timestamp
  UPDATE public.meeting_action_items
  SET resolved_at = now(),
      resolved_by = v_caller_id,
      resolution_note = 'Decision registered',
      updated_at = now()
  WHERE id = v_action_id;

  -- Fanout: link decision to each related card via board_item_event_links
  IF p_related_card_ids IS NOT NULL AND array_length(p_related_card_ids, 1) > 0 THEN
    FOREACH v_card_id IN ARRAY p_related_card_ids
    LOOP
      SELECT organization_id INTO v_card_org FROM public.board_items WHERE id = v_card_id;
      IF v_card_org IS NOT NULL THEN
        INSERT INTO public.board_item_event_links (
          organization_id, board_item_id, event_id, link_type, author_id, note
        ) VALUES (
          v_card_org, v_card_id, p_event_id, 'decision', v_caller_id,
          'Decision: ' || trim(p_title)
        )
        ON CONFLICT (board_item_id, event_id, link_type) DO NOTHING;
        GET DIAGNOSTICS v_links_created = ROW_COUNT;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'decision_id', v_action_id,
    'event_id', p_event_id,
    'title', trim(p_title),
    'related_cards_linked', COALESCE(array_length(p_related_card_ids, 1), 0),
    'created_at', now()
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.request_to_join_initiative(p_initiative_id uuid, p_message text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_initiative record;
  v_default_kind text;
  v_invitation_id uuid;
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF length(p_message) < 50 THEN
    RAISE EXCEPTION 'Message must be at least 50 characters describing your motivation (current: %)', length(p_message)
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT i.* INTO v_initiative FROM public.initiatives i WHERE i.id = p_initiative_id;
  IF v_initiative.id IS NULL THEN
    RAISE EXCEPTION 'Initiative not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_initiative.status <> 'active' THEN
    RAISE EXCEPTION 'Initiative is not active' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_initiative.join_policy NOT IN ('request_to_join', 'open') THEN
    RAISE EXCEPTION 'Initiative does not accept self-service requests (join_policy=%)', v_initiative.join_policy
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Skip if already engaged
  IF EXISTS (
    SELECT 1 FROM public.engagements e
    WHERE e.person_id = v_caller_person_id
      AND e.initiative_id = p_initiative_id
      AND e.status = 'active'
  ) THEN
    RAISE EXCEPTION 'You already have an active engagement in this initiative'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Skip if pending invitation/request exists
  IF EXISTS (
    SELECT 1 FROM public.initiative_invitations
    WHERE invitee_member_id = v_caller_member_id
      AND initiative_id = p_initiative_id
      AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'You already have a pending invitation/request for this initiative'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Default kind by initiative kind
  v_default_kind := CASE v_initiative.kind
    WHEN 'study_group' THEN 'study_group_participant'
    WHEN 'workgroup' THEN 'workgroup_member'
    WHEN 'committee' THEN 'committee_member'
    WHEN 'research_tribe' THEN 'volunteer'
    ELSE 'observer'
  END;

  -- Insert as self-invitation: invitee == inviter == caller (Notion-style request)
  -- Owner sees this in list_invitations_for_my_initiatives (next slice) and approves/declines
  INSERT INTO public.initiative_invitations
    (initiative_id, invitee_member_id, inviter_member_id, kind_scope, message)
  VALUES
    (p_initiative_id, v_caller_member_id, v_caller_member_id, v_default_kind, p_message)
  RETURNING id INTO v_invitation_id;

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', v_invitation_id,
    'initiative_id', p_initiative_id,
    'kind_scope', v_default_kind,
    'expires_at', (now() + interval '72 hours'),
    'note', 'Owner of initiative will review your request. Watch for notification or call list_my_initiative_invitations.'
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.resolve_action_item(p_action_item_id uuid, p_resolution_note text DEFAULT NULL::text, p_carry_to_event_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action record;
  v_carried_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  SELECT * INTO v_action FROM public.meeting_action_items WHERE id = p_action_item_id;
  IF v_action.id IS NULL THEN
    RETURN jsonb_build_object('error', 'action_item_not_found');
  END IF;

  IF v_action.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'already_resolved',
      'resolved_at', v_action.resolved_at, 'resolved_by', v_action.resolved_by);
  END IF;

  -- Carry-forward: create new action_item in target event linked back to original
  IF p_carry_to_event_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.events WHERE id = p_carry_to_event_id) THEN
      RETURN jsonb_build_object('error', 'carry_to_event_not_found');
    END IF;

    INSERT INTO public.meeting_action_items (
      event_id, description, assignee_id, assignee_name, due_date,
      board_item_id, checklist_item_id, kind, status, created_by
    ) VALUES (
      p_carry_to_event_id,
      v_action.description || ' (carried from prior meeting)',
      v_action.assignee_id, v_action.assignee_name, v_action.due_date,
      v_action.board_item_id, v_action.checklist_item_id, v_action.kind,
      'open', v_caller_id
    )
    RETURNING id INTO v_carried_id;

    UPDATE public.meeting_action_items
    SET carried_to_event_id = p_carry_to_event_id, updated_at = now()
    WHERE id = p_action_item_id;
  END IF;

  -- Mark resolved
  UPDATE public.meeting_action_items
  SET resolved_at = now(),
      resolved_by = v_caller_id,
      resolution_note = COALESCE(p_resolution_note,
        CASE WHEN p_carry_to_event_id IS NOT NULL THEN 'Carried forward to event ' || p_carry_to_event_id::text ELSE NULL END),
      status = CASE WHEN p_carry_to_event_id IS NOT NULL THEN 'carried_forward' ELSE 'completed' END,
      updated_at = now()
  WHERE id = p_action_item_id;

  RETURN jsonb_build_object(
    'success', true,
    'action_item_id', p_action_item_id,
    'resolved_at', now(),
    'carried_to_action_item_id', v_carried_id
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.respond_re_engagement(p_pipeline_id uuid, p_response text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_pipeline record;
BEGIN
  IF p_response NOT IN ('accepted','declined') THEN
    RETURN jsonb_build_object('error','Invalid response: must be accepted or declined');
  END IF;

  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;

  SELECT * INTO v_pipeline FROM public.re_engagement_pipeline WHERE id = p_pipeline_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Pipeline entry not found'); END IF;

  -- Self-action only: caller must be the pipeline subject
  IF v_pipeline.member_id <> v_caller.id THEN
    RETURN jsonb_build_object('error','Unauthorized: only the invited member can respond');
  END IF;

  IF v_pipeline.state <> 'invited' THEN
    RETURN jsonb_build_object('error','Cannot respond from state: ' || v_pipeline.state::text);
  END IF;

  UPDATE public.re_engagement_pipeline SET
    state = p_response::public.re_engagement_state,
    responded_at = now(),
    response = p_response,
    response_note = p_note
  WHERE id = p_pipeline_id;

  -- Notify managers about response
  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id)
  SELECT mgr.id,
         CASE WHEN p_response = 'accepted' THEN 're_engagement_accepted' ELSE 're_engagement_declined' END,
         COALESCE(v_caller.name,'Alumni') || ' ' ||
           CASE WHEN p_response = 'accepted' THEN 'aceitou o convite de retorno' ELSE 'declinou o convite de retorno' END,
         COALESCE(p_note, NULL),
         '/admin/members/re-engagement',
         're_engagement_pipeline', p_pipeline_id
  FROM public.members mgr
  WHERE mgr.is_active = true AND mgr.operational_role IN ('manager','deputy_manager');

  -- Audit log
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 're_engagement.' || p_response, 're_engagement_pipeline', p_pipeline_id,
    jsonb_build_object('response', p_response, 'cycle_code', v_pipeline.cycle_code),
    jsonb_strip_nulls(jsonb_build_object('note_excerpt', LEFT(p_note, 200)))
  );

  RETURN jsonb_build_object('success', true, 'pipeline_id', p_pipeline_id, 'response', p_response);
END $function$
;

CREATE OR REPLACE FUNCTION public.respond_to_initiative_invitation(p_invitation_id uuid, p_response text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_invitation record;
  v_engagement_id uuid;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
BEGIN
  -- Validate caller
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Validate response value
  IF p_response NOT IN ('accept', 'decline') THEN
    RAISE EXCEPTION 'Response must be "accept" or "decline" (got: %)', p_response
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Validate invitation
  SELECT * INTO v_invitation FROM public.initiative_invitations WHERE id = p_invitation_id;
  IF v_invitation.id IS NULL THEN
    RAISE EXCEPTION 'Invitation not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_invitation.invitee_member_id <> v_caller_member_id THEN
    RAISE EXCEPTION 'Unauthorized: caller is not the invitee' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_invitation.status <> 'pending' THEN
    RAISE EXCEPTION 'Invitation is not pending (current status: %)', v_invitation.status
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_invitation.expires_at < now() THEN
    -- Auto-expire on read
    UPDATE public.initiative_invitations SET status = 'expired' WHERE id = p_invitation_id;
    RAISE EXCEPTION 'Invitation has expired' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Update invitation
  UPDATE public.initiative_invitations
  SET status = CASE WHEN p_response = 'accept' THEN 'accepted' ELSE 'declined' END,
      responded_at = now(),
      responded_note = p_note
  WHERE id = p_invitation_id;

  -- If accepted: create engagement
  IF p_response = 'accept' THEN
    INSERT INTO public.engagements
      (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
    VALUES (
      v_caller_person_id,
      v_invitation.initiative_id,
      v_invitation.kind_scope,
      'participant',  -- default role; kind_scope determines actual capabilities
      'active',
      'consent',
      v_invitation.inviter_member_id,
      jsonb_build_object(
        'source', 'invitation_accept',
        'invitation_id', p_invitation_id,
        'invited_by', v_invitation.inviter_member_id,
        'invited_at', v_invitation.created_at
      ),
      v_org_id
    )
    RETURNING id INTO v_engagement_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', p_invitation_id,
    'response', p_response,
    'engagement_id', v_engagement_id,
    'responded_at', now()
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.review_change_request(p_cr_id uuid, p_action text, p_notes text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_mid uuid; v_cr record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id=auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  v_mid := v_caller.id;
  SELECT * INTO v_cr FROM change_requests WHERE id=p_cr_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','CR not found'); END IF;
  -- p178 ADR-0011 inline V4 refactor: top-level authority via can_by_member(manage_platform).
  -- Covers superadmin + manager + deputy_manager + co_gp (per engagement_kind_permissions seed).
  -- Curator designation + sponsor/chapter_liaison legacy paths preserved as fallback; full V3→V4
  -- sweep of the change_requests action surface is deferred to a dedicated ADR-0011 batch session.
  IF NOT can_by_member(v_mid, 'manage_platform') THEN
    IF EXISTS (SELECT 1 FROM unnest(v_caller.designations) d WHERE d='curator') THEN
      IF v_cr.cr_type='structural' AND p_action='approve' THEN
        RETURN jsonb_build_object('error','Curators cannot approve structural CRs'); END IF;
    ELSIF v_caller.operational_role IN ('sponsor','chapter_liaison') THEN NULL;
    ELSE RETURN jsonb_build_object('error','Unauthorized'); END IF;
  END IF;
  IF p_action='approve' THEN
    UPDATE change_requests SET status='approved',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=COALESCE(p_notes,review_notes),
      approved_by_members=array_append(COALESCE(approved_by_members,'{}'),v_mid),
      approved_at=now(),updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action='reject' THEN
    UPDATE change_requests SET status='rejected',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=p_notes,updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action='request_changes' THEN
    UPDATE change_requests SET status='under_review',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=p_notes,updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action='implement' THEN
    IF v_cr.status!='approved' THEN RETURN jsonb_build_object('error','Must be approved first'); END IF;
    UPDATE change_requests SET status='implemented',implemented_by=v_mid,implemented_at=now(),
      manual_version_to='R3',updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action = 'withdraw' THEN
    IF v_cr.status NOT IN ('draft', 'submitted', 'under_review') THEN
      RETURN jsonb_build_object('error', 'Cannot withdraw approved/implemented CR'); END IF;
    UPDATE change_requests SET status = 'withdrawn', review_notes = COALESCE(p_notes, review_notes), updated_at = now() WHERE id = p_cr_id;
  ELSIF p_action = 'resubmit' THEN
    IF v_cr.status != 'under_review' THEN
      RETURN jsonb_build_object('error', 'Can only resubmit CRs under review'); END IF;
    UPDATE change_requests SET status = 'submitted', submitted_at = now(), review_notes = COALESCE(p_notes, review_notes), updated_at = now() WHERE id = p_cr_id;
  ELSE RETURN jsonb_build_object('error','Invalid action'); END IF;

  -- G7: Notify CR submitter about status change
  IF v_cr.submitted_by IS NOT NULL AND v_cr.submitted_by != v_mid THEN
    PERFORM create_notification(v_cr.submitted_by, 'cr_status_changed', 'change_request', p_cr_id, v_cr.title, v_mid);
  END IF;

  RETURN jsonb_build_object('success',true,'cr_number',v_cr.cr_number,'new_status',p_action);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.review_initiative_request(p_invitation_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_is_admin boolean;
  v_invitation record;
  v_is_owner boolean;
  v_engagement_id uuid;
  v_invitee_person_id uuid;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_decision NOT IN ('approve', 'decline') THEN
    RAISE EXCEPTION 'Decision must be "approve" or "decline" (got: %)', p_decision
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT * INTO v_invitation FROM public.initiative_invitations WHERE id = p_invitation_id;
  IF v_invitation.id IS NULL THEN
    RAISE EXCEPTION 'Invitation not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_invitation.status <> 'pending' THEN
    RAISE EXCEPTION 'Invitation not pending (status=%)', v_invitation.status
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_invitation.expires_at < now() THEN
    UPDATE public.initiative_invitations SET status = 'expired' WHERE id = p_invitation_id;
    RAISE EXCEPTION 'Invitation has expired' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Validate this is a self-service request (invitee == inviter)
  -- Owner-initiated invites use respond_to_initiative_invitation by invitee directly
  IF v_invitation.invitee_member_id <> v_invitation.inviter_member_id THEN
    RAISE EXCEPTION 'Not a self-service request — invitee should respond directly via respond_to_initiative_invitation'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Authority: caller must be admin OR owner/coordinator of initiative
  v_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');

  IF NOT v_is_admin THEN
    v_is_owner := EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = v_caller_person_id
        AND e.initiative_id = v_invitation.initiative_id
        AND e.status = 'active'
        AND (e.kind LIKE '%_owner' OR e.kind LIKE '%_coordinator' OR e.role IN ('owner','coordinator','lead'))
    );
    IF NOT v_is_owner THEN
      RAISE EXCEPTION 'Unauthorized: caller is not admin nor owner/coordinator of this initiative'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Update invitation with reviewed_by/reviewed_at + final status
  UPDATE public.initiative_invitations
  SET status = CASE WHEN p_decision = 'approve' THEN 'accepted' ELSE 'declined' END,
      reviewed_by = v_caller_member_id,
      reviewed_at = now(),
      reviewed_note = p_note,
      responded_at = now()  -- per accountability advisor: mark responded for audit
  WHERE id = p_invitation_id;

  -- On approve: create engagement
  IF p_decision = 'approve' THEN
    SELECT m.person_id INTO v_invitee_person_id
    FROM public.members m WHERE m.id = v_invitation.invitee_member_id;

    INSERT INTO public.engagements
      (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
    VALUES (
      v_invitee_person_id,
      v_invitation.initiative_id,
      v_invitation.kind_scope,
      'participant',
      'active',
      'consent',
      v_caller_member_id,  -- granted_by = approver (not requester)
      jsonb_build_object(
        'source', 'self_service_request_approved',
        'invitation_id', p_invitation_id,
        'reviewed_by', v_caller_member_id,
        'review_authority', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END,
        'requested_at', v_invitation.created_at
      ),
      v_org_id
    )
    RETURNING id INTO v_engagement_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', p_invitation_id,
    'decision', p_decision,
    'engagement_id', v_engagement_id,
    'reviewed_by', v_caller_member_id,
    'review_authority', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END,
    'reviewed_at', now()
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.revoke_consent_via_token(p_token text, p_consent_type text DEFAULT 'ai_analysis'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_app selection_applications%ROWTYPE;
BEGIN
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'consent_giving' = ANY(scopes);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing consent_giving scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type % does not support consent revocation', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;

  IF p_consent_type <> 'ai_analysis' THEN
    RAISE EXCEPTION 'Unsupported consent type: % (only ai_analysis is supported)', p_consent_type;
  END IF;

  -- Mark revocation timestamp; trigger trg_supersede_ai_suggestions_on_consent_revoke
  -- will auto-supersede any non-consumed AI suggestions for this application.
  UPDATE selection_applications
     SET consent_ai_analysis_revoked_at = COALESCE(consent_ai_analysis_revoked_at, now()),
         updated_at = now()
   WHERE id = v_application_id
  RETURNING * INTO v_app;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Token references missing application';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'consent_type', p_consent_type,
    'revoked_at', v_app.consent_ai_analysis_revoked_at,
    'has_consent', false,
    'has_revoked', true
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rls_can_for_initiative(p_action text, p_initiative_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
    WHERE ae.auth_id = auth.uid() AND ae.is_authoritative = true
      AND (ekp.scope IN ('organization', 'global')
           OR (ekp.scope = 'initiative' AND ae.initiative_id = p_initiative_id))
  );
$function$
;

CREATE OR REPLACE FUNCTION public.seed_member_engagement_by_role(p_person_id uuid, p_template_slug text, p_initiative_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_person_id uuid;
  v_caller_org uuid;
  v_target_org uuid;
  v_template engagement_seed_templates%ROWTYPE;
  v_engagement_spec jsonb;
  v_kind text;
  v_role text;
  v_scope text;
  v_target_initiative_id uuid;
  v_new_id uuid;
  v_created_ids uuid[] := ARRAY[]::uuid[];
  v_skipped_count int := 0;
  v_invalid_kinds_roles text[] := ARRAY[]::text[];
BEGIN
  SELECT id, person_id, organization_id INTO v_caller_id, v_caller_person_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'unauthorized', 'detail', 'requires manage_member');
  END IF;

  SELECT m.organization_id INTO v_target_org
  FROM public.members m WHERE m.person_id = p_person_id;
  IF v_target_org IS NULL THEN
    SELECT organization_id INTO v_target_org
    FROM public.persons WHERE id = p_person_id;
  END IF;
  IF v_target_org IS NULL THEN
    RETURN jsonb_build_object('error', 'person_not_found');
  END IF;
  IF v_target_org != v_caller_org THEN
    RETURN jsonb_build_object('error', 'person_not_in_caller_org');
  END IF;

  SELECT * INTO v_template
  FROM public.engagement_seed_templates t
  WHERE t.slug = p_template_slug
    AND t.active = true
    AND (t.organization_id = v_caller_org OR t.organization_id IS NULL)
  ORDER BY t.organization_id NULLS LAST
  LIMIT 1;

  IF v_template.id IS NULL THEN
    RETURN jsonb_build_object('error', 'template_not_found', 'detail', 'no active template with slug: ' || p_template_slug);
  END IF;

  FOR v_engagement_spec IN SELECT * FROM jsonb_array_elements(v_template.engagements)
  LOOP
    v_kind := v_engagement_spec->>'kind';
    v_role := v_engagement_spec->>'role';
    v_scope := v_engagement_spec->>'scope';

    IF v_scope = 'initiative' AND p_initiative_id IS NULL THEN
      RETURN jsonb_build_object(
        'error', 'initiative_id_required',
        'detail', format('template item kind=%s role=%s scope=initiative requires p_initiative_id', v_kind, v_role)
      );
    END IF;

    v_target_initiative_id := CASE
      WHEN v_scope = 'initiative' THEN p_initiative_id
      ELSE NULL
    END;

    IF NOT EXISTS (
      SELECT 1 FROM public.engagement_kind_permissions
      WHERE kind = v_kind AND role = v_role
    ) THEN
      v_invalid_kinds_roles := array_append(v_invalid_kinds_roles, v_kind || '/' || v_role);
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.engagements
      WHERE person_id = p_person_id
        AND kind = v_kind
        AND role = v_role
        AND status = 'active'
        AND (
          (v_target_initiative_id IS NULL AND initiative_id IS NULL)
          OR initiative_id = v_target_initiative_id
        )
    ) THEN
      v_skipped_count := v_skipped_count + 1;
      CONTINUE;
    END IF;

    -- p172 #5 fix: granted_by FK → persons(id), not members(id)
    INSERT INTO public.engagements (
      person_id, organization_id, initiative_id, kind, role, status,
      start_date, legal_basis, granted_by, metadata
    ) VALUES (
      p_person_id, v_caller_org, v_target_initiative_id,
      v_kind, v_role, 'active',
      CURRENT_DATE, 'contract_volunteer', v_caller_person_id,
      jsonb_build_object(
        'seeded_via', 'seed_member_engagement_by_role',
        'template_slug', p_template_slug,
        'template_id', v_template.id,
        'seeded_at', now()
      )
    ) RETURNING id INTO v_new_id;

    v_created_ids := array_append(v_created_ids, v_new_id);
  END LOOP;

  IF cardinality(v_invalid_kinds_roles) > 0 THEN
    RETURN jsonb_build_object(
      'error', 'invalid_template_items',
      'detail', 'kind/role combos sem permissions seeded: ' || array_to_string(v_invalid_kinds_roles, ', '),
      'engagements_created', cardinality(v_created_ids),
      'engagement_ids', to_jsonb(v_created_ids)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'template_slug', p_template_slug,
    'template_id', v_template.id,
    'engagements_created', cardinality(v_created_ids),
    'engagements_skipped', v_skipped_count,
    'engagement_ids', to_jsonb(v_created_ids)
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.seed_pre_onboarding_steps(p_application_id uuid, p_member_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count int := 0;
  v_steps text[] := ARRAY['create_account', 'setup_credly', 'explore_platform', 'read_blog', 'start_pmi_certs'];
  v_xp int[] := ARRAY[50, 75, 50, 50, 150];
  v_sla_days int[] := ARRAY[7, 14, 14, 14, 30];
  v_step text;
  v_i int;
BEGIN
  FOR v_i IN 1..array_length(v_steps, 1) LOOP
    v_step := v_steps[v_i];
    -- Skip if step already exists
    IF NOT EXISTS (
      SELECT 1 FROM onboarding_progress 
      WHERE application_id = p_application_id AND step_key = v_step
    ) THEN
      INSERT INTO onboarding_progress (application_id, member_id, step_key, status, sla_deadline, metadata)
      VALUES (
        p_application_id, 
        p_member_id, 
        v_step, 
        'pending', 
        now() + (v_sla_days[v_i] || ' days')::interval,
        jsonb_build_object('xp', v_xp[v_i], 'phase', 'pre_onboarding')
      );
      v_count := v_count + 1;
    END IF;
  END LOOP;
  
  RETURN json_build_object('seeded', v_count, 'application_id', p_application_id);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.set_my_gamification_visibility(p_opt_out boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_old_value boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT id, gamification_opt_out INTO v_caller_id, v_old_value
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF v_old_value = COALESCE(p_opt_out, false) THEN
    RETURN jsonb_build_object(
      'success', true,
      'member_id', v_caller_id,
      'opt_out', v_old_value,
      'changed', false,
      'updated_at', now()
    );
  END IF;

  UPDATE public.members
  SET gamification_opt_out = COALESCE(p_opt_out, false),
      updated_at = now()
  WHERE id = v_caller_id;

  RETURN jsonb_build_object(
    'success', true,
    'member_id', v_caller_id,
    'opt_out', COALESCE(p_opt_out, false),
    'changed', true,
    'previous_value', v_old_value,
    'updated_at', now()
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.set_my_muted_notification_types(p_muted_types text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;

  -- Upsert into notification_preferences
  INSERT INTO public.notification_preferences (member_id, muted_types, updated_at)
  VALUES (v_caller_id, COALESCE(p_muted_types, ARRAY[]::text[]), now())
  ON CONFLICT (member_id) DO UPDATE
    SET muted_types = COALESCE(EXCLUDED.muted_types, ARRAY[]::text[]),
        updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'muted_types', COALESCE(p_muted_types, ARRAY[]::text[])
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.stage_alumni_for_re_engagement(p_member_id uuid, p_cycle_code text, p_source text DEFAULT 'manual_admin'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_member record;
  v_record record;
  v_pipeline_id uuid;
BEGIN
  IF p_source NOT IN ('cron_new_cycle','manual_admin') THEN
    RETURN jsonb_build_object('error','Invalid source: ' || p_source);
  END IF;

  -- Cron path: skip auth (called via SECURITY DEFINER from cron)
  IF p_source <> 'cron_new_cycle' THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
    IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
      RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
    END IF;
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Member not found'); END IF;

  IF v_member.member_status <> 'alumni' THEN
    RETURN jsonb_build_object('error','Member is not alumni (status: ' || COALESCE(v_member.member_status,'NULL') || ')');
  END IF;

  IF v_member.anonymized_at IS NOT NULL THEN
    RETURN jsonb_build_object('error','Cannot stage anonymized member (LGPD Art. 16 II)');
  END IF;

  -- Snapshot return_interest from offboarding record
  SELECT return_interest, reason_category_code INTO v_record
  FROM public.member_offboarding_records
  WHERE member_id = p_member_id
  ORDER BY offboarded_at DESC LIMIT 1;

  -- Idempotent: if active pipeline exists for (member,cycle), return it
  SELECT id INTO v_pipeline_id
  FROM public.re_engagement_pipeline
  WHERE member_id = p_member_id AND cycle_code = p_cycle_code
    AND state IN ('staged','invited','accepted')
  LIMIT 1;

  IF v_pipeline_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'pipeline_id', v_pipeline_id, 'idempotent', true);
  END IF;

  INSERT INTO public.re_engagement_pipeline (
    member_id, cycle_code, state, staged_by, staged_source,
    return_interest_snapshot, reason_category_snapshot
  ) VALUES (
    p_member_id, p_cycle_code, 'staged',
    CASE WHEN p_source = 'cron_new_cycle' THEN NULL ELSE v_caller.id END,
    p_source,
    v_record.return_interest,
    v_record.reason_category_code
  )
  RETURNING id INTO v_pipeline_id;

  RETURN jsonb_build_object(
    'success', true,
    'pipeline_id', v_pipeline_id,
    'member_name', v_member.name,
    'return_interest', v_record.return_interest,
    'reason_category', v_record.reason_category_code
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.submit_evaluation(p_application_id uuid, p_evaluation_type text, p_scores jsonb, p_notes text DEFAULT NULL::text, p_criterion_notes jsonb DEFAULT NULL::jsonb, p_ai_suggestion_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_criteria jsonb;
  v_criterion jsonb;
  v_key text;
  v_score numeric;
  v_weight numeric;
  v_weighted_sum numeric := 0;
  v_eval_id uuid;
  v_total_evaluators int;
  v_submitted_count int;
  v_all_subtotals numeric[];
  v_pert_score numeric;
  v_min_sub numeric;
  v_max_sub numeric;
  v_avg_sub numeric;
  v_cutoff numeric;
  v_median numeric;
  v_new_status text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found'; END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;
  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluator_id = v_caller.id
      AND evaluation_type = p_evaluation_type
      AND submitted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Evaluation already submitted and locked';
  END IF;

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria)
  LOOP
    v_key := v_criterion ->> 'key';
    v_weight := COALESCE((v_criterion ->> 'weight')::numeric, 1);
    IF NOT (p_scores ? v_key) THEN RAISE EXCEPTION 'Missing score for criterion: %', v_key; END IF;
    v_score := (p_scores ->> v_key)::numeric;
    IF v_score IS NULL THEN RAISE EXCEPTION 'Score for % must be numeric', v_key; END IF;
    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, criterion_notes, submitted_at
  ) VALUES (
    p_application_id, v_caller.id, p_evaluation_type,
    p_scores, ROUND(v_weighted_sum, 2), p_notes,
    COALESCE(p_criterion_notes, '{}'::jsonb), now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    scores = EXCLUDED.scores,
    weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes,
    criterion_notes = EXCLUDED.criterion_notes,
    submitted_at = now()
  RETURNING id INTO v_eval_id;

  SELECT COUNT(*) INTO v_total_evaluators FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND role IN ('evaluator', 'lead');

  SELECT COUNT(*) INTO v_submitted_count FROM public.selection_evaluations
  WHERE application_id = p_application_id AND evaluation_type = p_evaluation_type AND submitted_at IS NOT NULL;

  IF v_submitted_count >= v_cycle.min_evaluators THEN
    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal) INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = p_application_id AND evaluation_type = p_evaluation_type AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);
    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    IF p_evaluation_type = 'objective' THEN
      UPDATE public.selection_applications SET objective_score_avg = v_pert_score, updated_at = now() WHERE id = p_application_id;
      SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY objective_score_avg) INTO v_median
      FROM public.selection_applications WHERE cycle_id = v_app.cycle_id AND objective_score_avg IS NOT NULL;
      v_cutoff := ROUND(COALESCE(v_median, 0) * 0.75, 2);
      IF v_pert_score < v_cutoff AND v_cutoff > 0 THEN v_new_status := 'objective_cutoff'; ELSE v_new_status := 'interview_pending'; END IF;
      UPDATE public.selection_applications SET status = v_new_status, updated_at = now()
      WHERE id = p_application_id AND status IN ('submitted', 'screening', 'objective_eval');
    ELSIF p_evaluation_type = 'interview' THEN
      UPDATE public.selection_applications SET interview_score = v_pert_score, final_score = COALESCE(objective_score_avg, 0) + v_pert_score, status = 'final_eval', updated_at = now() WHERE id = p_application_id;
    ELSIF p_evaluation_type = 'leader_extra' THEN
      UPDATE public.selection_applications SET objective_score_avg = COALESCE(objective_score_avg, 0) + v_pert_score, final_score = COALESCE(objective_score_avg, 0) + v_pert_score + COALESCE(interview_score, 0), updated_at = now() WHERE id = p_application_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'evaluation_id', v_eval_id, 'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_submitted', v_submitted_count >= v_cycle.min_evaluators,
    'pert_score', v_pert_score, 'new_status', v_new_status
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.sync_initiative_from_tribe()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.tribe_id IS NOT NULL AND NEW.initiative_id IS NULL THEN
    SELECT id INTO NEW.initiative_id
    FROM public.initiatives
    WHERE legacy_tribe_id = NEW.tribe_id;
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.sync_member_status_consistency()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.member_status = 'active' AND NEW.is_active = false THEN NEW.is_active := true; END IF;
  IF NEW.member_status IN ('observer','alumni','inactive') AND NEW.is_active = true THEN NEW.is_active := false; END IF;
  IF NEW.member_status = 'alumni' AND NEW.operational_role IS DISTINCT FROM 'alumni' THEN NEW.operational_role := 'alumni'; END IF;
  IF NEW.member_status = 'observer' AND NEW.operational_role NOT IN ('observer','guest','none') THEN NEW.operational_role := 'observer'; END IF;
  IF NEW.member_status IN ('observer','alumni','inactive') AND NEW.designations IS NOT NULL AND array_length(NEW.designations, 1) > 0 THEN NEW.designations := '{}'::text[]; END IF;
  RETURN NEW;
END; $function$
;

CREATE OR REPLACE FUNCTION public.sync_tribe_from_initiative()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.initiative_id IS NOT NULL AND NEW.tribe_id IS NULL THEN
    SELECT legacy_tribe_id INTO NEW.tribe_id
    FROM public.initiatives
    WHERE id = NEW.initiative_id;
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_approval_signoff_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RAISE EXCEPTION 'approval_signoffs is append-only (id=%). UPDATE blocked.', OLD.id
    USING ERRCODE = 'check_violation';
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_approval_signoff_notify_fn()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chain record;
  v_gate jsonb;
  v_signed_count int;
  v_eligible_count int;
  v_threshold_num int;
  v_threshold_text text;
  v_gate_satisfied boolean := false;
  v_all_satisfied_after boolean := false;
  v_remaining_unsatisfied int;
BEGIN
  IF NEW.signoff_type NOT IN ('approval','acknowledge') THEN
    RETURN NEW;
  END IF;

  SELECT ac.id, ac.status, ac.gates INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = NEW.approval_chain_id;
  IF v_chain.id IS NULL THEN RETURN NEW; END IF;

  SELECT g INTO v_gate
  FROM jsonb_array_elements(v_chain.gates) g
  WHERE g->>'kind' = NEW.gate_kind LIMIT 1;
  IF v_gate IS NULL THEN RETURN NEW; END IF;

  v_threshold_text := v_gate->>'threshold';

  SELECT COUNT(*) INTO v_signed_count
  FROM public.approval_signoffs s
  WHERE s.approval_chain_id = NEW.approval_chain_id
    AND s.gate_kind = NEW.gate_kind
    AND s.signoff_type IN ('approval','acknowledge');

  IF v_threshold_text ~ '^[0-9]+$' THEN
    v_threshold_num := v_threshold_text::int;
    IF v_threshold_num = 0 THEN
      v_gate_satisfied := (v_signed_count = 1);
    ELSE
      v_gate_satisfied := (v_signed_count = v_threshold_num);
    END IF;
  ELSIF v_threshold_text = 'all' THEN
    -- ADR-0016 Amendment 2: dynamic live-query — signoffs approved vs current eligibles
    SELECT COUNT(*) INTO v_eligible_count
    FROM public.members m
    WHERE m.is_active = true
      AND public._can_sign_gate(m.id, NEW.approval_chain_id, NEW.gate_kind);
    v_gate_satisfied := (v_signed_count >= v_eligible_count);
  END IF;

  SELECT COUNT(*) INTO v_remaining_unsatisfied
  FROM jsonb_array_elements(v_chain.gates) g
  WHERE
    -- "all" dynamic: signoffs < current eligibles
    ((g->>'threshold') = 'all'
      AND (SELECT COUNT(*) FROM public.approval_signoffs s
           WHERE s.approval_chain_id = NEW.approval_chain_id
             AND s.gate_kind = (g->>'kind')
             AND s.signoff_type IN ('approval','acknowledge'))
         < (SELECT COUNT(*) FROM public.members m
            WHERE m.is_active = true
              AND public._can_sign_gate(m.id, NEW.approval_chain_id, g->>'kind')))
    OR
    -- numeric threshold > 0: signoffs < N
    ((g->>'threshold') ~ '^[0-9]+$'
      AND (g->>'threshold')::int > 0
      AND (SELECT COUNT(*) FROM public.approval_signoffs s
           WHERE s.approval_chain_id = NEW.approval_chain_id
             AND s.gate_kind = (g->>'kind')
             AND s.signoff_type IN ('approval','acknowledge')) < (g->>'threshold')::int)
    OR
    -- threshold=0 (informative): requires at least 1 signoff
    ((g->>'threshold') = '0'
      AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
                     WHERE s.approval_chain_id = NEW.approval_chain_id
                       AND s.gate_kind = (g->>'kind')
                       AND s.signoff_type IN ('approval','acknowledge')));

  v_all_satisfied_after := (v_remaining_unsatisfied = 0);

  IF v_all_satisfied_after AND v_gate_satisfied THEN
    PERFORM public._enqueue_gate_notifications(NEW.approval_chain_id, 'chain_approved', NEW.gate_kind);
  ELSIF v_gate_satisfied THEN
    PERFORM public._enqueue_gate_notifications(NEW.approval_chain_id, 'gate_advanced', NEW.gate_kind);
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_artia_sync_govdoc_ratified()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_service_key TEXT;
BEGIN
  -- Only fire when current_ratified_at changes (NULL → timestamp = ratification event)
  IF (OLD.current_ratified_at IS DISTINCT FROM NEW.current_ratified_at) THEN
    BEGIN
      SELECT decrypted_secret INTO v_service_key 
      FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

      PERFORM net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/sync-artia?mode=cron-daily',
        body := jsonb_build_object('source', 'trigger_govdoc', 'doc_id', NEW.id, 'event', 'ratified'),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_key
        ),
        timeout_milliseconds := 30000
      );
    EXCEPTION WHEN OTHERS THEN
      -- Don't break the original UPDATE if Artia trigger fails
      RAISE NOTICE 'Artia sync trigger failed: %', SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_document_comment_enforce_edit_window()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_is_admin boolean := false;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.body IS DISTINCT FROM OLD.body THEN
    SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();

    IF v_caller_member_id IS NOT NULL THEN
      v_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');
    END IF;

    IF NOT v_is_admin AND (now() - OLD.created_at) > interval '15 minutes' THEN
      RAISE EXCEPTION 'Edit window expired: comments can only be edited within 15 minutes of posting (comment_id=%, age=%)',
        OLD.id, now() - OLD.created_at
        USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO public.document_comment_edits (comment_id, edited_by, previous_body, new_body)
    VALUES (OLD.id, COALESCE(v_caller_member_id, OLD.author_id), OLD.body, NEW.body);
  END IF;

  NEW.updated_at = now();
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_document_version_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_id uuid;
  v_doc_info jsonb;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();

  SELECT jsonb_build_object(
    'document_id', gd.id,
    'document_title', gd.title,
    'doc_type', gd.doc_type
  ) INTO v_doc_info
  FROM public.governance_documents gd
  WHERE gd.id = NEW.document_id;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
    VALUES (
      COALESCE(v_actor_id, NEW.authored_by),
      'document_version.created',
      'document_version',
      NEW.id,
      v_doc_info || jsonb_build_object(
        'version_number', NEW.version_number,
        'version_label', NEW.version_label,
        'authored_at', NEW.authored_at
      )
    );
    RETURN NEW;
  END IF;

  IF OLD.published_at IS NULL AND NEW.published_at IS NOT NULL THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
    VALUES (
      COALESCE(v_actor_id, NEW.published_by),
      'document_version.published',
      'document_version',
      NEW.id,
      v_doc_info || jsonb_build_object(
        'version_number', NEW.version_number,
        'published_at', NEW.published_at
      )
    );
  END IF;

  IF OLD.locked_at IS NULL AND NEW.locked_at IS NOT NULL THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
    VALUES (
      COALESCE(v_actor_id, NEW.locked_by),
      'document_version.locked',
      'document_version',
      NEW.id,
      v_doc_info || jsonb_build_object(
        'version_number', NEW.version_number,
        'locked_at', NEW.locked_at
      )
    );
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_sync_current_version_on_publish()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.locked_at IS NOT NULL AND (OLD.locked_at IS NULL OR TG_OP = 'INSERT') THEN
    UPDATE public.governance_documents SET current_version_id = NEW.id, updated_at = now()
      WHERE id = NEW.document_id;
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.unlink_partner_from_card(p_partner_entity_id uuid, p_board_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_deleted_id uuid;
BEGIN
  SELECT m.id, m.name INTO v_member
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_partner') THEN
    RAISE EXCEPTION 'Access denied: manage_partner required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  DELETE FROM public.partner_cards
  WHERE partner_entity_id = p_partner_entity_id AND board_item_id = p_board_item_id
  RETURNING id INTO v_deleted_id;

  IF v_deleted_id IS NOT NULL THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (
      v_member.id, 'partner_card.unlinked', 'partner_card', v_deleted_id,
      jsonb_build_object('partner_entity_id', p_partner_entity_id, 'board_item_id', p_board_item_id)
    );
  END IF;

  RETURN jsonb_build_object('success', (v_deleted_id IS NOT NULL), 'deleted_id', v_deleted_id);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_card_comment(p_comment_id uuid, p_new_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_comment record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_comment FROM public.board_item_comments WHERE id = p_comment_id;
  IF v_comment.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Comment not found');
  END IF;

  -- Only author can edit own comment
  IF v_comment.author_id != v_caller_id THEN
    RETURN jsonb_build_object('error', 'Only author can edit own comment');
  END IF;

  IF v_comment.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Cannot edit deleted comment');
  END IF;

  IF coalesce(trim(p_new_body), '') = '' THEN
    RETURN jsonb_build_object('error', 'Body required');
  END IF;

  UPDATE public.board_item_comments
  SET body = p_new_body, edited_at = now(), updated_at = now()
  WHERE id = p_comment_id;

  RETURN jsonb_build_object('success', true, 'comment_id', p_comment_id);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_card_during_meeting(p_card_id uuid, p_event_id uuid, p_new_status text DEFAULT NULL::text, p_fields jsonb DEFAULT NULL::jsonb, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_card record;
  v_event record;
  v_old_status text;
  v_status_changed boolean := false;
  v_fields_applied boolean := false;
  v_link_type text;
  v_link_note text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'write_board') THEN
    RAISE EXCEPTION 'Requires write_board permission';
  END IF;

  SELECT id, status, organization_id, title INTO v_card
  FROM public.board_items WHERE id = p_card_id;
  IF v_card.id IS NULL THEN
    RETURN jsonb_build_object('error', 'card_not_found');
  END IF;
  v_old_status := v_card.status;

  SELECT id, title, initiative_id INTO v_event
  FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  IF p_new_status IS NOT NULL AND p_new_status <> v_old_status THEN
    PERFORM public.move_board_item(
      p_card_id,
      p_new_status,
      NULL,
      COALESCE(p_note, 'Updated during meeting ' || COALESCE(v_event.title, p_event_id::text))
    );
    v_status_changed := true;
  END IF;

  IF p_fields IS NOT NULL AND p_fields <> '{}'::jsonb THEN
    PERFORM public.update_board_item(p_card_id, p_fields);
    v_fields_applied := true;
  END IF;

  v_link_type := CASE WHEN v_status_changed THEN 'status_changed' ELSE 'discussed' END;

  v_link_note := COALESCE(
    p_note,
    CASE
      WHEN v_status_changed AND v_fields_applied
        THEN 'Status: ' || v_old_status || ' → ' || p_new_status || ' (and fields updated)'
      WHEN v_status_changed
        THEN 'Status: ' || v_old_status || ' → ' || p_new_status
      WHEN v_fields_applied
        THEN 'Card fields updated during meeting'
      ELSE 'Discussed during meeting'
    END
  );

  INSERT INTO public.board_item_event_links (
    organization_id, board_item_id, event_id, link_type, author_id, note
  ) VALUES (
    v_card.organization_id, p_card_id, p_event_id, v_link_type, v_caller_id, v_link_note
  )
  ON CONFLICT (board_item_id, event_id, link_type) DO UPDATE
    SET note = EXCLUDED.note;

  RETURN jsonb_build_object(
    'success', true,
    'card_id', p_card_id,
    'event_id', p_event_id,
    'old_status', v_old_status,
    'new_status', CASE WHEN v_status_changed THEN p_new_status ELSE v_old_status END,
    'status_changed', v_status_changed,
    'fields_applied', v_fields_applied,
    'link_type', v_link_type,
    'updated_at', now()
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_checklist_item(p_checklist_item_id uuid, p_text text DEFAULT NULL::text, p_position smallint DEFAULT NULL::smallint, p_target_date date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_item record;
  v_card record;
  v_board record;
  v_authorized boolean;
  v_old_text text;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  SELECT * INTO v_item FROM board_item_checklists WHERE id = p_checklist_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Checklist item not found'; END IF;

  SELECT * INTO v_card FROM board_items WHERE id = v_item.board_item_id;
  SELECT * INTO v_board FROM project_boards WHERE id = v_card.board_id;

  v_authorized := public.can_by_member(v_caller_id, 'write_board')
    OR v_card.assignee_id = v_caller_id
    OR EXISTS (
      SELECT 1 FROM board_members bm
      WHERE bm.board_id = v_board.id AND bm.member_id = v_caller_id
      AND bm.board_role IN ('admin', 'editor')
    );

  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership, or board editor role';
  END IF;

  IF p_text IS NOT NULL AND trim(p_text) = '' THEN
    RAISE EXCEPTION 'Text cannot be empty. Use delete_checklist_item to remove.';
  END IF;

  v_old_text := v_item.text;

  UPDATE board_item_checklists
  SET
    text = COALESCE(p_text, text),
    position = COALESCE(p_position, position),
    target_date = CASE WHEN p_target_date IS NOT NULL THEN p_target_date ELSE target_date END
  WHERE id = p_checklist_item_id;

  IF p_text IS NOT NULL AND p_text IS DISTINCT FROM v_old_text THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
    VALUES (v_card.board_id, v_card.id, 'activity_updated',
      v_old_text || ' → ' || p_text, v_caller_id);
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_future_events_in_group(p_event_id uuid, p_new_time_start time without time zone DEFAULT NULL::time without time zone, p_duration_minutes integer DEFAULT NULL::integer, p_meeting_link text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_visibility text DEFAULT NULL::text, p_type text DEFAULT NULL::text, p_nature text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_date date;
  v_rec_group uuid;
  v_updated_count int;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT i.legacy_tribe_id, e.date, e.recurrence_group
    INTO v_event_tribe, v_event_date, v_rec_group
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;
  IF v_rec_group IS NULL THEN RAISE EXCEPTION 'Event is not part of a recurring series'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  IF p_type IS NOT NULL AND p_type NOT IN ('geral','tribo','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar') THEN
    RAISE EXCEPTION 'Invalid event type: %', p_type;
  END IF;
  IF p_nature IS NOT NULL AND p_nature NOT IN ('kickoff','recorrente','avulsa','encerramento','workshop','entrevista_selecao') THEN
    RAISE EXCEPTION 'Invalid event nature: %', p_nature;
  END IF;

  WITH updated AS (
    UPDATE public.events SET
      time_start = COALESCE(p_new_time_start, time_start),
      duration_minutes = COALESCE(p_duration_minutes, duration_minutes),
      meeting_link = COALESCE(p_meeting_link, meeting_link),
      notes = COALESCE(p_notes, notes),
      visibility = COALESCE(p_visibility, visibility),
      type = COALESCE(p_type, type),
      nature = COALESCE(p_nature, nature),
      updated_at = now()
    WHERE recurrence_group = v_rec_group AND date >= v_event_date
    RETURNING id
  )
  SELECT count(*) INTO v_updated_count FROM updated;

  RETURN json_build_object('success', true, 'recurrence_group', v_rec_group, 'anchor_date', v_event_date, 'updated_count', v_updated_count);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_initiative(p_initiative_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_metadata jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_initiative record;
  v_kind_row record;
BEGIN
  SELECT * INTO v_initiative FROM public.initiatives WHERE id = p_initiative_id;
  IF v_initiative IS NULL THEN
    RAISE EXCEPTION 'Initiative not found: %', p_initiative_id USING ERRCODE = 'P0002';
  END IF;

  IF p_status IS NOT NULL THEN
    SELECT * INTO v_kind_row FROM public.initiative_kinds WHERE slug = v_initiative.kind;
    IF NOT (p_status = ANY(v_kind_row.lifecycle_states)) THEN
      RAISE EXCEPTION 'Invalid status "%" for kind "%". Allowed: %',
        p_status, v_initiative.kind, v_kind_row.lifecycle_states USING ERRCODE = 'P0006';
    END IF;
  END IF;

  UPDATE public.initiatives SET
    title = COALESCE(p_title, title),
    description = COALESCE(p_description, description),
    status = COALESCE(p_status, status),
    metadata = COALESCE(p_metadata, metadata),
    updated_at = now()
  WHERE id = p_initiative_id;

  RETURN jsonb_build_object('id', p_initiative_id, 'updated', true);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_my_application(p_fields jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app_id uuid;
  v_status text;
  v_phase text;
  v_allowed_keys text[] := ARRAY[
    'linkedin_url','resume_url','motivation_letter','areas_of_interest',
    'leadership_experience','academic_background','non_pmi_experience',
    'availability_declared','proposed_theme','credly_url',
    'linkedin_relevant_posts','reason_for_applying','phone'
  ];
  v_filtered jsonb := '{}'::jsonb;
  v_key text;
  v_updated_keys text[] := '{}';
BEGIN
  SELECT id, email, name INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_fields IS NULL OR jsonb_typeof(p_fields) <> 'object' THEN
    RAISE EXCEPTION 'p_fields must be a jsonb object';
  END IF;

  -- Filter to allowed keys only
  FOR v_key IN SELECT jsonb_object_keys(p_fields)
  LOOP
    IF v_key = ANY(v_allowed_keys) THEN
      v_filtered := v_filtered || jsonb_build_object(v_key, p_fields -> v_key);
      v_updated_keys := array_append(v_updated_keys, v_key);
    END IF;
  END LOOP;

  IF jsonb_typeof(v_filtered) = 'object' AND v_filtered = '{}'::jsonb THEN
    RAISE EXCEPTION 'No allowed fields in p_fields. Allowed: %', array_to_string(v_allowed_keys, ', ');
  END IF;

  -- Find candidate's most recent non-terminal application
  SELECT a.id, a.status, sc.phase INTO v_app_id, v_status, v_phase
  FROM public.selection_applications a
  JOIN public.selection_cycles sc ON sc.id = a.cycle_id
  WHERE lower(trim(a.email)) = lower(trim(v_caller.email))
    AND a.status NOT IN ('approved','converted','rejected','objective_cutoff','withdrawn','cancelled')
  ORDER BY a.created_at DESC
  LIMIT 1;

  IF v_app_id IS NULL THEN
    RAISE EXCEPTION 'No active application found for %', v_caller.email;
  END IF;

  -- Block edits during evaluation phases (avoid candidato editing while being evaluated)
  IF v_phase IN ('evaluating','interviews','ranking') THEN
    RAISE EXCEPTION 'Cannot edit application during phase %: contact comitê if needed', v_phase;
  END IF;

  -- Apply patch — use jsonb_populate_record-like pattern via dynamic UPDATE
  UPDATE public.selection_applications a SET
    linkedin_url        = COALESCE((v_filtered->>'linkedin_url'), linkedin_url),
    resume_url          = COALESCE((v_filtered->>'resume_url'), resume_url),
    motivation_letter   = COALESCE((v_filtered->>'motivation_letter'), motivation_letter),
    areas_of_interest   = COALESCE((v_filtered->>'areas_of_interest'), areas_of_interest),
    leadership_experience = COALESCE((v_filtered->>'leadership_experience'), leadership_experience),
    academic_background = COALESCE((v_filtered->>'academic_background'), academic_background),
    non_pmi_experience  = COALESCE((v_filtered->>'non_pmi_experience'), non_pmi_experience),
    availability_declared = COALESCE((v_filtered->>'availability_declared'), availability_declared),
    proposed_theme      = COALESCE((v_filtered->>'proposed_theme'), proposed_theme),
    credly_url          = COALESCE((v_filtered->>'credly_url'), credly_url),
    reason_for_applying = COALESCE((v_filtered->>'reason_for_applying'), reason_for_applying),
    phone               = COALESCE((v_filtered->>'phone'), phone),
    linkedin_relevant_posts = CASE
      WHEN v_filtered ? 'linkedin_relevant_posts'
      THEN (SELECT array_agg(value::text) FROM jsonb_array_elements_text(v_filtered->'linkedin_relevant_posts'))
      ELSE linkedin_relevant_posts
    END,
    updated_at = now()
  WHERE a.id = v_app_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 'update_my_application', 'selection_application', v_app_id,
    jsonb_build_object('updated_keys', to_jsonb(v_updated_keys)),
    jsonb_build_object('source','mcp','issue','#87','phase_at_edit', v_phase)
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_app_id,
    'updated_fields', to_jsonb(v_updated_keys)
  );
END; $function$
;

CREATE OR REPLACE FUNCTION public.update_notification_preferences(p_prefs jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  INSERT INTO notification_preferences (member_id, enabled, muted_types, email_digest, digest_frequency, updated_at)
  VALUES (v_member_id, COALESCE((p_prefs->>'enabled')::boolean, true),
    COALESCE(ARRAY(SELECT jsonb_array_elements_text(p_prefs->'muted_types')), '{}'),
    COALESCE((p_prefs->>'email_digest')::boolean, true),
    COALESCE(p_prefs->>'digest_frequency', 'weekly'), now())
  ON CONFLICT (member_id) DO UPDATE SET
    enabled = COALESCE((p_prefs->>'enabled')::boolean, notification_preferences.enabled),
    muted_types = COALESCE(ARRAY(SELECT jsonb_array_elements_text(p_prefs->'muted_types')), notification_preferences.muted_types),
    email_digest = COALESCE((p_prefs->>'email_digest')::boolean, notification_preferences.email_digest),
    digest_frequency = COALESCE(p_prefs->>'digest_frequency', notification_preferences.digest_frequency),
    updated_at = now();
  RETURN jsonb_build_object('success', true);
END; $function$
;

CREATE OR REPLACE FUNCTION public.update_organization(p_name text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_website_url text DEFAULT NULL::text, p_logo_url text DEFAULT NULL::text, p_host_chapter text DEFAULT NULL::text, p_primary_language text DEFAULT NULL::text, p_country text DEFAULT NULL::text, p_federated_chapters text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_org_id uuid;
  v_changes jsonb := '{}'::jsonb;
BEGIN
  -- Gate: manage_platform
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform');
  END IF;

  v_org_id := public.auth_org();
  IF v_org_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No organization scope');
  END IF;

  -- Validate primary_language if provided
  IF p_primary_language IS NOT NULL AND p_primary_language NOT IN ('pt-BR','en-US','es-LATAM') THEN
    RETURN jsonb_build_object('error', 'Invalid primary_language: must be pt-BR | en-US | es-LATAM');
  END IF;

  UPDATE public.organizations
  SET name               = COALESCE(p_name, name),
      description        = COALESCE(p_description, description),
      website_url        = COALESCE(p_website_url, website_url),
      logo_url           = COALESCE(p_logo_url, logo_url),
      host_chapter       = COALESCE(p_host_chapter, host_chapter),
      primary_language   = COALESCE(p_primary_language, primary_language),
      country            = COALESCE(p_country, country),
      federated_chapters = COALESCE(p_federated_chapters, federated_chapters),
      updated_at         = now()
  WHERE id = v_org_id;

  -- Audit
  v_changes := jsonb_build_object(
    'name', p_name, 'description', p_description, 'website_url', p_website_url,
    'logo_url', p_logo_url, 'host_chapter', p_host_chapter,
    'primary_language', p_primary_language, 'country', p_country,
    'federated_chapters', p_federated_chapters
  );

  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'organization_updated', 'info',
    'Organization ' || v_org_id::text || ' updated by member ' || v_caller_id::text,
    jsonb_build_object('organization_id', v_org_id, 'caller_id', v_caller_id, 'changes', v_changes)
  );

  RETURN jsonb_build_object('ok', true, 'organization_id', v_org_id);
END;
$function$
;

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

  -- Note: R8 wrapper does NOT auto-activate member or update application.status —
  -- those side-effects happen via the authenticated update_onboarding_step path
  -- when staff confirms. PMI candidate via token only marks their own steps.

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

CREATE OR REPLACE FUNCTION public.upsert_document_version(p_document_id uuid, p_content_html text, p_content_markdown text DEFAULT NULL::text, p_version_label text DEFAULT NULL::text, p_version_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_version record;
  v_version_id uuid;
  v_version_number int;
  v_version_label text;
  v_doc record;
BEGIN
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT gd.id, gd.title INTO v_doc FROM public.governance_documents gd WHERE gd.id = p_document_id;
  IF v_doc.id IS NULL THEN
    RAISE EXCEPTION 'governance_document not found (id=%)', p_document_id USING ERRCODE = 'no_data_found';
  END IF;

  IF length(coalesce(p_content_html,'')) = 0 THEN
    RAISE EXCEPTION 'content_html cannot be empty' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF p_version_id IS NOT NULL THEN
    SELECT dv.id, dv.document_id, dv.version_number, dv.version_label, dv.locked_at, dv.authored_by
    INTO v_version
    FROM public.document_versions dv WHERE dv.id = p_version_id;

    IF v_version.id IS NULL THEN
      RAISE EXCEPTION 'document_version not found (id=%)', p_version_id USING ERRCODE = 'no_data_found';
    END IF;
    IF v_version.document_id <> p_document_id THEN
      RAISE EXCEPTION 'document_version % does not belong to document %', p_version_id, p_document_id
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF v_version.locked_at IS NOT NULL THEN
      RAISE EXCEPTION 'document_version % is locked at % — immutable', p_version_id, v_version.locked_at
        USING ERRCODE = 'check_violation';
    END IF;

    UPDATE public.document_versions
      SET content_html = p_content_html,
          content_markdown = coalesce(p_content_markdown, content_markdown),
          version_label = coalesce(p_version_label, version_label),
          notes = coalesce(p_notes, notes),
          updated_at = now()
      WHERE id = p_version_id;

    v_version_id := p_version_id;
    v_version_number := v_version.version_number;
    v_version_label := coalesce(p_version_label, v_version.version_label);
  ELSE
    SELECT COALESCE(MAX(version_number), 0) + 1
    INTO v_version_number
    FROM public.document_versions WHERE document_id = p_document_id;

    v_version_label := coalesce(p_version_label, 'Rascunho v' || v_version_number::text);

    INSERT INTO public.document_versions (
      document_id, version_number, version_label, content_html, content_markdown,
      authored_by, authored_at, notes
    ) VALUES (
      p_document_id, v_version_number, v_version_label, p_content_html, p_content_markdown,
      v_member.id, now(), p_notes
    ) RETURNING id INTO v_version_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'version_id', v_version_id,
    'document_id', p_document_id,
    'version_number', v_version_number,
    'version_label', v_version_label,
    'authored_by', v_member.id,
    'updated_at', now()
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.v4_expire_engagements()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_suspended int := 0;
  v_offboarded int := 0;
  v_notified int := 0;
  v_details jsonb := '[]'::jsonb;
  v_engagement record;
BEGIN
  FOR v_engagement IN
    SELECT
      e.id AS engagement_id, e.person_id, p.name AS person_name,
      e.kind, e.role, e.end_date, ek.auto_expire_behavior, ek.renewable,
      i.title AS initiative_title
    FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.status = 'active' AND e.end_date IS NOT NULL AND e.end_date < CURRENT_DATE
  LOOP
    CASE v_engagement.auto_expire_behavior
      WHEN 'suspend' THEN
        UPDATE public.engagements SET status = 'suspended', updated_at = now()
        WHERE id = v_engagement.engagement_id;
        v_suspended := v_suspended + 1;
      WHEN 'offboard' THEN
        UPDATE public.engagements SET status = 'offboarded', updated_at = now()
        WHERE id = v_engagement.engagement_id;
        v_offboarded := v_offboarded + 1;
      WHEN 'notify_only' THEN
        v_notified := v_notified + 1;
    END CASE;

    v_details := v_details || jsonb_build_object(
      'engagement_id', v_engagement.engagement_id, 'person_name', v_engagement.person_name,
      'kind', v_engagement.kind, 'role', v_engagement.role, 'end_date', v_engagement.end_date,
      'action', v_engagement.auto_expire_behavior, 'renewable', v_engagement.renewable
    );
  END LOOP;

  IF (v_suspended + v_offboarded + v_notified) > 0 THEN
    INSERT INTO public.admin_audit_log (action, actor_id, target_type, metadata)
    VALUES ('v4_engagement_expiration', NULL, 'engagement',
      jsonb_build_object('mode', 'real', 'suspended', v_suspended, 'offboarded', v_offboarded,
        'notify_only', v_notified, 'details', v_details, 'run_at', now()));
  END IF;

  RETURN jsonb_build_object('mode', 'real', 'suspended', v_suspended, 'offboarded', v_offboarded,
    'notify_only', v_notified, 'total', v_suspended + v_offboarded + v_notified, 'run_at', now());
END;
$function$
;

CREATE OR REPLACE FUNCTION public.v4_expire_engagements_shadow()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_expired_count integer;
  v_details jsonb;
BEGIN
  SELECT count(*), COALESCE(jsonb_agg(jsonb_build_object(
    'engagement_id', e.id, 'person_name', p.name, 'kind', e.kind,
    'role', e.role, 'end_date', e.end_date, 'initiative', i.title
  )), '[]'::jsonb)
  INTO v_expired_count, v_details
  FROM public.engagements e
  JOIN public.persons p ON p.id = e.person_id
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.status = 'active' AND e.end_date IS NOT NULL AND e.end_date < CURRENT_DATE;

  IF v_expired_count > 0 THEN
    INSERT INTO public.admin_audit_log (action, actor_id, target_type, metadata)
    VALUES ('v4_expiration_shadow', NULL, 'engagement',
      jsonb_build_object('mode', 'shadow', 'would_expire_count', v_expired_count, 'details', v_details, 'run_at', now()));
  END IF;

  RETURN jsonb_build_object('mode', 'shadow', 'would_expire', v_expired_count, 'run_at', now());
END;
$function$
;

CREATE OR REPLACE FUNCTION public.validate_initiative_metadata(p_kind text, p_metadata jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_schema jsonb;
  v_field text;
  v_field_def jsonb;
  v_field_type text;
  v_actual_type text;
BEGIN
  SELECT custom_fields_schema INTO v_schema
  FROM public.initiative_kinds WHERE slug = p_kind;

  IF v_schema IS NULL OR v_schema = '{}'::jsonb THEN
    RETURN true;
  END IF;

  IF v_schema ? 'required' THEN
    FOR v_field IN SELECT jsonb_array_elements_text(v_schema->'required')
    LOOP
      IF NOT (p_metadata ? v_field) THEN
        RAISE EXCEPTION 'Missing required metadata field: "%"', v_field
          USING ERRCODE = 'P0007';
      END IF;
    END LOOP;
  END IF;

  IF v_schema ? 'properties' THEN
    FOR v_field, v_field_def IN SELECT * FROM jsonb_each(v_schema->'properties')
    LOOP
      IF p_metadata ? v_field THEN
        v_actual_type := jsonb_typeof(p_metadata->v_field);
        -- Skip null values (null is always valid)
        IF v_actual_type = 'null' THEN
          CONTINUE;
        END IF;
        v_field_type := v_field_def->>'type';

        CASE v_field_type
          WHEN 'string' THEN
            IF v_actual_type != 'string' THEN
              RAISE EXCEPTION 'Metadata field "%" must be string, got %', v_field, v_actual_type
                USING ERRCODE = 'P0008';
            END IF;
          WHEN 'number', 'integer' THEN
            IF v_actual_type != 'number' THEN
              RAISE EXCEPTION 'Metadata field "%" must be number, got %', v_field, v_actual_type
                USING ERRCODE = 'P0008';
            END IF;
          WHEN 'boolean' THEN
            IF v_actual_type != 'boolean' THEN
              RAISE EXCEPTION 'Metadata field "%" must be boolean, got %', v_field, v_actual_type
                USING ERRCODE = 'P0008';
            END IF;
          WHEN 'array' THEN
            IF v_actual_type != 'array' THEN
              RAISE EXCEPTION 'Metadata field "%" must be array, got %', v_field, v_actual_type
                USING ERRCODE = 'P0008';
            END IF;
          ELSE
            NULL;
        END CASE;
      END IF;
    END LOOP;
  END IF;

  RETURN true;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.validate_interview_booking_token(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_token_row record;
  v_app record;
BEGIN
  IF p_token IS NULL OR length(p_token) < 16 THEN
    RAISE EXCEPTION 'Invalid token format';
  END IF;

  SELECT * INTO v_token_row FROM public.onboarding_tokens WHERE token = p_token;
  IF v_token_row IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  IF v_token_row.expires_at < now() THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  IF NOT (v_token_row.scopes @> ARRAY['interview_booking']::text[]) THEN
    RAISE EXCEPTION 'Token does not have interview_booking scope';
  END IF;

  -- Increment access tracking
  UPDATE public.onboarding_tokens
  SET access_count = COALESCE(access_count, 0) + 1,
      last_accessed_at = now()
  WHERE token = p_token;

  -- Lookup application (read-only fields safe for anon)
  SELECT id, applicant_name, first_name, email, status
  INTO v_app FROM public.selection_applications
  WHERE id::text = v_token_row.source_id;

  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'first_name', COALESCE(NULLIF(trim(v_app.first_name), ''), split_part(v_app.applicant_name, ' ', 1)),
    'application_status', v_app.status,
    'expires_at', v_token_row.expires_at,
    'access_count', COALESCE(v_token_row.access_count, 0) + 1
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.verify_certificate(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  cert record;
  v_member_name text;
  v_issuer_name text;
  v_countersigner_name text;
BEGIN
  SELECT c.* INTO cert
  FROM certificates c
  WHERE c.verification_code = p_code;

  IF cert IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'error', 'not_found');
  END IF;

  SELECT name INTO v_member_name FROM members WHERE id = cert.member_id;

  IF cert.issued_by IS NOT NULL THEN
    SELECT name INTO v_issuer_name FROM members WHERE id = cert.issued_by;
  END IF;

  IF cert.counter_signed_by IS NOT NULL THEN
    SELECT name INTO v_countersigner_name FROM members WHERE id = cert.counter_signed_by;
  END IF;

  RETURN jsonb_build_object(
    'valid', COALESCE(cert.status, 'issued') = 'issued',
    'revoked', cert.status = 'revoked',
    'revoked_at', cert.revoked_at,
    'revoked_reason', cert.revoked_reason,
    'type', cert.type,
    'title', cert.title,
    'member_name', v_member_name,
    'issued_at', cert.issued_at,
    'issued_by', v_issuer_name,
    'counter_signed_by', v_countersigner_name,
    'counter_signed_at', cert.counter_signed_at,
    'cycle', cert.cycle,
    'period_start', cert.period_start,
    'period_end', cert.period_end,
    'function_role', cert.function_role,
    'language', cert.language,
    'verification_code', cert.verification_code
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.why_denied(p_person_id uuid, p_action text, p_resource_type text DEFAULT NULL::text, p_resource_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_person_exists boolean;
  v_has_engagements integer;
  v_has_authoritative integer;
  v_has_permission integer;
BEGIN
  SELECT EXISTS(SELECT 1 FROM persons WHERE id = p_person_id) INTO v_person_exists;
  IF NOT v_person_exists THEN
    RETURN jsonb_build_object('denied', true, 'reason', 'person_not_found');
  END IF;

  SELECT count(*) INTO v_has_engagements FROM engagements WHERE person_id = p_person_id AND status IN ('active', 'suspended');
  IF v_has_engagements = 0 THEN
    RETURN jsonb_build_object('denied', true, 'reason', 'no_active_engagements');
  END IF;

  SELECT count(*) INTO v_has_authoritative FROM auth_engagements WHERE person_id = p_person_id AND is_authoritative = true;
  IF v_has_authoritative = 0 THEN
    RETURN jsonb_build_object('denied', true, 'reason', 'no_authoritative_engagements',
      'engagements', (SELECT jsonb_agg(jsonb_build_object('kind', ae.kind, 'role', ae.role, 'is_authoritative', ae.is_authoritative, 'requires_agreement', ae.requires_agreement, 'has_agreement', ae.agreement_certificate_id IS NOT NULL)) FROM auth_engagements ae WHERE ae.person_id = p_person_id));
  END IF;

  SELECT count(*) INTO v_has_permission FROM auth_engagements ae
  JOIN engagement_kind_permissions ekp ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
  WHERE ae.person_id = p_person_id AND ae.is_authoritative = true;

  IF v_has_permission = 0 THEN
    RETURN jsonb_build_object('denied', true, 'reason', 'no_matching_permission', 'action', p_action,
      'active_roles', (SELECT jsonb_agg(DISTINCT jsonb_build_object('kind', ae.kind, 'role', ae.role)) FROM auth_engagements ae WHERE ae.person_id = p_person_id AND ae.is_authoritative = true),
      'available_actions', (SELECT jsonb_agg(DISTINCT ekp.action) FROM auth_engagements ae JOIN engagement_kind_permissions ekp ON ekp.kind = ae.kind AND ekp.role = ae.role WHERE ae.person_id = p_person_id AND ae.is_authoritative = true));
  END IF;

  RETURN jsonb_build_object('denied', false, 'granted_by', (
    SELECT jsonb_agg(jsonb_build_object('kind', ae.kind, 'role', ae.role, 'scope', ekp.scope, 'initiative_id', ae.initiative_id))
    FROM auth_engagements ae JOIN engagement_kind_permissions ekp ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
    WHERE ae.person_id = p_person_id AND ae.is_authoritative = true));
END;
$function$
;

