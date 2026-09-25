-- Checagem de chamador de sistema pelo GUC de role da requisicao, em funcoes SECURITY DEFINER.
--
-- Dentro de uma funcao SECURITY DEFINER de dono postgres, current_user e sempre o dono, entao uma
-- checagem de papel por current_user nao distingue quem chamou. As 14 funcoes abaixo passam a usar
-- public._request_is_rest_caller() (#684), que le o GUC de role: verdadeiro para authenticated/anon
-- via PostgREST, falso para service_role, pg_cron e conexao direta. Cron e service_role seguem
-- passando; o resto do corpo de cada funcao e identico a captura anterior, com UMA excecao:
-- member_resolve_email passa a exigir membro de quem chama pelo PostgREST (emenda a ADR-0095 §4).
--
-- Fora desta migration, de proposito: compute_ai_calibration_weekly e check_pre_onboarding_auto_steps.
-- Nenhuma das duas tem EXECUTE para anon/authenticated, e ambas sao chamadas por dentro de RPCs de
-- usuario (trigger_ai_calibration_run; approve_selection_application e
-- get_candidate_onboarding_progress). Trocar a checagem delas ativaria um gate interno que hoje nunca
-- dispara e mudaria a regra de autorizacao desses fluxos: isso pede decisao propria.


-- _audit_merit_transfer_on_completed_cards
CREATE OR REPLACE FUNCTION public._audit_merit_transfer_on_completed_cards()
RETURNS TABLE(
  item_id uuid,
  board_id uuid,
  title text,
  status text,
  assignee_id uuid,
  assignee_name text,
  assignee_role text,
  flag text,
  detail jsonb
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT (
    NOT public._request_is_rest_caller()
    OR (auth.uid() IS NOT NULL
        AND public.can((SELECT p.id FROM public.persons p
                        JOIN public.members m ON m.id = p.legacy_member_id
                        WHERE m.auth_id = auth.uid()), 'manage_platform'))
  ) THEN
    RAISE EXCEPTION 'Unauthorized: _audit_merit_transfer_on_completed_cards requires manage_platform';
  END IF;

  RETURN QUERY
  WITH completion_evt AS (
    -- first CARD-LEVEL completion moment (excludes activity/forecast-level events)
    SELECT e.item_id, min(e.created_at) AS first_completed_at
    FROM public.board_lifecycle_events e
    WHERE (e.action = 'status_change' AND e.new_status IN ('done', 'review', 'archived'))
       OR e.action IN ('archived', 'item_archived')
    GROUP BY e.item_id
  ),
  reassigned AS (
    -- a (re)assignment after completion, by someone OTHER than the current assignee (drop self-touches)
    SELECT e.item_id,
           max(e.created_at) AS last_reassigned_at,
           (array_agg(e.actor_member_id ORDER BY e.created_at DESC))[1] AS reassigned_by
    FROM public.board_lifecycle_events e
    JOIN completion_evt ce ON ce.item_id = e.item_id
    JOIN public.board_items bi ON bi.id = e.item_id
    WHERE e.action IN ('member_assigned', 'assigned')
      AND e.created_at > ce.first_completed_at
      AND bi.status IN ('done', 'review', 'archived')
      AND e.actor_member_id IS DISTINCT FROM bi.assignee_id
    GROUP BY e.item_id
  )
  SELECT bi.id, bi.board_id, bi.title, bi.status,
         bi.assignee_id, am.name, am.operational_role,
         'reassigned_after_completion'::text,
         jsonb_build_object(
           'first_completed_at', ce.first_completed_at,
           'last_reassigned_at', r.last_reassigned_at,
           'reassigned_by', rb.name)
  FROM reassigned r
  JOIN public.board_items bi ON bi.id = r.item_id
  JOIN completion_evt ce ON ce.item_id = r.item_id
  LEFT JOIN public.members am ON am.id = bi.assignee_id
  LEFT JOIN public.members rb ON rb.id = r.reassigned_by

  UNION ALL

  SELECT bi.id, bi.board_id, bi.title, bi.status,
         bi.assignee_id, am.name, am.operational_role,
         'completed_credit_from_non_leader_creator'::text,
         jsonb_build_object('created_by', cb.name, 'created_by_role', cb.operational_role)
  FROM public.board_items bi
  JOIN public.members am ON am.id = bi.assignee_id
  LEFT JOIN public.members cb ON cb.id = bi.created_by
  WHERE bi.status IN ('done', 'review', 'archived')
    AND am.operational_role IN ('manager', 'tribe_leader')
    AND bi.created_by IS NOT NULL
    AND bi.created_by IS DISTINCT FROM bi.assignee_id
    AND (cb.operational_role IS NULL OR cb.operational_role NOT IN ('manager', 'tribe_leader'))

  ORDER BY 8, 3;
END;
$function$;

-- _get_vault_secret
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
  IF public._request_is_rest_caller() THEN
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

-- _test_detect_inactive_with_threshold
CREATE OR REPLACE FUNCTION public._test_detect_inactive_with_threshold(p_threshold integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_old_value jsonb;
  v_result jsonb;
BEGIN
  -- Defense: service_role only (matches detect_inactive_members cron-bypass check).
  -- Phrasing aligned with ADR-0011 canonical hasAuthGate set (p187 MED-186.F).
  IF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Unauthorized: _test_detect_inactive_with_threshold requires service_role';
  END IF;

  IF p_threshold < 0 THEN
    RAISE EXCEPTION 'p_threshold must be >= 0 (got %)', p_threshold;
  END IF;

  -- Snapshot current site_config value
  SELECT value INTO v_old_value
    FROM public.site_config
   WHERE key = 'inactivity_threshold_days';

  -- Override. FICA FORA do frame que aborta, de proposito: o `detect_inactive_members` de dentro
  -- precisa enxergar o limiar sobrescrito, e a restauracao defensiva abaixo e quem o desfaz.
  UPDATE public.site_config
     SET value = to_jsonb(p_threshold)
   WHERE key = 'inactivity_threshold_days';

  -- #2407: o frame agora tem DUAS funcoes: restaurar `site_config` em caso de erro (como antes)
  -- e, no caminho feliz, DESFAZER tudo o que foi escrito aqui dentro.
  BEGIN
    -- #1170: a dedup de 6 dias derrotaria `managers_notified > 0`. Limpar a janela continua sendo
    -- o unico jeito de exercitar o caminho INSERT, e agora essa limpeza NAO SOBREVIVE ao bloco.
    IF (public.detect_inactive_members(p_dry_run := true)->>'candidates_count')::int > 0 THEN
      DELETE FROM public.notifications
       WHERE type = 'arm9_inactivity_alert'
         AND created_at > (now() - interval '6 days');
    END IF;

    v_result := public.detect_inactive_members(p_dry_run := false);

    -- #2407: a sentinela. Abortar o frame desfaz o DELETE acima E os INSERTs que
    -- `detect_inactive_members` acabou de fazer em `notifications` e `admin_audit_log`.
    -- `v_result` sobrevive porque variavel de PL/pgSQL nao e transacional, e e sobre ela que o
    -- teste afirma. SQLSTATE proprio para nao confundir a sentinela com erro de verdade: um
    -- `WHEN OTHERS` sozinho aqui engoliria o defeito que este mesmo repo passou o dia caçando.
    RAISE EXCEPTION USING ERRCODE = 'ND407', MESSAGE = '#2407 sentinela hermetica: desfaz as escritas do teste';
  EXCEPTION
    WHEN SQLSTATE 'ND407' THEN
      -- Caminho esperado: o frame ja foi desfeito. Nada a fazer.
      NULL;
    WHEN OTHERS THEN
      UPDATE public.site_config
         SET value = v_old_value
       WHERE key = 'inactivity_threshold_days';
      RAISE;
  END;

  -- Defensive restore (belt+suspenders for cases where caller forgot tx=rollback)
  UPDATE public.site_config
     SET value = v_old_value
   WHERE key = 'inactivity_threshold_days';

  RETURN v_result;
END;
$function$;

-- _test_invariants_with_synthetic_breach
CREATE OR REPLACE FUNCTION public._test_invariants_with_synthetic_breach(p_breach text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cycle_id uuid;
  v_org_id uuid;
  v_test_email text;
  v_result jsonb;
BEGIN
  IF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Unauthorized: _test_invariants_with_synthetic_breach requires service_role';
  END IF;

  IF p_breach NOT IN ('R', 'S') THEN
    RAISE EXCEPTION 'Invalid p_breach value: % (must be ''R'' or ''S'')', p_breach;
  END IF;

  -- #1801 — era `ORDER BY created_at DESC LIMIT 1`. Qualquer ciclo serviria aqui; usa o helper
  -- para que a classe não tenha exceção.
  v_cycle_id := public.selection_active_cycle_id();
  SELECT organization_id
  INTO v_org_id
  FROM public.selection_cycles
  WHERE id = v_cycle_id;

  IF v_cycle_id IS NULL THEN
    RAISE EXCEPTION 'No selection_cycles available — cannot seed synthetic breach';
  END IF;

  v_test_email := '__test_invariant_' || lower(p_breach) || '_' ||
                  replace(gen_random_uuid()::text, '-', '') || '@invariant.test';

  INSERT INTO public.selection_applications (
    cycle_id, organization_id, applicant_name, email, role_applied, status
  ) VALUES (
    v_cycle_id, v_org_id,
    '__test_invariant_synthetic__', v_test_email,
    'researcher', 'approved'
  );

  IF p_breach = 'S' THEN
    INSERT INTO public.members (
      organization_id, name, email, member_status, person_id, chapter
    ) VALUES (
      v_org_id, '__test_invariant_synthetic__', v_test_email,
      'active', NULL, 'Outro'
    );
  END IF;

  SELECT jsonb_agg(row_to_json(t) ORDER BY t.invariant_name)
  INTO v_result
  FROM public.check_schema_invariants() t
  WHERE t.invariant_name IN (
    'R_approved_application_has_member',
    'S_approved_member_has_person_id'
  );

  RETURN v_result;
END;
$function$;

-- _test_meeting_close_summary_roundtrip
CREATE OR REPLACE FUNCTION public._test_meeting_close_summary_roundtrip()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_event_id uuid;
  v_auth_id  uuid;
  v_canary   text := '__test_2351_' || replace(gen_random_uuid()::text, '-', '');
  v_ret_a jsonb; v_ret_b jsonb;
  v_notes_a text; v_notes_b text;
  v_sentinel constant text := '__ROLLBACK_2351__';
BEGIN
  IF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Unauthorized: _test_meeting_close_summary_roundtrip requires service_role';
  END IF;

  -- Um evento JA FECHADO e alguem que possa fecha-lo. Se nao houver, aborta com
  -- "nao medido" em vez de devolver um verde que nao mediu nada.
  SELECT e.id, m.auth_id INTO v_event_id, v_auth_id
  FROM public.events e
  CROSS JOIN LATERAL (
    SELECT mm.id, mm.auth_id FROM public.members mm
    WHERE mm.auth_id IS NOT NULL AND public._manage_event_scope_ok(mm.id, e.id)
    LIMIT 1
  ) m
  WHERE e.minutes_posted_at IS NOT NULL
  ORDER BY e.date DESC
  LIMIT 1;

  IF v_event_id IS NULL THEN
    RAISE EXCEPTION 'not_measured: no closed event with an authorized closer';
  END IF;

  BEGIN
    PERFORM set_config('request.jwt.claims',
            json_build_object('sub', v_auth_id, 'role', 'authenticated')::text, true);

    -- BRACO A (o que a #2351 conserta): reuniao JA FECHADA + resumo.
    v_ret_a := public.meeting_close(v_event_id, v_canary || '_A', NULL);
    SELECT notes INTO v_notes_a FROM public.events WHERE id = v_event_id;

    -- CONTROLE POSITIVO B: mesma funcao, mesmo evento, mesmo chamador, NAO fechada.
    -- Se B falhar, o instrumento esta quebrado e A nao prova nada.
    UPDATE public.events SET minutes_posted_at = NULL, notes = NULL WHERE id = v_event_id;
    v_ret_b := public.meeting_close(v_event_id, v_canary || '_B', NULL);
    SELECT notes INTO v_notes_b FROM public.events WHERE id = v_event_id;

    RAISE EXCEPTION '%', v_sentinel;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> v_sentinel THEN RAISE; END IF;
  END;

  RETURN jsonb_build_object(
    'event_id', v_event_id,
    'canary', v_canary,
    'arm_a', jsonb_build_object(
      'already_closed',   v_ret_a->'already_closed',
      'summary_appended', v_ret_a->'summary_appended',
      'notes_has_canary', COALESCE(v_notes_a, '') LIKE '%' || v_canary || '_A%'),
    'arm_b_control', jsonb_build_object(
      'already_closed',   v_ret_b->'already_closed',
      'summary_appended', v_ret_b->'summary_appended',
      'notes_has_canary', COALESCE(v_notes_b, '') LIKE '%' || v_canary || '_B%')
  );
END;
$function$;

-- auto_promote_eligible_leads_daily
CREATE OR REPLACE FUNCTION public.auto_promote_eligible_leads_daily()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_cycle record;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_total_promoted integer := 0;
  v_total_cycles integer := 0;
  v_cron_context boolean;
BEGIN
  v_cron_context := (NOT public._request_is_rest_caller());

  IF NOT v_cron_context THEN
    RAISE EXCEPTION 'Unauthorized: cron-only (called by pg_cron)';
  END IF;

  FOR v_cycle IN
    SELECT id, cycle_code FROM public.selection_cycles
    WHERE status = 'open' AND leads_auto_promoted_at IS NULL
    ORDER BY open_date ASC NULLS LAST
  LOOP
    v_result := public.auto_promote_eligible_leads_for_cycle(v_cycle.id);
    v_results := v_results || jsonb_build_array(v_result);
    v_total_cycles := v_total_cycles + 1;
    v_total_promoted := v_total_promoted + COALESCE((v_result->>'promoted')::int, 0);
  END LOOP;

  RETURN jsonb_build_object(
    'cycles_processed', v_total_cycles,
    'total_promoted', v_total_promoted,
    'per_cycle', v_results,
    'ran_at', now()
  );
END;
$func$;

-- check_schema_invariants
CREATE OR REPLACE FUNCTION public.check_schema_invariants()
 RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL
     AND public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants requires authentication';
  END IF;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'alumni' AND operational_role IS DISTINCT FROM 'alumni'
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A1_alumni_role_consistency'::text,
         'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'observer' AND operational_role NOT IN ('observer','guest','none')
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A2_observer_role_consistency'::text,
         'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
        -- Wave 1 fix: sponsor outranks researcher (committee/workgroup) so a sponsor who also sits on a
        -- committee (e.g. the governance committee) shows as a sponsor, not a researcher.
        WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
        -- Wave 2 WS-1 (PM 2026-06-28 'governança vence'): chapter_board (chapter director) outranks
        -- researcher/observer so a chapter director who also sits on a committee or observes a
        -- tribe still shows as 'Ponto Focal do Capítulo' (chapter_liaison). Stays BELOW sponsor
        -- and operational leaders (manager/deputy/tribe_leader) — those who lead operationally keep that role.
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(
          (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
          OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
              AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
          OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
              AND ae.role IN ('leader','co_leader','owner','coordinator'))
        ) THEN 'researcher'
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'institutional_auditor') THEN 'institutional_auditor'
        WHEN bool_or(ae.kind = 'observer') THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
        WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status='active' AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT c.member_id FROM computed c
    JOIN public.members m ON m.id = c.member_id
    WHERE m.operational_role IS DISTINCT FROM c.expected_role
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE ((member_status='active' AND is_active=false) OR (member_status IN ('observer','alumni','inactive') AND is_active=true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'B_is_active_status_mismatch'::text,
         'members.is_active must match member_status mapping (active=true, terminal=false)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND designations IS NOT NULL AND array_length(designations,1)>0
  )
  SELECT 'C_designations_in_terminal_status'::text,
         'members.designations must be empty when member_status is observer/alumni/inactive'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL AND m.auth_id IS DISTINCT FROM p.auth_id
  )
  SELECT 'D_auth_id_mismatch_person_member'::text,
         'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ae.engagement_id AS e_id FROM public.auth_engagements ae
    JOIN public.members m ON m.person_id = ae.person_id
    WHERE ae.status='active' AND m.member_status IN ('observer','alumni','inactive')
      AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact')
  )
  SELECT 'E_engagement_active_with_terminal_member'::text,
         'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(e_id ORDER BY e_id) FROM (SELECT e_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT i.id AS initiative_id FROM public.initiatives i
    WHERE i.legacy_tribe_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id)
  )
  SELECT 'F_initiative_legacy_tribe_orphan'::text,
         'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.current_version_id IS NOT NULL
      AND (dv.id IS NULL OR dv.locked_at IS NULL)
      AND NOT EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status IN ('review','approved','activated')
          AND ac.closed_at IS NULL
      )
  )
  SELECT 'J_current_version_published'::text,
         'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL — unless an open approval_chain (review/approved/activated, closed_at NULL) is in flight that will lock the version on close (Phase IP-1, chain-aware).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.operational_role='external_signer'
      AND NOT EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id=m.person_id AND ae.kind='external_signer' AND ae.status='active' AND ae.is_authoritative=true
      )
  )
  SELECT 'K_external_signer_integrity'::text,
         'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.member_status IN ('alumni','observer','inactive') AND m.anonymized_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id=m.id)
  )
  SELECT 'L_offboarding_record_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH expected AS (
    -- Audit A2 (mig 20260805000478): derive research_score from the already-consolidated PERT
    -- columns objective_score_avg (min-2 gated) + interview_score (min-1 gated), EXACTLY as
    -- public.compute_application_scores does (mig 20260805000475). research_score is NULL when
    -- objective_score_avg is NULL (a single-evaluator app is not rankable). The prior raw
    -- AVG(subtotais objetivos) + AVG(subtotais entrevista) derivation lacked the min_evaluators
    -- gate and flagged the correctly-nulled single-evaluator apps as false drift.
    SELECT a.id AS application_id, a.research_score AS cached,
      CASE
        WHEN a.objective_score_avg IS NOT NULL AND a.interview_score IS NOT NULL THEN round(a.objective_score_avg + a.interview_score, 2)
        WHEN a.objective_score_avg IS NOT NULL THEN round(a.objective_score_avg, 2)
        ELSE NULL
      END AS expected
    FROM public.selection_applications a
  ),
  drift AS (
    SELECT application_id FROM expected
    WHERE (cached IS NULL) IS DISTINCT FROM (expected IS NULL)
       OR (cached IS NOT NULL AND expected IS NOT NULL AND ABS(cached - expected) > 0.01)
  )
  SELECT 'M_application_score_consistency'::text,
         'selection_applications.research_score must equal compute_application_scores(application_id) derivation: objective_score_avg (PERT, min-2 gated) + interview_score (PERT, min-1 gated), NULL when objective_score_avg is NULL (sync trigger trg_recompute_application_scores; Audit A2 mig 20260805000478 replaced the pre-min-gate raw-AVG derivation).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND offboarded_at IS NULL AND anonymized_at IS NULL
      AND name <> 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'N_terminal_status_offboarded_at_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have offboarded_at NOT NULL (ARM-9 G6 defense-in-depth complement to L).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ma.id AS artifact_id FROM public.meeting_artifacts ma
    WHERE ma.event_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.events e WHERE e.id = ma.event_id)
  )
  SELECT 'O_meeting_artifact_event_orphan'::text,
         'meeting_artifacts.event_id must point to an existing event when not NULL (FK defense).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(artifact_id ORDER BY artifact_id) FROM (SELECT artifact_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  SELECT 'P_tribe_initiative_bridge_complete'::text,
         'tribes.is_active=true must have at least one initiative.legacy_tribe_id pointing to it (V3-V4 bridge; cron leader digest depends).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM public.tribes t
          WHERE t.is_active = true
            AND NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.legacy_tribe_id = t.id)),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS engagement_id FROM public.engagements
    WHERE status = 'expired' AND end_date > CURRENT_DATE
  )
  SELECT 'Q_expired_engagement_end_date'::text,
         'engagements.status=expired requires end_date <= CURRENT_DATE (impossible to be expired in the future; VEP service_latest_end_date is source of truth).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT a.id AS application_id
    FROM public.selection_applications a
    WHERE a.status = 'approved'
      AND a.email IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.members m WHERE lower(m.email) = lower(a.email)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.member_emails me WHERE lower(me.email) = lower(a.email)
      )
  )
  SELECT 'R_approved_application_has_member'::text,
         'selection_applications.status=approved must have a matching members row by lower(email). Bypass of approve_selection_application() canonical RPC creates this drift (Issue #180).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT DISTINCT m.id AS member_id
    FROM public.selection_applications a
    JOIN public.members m ON lower(m.email) = lower(a.email)
    WHERE a.status = 'approved' AND m.person_id IS NULL
  )
  SELECT 'S_approved_member_has_person_id'::text,
         'members tied to an approved selection_applications row must have person_id NOT NULL (V4 graph anchor for engagements). Issue #180.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH primary_email_counts AS (
    SELECT m.id AS member_id,
           COUNT(me.id) FILTER (WHERE me.is_primary = true) AS primary_count
    FROM public.members m
    LEFT JOIN public.member_emails me ON me.member_id = m.id
    WHERE m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT member_id FROM primary_email_counts
    WHERE primary_count <> 1
  )
  SELECT 'T_member_has_exactly_one_primary_email'::text,
         'Every member must have exactly one primary email in member_emails (Issue #205).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status = 'pending_proposer_consent'
      AND EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status NOT IN ('withdrawn','superseded')
      )
  )
  SELECT 'V_prime_pending_proposer_consent_no_open_chain'::text,
         'status=pending_proposer_consent must not have non-cancelled approval_chains rows (#315 P0-Q7 + Amendment A2 — pending_proposer_consent precedes any chain).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status IN ('approved','active')
      AND gd.current_ratified_chain_id IS NULL
  )
  SELECT 'V_status_chain_coherence'::text,
         'governance_documents with status approved/active must have current_ratified_chain_id NOT NULL (#315 P0-Q6 + #367 Wave 1b first leaf). NO carve-out: 7 legacy pre-chain docs backfilled with PM-designated synthetic chains via migration 20260805000038 (acknowledge signoffs, metadata.legacy_migration=true, role=migration_attestation).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT cp.id AS product_id
    FROM public.content_products cp
    WHERE
      CASE cp.source_kind
        WHEN 'governance_document_version' THEN
          NOT (cp.source_document_version_id IS NOT NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'board_item' THEN
          NOT (cp.source_board_item_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'publication_idea' THEN
          NOT (cp.source_publication_idea_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'external' THEN
          NOT (cp.source_external_uri IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL)
        WHEN 'none' THEN
          NOT (cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        ELSE TRUE
      END
  )
  SELECT 'W_content_product_source_integrity'::text,
         'content_products row must satisfy chk_content_products_source_integrity CHECK semantics (exactly one source FK populated per source_kind; ADR-0099 §2.2 + §6 step 9). Defense-in-depth complement to the CHECK constraint; mirrors V/V''/T pattern.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(product_id ORDER BY product_id) FROM (SELECT product_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT p.id AS parecer_id
    FROM public.blind_review_pareceres p
    WHERE NOT EXISTS (
      SELECT 1 FROM public.blind_review_assignments a
      WHERE a.session_id = p.session_id
        AND a.reviewer_member_id = p.reviewer_member_id
        AND a.status = 'active'
    )
  )
  SELECT 'X_blind_review_pareceres_session_product_match'::text,
         'blind_review_pareceres.reviewer_member_id must have an active blind_review_assignments row in the same session (assignment-parecer integrity; ADR-0099 §2.7 + §7 step 11). Defense-in-depth complement to FK constraints; catches drift if assignment is withdrawn while parecer remains. #382 PR-B.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(parecer_id ORDER BY parecer_id) FROM (SELECT parecer_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH pe AS (
    SELECT name AS k FROM public.partner_entities
    WHERE entity_type = 'pmi_chapter' AND status = 'active' AND NOT COALESCE(is_international, false)
  ),
  ch AS (
    SELECT 'PMI-' || code AS k FROM public.chapters WHERE status = 'active'
  ),
  drift AS (
    SELECT k FROM pe WHERE k NOT IN (SELECT k FROM ch)
    UNION ALL
    SELECT k FROM ch WHERE k NOT IN (SELECT k FROM pe)
  )
  SELECT 'Y_chapter_pipeline_parity'::text,
         'every active domestic pmi_chapter in partner_entities must have a matching active chapters row (by name = ''PMI-'' || chapters.code) and vice-versa — MEMBERSHIP parity (not just count), so it catches single-table inserts/archives even when row counts coincide. Drift = get_chapter_metrics()->>signed forks from the V4 chapters table (#481).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM drift),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS webinar_id FROM public.webinars
    WHERE status IS NULL OR status NOT IN ('planned','confirmed','completed','cancelled')
  )
  SELECT 'Z_webinar_status_domain'::text,
         'webinars.status must be within planned|confirmed|completed|cancelled (the realized=completed canonical definition depends on it; defense-in-depth complement to webinars_status_check — #479/#481).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(webinar_id ORDER BY webinar_id) FROM (SELECT webinar_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND current_cycle_active = true
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'B2_current_cycle_active_terminal_status'::text,
         'members in observer/alumni/inactive must have current_cycle_active=false (#483 sync_member_status_consistency B-trigger; CCA gates the get_gamification_leaderboard/get_public_leaderboard cohort).'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.person_id IS NOT NULL
      AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
      AND replace(m.chapter, 'PMI-', '') IN (SELECT chapter_code FROM public.chapter_registry)
      AND NOT (m.operational_role = 'guest' AND m.entry_chapter_code IS NULL)
      AND (SELECT COUNT(*) FROM public.member_chapter_affiliations a
            WHERE a.person_id = m.person_id AND a.is_primary) <> 1
  )
  SELECT 'U_active_person_has_primary_chapter_affiliation'::text,
         'every active registry-chaptered member''s person_id must have exactly one is_primary=true member_chapter_affiliations row, else the members.chapter COALESCE(entry, primary, legacy) derivation breaks silently (ADR-0104 Wave 3b-ii). Excluded: operational_role=''guest'' AND entry_chapter_code IS NULL (pre-onboarding, entry-chapter choice not yet made — affiliation is seeded by set_my_entry_chapter, Wave 3b-i; until then the COALESCE falls through to the legacy default). Non-registry chapters (Outro/Externo) excluded — legitimately unaffiliated.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT op.member_id
    FROM public.onboarding_progress op
    WHERE op.step_key = 'volunteer_term'
      AND op.status <> 'completed'
      AND op.member_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = op.member_id
          AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
      )
  )
  SELECT 'AA_volunteer_term_complete_when_cert_issued'::text,
         'a member holding an issued volunteer_agreement certificate must have their volunteer_term onboarding_progress step at status=completed. Guaranteed by the cert-side AFTER trigger (_trg_complete_volunteer_term_on_cert on certificates) plus the seed-side BEFORE guard (_trg_complete_volunteer_term_on_seed on onboarding_progress), p233 / issue #766. A non-completed step alongside an issued cert means a trigger was bypassed (service_role direct INSERT, or a cert backfill that did not fire the AFTER trigger). Directional: a member with no volunteer_term row, or a completed step without an issued cert (all certs rejected or superseded), is NOT a violation.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'term_signed'
      AND NOT EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = mm.member_id
          AND c.type = 'volunteer_agreement'
      )
  )
  SELECT 'AB_term_signed_milestone_has_cert_ancestry'::text,
         'a term_signed member_milestone must have at least one volunteer_agreement certificate of any status (issued/rejected/superseded) for the same member. Wave 3c reject/reissue is valid ancestry — the milestone persists after a cert is rejected or superseded because the member did sign once. A milestone with NO cert in any state indicates fabrication or a bad backfill (service_role direct INSERT into member_milestones; source_id is informational-only without FK). #766 PR2, mig 20260805000202. Directional complement to AA.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'first_attendance'
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.member_id = mm.member_id
          AND a.present = true
      )
  )
  SELECT 'AC_first_attendance_milestone_has_attendance'::text,
         'a first_attendance member_milestone must have at least one present=true attendance row for the same member. source_id is informational-only (no FK), so a milestone with no present attendance indicates fabrication or a bad backfill (service_role direct INSERT into member_milestones). #766 PR3, mig 20260805000203. Directional, mirrors AA/AB.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'first_deliverable'
      AND NOT EXISTS (
        SELECT 1 FROM public.tribe_deliverables td
        WHERE td.assigned_member_id = mm.member_id
          AND td.status = 'completed'
      )
  )
  SELECT 'AD_first_deliverable_milestone_has_completed_deliverable'::text,
         'a first_deliverable member_milestone must have at least one tribe_deliverable with status=''completed'' assigned to the same member. Keyed on status=''completed'' (same signal as the trigger and the XP sibling trg_tribe_deliverable_completed_xp; NOT completed_at, a derived audit column). A milestone with no completed deliverable indicates fabrication, a bad backfill, or a status reverted via service_role after the milestone fired. #766 PR3, mig 20260805000203. Directional, mirrors AA/AB.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'profile_complete'
      AND NOT EXISTS (
        SELECT 1 FROM public.members m
        WHERE m.id = mm.member_id
          AND m.profile_completed_at IS NOT NULL
      )
  )
  SELECT 'AE_profile_complete_milestone_has_profile_completed_at'::text,
         'a profile_complete member_milestone must have members.profile_completed_at set. The column is monotonic — only update_my_profile writes it (NULL -> now() once, never cleared) — so this directional check is false-positive-free, unlike promotion whose mutable operational_role cache demotes routinely (hence PR4 added no invariant). A milestone with a NULL profile_completed_at indicates fabrication, a bad backfill (service_role direct INSERT into member_milestones; source_id is informational-only without FK), or the column cleared via a manual UPDATE after the milestone fired. #766 PR5, mig 20260805000205. Directional, mirrors AA/AB/AC/AD.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT si.id AS interview_id
    FROM public.selection_interviews si
    WHERE si.status IN ('scheduled','rescheduled')
      AND EXISTS (
        SELECT 1 FROM public.selection_interviews si2
        WHERE si2.application_id = si.application_id
          AND si2.created_at > si.created_at
      )
  )
  SELECT 'AF_open_interview_is_newest_row'::text,
         'a selection_interviews row in an open status (scheduled/rescheduled) must be the most-recently-created interview row for its application. An open row older than another interview row of the same application indicates a reschedule/re-booking that did not close the prior open row (bypass of the AFTER INSERT trigger trg_supersede_prior_open_interviews, or pre-fix legacy drift). Root cause: sync_calendar_booking_to_interview / schedule_interview INSERTing a new scheduled row without superseding the prior open one (D4/D5, mig 20260805000210). KNOWN directional gap (defense-in-depth): a TERMINAL row inserted newer than an open row (only import_historical_interviews) is not superseded by the trigger and would surface here; the live path reaches completed via UPDATE in-place, so it is covered.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(interview_id ORDER BY interview_id) FROM (SELECT interview_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT e.id AS engagement_id
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    JOIN public.members m ON m.person_id = e.person_id
    WHERE e.kind = 'volunteer' AND e.status = 'active'
      AND m.tribe_id IS DISTINCT FROM i.legacy_tribe_id
  )
  SELECT 'AG_tribe_engagement_has_tribe_id'::text,
         'every active volunteer engagement in a research_tribe initiative must have member.tribe_id = initiative.legacy_tribe_id (the correctness contract of the bridge trigger trg_sync_tribe_id_from_engagement; count_tribe_slots reads members.tribe_id, so a divergence corrupts the slot count). A violation means the bridge was bypassed (service_role direct INSERT into engagements) or a stale legacy tribe_id conflicts with the engagement. Tribe Selection Híbrida PR1, mig 20260805000216. Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT e.person_id
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    WHERE e.kind = 'volunteer' AND e.status = 'active'
    GROUP BY e.person_id
    HAVING COUNT(*) > 1
  )
  SELECT 'AH_research_tribe_single_active_engagement'::text,
         'a person must have at most one active volunteer engagement across research_tribe initiatives. members.tribe_id is a single scalar and the bridge trigger trg_sync_tribe_id_from_engagement (admission + demotion branch) assumes a single active tribe engagement; two make tribe_id ambiguous and can leave a stale tribe_id after one is demoted. Supersedes the SPEC''s I_research_tribe_no_dual_pending (which false-positives on a legitimate tribe-move and whose committed-divergence sibling is already non-zero from frozen legacy tribe_selections staleness, below the bridge since AG=0). Tribe Selection Híbrida PR1, mig 20260805000216. Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(person_id ORDER BY person_id) FROM (SELECT person_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id FROM public.selection_applications WHERE interview_auto_rescue_count > 1
  )
  SELECT 'AI_unbooked_rescue_cap_respected'::text,
         'selection_applications with interview_auto_rescue_count > 1 (above cap=1). _selection_unbooked_rescue_cron + selection_rescue_unbooked_invite enforce the cap via a RAISE guard at count>=1; a value >1 means a re-entry bug or a service_role direct UPDATE bypassed the guard. D3 auto-rescue, mig 20260805000219. Baseline 0.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(id ORDER BY id) FROM (SELECT id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH expected(tbl) AS (
    VALUES ('initiatives'),('events'),('project_boards'),('board_items'),
           ('meeting_artifacts'),('tribe_deliverables'),('recurring_meeting_rules'),('governance_documents')
  ),
  drift AS (
    SELECT e.tbl FROM expected e
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_policies p
      WHERE p.schemaname = 'public'
        AND p.tablename = e.tbl
        AND p.permissive = 'RESTRICTIVE'
        AND p.cmd IN ('SELECT','ALL')
        AND p.qual ILIKE '%rls_can_see_%'
    )
  )
  SELECT 'AJ_confidential_visibility_gate_present'::text,
         'each of the 8 initiative-dependent tables (initiatives/events/project_boards/board_items/meeting_artifacts/tribe_deliverables/recurring_meeting_rules/governance_documents) must carry a RESTRICTIVE SELECT policy whose USING calls a rls_can_see_* helper — the confidential-initiative visibility gate (#785 PR-2, mig 20260805000232). A missing policy means the gate was dropped and a confidential initiative''s rows leak to non-engaged members. Structural catalog check (pg_policies); baseline 0.'::text,
         'high'::text,
         (SELECT COUNT(*)::integer FROM drift),
         NULL::uuid[];


  -- #333 (Wave 4, #221/#218): voice-biometric consent enforcement — periodic detector that
  -- complements the write-time trigger trg_pmi_video_screening_voice_consent.
  RETURN QUERY
  WITH ack AS (
    -- Applications with a documented LGPD Art.18 retroactive-notification retention basis
    -- (the #332 acknowledged pre-block row). The application id is parsed from the pii_access_log
    -- audit record so NO candidate identifier is hardcoded in this migration; the exclusion IS the
    -- documented retention, and it self-heals to nothing if the row is eventually deleted.
    SELECT (substring(pal.reason FROM 'application_id=([0-9a-fA-F-]+)'))::uuid AS application_id
    FROM public.pii_access_log pal
    WHERE pal.context = 'lgpd_art_18_retroactive_notification'
      AND pal.reason ~ 'application_id='
  ),
  drift AS (
    SELECT vs.id
    FROM public.pmi_video_screenings vs
    WHERE vs.transcription IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_applications sa
        WHERE sa.id = vs.application_id
          AND sa.consent_voice_biometric_at IS NOT NULL
          AND sa.consent_voice_biometric_revoked_at IS NULL
      )
      AND NOT EXISTS (
        SELECT 1 FROM ack WHERE ack.application_id = vs.application_id
      )
  )
  SELECT 'AK_voice_biometric_consent_enforcement'::text,
         'every pmi_video_screenings row with transcription IS NOT NULL must have a matching selection_applications row where consent_voice_biometric_at IS NOT NULL AND consent_voice_biometric_revoked_at IS NULL (voice-biometric consent, LGPD Art.11), UNLESS its application has a documented Art.18 retroactive-notification retention basis logged in pii_access_log. The BEFORE INSERT/UPDATE trigger trg_pmi_video_screening_voice_consent is the write-time moat; this invariant is the periodic detector for any NEW drift (trigger disabled, consent revoked without deleting the row, raw SQL bypass). #333/#221/#218 Wave 4. The 1 acknowledged pre-block row (#332, tacit Art.18 retention; PM path (b) 2026-06-27) is EXCLUDED via its retention record, so baseline is 0; a new non-consented transcription with no retention basis is flagged. Named AK because the U_ code is already held by U_active_person_has_primary_chapter_affiliation.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(id ORDER BY id) FROM (SELECT id FROM drift LIMIT 10) s)
  FROM drift;

  -- #209 / ADR-0107 (amended #1039 / ADR-0107 Amendment 1): Drive offboarding revocation
  -- queue state-machine integrity, auto-approve provenance included.
  RETURN QUERY
  WITH drift AS (
    SELECT id AS audit_id FROM public.drive_offboarding_audit
    WHERE
      (status = 'revoked' AND (revoked_at IS NULL
        OR (approved_by IS NULL AND approval_mode IS DISTINCT FROM 'auto')))
      OR (approval_mode = 'auto' AND (approved_by IS NOT NULL OR status = 'pending_revoke'))
      OR (status = 'skipped' AND skip_reason IS NULL)
      OR (status IN ('pending_revoke','approved') AND EXISTS (
            SELECT 1 FROM public.members m
            WHERE m.id = drive_offboarding_audit.member_id
              AND (m.member_status = 'active' OR m.offboarded_at IS NULL)))
  )
  SELECT 'AL_drive_revocation_terminal_consistency'::text,
         'drive_offboarding_audit (#209/ADR-0107, amended #1039/Amendment 1): a revoked row must carry revoked_at AND either approved_by (manual GP approve path) or approval_mode=''auto'' (alumni-only system approve via auto_approve_alumni_drive_revocations; already_absent is excluded from provenance checks by design — the grant was already gone, no proof of revocation is required); an auto row may never carry a human approver nor sit in pending_revoke (provenance coherence: auto is written exactly at the pending→approved flip; the write-side alumni-only filter is the moat — member_status is NOT re-checked here because a legitimately auto-revoked alumni can later return to active via the re-engagement pipeline); a skipped row must carry skip_reason (owner_permission | member_reactivated — structural Art. 37 evidence, council COND-2); and no OPEN row (pending_revoke/approved) may reference a member who is active / not offboarded — admin_reactivate_member cancels open rows to skipped/member_reactivated in the same transaction (#1039). A violation means a service_role direct write bypassed the RPC path, or a reactivation cleared offboarding without clearing the queue. Baseline 0.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(audit_id ORDER BY audit_id) FROM (SELECT audit_id FROM drift LIMIT 10) s)
  FROM drift;

  -- #301 / ADR-0108: curation temporary Drive grant state-machine integrity.
  RETURN QUERY
  WITH drift AS (
    SELECT id AS grant_id FROM public.drive_curation_grants
    WHERE (status = 'granted' AND (permission_id IS NULL OR granted_at IS NULL))
       OR (status = 'granted' AND revoked_at IS NOT NULL)
       OR (status = 'revoked' AND revoked_at IS NULL)
  )
  SELECT 'AM_drive_curation_grant_terminal_consistency'::text,
         'drive_curation_grants (#301/ADR-0108): a granted row must carry permission_id AND granted_at (proof the Drive POST succeeded) and must NOT carry revoked_at; a revoked row must carry revoked_at. The grant/revoke EF mark RPCs (mark_curation_grant_done/mark_curation_grant_revoked) are the only legitimate writers of these terminal states; a violation means a service_role direct write bypassed them. Named AM (AL is the #209 sibling). Baseline 0.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(grant_id ORDER BY grant_id) FROM (SELECT grant_id FROM drift LIMIT 10) s)
  FROM drift;

  -- #974 (PR-2 of #571) — no dynamic remission: every active cooperation_agreement
  -- must carry an active instrument_version_bindings pin to the IP policy (a hard
  -- document_versions.id), never a free-text "Política vigente" dynamic remission.
  -- GATED on a ratified (active) cooperation_addendum: dormant until the Adendo
  -- imports the policy into the agreements (pre-ratification no ratified instrument
  -- obliges the agreements to pin the policy — §9.7 / legal review 2026-06-30).
  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id
    FROM public.governance_documents gd
    WHERE gd.doc_type = 'cooperation_agreement'
      AND gd.status = 'active'
      AND EXISTS (
        SELECT 1 FROM public.governance_documents addn
        WHERE addn.doc_type = 'cooperation_addendum' AND addn.status = 'active'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.instrument_version_bindings ivb
        JOIN public.governance_documents ref ON ref.id = ivb.referenced_document_id
        WHERE ivb.bound_document_id = gd.id
          AND ref.doc_type = 'policy'
          AND ivb.status = 'active'
      )
  )
  SELECT 'AN_no_dynamic_remission_cooperation'::text,
         'every active cooperation_agreement must carry an active instrument_version_bindings row pinning the IP policy to a hard document_versions.id (referenced doc_type=policy, status=active) — never a free-text "Política vigente" dynamic remission. The Adendo de PI aos Acordos de Cooperação (cooperation_addendum, under_review at mig 20260805000302) PROPOSES to import the IP policy into all 4 bilateral agreements; this invariant is GATED on an active (ratified) cooperation_addendum and is dormant until then — pre-ratification no ratified instrument obliges the agreements to pin the policy (legal review 2026-06-30, SPEC §9.7). #974 PR-2 materializes 4 anticipatory pins now (pinned_version_id is NOT NULL by table constraint, so the pin can never be a dynamic reference). Once a cooperation_addendum ratifies, an active cooperation_agreement with no active policy pin = dynamic remission reintroduced (#974, mig 20260805000302). Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AO (#1269) regression guard for the dual-write leave-tribe orphan surfaced by live QA on
  -- 2026-07-10 (Andre Abreu, tribe 7). See AG (the opposite direction) and mig 20260805000396 (#1270).
  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id
    FROM public.members m
    JOIN public.initiatives i ON i.legacy_tribe_id = m.tribe_id AND i.kind = 'research_tribe'
    WHERE m.member_status = 'active'
      AND m.tribe_id IS NOT NULL
      AND m.person_id IS NOT NULL
      AND m.name NOT LIKE '%_synthetic%'
      AND EXISTS (
        SELECT 1 FROM public.engagements e
        WHERE e.person_id = m.person_id AND e.initiative_id = i.id
          AND e.kind = 'volunteer' AND e.status IN ('offboarded','expired')
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.engagements e2
        JOIN public.initiatives i2 ON i2.id = e2.initiative_id AND i2.kind = 'research_tribe'
        WHERE e2.person_id = m.person_id AND e2.kind = 'volunteer' AND e2.status = 'active'
      )
  )
  SELECT 'AO_active_member_stale_tribe_id_after_leave'::text,
         'an active member whose members.tribe_id points at a research_tribe they already LEFT (a terminal offboarded/expired volunteer engagement on that initiative) while holding NO active research_tribe engagement. The dual-write leave-tribe orphan surfaced by live QA on 2026-07-10 (Andre Abreu, tribe 7): the pre-#1270 demotion path cleared only ONE of members.tribe_id/initiative_id, so the bridge BEFORE trigger re-derived the stale side and the member was stranded in a cannot-leave empty-state while inflating count_tribe_slots. The #1270 fix (mig 20260805000396) now clears BOTH columns on demotion; this invariant is the periodic detector for any residual or bypass orphan (service_role direct write, pre-fix staleness). It deliberately does NOT flag legacy select_tribe members (engagement absent, not terminal) who keep a legitimate tribe_id with no engagement. Opposite-direction complement to AG. Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AP (#1221 fatia 1 / ADR-0121): interim leader-grant reversion integrity. The interim grant
  -- (engagements.metadata->>'interim_grant' = true) activates authority AHEAD of the signed term;
  -- when the real term is signed the engagement gets agreement_certificate_id AND the interim flag
  -- MUST be removed (ADR-0121 reversion rule). A row carrying BOTH is a stale interim grant whose flag
  -- was never reverted. Deferred from #1117. Baseline 0 (zero interim_grant flags live 2026-07-10).
  RETURN QUERY
  WITH drift AS (
    SELECT e.id AS engagement_id
    FROM public.engagements e
    WHERE COALESCE((e.metadata ->> 'interim_grant')::boolean, false) = true
      AND e.agreement_certificate_id IS NOT NULL
  )
  SELECT 'AP_interim_grant_reverted_when_cert_issued'::text,
         'an engagement carrying metadata->>''interim_grant''=true must NOT also have agreement_certificate_id set: the ADR-0121 interim leader-grant (mig 20260805000341) activates authority ahead of the signed volunteer term, and when the real term is signed (agreement_certificate_id set) the interim flag MUST be removed (the reversion rule). A row with both is a stale interim grant whose flag was never reverted — the engagement is authoritative via TWO paths at once, masking whether authority still rests on the honest-but-reversible interim basis. Deferred from #1117. Baseline 0 (zero interim_grant flags live 2026-07-10).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;


  -- AQ (#2104): a SEDE e resolvida ATRAVES de partner_chapters nos ramos president_go e
  -- cert_director_go. Sem a linha do contratante, os dois portoes negam em SILENCIO, que e
  -- a classe de falha mais cara. Este invariante converte o silencio em ruido alto.
  RETURN QUERY
  WITH drift AS (
    SELECT cr.id AS chapter_id
    FROM public.chapter_registry cr
    WHERE cr.is_contracting_chapter
      AND NOT EXISTS (SELECT 1 FROM public.partner_chapters pc
                      WHERE pc.registry_chapter_code = cr.chapter_code)
  )
  SELECT 'AQ_contracting_chapter_has_participation'::text,
         'o capitulo contratante tem de ter linha em partner_chapters: _can_sign_gate resolve a SEDE atraves dessa tabela nos ramos president_go e cert_director_go (#2104). Sem a linha, os dois portoes negam em SILENCIO.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(chapter_id ORDER BY chapter_id) FROM (SELECT chapter_id FROM drift LIMIT 10) s)
  FROM drift;


END;
$function$;

-- get_cycle_renewal_radar
CREATE OR REPLACE FUNCTION public.get_cycle_renewal_radar(p_as_of date DEFAULT CURRENT_DATE)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE  -- writes one LGPD Art. 37 pii_access_log row (the member email/name list is a nominal PII read)
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result    jsonb;
BEGIN
  -- LGPD dual-consumer gate (this RPC returns member PII):
  --   • in-app GP/manager  → auth.uid() set + can_by_member(manage_member)
  --   • operator/cron (MCP)→ service_role/postgres (already holds table-level read; the RPC just
  --     packages the cross-join). Blocks anon + authenticated non-GP.
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_member action';
    END IF;
  ELSIF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Unauthorized: authentication required';
  END IF;

  WITH active_vol AS (
    SELECT e.id            AS engagement_id,
           e.role,
           e.initiative_id,
           e.end_date      AS engagement_end_date,
           e.selection_application_id AS linked_app_id,
           e.agreement_certificate_id,
           m.id            AS member_id,
           m.name          AS member_name,
           m.email,
           m.operational_role,
           -- Full email set (primary + alternates) — faithful "by member" resolution (p277 inv. R).
           ( SELECT array_agg(DISTINCT lower(x)) FILTER (WHERE x IS NOT NULL)
             FROM ( SELECT m.email AS x
                    UNION
                    SELECT me.email FROM public.member_emails me WHERE me.member_id = m.id ) s
           )               AS email_set
    FROM public.engagements e
    JOIN public.members m ON m.person_id = e.person_id
    WHERE e.status = 'active' AND e.revoked_at IS NULL AND e.kind = 'volunteer'
  ),
  resolved AS (
    SELECT av.*,
           la.service_latest_end_date AS linked_service_end,
           em.email_max_end,
           em.email_max_end_cycle,
           cert.period_end AS cert_period_end,
           EXISTS (
             -- per-engagement precision: does a renewal application forward-link to THIS engagement?
             -- (an email-set match would false-positive for members holding two active engagements)
             SELECT 1 FROM public.selection_applications a
             WHERE a.renews_engagement_id = av.engagement_id
           ) AS renewal_link_present
    FROM active_vol av
    LEFT JOIN public.selection_applications la ON la.id = av.linked_app_id
    LEFT JOIN LATERAL (
      -- #1021 FIX: furthest VEP service-end across ALL apps matched to the member's email set (incl.
      -- the linked one), not just the FK-linked app. Carries the originating cycle for staleness judgement.
      SELECT a.service_latest_end_date AS email_max_end, sc.cycle_code AS email_max_end_cycle
      FROM public.selection_applications a
      LEFT JOIN public.selection_cycles sc ON sc.id = a.cycle_id
      WHERE lower(a.email) = ANY(av.email_set) AND a.service_latest_end_date IS NOT NULL
      ORDER BY a.service_latest_end_date DESC
      LIMIT 1
    ) em ON true
    LEFT JOIN public.certificates cert ON cert.id = av.agreement_certificate_id
  ),
  classified AS (
    SELECT r.*,
           r.email_max_end AS resolved_service_end,
           CASE
             WHEN r.email_max_end IS NULL THEN 'unknown'
             WHEN r.linked_service_end IS NOT NULL AND r.linked_service_end = r.email_max_end THEN 'linked'
             ELSE 'email_matched'
           END AS service_end_source,
           CASE
             WHEN r.email_max_end IS NULL THEN 'unknown'
             WHEN r.email_max_end <= p_as_of THEN 'lapsing'
             ELSE 'active_future'
           END AS renews_signal
    FROM resolved r
  )
  SELECT jsonb_build_object(
    'as_of', p_as_of,
    'summary', jsonb_build_object(
      'total_active_volunteer_engagements', count(*),
      'distinct_members',        count(DISTINCT member_id),
      'service_end_resolved',    count(*) FILTER (WHERE service_end_source <> 'unknown'),
      'recovered_by_email',      count(*) FILTER (WHERE service_end_source = 'email_matched'),
      'unknown',                 count(*) FILTER (WHERE service_end_source = 'unknown'),
      'lapsing',                 count(*) FILTER (WHERE renews_signal = 'lapsing'),
      'active_future',           count(*) FILTER (WHERE renews_signal = 'active_future'),
      'renewal_link_present',    count(*) FILTER (WHERE renewal_link_present)
    ),
    'members', COALESCE(jsonb_agg(
      jsonb_build_object(
        'member_id',            member_id,
        'member_name',          member_name,
        'email',                email,
        'role',                 role,
        'operational_role',     operational_role,
        'initiative_title',     (SELECT i.title FROM public.initiatives i WHERE i.id = classified.initiative_id),
        'engagement_end_date',  engagement_end_date,
        'linked_service_end',   linked_service_end,
        'resolved_service_end', resolved_service_end,
        'service_end_source',   service_end_source,
        'resolved_from_cycle',  CASE WHEN service_end_source = 'email_matched' THEN email_max_end_cycle ELSE NULL END,
        'cert_period_end',      cert_period_end,
        'renews_signal',        renews_signal,
        'renewal_link_present', renewal_link_present
      )
      ORDER BY
        CASE renews_signal WHEN 'lapsing' THEN 0 WHEN 'unknown' THEN 1 ELSE 2 END,
        member_name
    ), '[]'::jsonb)
  ) INTO v_result
  FROM classified;

  -- LGPD Art. 37: instrument the nominal PII read (member name/email list), matching every other
  -- list-reader RPC that returns member email (get_tribe_member_contacts, admin_list_members_with_pii,
  -- #999 verify_member_affiliations_bulk). Silently no-ops for the service_role/operator path
  -- (auth.uid() NULL → returns 0) and for an empty cohort (empty array → returns 0).
  PERFORM public.log_pii_access_batch(
    ARRAY(SELECT DISTINCT (elem->>'member_id')::uuid FROM jsonb_array_elements(v_result->'members') elem),
    ARRAY['name','email','operational_role','service_latest_end_date'],
    'get_cycle_renewal_radar',
    'cycle-turn renewal report as_of ' || p_as_of::text
  );

  RETURN v_result;
END;
$function$;

-- get_entry_chapter_diagnosis
CREATE OR REPLACE FUNCTION public.get_entry_chapter_diagnosis(p_cycle_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(application_id uuid, member_id uuid, applicant_name text, bucket text, active_br_codes text[], entry_chapter_code text, member_chapter text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id  uuid := p_cycle_id;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: get_entry_chapter_diagnosis requires manage_platform';
    END IF;
  ELSIF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Unauthorized: get_entry_chapter_diagnosis requires authentication';
  END IF;

  -- #1801 — era `ORDER BY sc.created_at DESC LIMIT 1`.
  IF v_cycle_id IS NULL THEN
    v_cycle_id := public.selection_active_cycle_id();
  END IF;

  RETURN QUERY
  SELECT
    sa.id,
    m.id,
    sa.applicant_name,
    (cls->>'bucket')::text,
    ARRAY(SELECT jsonb_array_elements_text(cls->'active_br_codes')),
    m.entry_chapter_code,
    m.chapter
  FROM public.selection_applications sa
  LEFT JOIN public.members m ON lower(m.email) = lower(sa.email)
  CROSS JOIN LATERAL public.classify_entry_chapter(
    sa.pmi_memberships, sa.community_profile_private, sa.pmi_data_fetched_at
  ) AS cls
  WHERE sa.cycle_id = v_cycle_id
    AND sa.status = 'approved'
  ORDER BY sa.applicant_name;
END;
$function$;

-- list_initiatives_missing_drive_workspace
CREATE OR REPLACE FUNCTION public.list_initiatives_missing_drive_workspace()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_rows jsonb; v_caller_id uuid; v_system boolean;
BEGIN
  -- GP-or-system. `current_caller_role()` (=auth.role()) is NULL when pg_cron invokes SQL directly,
  -- so we use the established cron-context bypass (ADR-0028 p89) that also matches service_role via
  -- PostgREST and the GP JWT path. Harmless read (titles + counts, no PII).
  v_system := (NOT public._request_is_rest_caller());
  IF NOT v_system THEN
    v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: GP only (manage_platform)';
    END IF;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'initiative_id', i.id, 'title', i.title, 'kind', i.kind,
           'created_at', i.created_at,
           'active_members', (SELECT count(DISTINCT e.person_id) FROM public.engagements e
                              WHERE e.initiative_id = i.id AND e.status='active')
         ) ORDER BY i.created_at), '[]'::jsonb)
  INTO v_rows
  FROM public.initiatives i
  WHERE i.status = 'active'
    AND i.kind IN ('research_tribe','workgroup')
    AND NOT EXISTS (SELECT 1 FROM public.initiative_drive_links l
                    WHERE l.initiative_id = i.id AND l.unlinked_at IS NULL AND l.link_purpose='workspace');
  RETURN v_rows;
