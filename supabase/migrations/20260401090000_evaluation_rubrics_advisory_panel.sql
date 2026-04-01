-- Evaluation Rubrics — Advisory Panel Design
-- ============================================
-- Panel: PMI Global Volunteer Consultant, Recruitment Lead, PMBOK 8ed Guardian,
--        Compliance Officer, Governance Lead
--
-- Key decisions:
-- 1. Certification: 0-2 scale (not 0-10) — binary/tiered per PMI volunteer framework
--    0 = No cert | 1 = Non-PMI cert or PMI in progress | 2 = PMP/CAPM/CPMAI active
-- 2. Other criteria: 0-10 with anchored descriptors to ensure inter-rater reliability
-- 3. Each criterion has visible rubric/guide shown to evaluators during scoring
-- 4. Weights remain unchanged (already validated by governance)

UPDATE selection_cycles
SET objective_criteria = '[
  {
    "key": "certification",
    "max": 2,
    "label": "Certificações PMI",
    "weight": 2,
    "guide": "0 = Não possui certificação | 1 = Outra certificação (não PMI) ou PMI em preparação | 2 = PMP, CAPM, CPMAI ou outra certificação PMI ativa"
  },
  {
    "key": "research_exp",
    "max": 10,
    "label": "Experiência em Pesquisa",
    "weight": 5,
    "guide": "0-2: Sem experiência em pesquisa | 3-4: Experiência acadêmica básica (TCC, monografia) | 5-6: Co-autor em publicações ou participação em projetos de pesquisa | 7-8: Publicações como autor principal ou liderança de projetos | 9-10: Pesquisador experiente com múltiplas publicações"
  },
  {
    "key": "gp_knowledge",
    "max": 10,
    "label": "Conhecimento em GP",
    "weight": 5,
    "guide": "0-2: Superficial ou nenhum | 3-4: Conceitos básicos, certificação em preparação | 5-6: Formação ou experiência prática em GP | 7-8: Experiência sólida + formação formal | 9-10: Especialista com certificação ativa e vasta experiência"
  },
  {
    "key": "ai_knowledge",
    "max": 10,
    "label": "Conhecimento em IA",
    "weight": 5,
    "guide": "0-2: Sem conhecimento | 3-4: Conceitual básico (cursos introdutórios) | 5-6: Aplicou IA em projetos ou formação em dados/ML | 7-8: Experiência prática com ferramentas de IA ou pesquisa na área | 9-10: Especialista com publicações ou implementações"
  },
  {
    "key": "tech_skills",
    "max": 10,
    "label": "Habilidades Técnicas",
    "weight": 5,
    "guide": "0-2: Básicas (informática geral) | 3-4: Ferramentas de pesquisa e documentação | 5-6: Ferramentas avançadas (análise de dados, metodologia) | 7-8: Domínio técnico relevante para pesquisa | 9-10: Expertise excepcional em múltiplas ferramentas e metodologias"
  },
  {
    "key": "availability",
    "max": 10,
    "label": "Disponibilidade",
    "weight": 3,
    "guide": "0-2: Menos de 2h/sem ou incerta | 3-4: 2-3h/sem | 5-6: 4-5h/sem | 7-8: 6-8h/sem com flexibilidade | 9-10: 8h+ semanais com alto comprometimento"
  },
  {
    "key": "motivation",
    "max": 10,
    "label": "Motivação / Carta",
    "weight": 5,
    "guide": "0-2: Genérica, sem conexão com o Núcleo | 3-4: Interesse básico sem especificidade | 5-6: Conecta motivação pessoal com objetivos do Núcleo | 7-8: Motivação clara, específica e alinhada com a missão | 9-10: Excepcional, com proposta concreta de contribuição"
  }
]'::jsonb
WHERE cycle_code = 'cycle3-2026-b2';
