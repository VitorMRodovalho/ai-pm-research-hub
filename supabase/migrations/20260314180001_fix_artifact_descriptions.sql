-- Fix descriptions that didn't match by ID (match by title + board instead)

-- T1 — Hayala Curto (board_id = '430df293-6676-4507-b893-98421a1397ca')
UPDATE board_items SET
  title = 'Pesquisa: Artefatos de GP Potencializáveis com IA',
  description = 'Levantamento de quais entregas da Gestão de Projetos podem ser potencializadas pelo uso de IA e como isso tem sido feito atualmente. Matriz de avaliação com foco em arquitetura agêntica. Entrevistas com profissionais e revisão de literatura sobre automação de artefatos de GP.'
WHERE board_id = '430df293-6676-4507-b893-98421a1397ca' AND title LIKE 'Pesquisa:%artefatos%';

UPDATE board_items SET
  title = 'Artigo LinkedIn — Quick Win Radar Tecnológico',
  description = 'Artigo rápido para LinkedIn com insights iniciais da pesquisa sobre como IA transforma artefatos clássicos de GP. Foco em visibilidade externa e engajamento da comunidade PMI. Formato acessível com exemplos práticos de ferramentas.'
WHERE board_id = '430df293-6676-4507-b893-98421a1397ca' AND title LIKE 'Artigo LinkedIn%Quick%';

UPDATE board_items SET
  title = 'Matriz de Artefatos Potencializáveis por IA',
  description = 'Framework de classificação de artefatos de GP segundo potencial de potencialização por IA. Eixos: complexidade do artefato × maturidade da IA disponível × impacto no projeto. Resultado: ranking priorizado para implementação de padrões agênticos.'
WHERE board_id = '430df293-6676-4507-b893-98421a1397ca' AND title LIKE 'Matriz de artefatos%';

UPDATE board_items SET
  title = 'Implementação de 2 Padrões Agênticos em GP',
  description = 'Prova de conceito implementando 2 padrões agênticos selecionados da matriz. Cada padrão aplicado a um artefato real de GP com medição de eficiência (tempo, qualidade, custo). Documentação de prompts, fluxos e resultados comparativos antes/depois.'
WHERE board_id = '430df293-6676-4507-b893-98421a1397ca' AND title LIKE 'Implementação de 2 padrões%';

UPDATE board_items SET
  title = 'Artigo Acadêmico — Radar Tecnológico e Padrões Agênticos',
  description = 'Artigo acadêmico consolidando os resultados da pesquisa sobre artefatos de GP potencializáveis por IA. Inclui a matriz de classificação, os 2 pilotos agênticos e análise comparativa. Alvo: submissão para publicação PMI ou periódico indexado.'
WHERE board_id = '430df293-6676-4507-b893-98421a1397ca' AND title = 'Artigo Acadêmico';

-- T3 — Marcel Fleming (board_id = '50474fd3-adbc-4980-ba2e-6dffec420321')
UPDATE board_items SET
  title = 'Ideação do Projeto Piloto TMO/PMO',
  description = 'Fase de ideação: definir escopo, problema central e hipóteses do projeto piloto sobre TMO (Transformation Management Office) e PMO do Futuro com IA. Inclui benchmark de PMOs que já usam IA, definição de métricas de sucesso e seleção de ferramentas candidatas.'
WHERE board_id = '50474fd3-adbc-4980-ba2e-6dffec420321' AND title LIKE 'Ideação do Projeto%';

UPDATE board_items SET
  title = 'Arquitetura do Modelo TMO/PMO do Futuro',
  description = 'Desenho da arquitetura do modelo TMO/PMO do Futuro integrado com IA. Componentes: camada de dados (portfólio, recursos, riscos), camada de inteligência (agentes, modelos preditivos), camada de decisão (dashboards, recomendações). Validação com stakeholders internos.'
WHERE board_id = '50474fd3-adbc-4980-ba2e-6dffec420321' AND title LIKE 'Arquitetura do Modelo%';

UPDATE board_items SET
  title = 'Construção da PoC — TMO com IA',
  description = 'Desenvolvimento técnico da prova de conceito: implementação dos componentes core do modelo TMO/PMO com IA. Integração com ferramentas existentes (Supabase, n8n, ou similares). Sprint de desenvolvimento com entregas incrementais.'
WHERE board_id = '50474fd3-adbc-4980-ba2e-6dffec420321' AND title LIKE 'Construção da PoC%';

UPDATE board_items SET
  title = 'Execução e Validação da PoC',
  description = 'Execução da PoC em contexto real ou simulado. Coleta de dados de desempenho, feedback dos usuários e métricas de eficácia. Comparação com baseline (processo manual). Documentação de lições aprendidas e ajustes necessários.'
WHERE board_id = '50474fd3-adbc-4980-ba2e-6dffec420321' AND title LIKE 'Execução da PoC%';

