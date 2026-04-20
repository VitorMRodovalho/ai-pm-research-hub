-- ADR-0016 Amendment 2 — Gate Matrix v2 per doc_type
--
-- Changes:
--   (a) Split doc_type 'addendum' into 'cooperation_addendum' + 'volunteer_addendum'
--   (b) resolve_default_gates(p_doc_type) — single source of truth for gate templates
--   (c) Refactor _can_sign_gate with optional p_doc_type + p_submitter_id for preview mode;
--       remove 'founder' from leader_awareness; add new gate_kind 'volunteers_in_role_active'
--       (via engagements V4); deprecate 'member_ratification' (fail-closed, was too broad)
--   (d) Propagate volunteers_in_role_active across _ip_ratify_cta_link,
--       _enqueue_gate_notifications, get_ratification_reminder_targets, sign_ip_ratification
--
-- Rollback: revert doc_type migration via reverse UPDATE + old CHECK; restore prior function
--   bodies from migration 20260503010000 + 20260502030000.

-- ============================================================
-- (a) doc_type split
-- ============================================================
ALTER TABLE public.governance_documents
  DROP CONSTRAINT IF EXISTS governance_documents_doc_type_check;

UPDATE public.governance_documents
SET doc_type = 'cooperation_addendum', updated_at = now()
WHERE id = '41de16e2-4f2e-4eac-b63e-8f0b45b22629'; -- Adendo PI aos Acordos

UPDATE public.governance_documents
SET doc_type = 'volunteer_addendum', updated_at = now()
WHERE id = 'd2b7782c-dc1a-44d4-a5d5-16248117a895'; -- Adendo Retificativo

ALTER TABLE public.governance_documents
  ADD CONSTRAINT governance_documents_doc_type_check
  CHECK (doc_type = ANY (ARRAY[
    'manual','cooperation_agreement','framework_reference',
    'cooperation_addendum','volunteer_addendum',
    'policy','volunteer_term_template','executive_summary'
  ]));

-- ============================================================
-- (b) resolve_default_gates
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_default_gates(p_doc_type text)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT CASE p_doc_type
    WHEN 'cooperation_agreement' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"chapter_witness","order":4,"threshold":5},
      {"kind":"president_go","order":5,"threshold":1},
      {"kind":"president_others","order":6,"threshold":4}
    ]'::jsonb
    WHEN 'cooperation_addendum' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"chapter_witness","order":4,"threshold":5},
      {"kind":"president_go","order":5,"threshold":1},
      {"kind":"president_others","order":6,"threshold":4}
    ]'::jsonb
    WHEN 'volunteer_term_template' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"volunteers_in_role_active","order":5,"threshold":"all"}
    ]'::jsonb
    WHEN 'volunteer_addendum' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"volunteers_in_role_active","order":5,"threshold":"all"}
    ]'::jsonb
    WHEN 'policy' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"president_others","order":5,"threshold":4}
    ]'::jsonb
    ELSE NULL
  END;
$$;
GRANT EXECUTE ON FUNCTION public.resolve_default_gates(text) TO authenticated;
COMMENT ON FUNCTION public.resolve_default_gates(text) IS
  'ADR-0016 Amendment 2: gates template per doc_type. NULL = doc outside IP workflow.';

-- ============================================================
-- (c) _can_sign_gate refactor
-- ============================================================
DROP FUNCTION IF EXISTS public._can_sign_gate(uuid, uuid, text);

