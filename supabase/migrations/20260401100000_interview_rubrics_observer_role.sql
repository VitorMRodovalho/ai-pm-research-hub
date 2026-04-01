-- Interview rubrics + observer role enforcement
-- Advisory panel: PMI Global Volunteer Consultant, Recruitment Lead, PMBOK 8ed Guardian

-- Interview criteria with anchored descriptors (same UX pattern as objective)
UPDATE selection_cycles
SET interview_criteria = '[
  {
    "key": "communication",
    "max": 10,
    "label": "Comunicação",
    "weight": 4,
    "guide": "0-2: Dificuldade de articulação, respostas confusas | 3-4: Comunica ideias básicas mas sem clareza técnica | 5-6: Comunicação clara, estrutura razoável nas respostas | 7-8: Articula ideias complexas com clareza, adapta linguagem ao público | 9-10: Excepcional — respostas estruturadas, exemplos concretos, escuta ativa"
  },
  {
    "key": "proactivity",
    "max": 10,
    "label": "Proatividade e Iniciativa",
    "weight": 3,
    "guide": "0-2: Reativo, sem exemplos de iniciativa própria | 3-4: Exemplos vagos de proatividade | 5-6: Demonstra iniciativa em situações específicas | 7-8: Histórico claro de identificar problemas e propor soluções antes de ser solicitado | 9-10: Líder natural em iniciativas, com impacto mensurável"
  },
  {
    "key": "teamwork",
    "max": 10,
    "label": "Trabalho em Equipe",
    "weight": 3,
    "guide": "0-2: Preferência por trabalho individual, sem exemplos colaborativos | 3-4: Colabora quando solicitado mas sem engajamento ativo | 5-6: Bom colaborador, lida razoavelmente com diferenças | 7-8: Histórico de colaboração efetiva em times diversos, resolve conflitos construtivamente | 9-10: Catalisador de equipe — engaja outros, mantém coesão em longo prazo"
  },
  {
    "key": "culture_alignment",
    "max": 10,
    "label": "Alinhamento Cultural (Núcleo/PMI)",
    "weight": 3,
    "guide": "0-2: Sem conhecimento dos valores PMI ou do Núcleo | 3-4: Conhecimento superficial, motivação genérica | 5-6: Demonstra conhecimento do Código de Ética PMI e propósito do Núcleo | 7-8: Valores claramente alinhados, postura ética consistente nos exemplos | 9-10: Embaixador natural — integridade, transparência e responsabilidade como segunda natureza"
  }
]'::jsonb
WHERE cycle_code = 'cycle3-2026-b2';

-- Observer role: get_evaluation_form returns committee_role so frontend can enforce
DROP FUNCTION IF EXISTS get_evaluation_form(uuid, text);
CREATE FUNCTION get_evaluation_form(p_application_id uuid, p_evaluation_type text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller record; v_app record; v_cycle record; v_committee record; v_draft record; v_criteria jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found: %', p_application_id; END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;
  IF v_committee IS NULL AND v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member for this cycle';
  END IF;

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  SELECT * INTO v_draft FROM public.selection_evaluations
  WHERE application_id = p_application_id AND evaluator_id = v_caller.id AND evaluation_type = p_evaluation_type;

  RETURN jsonb_build_object(
    'application', jsonb_build_object(
      'id', v_app.id, 'applicant_name', v_app.applicant_name, 'email', v_app.email,
      'chapter', v_app.chapter, 'role_applied', v_app.role_applied,
      'certifications', v_app.certifications, 'linkedin_url', v_app.linkedin_url,
      'resume_url', v_app.resume_url, 'motivation_letter', v_app.motivation_letter,
      'non_pmi_experience', v_app.non_pmi_experience, 'areas_of_interest', v_app.areas_of_interest,
      'availability_declared', v_app.availability_declared, 'proposed_theme', v_app.proposed_theme,
      'leadership_experience', v_app.leadership_experience, 'academic_background', v_app.academic_background,
      'membership_status', v_app.membership_status, 'status', v_app.status
    ),
    'criteria', v_criteria,
    'evaluation_type', p_evaluation_type,
    'committee_role', COALESCE(v_committee.role, 'superadmin'),
    'draft', CASE WHEN v_draft IS NOT NULL THEN jsonb_build_object(
      'id', v_draft.id, 'scores', v_draft.scores, 'notes', v_draft.notes,
      'criterion_notes', COALESCE(v_draft.criterion_notes, '{}'::jsonb),
      'weighted_subtotal', v_draft.weighted_subtotal, 'submitted_at', v_draft.submitted_at
    ) ELSE NULL END,
    'is_locked', CASE WHEN v_draft.submitted_at IS NOT NULL THEN true ELSE false END
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
