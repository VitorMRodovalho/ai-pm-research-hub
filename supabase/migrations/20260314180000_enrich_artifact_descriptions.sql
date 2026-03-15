-- Enrich artifact descriptions with leader presentation context
-- Dates already correctly set in initial load; T3 stays NULL

-- ═══════════════════════════════════════════════════════════════
-- T1 — Hayala Curto (Radar Tecnológico do GP)
-- ═══════════════════════════════════════════════════════════════

UPDATE board_items SET
  title = 'Pesquisa: Artefatos de GP Potencializáveis com IA',
  description = 'Levantamento de quais entregas da Gestão de Projetos podem ser potencializadas pelo uso de IA e como isso tem sido feito atualmente. Matriz de avaliação com foco em arquitetura agêntica. Entrevistas com profissionais e revisão de literatura sobre automação de artefatos de GP.'
WHERE id = '57b85b8f-5a40-4b61-9629-bd77e4e0e93a';

UPDATE board_items SET
  title = 'Artigo LinkedIn — Quick Win Radar Tecnológico',
  description = 'Artigo rápido para LinkedIn com insights iniciais da pesquisa sobre como IA transforma artefatos clássicos de GP. Foco em visibilidade externa e engajamento da comunidade PMI. Formato acessível com exemplos práticos de ferramentas.'
WHERE id = '9a5428b7-5dea-458b-b344-34eee2e3a5a1';

UPDATE board_items SET
  title = 'Matriz de Artefatos Potencializáveis por IA',
  description = 'Framework de classificação de artefatos de GP segundo potencial de potencialização por IA. Eixos: complexidade do artefato × maturidade da IA disponível × impacto no projeto. Resultado: ranking priorizado para implementação de padrões agênticos.'
WHERE id = '15cac7aa-2d85-4d6b-9e57-f2e1d70ec95f';

UPDATE board_items SET
  title = 'Implementação de 2 Padrões Agênticos em GP',
  description = 'Prova de conceito implementando 2 padrões agênticos selecionados da matriz. Cada padrão aplicado a um artefato real de GP com medição de eficiência (tempo, qualidade, custo). Documentação de prompts, fluxos e resultados comparativos antes/depois.'
WHERE id = '9c49126e-7b2f-40d3-9b86-38b7e6d7d50e';

UPDATE board_items SET
  title = 'Artigo Acadêmico — Radar Tecnológico e Padrões Agênticos',
  description = 'Artigo acadêmico consolidando os resultados da pesquisa sobre artefatos de GP potencializáveis por IA. Inclui a matriz de classificação, os 2 pilotos agênticos e análise comparativa. Alvo: submissão para publicação PMI ou periódico indexado.'
WHERE id = '13e404b1-fb70-4e62-811c-e1320b6bde3e';

-- ═══════════════════════════════════════════════════════════════
-- T2 — Débora Moura (Agentes Autônomos)
-- ═══════════════════════════════════════════════════════════════

UPDATE board_items SET
  title = 'Plano Inicial + Framework EAA (Engenharia de Agentes Autônomos)',
  description = 'Definição do framework EAA — Engenharia de Agentes Autônomos aplicada a GP. Inclui taxonomia de agentes (monitoramento de cronograma, alertas de risco, métricas de planos de ação, geração de relatórios), arquitetura de referência e critérios de avaliação. Base para todas as entregas subsequentes da tribo.'
WHERE id = '5585a53f-2cec-48ab-babb-38825ec0d18c';

UPDATE board_items SET
  title = 'Artigo LinkedIn — Agentes Autônomos em GP',
  description = 'Artigo LinkedIn introduzindo o conceito de agentes autônomos aplicados à gestão de projetos. Foco em casos de uso práticos: monitoramento automatizado de cronograma, alertas preditivos de risco e geração automática de status reports. Linguagem acessível para a comunidade PMI.'
WHERE id = '642fe90f-20ad-4ba4-a9e7-05470ed7c5de';

