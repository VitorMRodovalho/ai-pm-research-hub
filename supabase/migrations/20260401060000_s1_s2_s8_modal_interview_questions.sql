-- S1+S2+S8: Enhanced candidate modal + interview questions per cycle
-- ================================================================

-- S8: Add interview_questions column to store structured questions per cycle
ALTER TABLE selection_cycles ADD COLUMN IF NOT EXISTS interview_questions jsonb DEFAULT '[]';

-- S2: Seed interview questions for Batch 2 (5 pillars from official DOCX)
UPDATE selection_cycles
SET interview_questions = '[
  {
    "pillar": "background",
    "label": "Background",
    "scored": false,
    "questions": [
      "Conte-nos brevemente sobre sua carreira e principais conquistas que obteve ao longo dela",
      "Já teve experiências anteriores com voluntariado? Se sim, detalhe"
    ]
  },
  {
    "pillar": "communication",
    "label": "Comunicação",
    "scored": true,
    "criterion_key": "communication",
    "questions": [
      "Conte uma situação em que precisou comunicar uma ideia técnica complexa para alguém sem conhecimento prévio. Como estruturou a explicação?",
      "Quando você escreve um artigo ou relatório, como garante que a mensagem seja clara e acessível ao público-alvo?",
      "Dê um exemplo de como lidou com um mal-entendido em um projeto. O que fez para esclarecer a comunicação?"
    ]
  },
  {
    "pillar": "proactivity",
    "label": "Proatividade e Iniciativa",
    "scored": true,
    "criterion_key": "proactivity",
    "questions": [
      "Fale sobre uma ocasião em que você percebeu um problema antes que ele se tornasse crítico. O que fez?",
      "Descreva uma ideia que você propôs em um projeto ou equipe que trouxe melhorias significativas.",
      "Quando você identifica uma oportunidade de pesquisa ou inovação fora do escopo inicial, como costuma agir?"
    ]
  },
  {
    "pillar": "teamwork",
    "label": "Trabalho em Equipe",
    "scored": true,
    "criterion_key": "teamwork",
    "questions": [
      "Cite um exemplo de projeto em que você teve que colaborar com pessoas de diferentes perfis. Como lidou com as diferenças?",
      "Já enfrentou uma situação em que houve conflito em um time? Qual foi sua postura?",
      "Em sua visão, o que é mais importante para manter um time engajado e produtivo em longo prazo?"
    ]
  },
  {
    "pillar": "culture_alignment",
    "label": "Alinhamento com a Cultura do Núcleo / PMI",
    "scored": true,
    "criterion_key": "culture_alignment",
    "questions": [
      "O Núcleo segue o Código de Ética do PMI, incluindo responsabilidade e transparência. Como você aplicaria esses princípios em sua atuação?",
      "Nosso objetivo é produzir conhecimento original e de impacto. Qual seria sua motivação pessoal para contribuir com esse propósito?",
      "O Núcleo valoriza colaboração e integridade. O que você faria se identificasse um colega apresentando conteúdo sem a devida citação ou atribuição de autoria?"
    ]
  }
]'::jsonb
WHERE cycle_code = 'cycle3-2026-b2';

-- S1+S9: Update get_selection_dashboard to return all candidate fields
DROP FUNCTION IF EXISTS get_selection_dashboard(text);
CREATE FUNCTION get_selection_dashboard(p_cycle_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_caller record; v_cycle_id uuid; v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager') AND NOT (v_caller.designations && ARRAY['curator'])) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    SELECT id INTO v_cycle_id FROM selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found', 'cycle', null, 'applications', '[]'::jsonb, 'stats', jsonb_build_object('total', 0));
  END IF;

  SELECT jsonb_build_object(
    'cycle', (SELECT jsonb_build_object(
      'id', c.id, 'cycle_code', c.cycle_code, 'title', c.title, 'status', c.status,
      'interview_booking_url', c.interview_booking_url,
      'interview_questions', COALESCE(c.interview_questions, '[]'::jsonb)
    ) FROM selection_cycles c WHERE c.id = v_cycle_id),
    'applications', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', a.id, 'applicant_name', a.applicant_name, 'email', a.email,
        'role_applied', a.role_applied, 'chapter', a.chapter, 'status', a.status,
        'objective_score', a.objective_score_avg,
        'final_score', a.final_score,
        'rank_chapter', a.rank_chapter, 'rank_overall', a.rank_overall,
        'linkedin_url', a.linkedin_url, 'resume_url', a.resume_url,
        'tags', a.tags, 'feedback', a.feedback,
        'motivation', a.motivation_letter,
        'experience_years', a.seniority_years,
        'membership_status', a.membership_status,
        'certifications', a.certifications,
        'is_returning_member', a.is_returning_member,
        'application_date', a.application_date,
        'academic_background', a.academic_background,
        'areas_of_interest', a.areas_of_interest,
        'availability_declared', a.availability_declared,
        'non_pmi_experience', a.non_pmi_experience,
        'proposed_theme', a.proposed_theme,
        'leadership_experience', a.leadership_experience,
        'created_at', a.created_at
      ) ORDER BY a.final_score DESC NULLS LAST)
      FROM selection_applications a WHERE a.cycle_id = v_cycle_id
    ), '[]'::jsonb),
    'stats', jsonb_build_object(
      'total', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id),
      'approved', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted')),
      'rejected', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status IN ('rejected', 'objective_cutoff')),
      'pending', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')),
      'cancelled', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status IN ('cancelled', 'withdrawn')),
      'waitlist', (SELECT count(*) FROM selection_applications WHERE cycle_id = v_cycle_id AND status = 'waitlist')
    )
  ) INTO v_result;
  RETURN v_result;
END;
$$;

NOTIFY pgrst, 'reload schema';
