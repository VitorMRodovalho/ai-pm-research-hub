-- Track Q-B Phase B (2-touch drift diff) — drift-correction batch 4 partial (10 fns)
--
-- Captures live `pg_get_functiondef` body as-of 2026-04-25 for 10 of the 35
-- two-migration-touched (2-touch) functions where the live body diverged
-- from the latest migration capture.
--
-- 2-touch drift rate: 35/96 = 36.5% (HIGHEST of all buckets — confirms
-- older-fns-drift-more theory). 5+ migrations had 40%, 4-touch 26.5%,
-- 3-touch 32%, 2-touch 36.5%. Non-monotonic distribution.
--
-- This migration captures 10 of the 35 drifted fns prioritizing high-impact
-- and small-but-recently-touched fns. The remaining 25 drifted are documented
-- in `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md` Phase B section as continuation
-- work for next session.
--
-- Captured (10):
--   _enqueue_gate_notifications  (10KB IP gate notification engine — ~80% of
--     the IP-1 ratification flow's notification dispatch logic)
--   finalize_decisions           (7KB selection cycle decision committer —
--     creates members, seeds onboarding, audit, dispatches notifications)
--   _delivery_mode_for           (1.3KB ADR-0022 W1 delivery routing —
--     19 notification types mapped to delivery modes)
--   broadcast_count_today        (0.2KB tribe-broadcast counter via initiative)
--   exec_chapter_roi             (1.7KB chapter ROI exec view via
--     analytics_member_scope)
--   get_my_certificates          (1KB member-self cert listing)
--   get_publication_submissions  (0.6KB publication submissions reader)
--   log_webinar_created          (0.5KB webinar lifecycle event trigger)
--   set_curation_due_date        (0.5KB curation SLA trigger)
--   trg_document_version_immutable (0.7KB document version lock trigger)
--
-- 25 drifted fns NOT captured here (Phase B batch 4 continuation):
--   admin_inactivate_member, admin_link_communication_boards,
--   admin_list_members, admin_send_campaign, admin_update_member_audited,
--   get_audit_log, get_cycle_evolution, get_diversity_dashboard,
--   get_ghost_visitors, get_initiative_events_timeline, get_initiative_stats,
--   get_kpi_dashboard, get_member_detail, get_ratification_reminder_targets,
--   get_selection_dashboard, get_version_diff, import_vep_applications,
--   list_pending_curation, manage_initiative_engagement, offboard_member,
--   register_own_presence, submit_curation_review, submit_interview_scores,
--   try_auto_link_ghost, upsert_event_minutes.
--
-- 61 clean fns (no drift, no migration needed): see
-- `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md` Phase B section for full list.
--
-- Bodies preserved verbatim from `pg_get_functiondef`. CREATE OR REPLACE
-- is idempotent on existing live state. Dollar-quote tag `$$` (verified
-- safe — no `$$` literals in any body).

CREATE OR REPLACE FUNCTION public._enqueue_gate_notifications(p_chain_id uuid, p_event text, p_gate_kind text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_chain record; v_doc record; v_version record; v_submitter record;
  v_gate jsonb; v_target record; v_link text; v_title text; v_body text;
  v_notif_type text; v_enqueued int := 0;
  v_action_label text; v_role_singular text; v_action_verb text;
BEGIN
  IF p_event NOT IN ('chain_opened','gate_advanced','chain_approved') THEN
    RAISE EXCEPTION 'Invalid event: %', p_event USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id, ac.opened_by
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN 0; END IF;

  SELECT gd.id, gd.title, gd.doc_type INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT dv.id, dv.version_label INTO v_version
  FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT m.id, m.name, m.email INTO v_submitter
  FROM public.members m WHERE m.id = v_chain.opened_by;

  IF p_event = 'chain_opened' THEN
    SELECT g INTO v_gate FROM jsonb_array_elements(v_chain.gates) g
    ORDER BY (g->>'order')::int ASC LIMIT 1;
    IF v_gate IS NULL THEN RETURN 0; END IF;

    v_link := public._ip_ratify_cta_link(p_chain_id, v_gate->>'kind');
    v_notif_type := 'ip_ratification_gate_pending';

    v_action_label := CASE v_gate->>'kind'
      WHEN 'curator' THEN 'Curadoria'
      WHEN 'leader_awareness' THEN 'Ciencia da lideranca'
      WHEN 'submitter_acceptance' THEN 'Aceite do GP'
      WHEN 'chapter_witness' THEN 'Testemunho de capitulo'
      WHEN 'president_go' THEN 'Assinatura da presidencia PMI-GO'
      WHEN 'president_others' THEN 'Assinatura de presidencia de capitulo'
      WHEN 'volunteers_in_role_active' THEN 'Ratificacao de voluntario em funcao ativa'
      WHEN 'member_ratification' THEN 'Ratificacao de membro'
      ELSE v_gate->>'kind' END;
    v_role_singular := CASE v_gate->>'kind'
      WHEN 'curator' THEN 'curador(a)'
      WHEN 'leader_awareness' THEN 'lider do Nucleo'
      WHEN 'submitter_acceptance' THEN 'Gerente de Projeto'
      WHEN 'chapter_witness' THEN 'ponto focal do seu capitulo'
      WHEN 'president_go' THEN 'presidencia do PMI-GO'
      WHEN 'president_others' THEN 'presidencia do seu capitulo'
      WHEN 'volunteers_in_role_active' THEN 'voluntario(a) em funcao ativa'
      WHEN 'member_ratification' THEN 'membro ativo'
      ELSE v_gate->>'kind' END;
    v_action_verb := CASE v_gate->>'kind'
      WHEN 'curator' THEN 'ler o documento completo e decidir se ele avanca para a fase de aprovacao pelas presidencias de capitulo. Voce pode registrar duvidas ou pontos de ajuste como comentarios antes de aprovar'
      WHEN 'leader_awareness' THEN 'ler o documento e registrar ciencia. Este passo nao bloqueia o workflow, mas formaliza que a lideranca esta ciente do que sera ratificado'
      WHEN 'submitter_acceptance' THEN 'confirmar formalmente que o documento esta pronto para circular as presidencias de capitulo'
      WHEN 'chapter_witness' THEN 'confirmar que o documento foi apresentado e e de conhecimento dos membros do seu capitulo'
      WHEN 'president_go' THEN 'ler e assinar como presidencia do capitulo-sede. Apos sua assinatura, as demais presidencias serao notificadas'
      WHEN 'president_others' THEN 'ler e assinar como presidencia do seu capitulo, apos a presidencia PMI-GO ja ter assinado'
      WHEN 'volunteers_in_role_active' THEN 'ler o documento e ratificar como voluntario(a) em funcao ativa. Sua ratificacao formaliza a adesao pessoal aos termos atualizados enquanto voce mantem funcao ativa no Nucleo'
      WHEN 'member_ratification' THEN 'ler o documento e ratificar como membro ativo. Sua ratificacao formaliza a adesao pessoal aos termos'
      ELSE 'revisar e agir conforme o seu papel neste workflow' END;

    FOR v_target IN
      SELECT m.id AS member_id, m.name FROM public.members m
      WHERE m.is_active = true
        AND public._can_sign_gate(m.id, p_chain_id, v_gate->>'kind')
        AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
          WHERE s.approval_chain_id = p_chain_id
            AND s.gate_kind = v_gate->>'kind' AND s.signer_id = m.id)
    LOOP
      v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                 ' — ' || v_action_label || ' solicitada por ' || COALESCE(v_submitter.name, 'Gerente de Projeto');
      v_body := COALESCE(v_submitter.name, 'O Gerente de Projeto') ||
                ' submeteu o documento "' || v_doc.title || '" versao ' ||
                COALESCE(v_version.version_label,'') || ' para ratificacao no Nucleo IA & GP. ' ||
                'Como ' || v_role_singular || ', voce deve ' || v_action_verb || '.';
      PERFORM public.create_notification(
        v_target.member_id, v_notif_type, v_title, v_body, v_link,
        'approval_chain', p_chain_id);
      v_enqueued := v_enqueued + 1;
    END LOOP;
    RETURN v_enqueued;
  END IF;

  IF p_event = 'gate_advanced' AND p_gate_kind IS NOT NULL THEN
    SELECT g INTO v_gate FROM jsonb_array_elements(v_chain.gates) g
    WHERE (g->>'order')::int > (
      SELECT (g2->>'order')::int FROM jsonb_array_elements(v_chain.gates) g2
      WHERE g2->>'kind' = p_gate_kind LIMIT 1)
    ORDER BY (g->>'order')::int ASC LIMIT 1;

    IF v_gate IS NOT NULL THEN
      v_link := public._ip_ratify_cta_link(p_chain_id, v_gate->>'kind');
      v_notif_type := CASE WHEN (v_gate->>'kind') IN ('volunteers_in_role_active','member_ratification')
                          THEN 'ip_ratification_awaiting_members'
                          ELSE 'ip_ratification_gate_pending' END;

      v_action_label := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'Curadoria'
        WHEN 'leader_awareness' THEN 'Ciencia da lideranca'
        WHEN 'submitter_acceptance' THEN 'Aceite do GP'
        WHEN 'chapter_witness' THEN 'Testemunho de capitulo'
        WHEN 'president_go' THEN 'Assinatura da presidencia PMI-GO'
        WHEN 'president_others' THEN 'Assinatura de presidencia de capitulo'
        WHEN 'volunteers_in_role_active' THEN 'Ratificacao de voluntario em funcao ativa'
        WHEN 'member_ratification' THEN 'Ratificacao de membro'
        ELSE v_gate->>'kind' END;
      v_role_singular := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'curador(a)'
        WHEN 'leader_awareness' THEN 'lider do Nucleo'
        WHEN 'submitter_acceptance' THEN 'Gerente de Projeto'
        WHEN 'chapter_witness' THEN 'ponto focal do seu capitulo'
        WHEN 'president_go' THEN 'presidencia do PMI-GO'
        WHEN 'president_others' THEN 'presidencia do seu capitulo'
        WHEN 'volunteers_in_role_active' THEN 'voluntario(a) em funcao ativa'
        WHEN 'member_ratification' THEN 'membro ativo'
        ELSE v_gate->>'kind' END;
      v_action_verb := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'ler o documento e aprovar como curador'
        WHEN 'leader_awareness' THEN 'ler e registrar ciencia'
        WHEN 'submitter_acceptance' THEN 'confirmar que esta pronto para circular presidencias'
        WHEN 'chapter_witness' THEN 'confirmar como ponto focal do seu capitulo'
        WHEN 'president_go' THEN 'assinar como presidencia PMI-GO'
        WHEN 'president_others' THEN 'assinar como presidencia de capitulo'
        WHEN 'volunteers_in_role_active' THEN 'ratificar como voluntario(a) em funcao ativa'
        WHEN 'member_ratification' THEN 'ratificar como membro ativo'
        ELSE 'agir conforme seu papel' END;

      FOR v_target IN
        SELECT m.id AS member_id, m.name FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, p_chain_id, v_gate->>'kind')
          AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
            WHERE s.approval_chain_id = p_chain_id
              AND s.gate_kind = v_gate->>'kind' AND s.signer_id = m.id)
      LOOP
        v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                   ' — sua ' || lower(v_action_label) || ' agora e necessaria';
        v_body := 'O gate anterior foi satisfeito. Voce esta agora elegivel para ' ||
                  v_action_verb || ' no documento "' || v_doc.title || '" versao ' ||
                  COALESCE(v_version.version_label,'') ||
                  ', submetido por ' || COALESCE(v_submitter.name, 'Gerente de Projeto') ||
                  ' para ratificacao no Nucleo IA & GP. Como ' || v_role_singular || ', ' || v_action_verb || '.';
        PERFORM public.create_notification(
          v_target.member_id, v_notif_type, v_title, v_body, v_link,
          'approval_chain', p_chain_id);
        v_enqueued := v_enqueued + 1;
      END LOOP;
    END IF;

    IF v_submitter.id IS NOT NULL THEN
      v_link := '/admin/governance/documents/' || p_chain_id::text;
      v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                 ' — gate "' || p_gate_kind || '" satisfeito';
      v_body := 'O gate "' || p_gate_kind || '" da cadeia de ratificacao do documento "' ||
                v_doc.title || '" versao ' || COALESCE(v_version.version_label,'') ||
                ' foi satisfeito. O workflow avancou automaticamente. Acompanhe o progresso dos proximos gates na plataforma.';
      PERFORM public.create_notification(
        v_submitter.id, 'ip_ratification_gate_advanced', v_title, v_body, v_link,
        'approval_chain', p_chain_id);
      v_enqueued := v_enqueued + 1;
    END IF;
    RETURN v_enqueued;
  END IF;

  IF p_event = 'chain_approved' AND v_submitter.id IS NOT NULL THEN
    v_link := '/admin/governance/documents/' || p_chain_id::text;
    v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
               ' — cadeia de ratificacao concluida';
    v_body := 'Todos os gates da cadeia de ratificacao do documento "' || v_doc.title ||
              '" versao ' || COALESCE(v_version.version_label,'') ||
              ' foram satisfeitos. O documento pode ser ativado como vigente no Nucleo IA & GP.';
    PERFORM public.create_notification(
      v_submitter.id, 'ip_ratification_chain_approved', v_title, v_body, v_link,
      'approval_chain', p_chain_id);
    RETURN 1;
  END IF;

  RETURN 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_decisions(p_cycle_id uuid, p_decisions jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_committee record;
  v_decision jsonb;
  v_app_id uuid;
  v_app record;
  v_status text;
  v_feedback text;
  v_convert_to text;
  v_approved_count int := 0;
  v_rejected_count int := 0;
  v_waitlisted_count int := 0;
  v_converted_count int := 0;
  v_created_members int := 0;
  v_member_id uuid;
  v_has_partner boolean;
BEGIN
  -- Auth: committee lead or superadmin
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_committee FROM selection_committee
  WHERE cycle_id = p_cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND v_caller.is_superadmin IS NOT TRUE
     AND v_caller.operational_role NOT IN ('manager', 'deputy_manager') THEN
    RETURN json_build_object('error', 'Unauthorized: must be committee lead or superadmin');
  END IF;

  FOR v_decision IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    v_app_id := (v_decision->>'application_id')::uuid;
    v_status := v_decision->>'decision';
    v_feedback := v_decision->>'feedback';
    v_convert_to := v_decision->>'convert_to';

    SELECT * INTO v_app FROM selection_applications WHERE id = v_app_id AND cycle_id = p_cycle_id;
    IF NOT FOUND THEN CONTINUE; END IF;

    -- Handle conversion flow (researcher → leader)
    IF v_convert_to IS NOT NULL AND v_convert_to != '' THEN
      UPDATE selection_applications SET
        status = 'converted',
        converted_from = v_app.role_applied,
        converted_to = v_convert_to,
        conversion_reason = coalesce(v_feedback, 'Promoted by committee'),
        role_applied = v_convert_to,
        feedback = coalesce(v_feedback, feedback),
        updated_at = now()
      WHERE id = v_app_id;
      v_converted_count := v_converted_count + 1;

      -- Notify candidate with conversion offer
      PERFORM create_notification(
        m.id, 'selection_conversion_offer',
        'Proposta de conversão de papel',
        'O comitê identificou seu perfil para o papel de ' || v_convert_to || '. Acesse a plataforma para mais detalhes.',
        '/admin/selection', 'selection_application', v_app_id
      ) FROM members m WHERE m.email = v_app.email;

      CONTINUE;
    END IF;

    -- Normal decision
    UPDATE selection_applications SET
      status = v_status, feedback = coalesce(v_feedback, feedback), updated_at = now()
    WHERE id = v_app_id;

    IF v_status = 'approved' THEN
      v_approved_count := v_approved_count + 1;

      -- Partner chapter validation
      SELECT EXISTS (
        SELECT 1 FROM selection_membership_snapshots WHERE application_id = v_app_id AND is_partner_chapter = true
      ) INTO v_has_partner;
      IF NOT v_has_partner THEN
        UPDATE selection_applications SET tags = array_append(tags, 'no_partner_chapter')
        WHERE id = v_app_id AND NOT ('no_partner_chapter' = ANY(tags));
      END IF;

      -- Find or create member
      SELECT id INTO v_member_id FROM members WHERE email = v_app.email LIMIT 1;

      IF v_member_id IS NOT NULL THEN
        -- Reactivate existing member
        UPDATE members SET is_active = true, current_cycle_active = true, updated_at = now()
        WHERE id = v_member_id AND (is_active = false OR current_cycle_active = false);
      ELSE
        -- Create new member
        INSERT INTO members (name, email, pmi_id, chapter, operational_role, is_active, current_cycle_active)
        VALUES (v_app.applicant_name, v_app.email, v_app.pmi_id, v_app.chapter,
          CASE WHEN v_app.role_applied = 'leader' THEN 'tribe_leader' ELSE 'researcher' END, true, true)
        RETURNING id INTO v_member_id;
        v_created_members := v_created_members + 1;
      END IF;

      -- Seed pre-onboarding + standard onboarding steps
      INSERT INTO onboarding_progress (application_id, member_id, step_key, status, sla_deadline, metadata)
      SELECT v_app_id, v_member_id, s.key, 'pending', now() + (s.sla || ' days')::interval,
             jsonb_build_object('xp', s.xp, 'phase', 'pre_onboarding')
      FROM (VALUES ('create_account',50,7),('setup_credly',75,14),('explore_platform',50,14),('read_blog',50,14),('start_pmi_certs',150,30)) AS s(key,xp,sla)
      WHERE NOT EXISTS (SELECT 1 FROM onboarding_progress WHERE member_id = v_member_id AND step_key = s.key);

      INSERT INTO onboarding_progress (application_id, member_id, step_key, status, sla_deadline)
      SELECT v_app_id, v_member_id, (step->>'key'), 'pending', now() + ((step->>'sla_days')::int || ' days')::interval
      FROM selection_cycles sc, jsonb_array_elements(sc.onboarding_steps) AS step
      WHERE sc.id = p_cycle_id
      AND NOT EXISTS (SELECT 1 FROM onboarding_progress WHERE member_id = v_member_id AND step_key = (step->>'key'));

      PERFORM check_pre_onboarding_auto_steps(v_member_id);

      -- Notify approved member
      PERFORM create_notification(
        v_member_id, 'selection_approved',
        'Parabéns! Você foi aprovado no Núcleo IA',
        'Sua candidatura foi aprovada. Acesse a plataforma para iniciar o onboarding.',
        '/onboarding', 'selection_application', v_app_id
      );

    ELSIF v_status = 'rejected' THEN
      v_rejected_count := v_rejected_count + 1;
    ELSIF v_status = 'waitlist' THEN
      v_waitlisted_count := v_waitlisted_count + 1;
    END IF;

    -- Audit
    INSERT INTO data_anomaly_log (anomaly_type, severity, message, details)
    VALUES ('selection_decision', 'info', v_app.applicant_name || ' → ' || v_status,
      jsonb_build_object('application_id', v_app_id, 'decision', v_status, 'actor', v_caller.name));
  END LOOP;

  -- Diversity snapshot
  INSERT INTO selection_diversity_snapshots (cycle_id, snapshot_type, metrics)
  VALUES (p_cycle_id, 'approved', (
    SELECT jsonb_build_object(
      'by_chapter', (SELECT jsonb_object_agg(coalesce(chapter,'unknown'), cnt) FROM (SELECT chapter, count(*) as cnt FROM selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY chapter) x),
      'by_gender', (SELECT jsonb_object_agg(coalesce(gender,'unknown'), cnt) FROM (SELECT gender, count(*) as cnt FROM selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY gender) x),
      'by_role', (SELECT jsonb_object_agg(role_applied, cnt) FROM (SELECT role_applied, count(*) as cnt FROM selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY role_applied) x),
      'total_approved', v_approved_count, 'total_rejected', v_rejected_count,
      'total_converted', v_converted_count, 'finalized_at', now()
    )
  ));

  RETURN json_build_object(
    'approved', v_approved_count, 'rejected', v_rejected_count,
    'waitlisted', v_waitlisted_count, 'converted', v_converted_count,
    'members_created', v_created_members, 'cycle_id', p_cycle_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $$
  SELECT CASE p_type
    WHEN 'volunteer_agreement_signed'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    WHEN 'certificate_ready'             THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_advanced'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_chain_approved'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_awaiting_members' THEN 'transactional_immediate'
    WHEN 'webinar_status_confirmed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_completed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_cancelled'      THEN 'transactional_immediate'
    WHEN 'weekly_card_digest_member'     THEN 'transactional_immediate'
    WHEN 'governance_cr_new'             THEN 'transactional_immediate'
    WHEN 'governance_cr_vote'            THEN 'transactional_immediate'
    WHEN 'governance_cr_approved'        THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$$;

CREATE OR REPLACE FUNCTION public.broadcast_count_today(p_tribe_id integer)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT count(*)::integer
  FROM public.broadcast_log bl
  JOIN public.initiatives i ON i.id = bl.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id
    AND bl.sent_at >= current_date
    AND bl.status = 'sent';
$$;

CREATE OR REPLACE FUNCTION public.exec_chapter_roi(p_cycle_code text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare
  v_result jsonb;
begin
  if not public.can_read_internal_analytics() then
    raise exception 'Internal analytics access required';
  end if;

  with scoped as (
    select * from public.analytics_member_scope(p_cycle_code, p_tribe_id, p_chapter)
  ),
  -- Derive chapter affiliation from members.chapter (replaces member_chapter_affiliations table)
  affiliation_scope as (
    select distinct
      s.member_id,
      s.chapter as chapter_code,
      s.first_cycle_start,
      s.cycle_start,
      s.is_current
    from scoped s
    where s.chapter is not null and trim(s.chapter) <> ''
  )
  select jsonb_build_object(
    'cycle_code', (select max(cycle_code) from scoped),
    'cycle_label', (select max(cycle_label) from scoped),
    'attribution_window', jsonb_build_object('before_days', 30, 'after_days', 90),
    'chapters', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.attributed_conversions desc, r.chapter_code)
      from (
        select
          chapter_code,
          count(*)::integer as affiliated_members,
          count(*) filter (where is_current)::integer as current_active_affiliates,
          count(*) filter (
            where first_cycle_start is not null
              and first_cycle_start >= cycle_start - interval '30 days'
              and first_cycle_start < cycle_start + interval '90 days'
          )::integer as attributed_conversions
        from affiliation_scope
        group by chapter_code
      ) r
    ), '[]'::jsonb)
  ) into v_result;

  return coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'attribution_window', jsonb_build_object('before_days', 30, 'after_days', 90),
    'chapters', '[]'::jsonb
  ));