UPDATE board_items SET
  title = 'Webinar Comunitário — Agentes Autônomos em Ação',
  description = 'Webinar aberto à comunidade PMI demonstrando agentes autônomos funcionais. Demo ao vivo de pelo menos um agente do framework EAA. Q&A com participantes sobre aplicabilidade em seus contextos. Gravação disponibilizada no canal do núcleo.'
WHERE id = '6e8ef406-0e41-4ade-9860-2bc5f898e624';

UPDATE board_items SET
  title = 'Publicação Final — Framework EAA',
  description = 'E-book, Guia Prático ou Artigo Científico completo. Resultado esperado: framework EAA estruturado + agente funcional + publicação científica com impacto real no PMI. Escopo do agente: monitoramento de cronograma, alertas de risco, métricas de planos de ação, geração de relatórios.'
WHERE id = '2c850373-64b9-4416-8b18-5dcf4332bb0c';

-- ═══════════════════════════════════════════════════════════════
-- T3 — Marcel Fleming (TMO & PMO do Futuro) — dates stay NULL
-- ═══════════════════════════════════════════════════════════════

UPDATE board_items SET
  title = 'Ideação do Projeto Piloto TMO/PMO',
  description = 'Fase de ideação: definir escopo, problema central e hipóteses do projeto piloto sobre TMO (Transformation Management Office) e PMO do Futuro com IA. Inclui benchmark de PMOs que já usam IA, definição de métricas de sucesso e seleção de ferramentas candidatas.'
WHERE id = '00feaf8b-7c41-40be-b16b-c7bbbe5dffc2';

UPDATE board_items SET
  title = 'Arquitetura do Modelo TMO/PMO do Futuro',
  description = 'Desenho da arquitetura do modelo TMO/PMO do Futuro integrado com IA. Componentes: camada de dados (portfólio, recursos, riscos), camada de inteligência (agentes, modelos preditivos), camada de decisão (dashboards, recomendações). Validação com stakeholders internos.'
WHERE id = 'f669df3e-cb2a-46dd-8f41-9e24d68e66f1';

UPDATE board_items SET
  title = 'Construção da PoC — TMO com IA',
  description = 'Desenvolvimento técnico da prova de conceito: implementação dos componentes core do modelo TMO/PMO com IA. Integração com ferramentas existentes (Supabase, n8n, ou similares). Sprint de desenvolvimento com entregas incrementais.'
WHERE id = 'e80aae52-9ff8-4a18-b7a0-6fe7a7f84133';

UPDATE board_items SET
  title = 'Execução e Validação da PoC',
  description = 'Execução da PoC em contexto real ou simulado. Coleta de dados de desempenho, feedback dos usuários e métricas de eficácia. Comparação com baseline (processo manual). Documentação de lições aprendidas e ajustes necessários.'
WHERE id = '3c5344a7-4b37-453b-aaaa-14da7f94ac42';

UPDATE board_items SET
  title = 'Relatório / Artigo Final TMO com IA',
  description = 'Relatório ou artigo acadêmico consolidando resultados do piloto TMO/PMO do Futuro. Estrutura: contexto e problema, revisão de literatura, modelo proposto, resultados da PoC, análise comparativa, conclusões e próximos passos. Alvo: publicação PMI ou periódico de gestão de projetos.'
WHERE id = 'e0142a94-a405-4cb0-aade-e8411a3a7b41';

-- ═══════════════════════════════════════════════════════════════
-- T4 — Fernando Maquiaveli (Cultura & Change)
-- ═══════════════════════════════════════════════════════════════

UPDATE board_items SET
  title = 'Roadmap de Pesquisa — Cultura & Change com IA',
  description = 'Roadmap de pesquisa da tribo Cultura & Change: como a IA pode auxiliar processos de gestão de mudança organizacional. Mapeamento de ferramentas de IA para change management, definição de hipóteses de pesquisa e cronograma de entregas.'
