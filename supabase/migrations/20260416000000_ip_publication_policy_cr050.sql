-- ============================================================================
-- IP & Publication Policy + CR-050
-- Purpose: Insert governance_document "Política de Publicação e Propriedade
--          Intelectual do Núcleo" + CR-050 requesting volunteer agreement
--          clause 2 revision and adoption of publication policy.
-- Context: Current clause 2 assigns all IP to PMI-GO alone, conflicting with
--          multi-chapter collaboration and Brazilian copyright law (Lei 9.610/1998
--          Art. 24-27 inalienable moral rights, Art. 49§4 5-year future works limit,
--          Art. 50 specific rights requirement). PMI Code of Ethics §3.3.4 mandates
--          respect for property rights of others including intellectual property.
-- Rollback: DELETE FROM governance_documents WHERE doc_type = 'policy'
--           AND title ILIKE '%Publicação e Propriedade Intelectual%';
--           DELETE FROM change_requests WHERE cr_number = 'CR-050';
-- ============================================================================

-- ═══ PART 1: Política de Publicação e Propriedade Intelectual ═══

INSERT INTO governance_documents (
  title, doc_type, description, version, status, valid_from,
  parties, signatories, content
)
SELECT
  'Política de Publicação e Propriedade Intelectual do Núcleo de IA & GP',
  'policy',
  'Define os 3 tracks de publicação (Aberto, Framework, Restrito), regras de crédito autoral, licenciamento, e governança de propriedade intelectual para outputs do programa.',
  'v1.0-draft',
  'draft',
  now()::date,
  ARRAY['PMI-GO','PMI-CE','PMI-DF','PMI-MG','PMI-RS'],
  '[{"name":"Vitor Maia Rodovalho","role":"Gerente de Projeto"}]'::jsonb,
  '{
    "title": "Política de Publicação e Propriedade Intelectual",
    "version": "v1.0-draft",
    "effective_date": null,
    "approved_by": null,
    "status": "draft — pendente validação jurídica e aprovação dos 5 presidentes",

    "1_objetivo": "Estabelecer regras claras para publicação, crédito autoral e licenciamento de obras intelectuais produzidas no âmbito do Núcleo de Estudos e Pesquisa em IA & GP, respeitando a legislação brasileira de direitos autorais (Lei 9.610/1998), a Lei do Serviço Voluntário (Lei 9.608/1998), a LGPD (Lei 13.709/2018) e o Código de Ética do PMI.",

    "2_principios": [
      "Direitos morais (autoria, crédito, integridade) são inalienáveis e pertencem aos autores (Lei 9.610/1998, Art. 24-27)",
      "O Núcleo é uma colaboração multi-capítulo; IP não pertence a um único capítulo",
      "Pesquisadores devem ter caminho claro para publicação com crédito adequado",
      "Transparência e equidade entre voluntários de todos os capítulos",
      "Proteção de informações confidenciais e dados pessoais (LGPD)"
    ],

    "3_tracks": {
      "track_a_aberto": {
        "nome": "Track A — Aberto",
        "tipos": "Artigos, reviews comparativas, análises de mercado, webinars, posts de blog, apresentações em eventos",
        "licenca": "CC-BY 4.0 (Creative Commons Atribuição 4.0 Internacional)",
        "aprovacao": "Notificação ao Gerente de Projeto (não requer autorização prévia)",
        "credito": "Autor(es) individual(is) + 'Núcleo de Estudos e Pesquisa em IA & GP — PMI [Capítulos]'",
        "exemplos": "Board items de tribos, webinars mensais, posts no blog nucleoia.vitormr.dev, submissões a congressos",
        "restricoes": "Não pode incluir dados PII, informações confidenciais de membros, ou material protegido do PMI (PMBOK, figuras, glossário) sem permissão CCC"
      },
      "track_b_framework": {
        "nome": "Track B — Framework",
        "tipos": "Frameworks originais, metodologias, ferramentas conceituais, templates reutilizáveis, código-fonte de ferramentas",
        "licenca": "CC-BY-SA 4.0 (para documentos/metodologias) ou MIT (para código-fonte)",
        "aprovacao": "Gerente de Projeto + pelo menos 1 presidente de capítulo parceiro",
        "credito": "Autores individuais (por contribuição substantiva) + líder da tribo (se supervisionou) + Núcleo",
        "exemplos": "EAA (Engenharia de Agentes Autônomos), CPMAI study materials, templates de avaliação",
        "restricoes": "Revisão prévia pelo GP para garantir que não contém IP de terceiros ou dados proprietários"
      },
      "track_c_restrito": {
        "nome": "Track C — Restrito",
        "tipos": "Algoritmos proprietários, modelos de scoring, dados de seleção, invenções patenteáveis, dados PII agregados",
        "licenca": "Proprietário (Núcleo/PMI-GO como capítulo sede)",
        "aprovacao": "Gerente de Projeto + presidente do capítulo sede + DPO (quando envolver dados pessoais)",
        "credito": "Inventores/autores registrados internamente; publicação externa requer aprovação específica",
        "exemplos": "Scoring de processo seletivo, algoritmos de matching tribo-candidato, modelos preditivos",
        "restricoes": "Acesso restrito. Avaliação de patenteabilidade antes de qualquer divulgação (Lei 9.279/1996)"
      }
    },

    "4_regras_credito": {
      "autoria": "Todo output inclui nome dos autores individuais na ordem de contribuição substantiva",
      "afiliacao": "Formato: Nome do Autor, Núcleo de Estudos e Pesquisa em IA & GP — PMI [Capítulo de origem]",
      "lider_tribo": "Líder da tribo é coautor automático se supervisionou o trabalho e contribuiu intelectualmente",
      "gp": "Gerente de Projeto é mencionado em acknowledgments, não como coautor (exceto se contribuiu intelectualmente)",
      "capitulo": "Todos os capítulos signatários dos Acordos de Cooperação são citados na afiliação institucional",
      "plataforma": "A plataforma (nucleoia.vitormr.dev) é citada como infraestrutura de apoio, não como autora"
    },

    "5_publicacao_externa": {
      "congressos": "Submissão a congressos/seminários requer notificação ao GP com 15 dias de antecedência. GP pode solicitar revisão, mas não pode vetar publicação Track A.",
      "journals": "Submissão a periódicos acadêmicos segue mesmas regras de Track A/B conforme natureza do conteúdo.",
      "webinars": "Webinars internos são Track A por padrão. Gravações ficam disponíveis na plataforma.",
      "midia": "Entrevistas e matérias em mídia sobre o Núcleo requerem coordenação com o GP e o capítulo sede.",
      "pmi_events": "Apresentações em eventos PMI (CBGPL, PMI Global Congress, etc.) seguem Track A com notificação ao GP e ao presidente do capítulo de origem do apresentador."
    },

    "6_ip_cooperacao": {
      "multi_capitulo": "Obras produzidas por voluntários de qualquer capítulo parceiro recebem tratamento igualitário quanto a crédito e direitos.",
      "obra_coletiva": "Obras com contribuições de múltiplos voluntários são consideradas obras coletivas (Lei 9.610/1998, Art. 5, VIII-h). Direitos patrimoniais pertencem ao Núcleo como programa.",
      "saida_capitulo": "Em caso de saída de capítulo (aviso de 30 dias conforme Acordo de Cooperação), o capítulo retém direito de uso perpétuo das obras criadas durante sua participação, sem exclusividade.",
      "addendum": "Cada Acordo de Cooperação bilateral deverá incluir addendum de IP referenciando esta política."
    },

    "7_material_pmi": {
      "restricao": "Material protegido do PMI (PMBOK Guide, figuras, glossário) NÃO pode ser reproduzido na wiki ou publicações sem permissão via Copyright Clearance Center (CCC) ou PMI Permissions Form.",
      "excecoes_capitulo": "Capítulos têm permissão parcial conforme PMI Chapter Manual — verificar escopo antes de usar.",
      "ai_training": "Publicações do PMI incluem cláusula NO AI TRAINING (©2025). Respeitar integralmente.",
      "citacao": "Citação breve (até 650 palavras) com fonte completa é permitida como fair use."
    },

    "8_revisao": "Esta política será revisada anualmente ou quando houver mudança significativa na composição de capítulos ou na legislação aplicável."
  }'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM governance_documents
  WHERE doc_type = 'policy'
    AND title ILIKE '%Publicação e Propriedade Intelectual%'
);