UPDATE board_items SET
  title = 'Relatório / Artigo Final TMO com IA',
  description = 'Relatório ou artigo acadêmico consolidando resultados do piloto TMO/PMO do Futuro. Estrutura: contexto e problema, revisão de literatura, modelo proposto, resultados da PoC, análise comparativa, conclusões e próximos passos. Alvo: publicação PMI ou periódico de gestão de projetos.'
WHERE board_id = '50474fd3-adbc-4980-ba2e-6dffec420321' AND title LIKE 'Relatório / Artigo Final%';

-- T5 — Jefferson Pinto (board_id = 'bb0c431c-3269-4b03-b24e-cf406b59ee77')
UPDATE board_items SET
  title = 'Taxonomia de Competências em IA para GP',
  description = 'Definição da taxonomia de competências que profissionais de gestão de projetos precisam desenvolver para trabalhar com IA. Baseada em frameworks PMI (PMBOK, PMIef) e complementada com competências específicas de IA. Categorias: técnicas, comportamentais, estratégicas.'
WHERE board_id = 'bb0c431c-3269-4b03-b24e-cf406b59ee77' AND title LIKE 'Taxonomia de competências%';

UPDATE board_items SET
  title = 'Matriz de Competências × Proficiência × IA',
  description = 'Matriz cruzando competências identificadas com níveis de proficiência (básico, intermediário, avançado) e ferramentas de IA correspondentes. Para cada célula: exemplos de atividades, critérios de avaliação e recursos de aprendizagem recomendados.'
WHERE board_id = 'bb0c431c-3269-4b03-b24e-cf406b59ee77' AND title LIKE 'Matriz de Competências%';

UPDATE board_items SET
  title = 'Rubricas de Proficiência em IA para GP',
  description = 'Rubricas detalhadas de proficiência para cada competência da taxonomia. Descritores comportamentais observáveis por nível. Permite autoavaliação e avaliação por pares. Alinhadas com credenciais PMI e frameworks de competência digital.'
WHERE board_id = 'bb0c431c-3269-4b03-b24e-cf406b59ee77' AND title LIKE 'Rubricas de Proficiência%';

UPDATE board_items SET
  title = 'Checklist de Evidências — Gate A',
  description = 'Checklist para validação de competências em IA: quais evidências um profissional de GP deve apresentar para comprovar proficiência. Formatos aceitos: certificados, projetos realizados, portfólio de prompts, resultados mensuráveis. Marco Gate A do toolkit.'
WHERE board_id = 'bb0c431c-3269-4b03-b24e-cf406b59ee77' AND title LIKE 'Checklist de Evidências%';

UPDATE board_items SET
  title = 'Toolkit v1.0 de Talentos & Upskilling — Gate B',
  description = 'Toolkit completo v1.0: taxonomia + matriz + rubricas + checklist integrados em documento/ferramenta utilizável. Inclui guia de aplicação para organizações e indivíduos. Marco Gate B — versão pronta para validação externa.'
WHERE board_id = 'bb0c431c-3269-4b03-b24e-cf406b59ee77' AND title = 'Toolkit v1.0';

UPDATE board_items SET
  title = 'Artigo Acadêmico Aplicado — Competências de IA em GP',
  description = 'Artigo acadêmico aplicado documentando o toolkit e seus resultados de validação. Metodologia: design science research. Contribuição: framework prático e testado de upskilling em IA para profissionais de projetos. Alvo: periódico de gestão de projetos ou educação profissional.'
WHERE board_id = 'bb0c431c-3269-4b03-b24e-cf406b59ee77' AND title LIKE 'Artigo Aplicado%';

UPDATE board_items SET
  title = 'Webinário de Discussão — Competências de IA',
  description = 'Webinário interativo com a comunidade PMI para discutir as competências de IA identificadas. Formato: apresentação dos resultados + painel de discussão com profissionais de mercado. Coleta de feedback para refinamento do toolkit antes da versão final.'
WHERE board_id = 'bb0c431c-3269-4b03-b24e-cf406b59ee77' AND title LIKE 'Webinário de Discussão%';

UPDATE board_items SET
  title = 'Relatório Final — Toolkit Consolidado',
  description = 'Relatório final consolidando o toolkit completo de talentos e upskilling em IA para GP. Inclui: taxonomia validada, matriz atualizada, rubricas refinadas, resultados do webinário, recomendações para organizações. Entrega final da tribo — publicação e distribuição ampla.'
WHERE board_id = 'bb0c431c-3269-4b03-b24e-cf406b59ee77' AND title = 'Relatório Final';

-- T6 — Fabricio Costa (board_id = '118b55be-9dcd-4b2d-82c7-5c457fb1fc1e') — 2 items that didn't match
UPDATE board_items SET
  title = '2º Webinar — Resultados e Plataforma Final',
  description = 'Segundo webinar da tribo apresentando resultados consolidados e demo da plataforma final de mensuração de ROI. Comparativo com resultados do 1º webinar. Sessão hands-on para participantes testarem a plataforma.'
WHERE board_id = '118b55be-9dcd-4b2d-82c7-5c457fb1fc1e' AND title LIKE '2%Webinar%' AND cycle = 3;