WHERE id = '8c06f098-173f-480c-8eba-bd0272ccfdc0';

UPDATE board_items SET
  title = 'Biblioteca de Prompts para Change Management',
  description = 'Biblioteca curada de prompts para gestão de mudanças organizacionais. Categorias: diagnóstico de resistência, comunicação de mudança, engajamento de stakeholders, treinamento adaptativo, monitoramento de adoção. Testados e validados com ChatGPT, Claude e Gemini.'
WHERE id = 'b4be26bc-3556-49bd-8719-ce07c7d50318';

UPDATE board_items SET
  title = 'Infográfico v1 — IA na Gestão de Mudança',
  description = 'Primeira versão do infográfico visual sobre o papel da IA na gestão de mudança organizacional. Formato: fluxo visual mostrando pontos de intervenção da IA no ciclo de change management. Para divulgação em redes sociais e comunidade PMI.'
WHERE id = '2c5c557c-8779-40c4-bc7a-59d820effe9f';

UPDATE board_items SET
  title = 'Playbook v1 — IA para Change Management',
  description = 'Primeira versão do playbook prático de como usar IA em processos de change management. Estrutura: framework conceitual, toolkit de prompts, templates de comunicação assistida por IA, roteiro de implementação passo a passo. Validado com casos reais.'
WHERE id = '192ab47d-60f4-471d-96be-ab0a3dbabbd8';

UPDATE board_items SET
  title = 'Report de Resultados Intermediários T4',
  description = 'Relatório de resultados intermediários da pesquisa sobre cultura e change management com IA. Métricas coletadas, feedback de aplicação prática da biblioteca de prompts e do playbook v1. Análise de gaps e ajustes para segunda fase.'
WHERE id = '8ca8e861-eac2-40a4-b843-ec4848825821';

UPDATE board_items SET
  title = 'Infográfico v2 — Resultados e Impacto',
  description = 'Segunda versão do infográfico incorporando dados reais de aplicação. Comparativo antes/depois do uso de IA em processos de mudança. Métricas de eficácia: tempo de adoção, resistência reduzida, satisfação dos stakeholders.'
WHERE id = '4808a322-9b45-4fc5-90c2-6a8ec1890c56';

UPDATE board_items SET
  title = 'Estudo de Caso Prático — Change Management com IA',
  description = 'Estudo de caso documentando implementação real de mudança organizacional assistida por IA. Contexto empresarial, desafios encontrados, ferramentas utilizadas, resultados mensuráveis. Formato publicável para ProjectManagement.com ou similar.'
WHERE id = 'c4e458b2-b9c6-453c-a17f-7b431451412c';

UPDATE board_items SET
  title = 'Artigo Acadêmico Publicado — Entrega Final T4',
  description = 'Artigo acadêmico publicado consolidando toda a pesquisa da tribo. Revisão por pares, metodologia científica aplicada. Temas: impacto da IA em change management, eficácia comparativa de abordagens tradicionais vs. IA-assistidas. Submissão para periódico indexado ou conferência PMI.'
WHERE id = '17ac3ee5-b3f5-40b6-9052-185788a91ea5';

UPDATE board_items SET
  description = 'Webinar da tribo Cultura & Change para a comunidade PMI e convidados. Apresentação dos resultados da pesquisa, demo da biblioteca de prompts e do playbook. Sessão de Q&A e coleta de feedback para iteração final.'
WHERE id = 'd234c108-dbe4-4f5e-813a-d2880985b770';

UPDATE board_items SET
  title = 'Playbook v2 — Versão Consolidada',
  description = 'Segunda versão do playbook incorporando feedbacks da comunidade, resultados do estudo de caso e iterações sobre a biblioteca de prompts. Versão final para distribuição ampla na comunidade PMI.'
WHERE id = 'a0268489-d5ef-4da9-aecb-04336c19e216';