CREATE FUNCTION public._can_sign_gate(
  p_member_id uuid,
  p_chain_id uuid,
  p_gate_kind text,
  p_doc_type text DEFAULT NULL,
  p_submitter_id uuid DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_chain record;
  v_doc_type text;
  v_submitter_id uuid;
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.chapter, m.is_active,
         m.member_status, m.person_id
  INTO v_member FROM public.members m WHERE m.id = p_member_id;
  IF v_member.id IS NULL OR v_member.is_active = false THEN RETURN false; END IF;

  IF p_chain_id IS NOT NULL THEN
    SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.opened_by INTO v_chain
    FROM public.approval_chains ac WHERE ac.id = p_chain_id;
    IF v_chain.id IS NULL OR v_chain.status NOT IN ('review','approved') THEN RETURN false; END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_chain.gates) g WHERE g->>'kind' = p_gate_kind) THEN
      RETURN false;
    END IF;
    SELECT gd.doc_type INTO v_doc_type
    FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;
    v_submitter_id := v_chain.opened_by;
  ELSE
    IF p_doc_type IS NULL THEN RETURN false; END IF;
    v_doc_type := p_doc_type;
    v_submitter_id := p_submitter_id;
  END IF;

  RETURN CASE p_gate_kind
    WHEN 'curator' THEN 'curator' = ANY(v_member.designations)
    WHEN 'leader' THEN v_member.operational_role IN ('tribe_leader','manager','deputy_manager')
    WHEN 'leader_awareness' THEN
      v_member.operational_role IN ('tribe_leader','manager','deputy_manager')
    WHEN 'submitter_acceptance' THEN
      v_submitter_id IS NOT NULL AND v_member.id = v_submitter_id
    WHEN 'president_go' THEN
      v_member.chapter = 'PMI-GO'
      AND 'chapter_board' = ANY(v_member.designations)
      AND (
        'legal_signer' = ANY(v_member.designations)
        OR (v_doc_type = 'volunteer_term_template' AND 'voluntariado_director' = ANY(v_member.designations))
      )
    WHEN 'president_others' THEN
      v_member.chapter IN ('PMI-CE','PMI-DF','PMI-MG','PMI-RS')
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)
    WHEN 'chapter_witness' THEN (
      v_member.operational_role = 'chapter_liaison'
      OR 'chapter_liaison' = ANY(v_member.designations)
      OR (
        'chapter_vice_president' = ANY(v_member.designations)
        AND NOT EXISTS (
          SELECT 1 FROM public.members m2
          WHERE m2.is_active = true
            AND m2.chapter = v_member.chapter
            AND (m2.operational_role = 'chapter_liaison' OR 'chapter_liaison' = ANY(m2.designations))
        )
      )
    )
    WHEN 'volunteers_in_role_active' THEN
      v_member.member_status = 'active'
      AND EXISTS (
        SELECT 1 FROM public.engagements e
        WHERE e.person_id = v_member.person_id
          AND e.kind = 'volunteer'
          AND e.status = 'active'
          AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
          AND e.role IN ('researcher','leader','manager')
      )
    WHEN 'external_signer' THEN
      v_member.operational_role = 'external_signer'
    WHEN 'member_ratification' THEN false
    ELSE false
  END;
END;
$function$;

COMMENT ON FUNCTION public._can_sign_gate(uuid, uuid, text, text, uuid) IS
  'ADR-0016 Amendment 2: eligibility predicate. Dual-mode: chain_id lookup OR doc_type+submitter_id preview. New volunteers_in_role_active (engagements V4). Deprecated member_ratification (fail-closed).';

