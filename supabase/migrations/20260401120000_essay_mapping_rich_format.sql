-- Essay mapping: rich format with question text + backward compatibility
-- ====================================================================
-- Old format: {"1": "motivation_letter"} (still works)
-- New format: {"1": {"field": "motivation_letter", "question": "Você é filiado..."}}

-- Helper function to extract field from either format
CREATE OR REPLACE FUNCTION get_essay_field(p_mapping jsonb, p_index text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN jsonb_typeof(p_mapping->p_index) = 'object' THEN p_mapping->p_index->>'field'
    ELSE p_mapping->>p_index
  END;
$$;

-- Update leader opportunity with real VEP questions
UPDATE vep_opportunities
SET essay_mapping = '{
  "1": {"field": "motivation_letter", "question": "Você é filiado a um dos capítulos parceiros do Núcleo (PMI-CE, PMI-DF, PMI-GO, PMI-MG ou PMI-RS)? Se sim, qual?"},
  "2": {"field": "proposed_theme", "question": "Qual temática inédita ou pouco explorada na interseção de IA e GP você propõe liderar? Defenda a necessidade e cite seu background."},
  "3": {"field": "leadership_experience", "question": "Descreva uma experiência onde você precisou guiar um time em um projeto incerto ou inovador. Como estimula o desenvolvimento de voluntários?"},
  "4": {"field": "academic_background", "question": "Qual sua base acadêmica ou teórica (MBA, Mestrado, Certificações) que lhe dá segurança para atuar como revisor técnico?"}
}'::jsonb,
  eligibility = 'Ser filiado ativo a um dos capítulos parceiros. Curiosidade investigativa. Histórico em liderança (>8 anos). Pós-graduação/Mestrado desejável.',
  positions_available = 10
WHERE opportunity_id = '64966';

-- Update researcher opportunity with question texts
UPDATE vep_opportunities
SET essay_mapping = '{
  "1": {"field": "motivation_letter", "question": "Você é filiado a um dos capítulos parceiros? Se sim, qual?"},
  "2": {"field": "areas_of_interest", "question": "Qual perfil de pesquisador você se identifica? Qual sua motivação para contribuir?"},
  "3": {"field": "academic_background", "question": "Conhece o PMBOK? Possui formação em GP? Certificação PMI em preparação?"},
  "4": {"field": "availability_declared", "question": "Disponibilidade real de quantas horas semanais?"}
}'::jsonb
WHERE opportunity_id = '64967';