UPDATE board_items SET
  title = 'Proposta de Workshop — IA em Change Management',
  description = 'Proposta estruturada de workshop hands-on sobre uso de IA em change management. Inclui: roteiro de atividades, materiais necessários, pré-requisitos dos participantes, métricas de aprendizagem. Para aplicação em eventos PMI e organizações parceiras.'
WHERE id = 'd1922919-feed-413a-b9cc-3d2dda325546';

-- ═══════════════════════════════════════════════════════════════
-- T5 — Jefferson Pinto (Talentos & Upskilling)
-- ═══════════════════════════════════════════════════════════════

UPDATE board_items SET
  title = 'Taxonomia de Competências em IA para GP',
  description = 'Definição da taxonomia de competências que profissionais de gestão de projetos precisam desenvolver para trabalhar com IA. Baseada em frameworks PMI (PMBOK, PMIef) e complementada com competências específicas de IA. Categorias: técnicas, comportamentais, estratégicas.'
WHERE id = '51cdcb41-b7d0-41c2-9f5a-6a1e50c92f5c';

UPDATE board_items SET
  title = 'Matriz de Competências × Proficiência × IA',
  description = 'Matriz cruzando competências identificadas com níveis de proficiência (básico, intermediário, avançado) e ferramentas de IA correspondentes. Para cada célula: exemplos de atividades, critérios de avaliação e recursos de aprendizagem recomendados.'
WHERE id = 'f8dfcec7-95ac-41bc-89d9-ac5812e39c82';

UPDATE board_items SET
  title = 'Rubricas de Proficiência em IA para GP',
  description = 'Rubricas detalhadas de proficiência para cada competência da taxonomia. Descritores comportamentais observáveis por nível. Permite autoavaliação e avaliação por pares. Alinhadas com credenciais PMI e frameworks de competência digital.'
WHERE id = '17f390d6-53b3-4f09-af3c-e4406356b6c3';

UPDATE board_items SET
  title = 'Checklist de Evidências — Gate A',
  description = 'Checklist para validação de competências em IA: quais evidências um profissional de GP deve apresentar para comprovar proficiência. Formatos aceitos: certificados, projetos realizados, portfólio de prompts, resultados mensuráveis. Marco Gate A do toolkit.'
WHERE id = '9aed247c-d22d-47b3-89ae-63be7dc6e6ad';

UPDATE board_items SET
  title = 'Toolkit v1.0 de Talentos & Upskilling — Gate B',
  description = 'Toolkit completo v1.0: taxonomia + matriz + rubricas + checklist integrados em documento/ferramenta utilizável. Inclui guia de aplicação para organizações e indivíduos. Marco Gate B — versão pronta para validação externa.'
WHERE id = '1dd2aabb-ad0e-4a59-b26e-db469b8e7e2e';

UPDATE board_items SET
  title = 'Artigo Acadêmico Aplicado — Competências de IA em GP',
  description = 'Artigo acadêmico aplicado documentando o toolkit e seus resultados de validação. Metodologia: design science research. Contribuição: framework prático e testado de upskilling em IA para profissionais de projetos. Alvo: periódico de gestão de projetos ou educação profissional.'
WHERE id = '51b61145-4949-45cc-afab-c4b3f9eb3af8';

UPDATE board_items SET
  title = 'Webinário de Discussão — Competências de IA',
  description = 'Webinário interativo com a comunidade PMI para discutir as competências de IA identificadas. Formato: apresentação dos resultados + painel de discussão com profissionais de mercado. Coleta de feedback para refinamento do toolkit antes da versão final.'
WHERE id = '516369c6-e59f-4d11-810b-e55f93f74c8b';

UPDATE board_items SET
  title = 'Relatório Final — Toolkit Consolidado',
  description = 'Relatório final consolidando o toolkit completo de talentos e upskilling em IA para GP. Inclui: taxonomia validada, matriz atualizada, rubricas refinadas, resultados do webinário, recomendações para organizações. Entrega final da tribo — publicação e distribuição ampla.'