END;
$$;

-- member_resolve_email
CREATE OR REPLACE FUNCTION public.member_resolve_email(p_email text)
RETURNS uuid
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_member_id uuid;
BEGIN
  IF auth.uid() IS NULL
     AND public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- ADR-0095 §4, emenda de 2026-09-25: com cadastro aberto, "qualquer autenticado" e qualquer
  -- pessoa, entao resolver e-mail passa a exigir MEMBRO. service_role e cron seguem pelo GUC de role.
  IF public._request_is_rest_caller() AND NOT public.rls_is_member() THEN
    RAISE EXCEPTION 'Unauthorized: member_resolve_email requires membership';
  END IF;

  SELECT me.member_id INTO v_member_id
  FROM public.member_emails me
  WHERE me.email = p_email::citext
  LIMIT 1;

  RETURN v_member_id;
END;
$$;

-- notify_missing_drive_workspaces
CREATE OR REPLACE FUNCTION public.notify_missing_drive_workspaces()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_missing jsonb; v_n int; v_gp uuid;
BEGIN
  -- Invoked by pg_cron (weekly) directly via SQL → no PostgREST JWT context, so auth.role() is NULL.
  -- Accept the cron context (postgres/supabase_admin) OR service_role (ADR-0028 p89 cron-bypass).
  IF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'service-role or cron only';
  END IF;
  v_missing := public.list_initiatives_missing_drive_workspace();
  v_n := jsonb_array_length(coalesce(v_missing,'[]'::jsonb));
  IF v_n = 0 THEN RETURN jsonb_build_object('missing', 0); END IF;

  FOR v_gp IN
    SELECT m.id FROM public.members m
    WHERE m.member_status='active' AND public.can_by_member(m.id,'manage_platform')
  LOOP
    PERFORM public.create_notification(
      v_gp,
      'drive_workspace_missing'::text,
      (v_n::text || ' tribo(s)/workgroup(s) ativo(s) sem pasta Drive de workspace')::text,
      'Novas iniciativas foram criadas sem pasta de Drive. Provisione via MCP (provision_initiative_drive) — cria a subpasta, vincula e concede acesso ao roster. #1376.'::text,
      NULL::text, 'drive_membership_grants'::text, NULL::uuid);
  END LOOP;

  RETURN jsonb_build_object('missing', v_n, 'items', v_missing);