end;
$$;

CREATE OR REPLACE FUNCTION public.get_my_certificates(p_include_volunteer_agreements boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_member_id uuid; result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id, 'type', c.type, 'title', c.title, 'cycle', c.cycle, 'status', c.status,
    'verification_code', c.verification_code, 'issued_at', c.issued_at,
    'issued_by_name', ib.name, 'counter_signed_by_name', cs.name,
    'counter_signed_at', c.counter_signed_at, 'period_start', c.period_start,
    'period_end', c.period_end, 'language', c.language,
    'has_counter_signature', c.counter_signed_by IS NOT NULL, 'signature_hash', c.signature_hash,
    'function_role', c.function_role
  ) ORDER BY c.issued_at DESC), '[]'::jsonb) INTO result
  FROM certificates c
  LEFT JOIN members ib ON ib.id = c.issued_by
  LEFT JOIN members cs ON cs.id = c.counter_signed_by
  WHERE c.member_id = v_member_id
    AND COALESCE(c.status, 'issued') != 'revoked'
    AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement');
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_publication_submissions(p_status submission_status DEFAULT NULL::submission_status, p_tribe_id integer DEFAULT NULL::integer)
 RETURNS TABLE(id uuid, title text, abstract text, target_type submission_target_type, target_name text, status submission_status, submission_date date, presentation_date date, primary_author_name text, tribe_name text, estimated_cost_brl numeric, actual_cost_brl numeric, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ps.id, ps.title, ps.abstract, ps.target_type, ps.target_name,
    ps.status, ps.submission_date, ps.presentation_date,
    m.name AS primary_author_name,
    i.title AS tribe_name,
    ps.estimated_cost_brl, ps.actual_cost_brl, ps.created_at
  FROM public.publication_submissions ps
  LEFT JOIN public.members m ON m.id = ps.primary_author_id
  LEFT JOIN public.initiatives i ON i.id = ps.initiative_id
  WHERE (p_status IS NULL OR ps.status = p_status)
    AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
  ORDER BY ps.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_webinar_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_actor_id uuid;
  v_legacy_tribe_id int;
BEGIN
  SELECT id INTO v_actor_id FROM members WHERE auth_id = auth.uid();

  -- ADR-0015 Phase 3b: webinars.tribe_id droppado; derivar via initiative
  SELECT legacy_tribe_id INTO v_legacy_tribe_id
  FROM public.initiatives WHERE id = NEW.initiative_id;

  INSERT INTO webinar_lifecycle_events (webinar_id, action, actor_id, new_status, metadata)
  VALUES (NEW.id, 'created', v_actor_id, NEW.status,
    jsonb_build_object('chapter_code', NEW.chapter_code, 'legacy_tribe_id', v_legacy_tribe_id));

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_curation_due_date()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $$ DECLARE v_sla_days int; BEGIN IF NEW.curation_status = 'curation_pending' AND (OLD.curation_status IS DISTINCT FROM 'curation_pending') THEN SELECT sla_days INTO v_sla_days FROM board_sla_config WHERE board_id = NEW.board_id; NEW.curation_due_at := now() + make_interval(days => coalesce(v_sla_days, 7)); END IF; IF NEW.curation_status IN ('published', 'draft') AND OLD.curation_status = 'curation_pending' THEN NEW.curation_due_at := NULL; END IF; RETURN NEW; END; $$;

CREATE OR REPLACE FUNCTION public.trg_document_version_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF OLD.locked_at IS NOT NULL THEN
    IF NEW.content_html IS DISTINCT FROM OLD.content_html
       OR NEW.content_markdown IS DISTINCT FROM OLD.content_markdown
       OR NEW.version_number IS DISTINCT FROM OLD.version_number
       OR NEW.version_label IS DISTINCT FROM OLD.version_label
       OR NEW.document_id IS DISTINCT FROM OLD.document_id
       OR NEW.locked_at IS DISTINCT FROM OLD.locked_at
    THEN
      RAISE EXCEPTION 'document_versions row locked at % is immutable (id=%, document=%)', OLD.locked_at, OLD.id, OLD.document_id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;