WHERE id = '5d9d7541-a09b-4a35-b2e0-0cdeabac65d1';

-- ═══════════════════════════════════════════════════════════════
-- T6 — Fabricio Costa (ROI & Portfólio)
-- ═══════════════════════════════════════════════════════════════

UPDATE board_items SET
  title = 'Pesquisa Inicial + Escopo — ROI de IA em Portfólios',
  description = 'Pesquisa inicial e definição de escopo: como medir ROI de projetos de IA em portfólios organizacionais. Revisão de modelos existentes (TEI, TCO, Value-at-Risk), gaps identificados, proposta de modelo adaptado para contexto PMI. Definição de métricas e KPIs alvo.'
WHERE id = '956631d1-f48e-4d57-980f-f1ec838d10aa';

UPDATE board_items SET
  title = 'Artigo LinkedIn — Quick Win ROI de IA',
  description = 'Artigo LinkedIn quick win com insights provocativos sobre ROI de IA em portfólios de projetos. Formato: "5 mitos sobre ROI de IA que todo PM deve conhecer". Engajamento da comunidade e posicionamento da tribo como referência no tema.'
WHERE id = '4c588bc2-5041-4f35-a108-0c9324e2041e';

UPDATE board_items SET
  title = '1º Webinar — ROI de IA em Portfólios',
  description = 'Primeiro webinar aberto à comunidade sobre ROI e portfólio de IA. Apresentação do modelo conceitual, cases de mercado e demo preliminar da plataforma. Coleta de feedback e validação de hipóteses com profissionais da área.'
WHERE id = 'f5a77542-4007-4229-916b-ead5852b20e6';

UPDATE board_items SET
  title = 'Protótipo v1 — Plataforma de Mensuração de ROI',
  description = 'Primeira versão funcional do protótipo de plataforma para mensuração de ROI de projetos de IA. Funcionalidades: input de projetos, cálculo automatizado de métricas, dashboard visual de portfólio. Stack: web app com integração Supabase.'
WHERE id = 'd8396382-2fa9-44cc-bd77-73bb7e9926f2';

UPDATE board_items SET
  title = 'Artigos Contínuos — Série ROI & Portfólio',
  description = 'Série de artigos contínuos publicados ao longo do ciclo sobre diferentes aspectos de ROI de IA: métricas qualitativas vs. quantitativas, framework de priorização, estudos de caso, benchmarks de mercado. Mínimo 3 artigos LinkedIn + 1 para ProjectManagement.com.'
WHERE id = 'cbb0190f-9f4a-4040-bbd1-1d7de0a75abc';

UPDATE board_items SET
  title = 'Submissão de Artigo Acadêmico — ROI de IA',
  description = 'Submissão formal de artigo acadêmico sobre modelo de mensuração de ROI de IA em portfólios de projetos. Metodologia rigorosa, dados coletados da plataforma, análise estatística. Alvo: conferência PMI Global ou periódico de gestão de portfólio.'
WHERE id = 'bb93ccc1-c41a-4e06-885b-6145211cc001';

UPDATE board_items SET
  title = '2º Webinar — Resultados e Plataforma Final',
  description = 'Segundo webinar da tribo apresentando resultados consolidados e demo da plataforma final de mensuração de ROI. Comparativo com resultados do 1º webinar. Sessão hands-on para participantes testarem a plataforma.'
WHERE id = '65462c74-80dc-43e0-b53b-5b14a1b9e5e8';

UPDATE board_items SET
  title = 'Plataforma Final de Mensuração de ROI — Entrega Final',
  description = 'Versão final da plataforma de mensuração de ROI de IA em portfólios. Features completas: cálculo multi-métrica, comparativo temporal, exportação de relatórios, integração com dashboards existentes. Documentação técnica e de usuário. Entrega final da tribo.'