END;
$$;

-- nudge_entry_chapter_cohort
CREATE OR REPLACE FUNCTION public.nudge_entry_chapter_cohort(
  p_cycle_id uuid DEFAULT NULL,
  p_dry_run  boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_rec       record;
  v_title     text;
  v_body      text;
  v_sent      int := 0;
  v_skipped   int := 0;
  v_plan      jsonb := '[]'::jsonb;
BEGIN
  -- manage_platform, or service_role/postgres (cron/tests) — same gate as get_entry_chapter_diagnosis.
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: nudge_entry_chapter_cohort requires manage_platform';
    END IF;
  ELSIF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Unauthorized: nudge_entry_chapter_cohort requires authentication';
  END IF;

  FOR v_rec IN
    SELECT d.member_id, d.applicant_name, d.bucket
    FROM public.get_entry_chapter_diagnosis(p_cycle_id) d
    WHERE d.member_id IS NOT NULL
      AND d.entry_chapter_code IS NULL
      AND d.bucket IN ('ambiguous', 'profile_private', 'no_fetch', 'not_affiliated')
    ORDER BY d.applicant_name
  LOOP
    v_title := CASE v_rec.bucket
      WHEN 'ambiguous'       THEN 'Escolha seu capítulo de entrada no Núcleo'
      WHEN 'profile_private' THEN 'Deixe seu perfil PMI público para confirmarmos seu capítulo'
      WHEN 'no_fetch'        THEN 'Vincule seu perfil PMI para definir seu capítulo de entrada'
      ELSE                        'Confirme sua filiação PMI para definir seu capítulo de entrada'
    END;
    v_body := CASE v_rec.bucket
      WHEN 'ambiguous' THEN
        'Encontramos mais de um capítulo PMI ativo na sua filiação. Escolha por qual capítulo você entra no Núcleo para ajustarmos a governança e os indicadores do seu capítulo. Leva um clique no seu perfil.'
      WHEN 'profile_private' THEN
        'Seu perfil no community.pmi.org está com a visibilidade privada, então não conseguimos ler seus capítulos para definir seu capítulo de entrada no Núcleo. Acesse community.pmi.org, deixe seu perfil público (ao menos a seção de capítulos) e nós atualizamos automaticamente.'
      WHEN 'no_fetch' THEN
        'Ainda não localizamos seu perfil no community.pmi.org. Se você tem filiação PMI, confira se o perfil está criado e público em community.pmi.org para confirmarmos seu capítulo de entrada no Núcleo automaticamente.'
      ELSE
        'Não conseguimos confirmar uma filiação PMI ativa no seu perfil do community.pmi.org. Para registrarmos seu capítulo de entrada no Núcleo, verifique se sua filiação PMI está ativa e se o capítulo aparece no seu perfil em community.pmi.org. Assim que estiver regular, atualizamos automaticamente.'
    END;

    v_plan := v_plan || jsonb_build_object(
      'member_id', v_rec.member_id,
      'name', v_rec.applicant_name,
      'bucket', v_rec.bucket,
      'title', v_title
    );

    IF p_dry_run THEN
      CONTINUE;
    END IF;

    -- Dedup: do not re-fire if this member already got the nudge in the last 30 days.
    IF EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = v_rec.member_id
        AND n.type = 'entry_chapter_action_needed'
        AND n.created_at > now() - interval '30 days'
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    PERFORM public.create_notification(
      v_rec.member_id,
      'entry_chapter_action_needed',
      v_title,
      v_body,
      '/profile#entry-chapter-card'
    );
    v_sent := v_sent + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'cycle_id', p_cycle_id,
    'candidates', jsonb_array_length(v_plan),
    'sent', v_sent,
    'skipped_recent', v_skipped,
    'plan', v_plan
  );