UPDATE board_items SET
  title = 'Plataforma Final de Mensuração de ROI — Entrega Final',
  description = 'Versão final da plataforma de mensuração de ROI de IA em portfólios. Features completas: cálculo multi-métrica, comparativo temporal, exportação de relatórios, integração com dashboards existentes. Documentação técnica e de usuário. Entrega final da tribo.'
WHERE board_id = '118b55be-9dcd-4b2d-82c7-5c457fb1fc1e' AND title LIKE 'Plataforma final%' AND cycle = 3;

-- T7 — Marcos Klemz (board_id = '38cc997c-9345-4ee1-acb5-ed2ddf33b734')
UPDATE board_items SET
  title = 'Estruturação dos Pilares Risco/Compliance para IA',
  description = 'Definição e estruturação dos pilares fundamentais de risco e compliance para projetos de IA em organizações. Mapeamento regulatório (LGPD, EU AI Act, NIST AI RMF), identificação de gaps em frameworks de GP existentes, proposta de extensão para incluir governança de IA.'
WHERE board_id = '38cc997c-9345-4ee1-acb5-ed2ddf33b734' AND title LIKE 'Estruturação pilares%';

UPDATE board_items SET
  title = 'Framework de Governança de IA para Organizações',
  description = 'Framework completo de governança de IA: papéis e responsabilidades, processos de aprovação, controles de qualidade, monitoramento contínuo e auditoria. Alinhado com PMBOK, ISO 42001 e boas práticas de Responsible AI. Inclui templates e checklists aplicáveis.'
WHERE board_id = '38cc997c-9345-4ee1-acb5-ed2ddf33b734' AND title LIKE 'Framework de Governança%';

UPDATE board_items SET
  title = 'Matriz de Qualidade de Dados para IA',
  description = 'Matriz de avaliação de qualidade de dados especificamente para projetos de IA. Dimensões: completude, consistência, acurácia, atualidade, representatividade, viés. Scoring automatizado com recomendações de remediação. Ferramenta prática para PMOs e líderes de projeto.'
WHERE board_id = '38cc997c-9345-4ee1-acb5-ed2ddf33b734' AND title LIKE 'Matriz Qualidade%';

UPDATE board_items SET
  title = 'Piloto de Governança + Workshop de Validação — Gate A',
  description = 'Piloto aplicando o framework de governança em contexto real ou simulado. Workshop de validação com profissionais de GP e compliance. Coleta de métricas de usabilidade e eficácia. Marco Gate A: framework validado e pronto para refinamento.'
WHERE board_id = '38cc997c-9345-4ee1-acb5-ed2ddf33b734' AND title LIKE 'Piloto e Workshop%';

UPDATE board_items SET
  title = 'Guia de Métricas de Valor para Projetos de IA',
  description = 'Guia prático de métricas para avaliar valor gerado por projetos de IA. Além de ROI financeiro: métricas de confiabilidade, fairness, explicabilidade, segurança e conformidade regulatória. Templates de dashboard e relatórios para stakeholders.'
WHERE board_id = '38cc997c-9345-4ee1-acb5-ed2ddf33b734' AND title LIKE 'Guia de Métricas%';

UPDATE board_items SET
  title = 'Checklist de Critérios de Aceite para GenAI/RAG',
  description = 'Checklist detalhado de critérios de aceite para entregas de projetos GenAI e RAG. Cobre: qualidade das respostas, alucinações, latência, custo por query, privacidade dos dados, conformidade regulatória. Formato go/no-go para cada critério com thresholds configuráveis.'
WHERE board_id = '38cc997c-9345-4ee1-acb5-ed2ddf33b734' AND title LIKE 'Checklist Critérios%';

UPDATE board_items SET
  title = 'Toolkit v1.0 de Governança de IA — Gate B',
  description = 'Toolkit completo v1.0 integrando todos os artefatos: framework de governança, matriz de dados, métricas de valor, checklist GenAI/RAG. Documento consolidado + templates + ferramenta de avaliação. Marco Gate B: versão para distribuição piloto.'
WHERE board_id = '38cc997c-9345-4ee1-acb5-ed2ddf33b734' AND title = 'Toolkit v1.0';

UPDATE board_items SET
  title = 'Treinamento da Comunidade + Coleta de Feedbacks',
  description = 'Sessão de treinamento para a comunidade PMI sobre o toolkit de governança de IA. Formato workshop hands-on com aplicação prática dos checklists e frameworks. Coleta estruturada de feedbacks para refinamento final antes do relatório.'
WHERE board_id = '38cc997c-9345-4ee1-acb5-ed2ddf33b734' AND title LIKE 'Treinamento comunidade%';

UPDATE board_items SET
  title = 'Relatório Final — Toolkit de Governança Consolidado',
  description = 'Relatório final consolidando framework de governança, toolkit completo e resultados de validação. Inclui: análise de eficácia, feedback da comunidade, roadmap de evolução, recomendações para adoção organizacional. Entrega final da tribo — publicação e distribuição ampla.'
WHERE board_id = '38cc997c-9345-4ee1-acb5-ed2ddf33b734' AND title = 'Relatório Final';