WHERE id = 'a3230f2b-eca3-4e1e-94c2-99f99a2b1be2';

-- ═══════════════════════════════════════════════════════════════
-- T7 — Marcos Klemz (Governança & Trustworthy AI)
-- ═══════════════════════════════════════════════════════════════

UPDATE board_items SET
  title = 'Estruturação dos Pilares Risco/Compliance para IA',
  description = 'Definição e estruturação dos pilares fundamentais de risco e compliance para projetos de IA em organizações. Mapeamento regulatório (LGPD, EU AI Act, NIST AI RMF), identificação de gaps em frameworks de GP existentes, proposta de extensão para incluir governança de IA.'
WHERE id = '54119833-ecf7-4a0a-80d2-d6b57f0f5cfc';

UPDATE board_items SET
  title = 'Framework de Governança de IA para Organizações',
  description = 'Framework completo de governança de IA: papéis e responsabilidades, processos de aprovação, controles de qualidade, monitoramento contínuo e auditoria. Alinhado com PMBOK, ISO 42001 e boas práticas de Responsible AI. Inclui templates e checklists aplicáveis.'
WHERE id = 'ad36b62e-3c2a-4f26-9c3e-5e9ef2caa5c1';

UPDATE board_items SET
  title = 'Matriz de Qualidade de Dados para IA',
  description = 'Matriz de avaliação de qualidade de dados especificamente para projetos de IA. Dimensões: completude, consistência, acurácia, atualidade, representatividade, viés. Scoring automatizado com recomendações de remediação. Ferramenta prática para PMOs e líderes de projeto.'
WHERE id = '94e17c80-3e1e-4cd3-b833-03b2e8e17b80';

UPDATE board_items SET
  title = 'Piloto de Governança + Workshop de Validação — Gate A',
  description = 'Piloto aplicando o framework de governança em contexto real ou simulado. Workshop de validação com profissionais de GP e compliance. Coleta de métricas de usabilidade e eficácia. Marco Gate A: framework validado e pronto para refinamento.'
WHERE id = '972f7154-cb08-4daa-a1e7-5bdb23e2f86b';

UPDATE board_items SET
  title = 'Guia de Métricas de Valor para Projetos de IA',
  description = 'Guia prático de métricas para avaliar valor gerado por projetos de IA. Além de ROI financeiro: métricas de confiabilidade, fairness, explicabilidade, segurança e conformidade regulatória. Templates de dashboard e relatórios para stakeholders.'
WHERE id = '05c5153b-03fd-4a3f-9e1b-89a80fe2e50a';

UPDATE board_items SET
  title = 'Checklist de Critérios de Aceite para GenAI/RAG',
  description = 'Checklist detalhado de critérios de aceite para entregas de projetos GenAI e RAG. Cobre: qualidade das respostas, alucinações, latência, custo por query, privacidade dos dados, conformidade regulatória. Formato go/no-go para cada critério com thresholds configuráveis.'
WHERE id = 'f310c360-a4cb-41b2-ac74-ee0f97f15d79';

UPDATE board_items SET
  title = 'Toolkit v1.0 de Governança de IA — Gate B',
  description = 'Toolkit completo v1.0 integrando todos os artefatos: framework de governança, matriz de dados, métricas de valor, checklist GenAI/RAG. Documento consolidado + templates + ferramenta de avaliação. Marco Gate B: versão para distribuição piloto.'
WHERE id = '4f5a143b-dfc5-4b1e-876e-e64d2e5e6a4f';

UPDATE board_items SET
  title = 'Treinamento da Comunidade + Coleta de Feedbacks',
  description = 'Sessão de treinamento para a comunidade PMI sobre o toolkit de governança de IA. Formato workshop hands-on com aplicação prática dos checklists e frameworks. Coleta estruturada de feedbacks para refinamento final antes do relatório.'
WHERE id = '7460dcf3-bc15-46d1-a8a4-7d1e86744866';