-- ============================================================
-- (d) _ip_ratify_cta_link
-- ============================================================
CREATE OR REPLACE FUNCTION public._ip_ratify_cta_link(p_chain_id uuid, p_gate_kind text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN p_gate_kind IN ('volunteers_in_role_active','member_ratification','external_signer')
      THEN '/governance/ip-agreement?chain_id=' || p_chain_id::text
    ELSE '/admin/governance/documents/' || p_chain_id::text
  END;
$function$;

-- ============================================================
-- (e) _enqueue_gate_notifications (add labels/verbs for volunteers_in_role_active)
-- ============================================================
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
      ELSE v_gate->>'kind'
    END;
    v_role_singular := CASE v_gate->>'kind'
      WHEN 'curator' THEN 'curador(a)'
      WHEN 'leader_awareness' THEN 'lider do Nucleo'
      WHEN 'submitter_acceptance' THEN 'Gerente de Projeto'
      WHEN 'chapter_witness' THEN 'ponto focal do seu capitulo'
      WHEN 'president_go' THEN 'presidencia do PMI-GO'
      WHEN 'president_others' THEN 'presidencia do seu capitulo'
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
    RETURN v_enqueued;
  END IF;

  IF p_event = 'gate_advanced' AND p_gate_kind IS NOT NULL THEN
    SELECT g INTO v_gate FROM jsonb_array_elements(v_chain.gates) g
    WHERE (g->>'order')::int > (
      SELECT (g2->>'order')::int FROM jsonb_array_elements(v_chain.gates) g2
      WHERE g2->>'kind' = p_gate_kind LIMIT 1
    )
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
        ELSE v_gate->>'kind'
      END;
      v_role_singular := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'curador(a)'
        WHEN 'leader_awareness' THEN 'lider do Nucleo'
        WHEN 'submitter_acceptance' THEN 'Gerente de Projeto'
        WHEN 'chapter_witness' THEN 'ponto focal do seu capitulo'
        WHEN 'president_go' THEN 'presidencia do PMI-GO'
        WHEN 'president_others' THEN 'presidencia do seu capitulo'
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

-- ============================================================
-- (f) get_ratification_reminder_targets (use _can_sign_gate + accept both gate_kinds)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_ratification_reminder_targets(p_document_id uuid)
RETURNS TABLE(target_type text, member_id uuid, person_id uuid, name text, email text,
              expected_gate_kind text, chain_id uuid, version_label text, days_since_chain_opened integer)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_current_version uuid;
  v_chain_id uuid;
  v_chain_opened_at timestamptz;
  v_chain_gates jsonb;
  v_version_label text;
  v_member_gate_kind text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: requires manage_member' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT current_version_id INTO v_current_version
  FROM public.governance_documents WHERE id = p_document_id;
  IF v_current_version IS NULL THEN RETURN; END IF;

  SELECT dv.version_label INTO v_version_label
  FROM public.document_versions dv WHERE dv.id = v_current_version;

  SELECT ac.id, ac.opened_at, ac.gates
    INTO v_chain_id, v_chain_opened_at, v_chain_gates
  FROM public.approval_chains ac
  WHERE ac.document_id = p_document_id
    AND ac.version_id = v_current_version
    AND ac.status IN ('review', 'approved')
  ORDER BY ac.opened_at DESC NULLS LAST
  LIMIT 1;

  IF v_chain_id IS NULL THEN RETURN; END IF;

  SELECT g->>'kind' INTO v_member_gate_kind
  FROM jsonb_array_elements(v_chain_gates) g
  WHERE g->>'kind' IN ('volunteers_in_role_active','member_ratification')
  LIMIT 1;

  IF v_member_gate_kind IS NOT NULL THEN
    RETURN QUERY
    SELECT
      'member_pending_ratification'::text,
      m.id, m.person_id, m.name, m.email,
      v_member_gate_kind::text,
      v_chain_id, v_version_label,
      GREATEST(0, EXTRACT(day FROM (now() - v_chain_opened_at))::int)
    FROM public.members m
    WHERE public._can_sign_gate(m.id, v_chain_id, v_member_gate_kind)
      AND NOT EXISTS (
        SELECT 1 FROM public.member_document_signatures mds
        WHERE mds.member_id = m.id AND mds.signed_version_id = v_current_version
      );
  END IF;

  RETURN QUERY
  SELECT
    'external_signer_pending'::text,
    m.id, m.person_id, m.name, m.email,
    COALESCE(ae.role, 'external_signer')::text,
    v_chain_id, v_version_label,
    GREATEST(0, EXTRACT(day FROM (now() - v_chain_opened_at))::int)
  FROM public.members m
  JOIN public.auth_engagements ae ON ae.person_id = m.person_id
  WHERE m.operational_role = 'external_signer'
    AND ae.kind = 'external_signer'
    AND ae.status = 'active'
    AND ae.is_authoritative = true
    AND NOT EXISTS (
      SELECT 1 FROM public.approval_signoffs s
      WHERE s.approval_chain_id = v_chain_id AND s.signer_id = m.id
    )
    AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_chain_gates) g
      WHERE g->>'kind' = COALESCE(ae.role, 'external_signer')
    );