-- ═══ PART 2: CR-050 — Revisão de IP e Política de Publicação ═══

INSERT INTO change_requests (
  cr_number, title, description, cr_type, status, priority, impact_level,
  impact_description, justification, proposed_changes, gc_references,
  manual_version_from, requested_by, requested_by_role,
  submitted_at, created_at, updated_at
)
SELECT
  'CR-050',
  'Revisão da Cláusula de Propriedade Intelectual e Adoção de Política de Publicação',
  'A cláusula 2 do Termo de Voluntariado atual ("todos os direitos [...] cedidos ao PMI Goiás por prazo indeterminado") apresenta 4 problemas: (1) viola direitos morais inalienáveis (Lei 9.610/1998 Art. 24-27); (2) cessão genérica sem especificação de direitos é restritiva judicialmente (Art. 50); (3) cessão de obras futuras por prazo indeterminado é nula além de 5 anos (Art. 49§4); (4) atribui IP a um único capítulo quando o programa é multi-capítulo. Adicionalmente, não existe política de publicação que defina como pesquisadores podem publicar outputs do programa, criando barreira ao engajamento e à sustentabilidade.',
  'structural',
  'submitted',
  'high',
  'high',
  'Afeta todos os 52 voluntários ativos de 5 capítulos (GO: 19, CE: 14, MG: 9, DF: 6, RS: 4), 7 tribos ativas, e a capacidade de publicação científica do programa. Impacta diretamente engajamento de pesquisadores e sustentabilidade.',
  'Fundamentação legal: Lei 9.610/1998 (direitos autorais — Art. 11, 24-27, 49§4, 50); Lei 9.608/1998 (voluntariado — Art. 2); PMI Code of Ethics §3.3.4 (respeito a direitos de propriedade). Referências: CNCF IP Policy, Apache CLA, Linux Foundation DCO. Análise de 6 documentos PMI (Terms of Use, Permissions, REP IP Guidelines, Code of Ethics, Purchasing Terms, Chapter Manual) confirmou que PMI não reivindica IP criado em plataformas independentes de capítulos.',
  'MUDANÇAS PROPOSTAS:

1. REVISÃO DA CLÁUSULA 2 DO TERMO DE VOLUNTARIADO
   - 2.1: Voluntário retém direitos morais (autoria, crédito, integridade) — conforme lei
   - 2.2: Voluntário concede ao NÚCLEO (não PMI-GO) licença não-exclusiva, gratuita, irrevogável e mundial para reproduzir, distribuir, criar derivados e sublicenciar — para fins educacionais e científicos
   - 2.3: Voluntário mantém direito de publicar individualmente ou em coautoria, com atribuição ao Núcleo
   - 2.4: Publicações requerem NOTIFICAÇÃO ao GP (não autorização), exceto conteúdo confidencial (cláusula 9)
   - 2.5: Track de Propriedade Industrial para invenções patenteáveis

2. ADOÇÃO DA POLÍTICA DE PUBLICAÇÃO (3 TRACKS)
   - Track A (Aberto): CC-BY 4.0 — artigos, reviews, webinars. Notificação ao GP.
   - Track B (Framework): CC-BY-SA 4.0 / MIT — frameworks originais. GP + 1 presidente.
   - Track C (Restrito): Proprietário — dados PII, algoritmos, patentes. GP + presidente + DPO.

3. ADDENDUM DE IP NOS ACORDOS DE COOPERAÇÃO
   - Obras coletivas multi-capítulo: patrimoniais ao Núcleo como programa
   - Cada capítulo tem direito de uso irrevogável
   - Saída de capítulo: retém uso perpétuo, sem exclusividade

4. REGRAS DE CRÉDITO AUTORAL
   - Autores individuais na ordem de contribuição substantiva
   - Afiliação: "Núcleo de Estudos e Pesquisa em IA & GP — PMI [Capítulos]"
   - Líder de tribo como coautor se supervisionou trabalho

5. ATUALIZAÇÃO DO SISTEMA
   - Atualizar sign_volunteer_agreement() com nova cláusula 2 (subcláusulas 2.1-2.5)
   - Re-assinatura ou aceite incremental dos voluntários ativos
   - Inserir Política de Publicação como governance_document',
  ARRAY['Manual §3 (Voluntariado)', '§4.6 (Confidencialidade)', '§7 (Plataforma)', 'Apêndice B (Documentos Oficiais)'],
  'R3',
  (SELECT id FROM members WHERE name ILIKE '%Vitor%Rodovalho%' LIMIT 1),
  'manager',
  now(), now(), now()
WHERE NOT EXISTS (SELECT 1 FROM change_requests WHERE cr_number = 'CR-050');

NOTIFY pgrst, 'reload schema';