UPDATE board_items SET
  title = 'Relatório Final — Toolkit de Governança Consolidado',
  description = 'Relatório final consolidando framework de governança, toolkit completo e resultados de validação. Inclui: análise de eficácia, feedback da comunidade, roadmap de evolução, recomendações para adoção organizacional. Entrega final da tribo — publicação e distribuição ampla.'
WHERE id = '3ee499ab-c2c0-4d5a-8df7-c9ac8a0aede1';

-- ═══════════════════════════════════════════════════════════════
-- T8 — Ana Carla Cavalcante (Inclusão & Colaboração)
-- ═══════════════════════════════════════════════════════════════

UPDATE board_items SET
  title = 'Artigo de Revisão Crítica — Cérebro Neuroatípico e IA',
  description = 'Artigo acadêmico de revisão crítica sobre como o cérebro neuroatípico interage com ferramentas de IA. Revisão de literatura em neurociência cognitiva e HCI (Human-Computer Interaction). Hipótese: perfis neuroatípicos podem ter vantagens específicas no uso de IA generativa. Pilar 1 do Neuro-Advantage Framework.'
WHERE id = 'ad17ebe4-6050-4195-a094-13c4fa1eac72';

UPDATE board_items SET
  title = 'Protocolo Metodológico — Neuro-Advantage Framework',
  description = 'Protocolo metodológico rigoroso para o framework de inclusão e neurodiversidade. Define: metodologia de pesquisa (mixed-methods), critérios de seleção de participantes, instrumentos de coleta (questionários, testes cognitivos, entrevistas), análise de dados, ética e consentimento. Pilar 2.'
WHERE id = '06eea35c-b16d-460e-9a29-3aa09f9fcd79';

UPDATE board_items SET
  title = 'Modelo de Alinhamento Cognitivo — Neurodiversidade × IA',
  description = 'Modelo teórico de alinhamento entre perfis cognitivos neuroatípicos (TDAH, TEA, dislexia, altas habilidades) e ferramentas de IA. Mapeia: pontos fortes cognitivos × funcionalidades de IA × contextos de projeto. Resultado: recomendações personalizadas de ferramentas por perfil. Pilar 3.'
WHERE id = '264fe070-6e38-49cc-acca-119ad35bc69f';

UPDATE board_items SET
  title = 'Palestra/Webinar — Neurodiversidade e IA em Projetos',
  description = 'Palestra ou webinar explicativo sobre neurodiversidade e IA em gestão de projetos. Público: comunidade PMI e profissionais de RH/D&I. Formato: apresentação conceitual + casos reais + discussão aberta. Objetivo: sensibilizar e gerar interesse para o estudo de campo. Pilar 4.'
WHERE id = 'de8e6b0e-0b5b-4d3f-a5d1-939c47ee8cb8';

UPDATE board_items SET
  title = 'Estudo de Campo — Neuro-Advantage em Ambientes de Projeto',
  description = 'Estudo de campo com profissionais neuroatípicos em ambientes reais de projeto. Coleta de dados quantitativos (desempenho, produtividade, satisfação) e qualitativos (entrevistas, diários). Comparação com grupo controle neurotípico. Análise estatística e interpretação. Pilar 5 — pesquisa multi-ciclo.'
WHERE id = 'ba7efa6f-1d7f-429f-9149-8cab454b39e4';

UPDATE board_items SET
  title = 'Neuro-Advantage Framework 1.0 — Entrega Final Multi-Ciclo',
  description = 'Framework Neuro-Advantage 1.0: modelo completo integrando revisão crítica, protocolo metodológico, modelo de alinhamento cognitivo, resultados do estudo de campo. Publicação acadêmica + guia prático para organizações. Entrega final da pesquisa multi-ciclo (ciclos 3+4+5, pré-aprovado 1.5 ano).'
WHERE id = '5184f209-7266-4d77-81cf-831eabd89bbe';