END;
$function$;

-- ============================================================
-- (g) sign_ip_ratification — accept volunteers_in_role_active with same cert + UE-consent rules
-- ============================================================
CREATE OR REPLACE FUNCTION public.sign_ip_ratification(
  p_chain_id uuid,
  p_gate_kind text,
  p_signoff_type text DEFAULT 'approval'::text,
  p_sections_verified jsonb DEFAULT NULL::jsonb,
  p_comment_body text DEFAULT NULL::text,
  p_ue_consent_49_1_a boolean DEFAULT NULL::boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_chain record;
  v_version record;
  v_doc record;
  v_signoff_id uuid;
  v_hash text;
  v_snapshot jsonb;
  v_existing uuid;
  v_all_satisfied boolean;
  v_cert_id uuid;
  v_cert_code text;
  v_gates_remaining int;
  v_mbr_signature_id uuid;
  v_is_eu boolean := false;
  v_ue_consent_required boolean := false;
  v_is_member_ratify boolean := false;
  v_ue_docs text[] := ARRAY[
    'Termo de Compromisso de Voluntário — Núcleo de IA & GP',
    'Adendo Retificativo ao Termo de Compromisso de Voluntario'
  ];
BEGIN
  SELECT m.id, m.name, m.email, m.operational_role, m.pmi_id, m.chapter,
         m.designations, m.member_status, m.person_id
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error','not_authenticated'); END IF;

  IF NOT public._can_sign_gate(v_member.id, p_chain_id, p_gate_kind) THEN
    RETURN jsonb_build_object('error','access_denied','message','Member not authorized for gate_kind=' || p_gate_kind);
  END IF;

  SELECT ac.id, ac.status, ac.document_id, ac.version_id, ac.gates
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN jsonb_build_object('error','chain_not_found'); END IF;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html, dv.locked_at
  INTO v_version FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT gd.id, gd.title, gd.doc_type INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT id INTO v_existing FROM public.approval_signoffs
  WHERE approval_chain_id = p_chain_id AND gate_kind = p_gate_kind AND signer_id = v_member.id;
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error','already_signed','signoff_id',v_existing); END IF;

  v_is_member_ratify := (p_gate_kind IN ('member_ratification','volunteers_in_role_active'));

  IF v_is_member_ratify AND v_doc.title = ANY(v_ue_docs) THEN
    v_is_eu := public.is_eu_resident(v_member.person_id);
    IF v_is_eu THEN
      v_ue_consent_required := true;
      IF p_ue_consent_49_1_a IS NULL OR p_ue_consent_49_1_a = false THEN
        RETURN jsonb_build_object(
          'error', 'ue_consent_required',
          'message', 'EU resident must explicitly consent to Art. 49(1)(a) GDPR data transfer.',
          'document_title', v_doc.title,
          'applicable_clause', CASE
            WHEN v_doc.title = 'Termo de Compromisso de Voluntário — Núcleo de IA & GP' THEN 'Clausula 14'
            ELSE 'Art. 8'
          END
        );
      END IF;
    END IF;
  END IF;

  v_snapshot := jsonb_build_object(
    'document_id', v_doc.id, 'document_title', v_doc.title, 'doc_type', v_doc.doc_type,
    'version_id', v_version.id, 'version_number', v_version.version_number, 'version_label', v_version.version_label,
    'version_locked_at', v_version.locked_at,
    'signer_id', v_member.id, 'signer_name', v_member.name, 'signer_email', v_member.email,
    'signer_role', v_member.operational_role, 'signer_chapter', v_member.chapter,
    'signer_pmi_id', v_member.pmi_id, 'signer_designations', to_jsonb(v_member.designations),
    'gate_kind', p_gate_kind, 'signoff_type', p_signoff_type, 'signed_at', now(),
    'signer_is_eu_resident', v_is_eu,
    'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false),
    'ue_consent_required_by_policy', v_ue_consent_required);

  v_hash := encode(sha256(convert_to(v_snapshot::text || v_member.id::text || now()::text || 'nucleo-ia-ip-ratify-salt', 'UTF8')), 'hex');

  INSERT INTO public.approval_signoffs (
    approval_chain_id, gate_kind, signer_id, signoff_type,
    signed_at, signature_hash, content_snapshot, sections_verified, comment_body
  ) VALUES (
    p_chain_id, p_gate_kind, v_member.id, p_signoff_type,
    now(), v_hash, v_snapshot, p_sections_verified, p_comment_body
  ) RETURNING id INTO v_signoff_id;

  SELECT COUNT(*) INTO v_gates_remaining
  FROM jsonb_array_elements(v_chain.gates) g
  WHERE (g->>'threshold') = 'all'
     OR ((g->>'threshold') ~ '^[0-9]+$'
        AND (SELECT COUNT(*) FROM public.approval_signoffs s
             WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (g->>'kind')
               AND s.signoff_type IN ('approval','acknowledge')) < (g->>'threshold')::int);

  v_all_satisfied := (v_gates_remaining = 0);

  IF v_is_member_ratify AND p_signoff_type = 'approval' THEN
    v_cert_code := 'IPRAT-' || EXTRACT(YEAR FROM now())::text || '-' || UPPER(SUBSTRING(gen_random_uuid()::text FROM 1 FOR 6));

    INSERT INTO public.certificates (
      member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
      function_role, language, status, signature_hash, content_snapshot, template_id
    ) VALUES (
      v_member.id, 'ip_ratification',
      'Ratificacao IP — ' || v_doc.title,
      'Ratificacao do documento ' || v_doc.title || ' versao ' || v_version.version_label,
      EXTRACT(YEAR FROM now())::int, now(), v_member.id, v_cert_code,
      v_member.operational_role, 'pt-BR', 'issued', v_hash, v_snapshot, v_doc.id::text
    ) RETURNING id INTO v_cert_id;

    INSERT INTO public.member_document_signatures (
      member_id, document_id, signed_version_id, approval_chain_id,
      signoff_id, certificate_id, signed_at, is_current
    ) VALUES (v_member.id, v_doc.id, v_version.id, p_chain_id, v_signoff_id, v_cert_id, now(), true)
    RETURNING id INTO v_mbr_signature_id;
  END IF;

  IF v_all_satisfied AND v_chain.status = 'review' THEN
    UPDATE public.approval_chains SET status = 'approved', approved_at = now(), updated_at = now()
      WHERE id = p_chain_id;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'ip_ratification_signoff', 'approval_signoff', v_signoff_id,
    jsonb_build_object('chain_id', p_chain_id, 'gate_kind', p_gate_kind, 'signoff_type', p_signoff_type,
      'document_id', v_doc.id, 'document_title', v_doc.title, 'version_label', v_version.version_label,
      'chain_satisfied', v_all_satisfied, 'certificate_id', v_cert_id,
      'signer_is_eu_resident', v_is_eu,
      'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false)));

  RETURN jsonb_build_object('success', true, 'signoff_id', v_signoff_id, 'signature_hash', v_hash,
    'gates_remaining', v_gates_remaining, 'chain_satisfied', v_all_satisfied,
    'certificate_id', v_cert_id, 'certificate_code', v_cert_code,
    'member_signature_id', v_mbr_signature_id, 'signed_at', now(),
    'signer_is_eu_resident', v_is_eu,
    'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false));
END;
$function$;

NOTIFY pgrst, 'reload schema';