END;
$function$;

-- record_drive_discovery
CREATE OR REPLACE FUNCTION public.record_drive_discovery(
  p_initiative_drive_link_id uuid,
  p_drive_file_id text,
  p_drive_file_url text,
  p_filename text,
  p_mime_type text DEFAULT NULL,
  p_size_bytes bigint DEFAULT NULL,
  p_drive_modified_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_initiative_id uuid;
  v_existing_id uuid;
  v_new_id uuid;
  v_filename_date date;
  v_matched_event_id uuid;
  v_match_strategy text := 'unmatched';
  v_match_confidence text := 'none';
  v_event_minutes_url text;
  v_event_date date;
  v_auto_promoted boolean := false;
BEGIN
  -- Caller authorization: service_role only (cron) OR view_internal_analytics
  IF public._request_is_rest_caller() THEN
    DECLARE
      v_caller_id uuid;
    BEGIN
      SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
      IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
        RETURN jsonb_build_object('error', 'Unauthorized: requires service_role or view_internal_analytics');
      END IF;
    END;
  END IF;

  -- Idempotent: skip if already discovered
  SELECT id INTO v_existing_id FROM public.drive_file_discoveries
  WHERE drive_file_id = p_drive_file_id;
  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object('is_new', false, 'discovery_id', v_existing_id);
  END IF;

  -- Resolve initiative
  SELECT initiative_id INTO v_initiative_id
  FROM public.initiative_drive_links
  WHERE id = p_initiative_drive_link_id AND unlinked_at IS NULL;
  IF v_initiative_id IS NULL THEN
    RETURN jsonb_build_object('error', 'initiative_drive_link not found or unlinked');
  END IF;

  -- Try filename date heuristic
  v_filename_date := public._extract_date_from_filename(p_filename);
  IF v_filename_date IS NOT NULL THEN
    SELECT e.id, e.minutes_url, e.date
      INTO v_matched_event_id, v_event_minutes_url, v_event_date
    FROM public.events e
    WHERE e.initiative_id = v_initiative_id
      AND e.date BETWEEN v_filename_date - INTERVAL '7 days' AND v_filename_date + INTERVAL '7 days'
    ORDER BY ABS(e.date - v_filename_date)
    LIMIT 1;

    IF v_matched_event_id IS NOT NULL THEN
      v_match_strategy := 'filename_date';
      v_match_confidence := CASE
        WHEN v_filename_date = v_event_date THEN 'high'
        WHEN ABS(v_filename_date - v_event_date) <= 1 THEN 'medium'
        ELSE 'low'
      END;
      -- Auto-promote: only if event has no minutes_url yet
      IF v_event_minutes_url IS NULL THEN
        UPDATE public.events
        SET minutes_url = p_drive_file_url,
            minutes_posted_at = COALESCE(p_drive_modified_at, now()),
            updated_at = now()
        WHERE id = v_matched_event_id;
        v_auto_promoted := true;
      END IF;
    END IF;
  END IF;

  -- INSERT discovery
  INSERT INTO public.drive_file_discoveries (
    initiative_drive_link_id, drive_file_id, drive_file_url, filename,
    mime_type, size_bytes, drive_modified_at,
    matched_event_id, match_strategy, match_confidence,
    promoted_to_minutes_url, promoted_at, promoted_by
  ) VALUES (
    p_initiative_drive_link_id, p_drive_file_id, p_drive_file_url, p_filename,
    p_mime_type, p_size_bytes, p_drive_modified_at,
    v_matched_event_id, v_match_strategy, v_match_confidence,
    v_auto_promoted, CASE WHEN v_auto_promoted THEN now() ELSE NULL END, NULL
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'is_new', true,
    'discovery_id', v_new_id,
    'matched_event_id', v_matched_event_id,
    'match_strategy', v_match_strategy,
    'match_confidence', v_match_confidence,
    'auto_promoted', v_auto_promoted
  );
END;
$$;

