-- p651 / GC-097: governance gates with the same order are parallel.
-- Notify every eligible signer in the active order instead of selecting a single
-- gate with ORDER BY ... LIMIT 1.

CREATE OR REPLACE FUNCTION public._enqueue_gate_notifications(p_chain_id uuid, p_event text, p_gate_kind text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chain record;
  v_doc record;
  v_version record;
  v_submitter record;
  v_gate jsonb;
  v_target record;
  v_link text;
  v_title text;
  v_body text;
  v_notif_type text;
  v_enqueued int := 0;
  v_action_label text;
  v_role_singular text;
  v_action_verb text;
  v_current_order int;
  v_next_order int;
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
    SELECT MIN((g->>'order')::int) INTO v_next_order
    FROM jsonb_array_elements(v_chain.gates) g;

    IF v_next_order IS NULL THEN RETURN 0; END IF;

    FOR v_gate IN
      SELECT g FROM jsonb_array_elements(v_chain.gates) g
      WHERE (g->>'order')::int = v_next_order
      ORDER BY g->>'kind'
    LOOP
      v_link := public._ip_ratify_cta_link(p_chain_id, v_gate->>'kind');
      v_notif_type := 'ip_ratification_gate_pending';

      v_action_label := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'Curadoria'
        WHEN 'leader_awareness' THEN 'Ciencia da lideranca'
        WHEN 'submitter_acceptance' THEN 'Aceite do GP'
        WHEN 'chapter_witness' THEN 'Testemunho de capitulo'
        WHEN 'president_go' THEN 'Assinatura da presidencia PMI-GO'
        WHEN 'president_others' THEN 'Assinatura de presidencia de capitulo'
        WHEN 'cert_director_go' THEN 'Validacao da Diretoria de Certificacao PMI-GO'
        WHEN 'volunteers_in_role_active' THEN 'Ratificacao de voluntario em funcao ativa'
        WHEN 'member_ratification' THEN 'Ratificacao de membro'
        ELSE v_gate->>'kind'
      END;
      v_role_singular := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'curador(a)'
        WHEN 'leader_awareness' THEN 'lider do Nucleo'
        WHEN 'submitter_acceptance' THEN 'Gerente de Projeto'
        WHEN 'chapter_witness' THEN 'ponto focal do seu capitulo'
        WHEN 'president_go' THEN 'presidencia do PMI-GO'
        WHEN 'president_others' THEN 'presidencia do seu capitulo'
        WHEN 'cert_director_go' THEN 'Diretoria de Certificacao do PMI-GO'
        WHEN 'volunteers_in_role_active' THEN 'voluntario(a) em funcao ativa'
        WHEN 'member_ratification' THEN 'membro ativo'
        ELSE v_gate->>'kind'
      END;
      v_action_verb := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'ler o documento completo e decidir se ele avanca para a fase de aprovacao pelas presidencias de capitulo. Voce pode registrar duvidas ou pontos de ajuste como comentarios antes de aprovar'
        WHEN 'leader_awareness' THEN 'ler o documento e registrar ciencia. Este passo nao bloqueia o workflow, mas formaliza que a lideranca esta ciente do que sera ratificado'
        WHEN 'submitter_acceptance' THEN 'confirmar formalmente que o documento esta pronto para circular as presidencias de capitulo'
        WHEN 'chapter_witness' THEN 'confirmar que o documento foi apresentado e e de conhecimento dos membros do seu capitulo'
        WHEN 'president_go' THEN 'ler e assinar como presidencia do capitulo-sede. Apos sua assinatura, as demais presidencias serao notificadas'
        WHEN 'president_others' THEN 'ler e assinar como presidencia do seu capitulo, apos a presidencia PMI-GO ja ter assinado'
        WHEN 'cert_director_go' THEN 'validar como Diretoria de Certificacao do PMI-GO'
        WHEN 'volunteers_in_role_active' THEN 'ler o documento e ratificar como voluntario(a) em funcao ativa. Sua ratificacao formaliza a adesao pessoal aos termos atualizados enquanto voce mantem funcao ativa no Nucleo'
        WHEN 'member_ratification' THEN 'ler o documento e ratificar como membro ativo. Sua ratificacao formaliza a adesao pessoal aos termos'
        ELSE 'revisar e agir conforme o seu papel neste workflow'
      END;

      FOR v_target IN
        SELECT m.id AS member_id, m.name FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, p_chain_id, v_gate->>'kind')
          AND NOT EXISTS (
            SELECT 1 FROM public.approval_signoffs s
            WHERE s.approval_chain_id = p_chain_id
              AND s.gate_kind = v_gate->>'kind' AND s.signer_id = m.id
          )
      LOOP
        v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                   ' — ' || v_action_label || ' solicitada por ' || COALESCE(v_submitter.name, 'Gerente de Projeto');
        v_body := COALESCE(v_submitter.name, 'O Gerente de Projeto') ||
                  ' submeteu o documento "' || v_doc.title || '" versao ' ||
                  COALESCE(v_version.version_label,'') || ' para ratificacao no Nucleo IA & GP. ' ||
                  'Como ' || v_role_singular || ', voce deve ' || v_action_verb || '.';

        PERFORM public.create_notification(
          v_target.member_id, v_notif_type, v_title, v_body, v_link,
          'approval_chain', p_chain_id
        );
        v_enqueued := v_enqueued + 1;
      END LOOP;
    END LOOP;
    RETURN v_enqueued;
  END IF;

  IF p_event = 'gate_advanced' AND p_gate_kind IS NOT NULL THEN
    SELECT (g->>'order')::int INTO v_current_order
    FROM jsonb_array_elements(v_chain.gates) g
    WHERE g->>'kind' = p_gate_kind
    LIMIT 1;

    SELECT MIN((g->>'order')::int) INTO v_next_order
    FROM jsonb_array_elements(v_chain.gates) g
    WHERE v_current_order IS NOT NULL
      AND (g->>'order')::int > v_current_order;

    IF v_next_order IS NOT NULL THEN
      FOR v_gate IN
        SELECT g FROM jsonb_array_elements(v_chain.gates) g
        WHERE (g->>'order')::int = v_next_order
        ORDER BY g->>'kind'
      LOOP
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
          WHEN 'cert_director_go' THEN 'Validacao da Diretoria de Certificacao PMI-GO'
          WHEN 'volunteers_in_role_active' THEN 'Ratificacao de voluntario em funcao ativa'
          WHEN 'member_ratification' THEN 'Ratificacao de membro'
          ELSE v_gate->>'kind'
        END;
        v_role_singular := CASE v_gate->>'kind'
          WHEN 'curator' THEN 'curador(a)'
          WHEN 'leader_awareness' THEN 'lider do Nucleo'
          WHEN 'submitter_acceptance' THEN 'Gerente de Projeto'
          WHEN 'chapter_witness' THEN 'ponto focal do seu capitulo'
          WHEN 'president_go' THEN 'presidencia do PMI-GO'
          WHEN 'president_others' THEN 'presidencia do seu capitulo'
          WHEN 'cert_director_go' THEN 'Diretoria de Certificacao do PMI-GO'
          WHEN 'volunteers_in_role_active' THEN 'voluntario(a) em funcao ativa'
          WHEN 'member_ratification' THEN 'membro ativo'
          ELSE v_gate->>'kind'
        END;
        v_action_verb := CASE v_gate->>'kind'
          WHEN 'curator' THEN 'ler o documento e aprovar como curador'
          WHEN 'leader_awareness' THEN 'ler e registrar ciencia'
          WHEN 'submitter_acceptance' THEN 'confirmar que esta pronto para circular presidencias'
          WHEN 'chapter_witness' THEN 'confirmar como ponto focal do seu capitulo'
          WHEN 'president_go' THEN 'assinar como presidencia PMI-GO'
          WHEN 'president_others' THEN 'assinar como presidencia de capitulo'
          WHEN 'cert_director_go' THEN 'validar como Diretoria de Certificacao do PMI-GO'
          WHEN 'volunteers_in_role_active' THEN 'ratificar como voluntario(a) em funcao ativa'
          WHEN 'member_ratification' THEN 'ratificar como membro ativo'
          ELSE 'agir conforme seu papel'
        END;

        FOR v_target IN
          SELECT m.id AS member_id, m.name FROM public.members m
          WHERE m.is_active = true
            AND public._can_sign_gate(m.id, p_chain_id, v_gate->>'kind')
            AND NOT EXISTS (
              SELECT 1 FROM public.approval_signoffs s
              WHERE s.approval_chain_id = p_chain_id
                AND s.gate_kind = v_gate->>'kind' AND s.signer_id = m.id
            )
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
            'approval_chain', p_chain_id
          );
          v_enqueued := v_enqueued + 1;
        END LOOP;
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
        'approval_chain', p_chain_id
      );
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
      'approval_chain', p_chain_id
    );
    RETURN 1;
  END IF;

  RETURN 0;
END;
$function$;
