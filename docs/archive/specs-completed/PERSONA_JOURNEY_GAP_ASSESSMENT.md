# Simulação de Jornadas por Persona — Gap Assessment

**Data:** 2026-03-13
**Análise por:** CXO, Senior Product Lead, Data Architect, AI Engineer, PM/FP&A Consultant
**Plataforma:** nucleoia.vitormr.dev (produção)

---

## PERSONAS ANALISADAS

| # | Persona | Perfil | Frequência de uso |
|---|---|---|---|
| P1 | Pesquisador (Nível 4) | Membro ativo de tribo, produz artigos | Diária/semanal |
| P2 | Líder de Tribo (Nível 3) | Gerencia tribo, orienta pesquisadores | Semanal |
| P3 | GP — Gerente de Projeto (Nível 2) | Coordena tudo, reporta a sponsors | Diária |
| P4 | Admin da Plataforma (Superadmin) | Mantém infra, resolve problemas técnicos | Sob demanda |
| P5 | Sponsor / Presidente de Capítulo (Nível 1) | Supervisão estratégica, cobra resultados | Mensal |
| P6 | Chapter Liaison / Ponto Focal | Ponte entre capítulo e Núcleo | Quinzenal |
| P7 | Time de Comunicação | Publica em redes sociais, promove o Núcleo | Semanal |
| P8 | Curador (Comitê de Curadoria) | Revisa e aprova artigos | Sob demanda |
| P9 | Representante PMI Global | Avalia a iniciativa para chancelamento | Eventual (1-2x/ano) |
| P10 | Acadêmico / Pesquisador Externo | Avalia potencial para publicação/congresso | Eventual |
| P11 | Visitante / Potencial Membro | Quer conhecer o Núcleo e participar | Primeira visita |

---

## P1: PESQUISADOR (João, PMI-MG, Tribo 5 — Talentos & Upskilling)

### Jornada esperada

```
Login → Workspace → Ver board da tribo → Pegar card de tarefa → 
Pesquisar → Redigir → Submeter para peer review → Revisar colegas → 
Registrar presença em reuniões → Acompanhar progresso na trilha IA → 
Ver XP e posição no ranking
```

### Simulação passo a passo

| Step | Ação | Funciona? | Fricção |
|---|---|---|---|
| 1 | Login via Google | ✅ | — |
| 2 | Vê Workspace | ✅ | — |
| 3 | Clica "Minha Tribo" → /tribe/5?tab=board | ✅ | — |
| 4 | Vê board com cards | ✅ | Cards podem não ter descrição clara do que fazer |
| 5 | Abre um card → CardDetail | ✅ | — |
| 6 | Se auto-atribui como author | ⚠️ | Precisa que líder ou ele mesmo adicione via MemberPicker. Não há botão "Pegar para mim" |
| 7 | Edita descrição/checklist | ✅ | — |
| 8 | Move card para "Em andamento" | ✅ | Via DnD ou dropdown |
| 9 | Quer anexar referência (PDF) | ✅ | Upload de attachments funciona |
| 10 | Termina rascunho → submete para peer review | ❌ | **NÃO EXISTE botão "Submeter para Peer Review"**. O card muda de coluna manualmente mas não há fluxo guiado. |
| 11 | Quer ver feedback do peer review | ❌ | **Não há mecanismo de peer review no board da tribo**. O peer review é informal (WhatsApp/reunião). |
| 12 | Registra presença na reunião semanal | ✅ | Quick check-in no workspace OU /attendance |
| 13 | Vê feedback pós check-in (XP + horas) | ✅ | Toast com dados |
| 14 | Acompanha trilha IA | ✅ | /#trail mostra ranking |
| 15 | Vê perfil com horas reais | ✅ | Corrigido (não mais placeholder) |
| 16 | Vê posição no leaderboard | ✅ | /gamification |

### Gaps identificados (P1)

| # | Gap | Severidade | Perspectiva |
|---|---|---|---|
| G1.1 | **Sem botão "Pegar para mim"** — Pesquisador precisa abrir card, ir no MemberPicker, buscar seu nome, adicionar. Deveria ter um clique. | Média | CXO |
| G1.2 | **Sem fluxo guiado de peer review na tribo** — O Manual define 7 etapas mas o board da tribo não tem colunas correspondentes por default. O pesquisador não sabe qual é o próximo passo. | Alta | Product Lead |
| G1.3 | **Sem notificações** — Quando alguém atribui um card ao João, ele não sabe. Sem email, sem badge, sem nada. Ele descobre na reunião. | Alta | CXO |
| G1.4 | **Sem visão "Meus Cards"** — João quer ver rapidamente tudo que está atribuído a ele, across all boards. Hoje precisa navegar board por board. | Média | Product Lead |
| G1.5 | **Onboarding incompleto** — João novo no ciclo 3 não tem guia de "por onde começar". A página /onboarding existe mas está vazia ou genérica. | Média | CXO |

---

## P2: LÍDER DE TRIBO (Jefferson, PMI-DF, Tribo 5 — Talentos & Upskilling)

### Jornada esperada

```
Login → Workspace → Ver board da tribo → Criar cards de entrega → 
Atribuir pesquisadores → Acompanhar progresso → Registrar presença do time →
Revisar entregas → Submeter para curadoria → Gerar eventos recorrentes →
Enviar comunicado para a tribo → Ver métricas de produtividade
```

### Simulação

| Step | Ação | Funciona? | Fricção |
|---|---|---|---|
| 1 | Login → Workspace | ✅ | — |
| 2 | Ver board da tribo /tribe/5?tab=board | ✅ | — |
| 3 | Criar card de entrega | ✅ | CardCreate funciona |
| 4 | Atribuir pesquisadores (múltiplos) | ✅ | MemberPickerMulti com roles |
| 5 | Acompanhar progresso dos cards | ⚠️ | Vê status por card mas **sem visão consolidada** (% concluído, burndown) |
| 6 | Registrar presença do time (bulk) | ✅ | Bulk roster no attendance |
| 7 | Gerar eventos recorrentes | ✅ | create_recurring_weekly_events |
| 8 | Revisar entrega de pesquisador | ⚠️ | Abre o card, lê, mas **não tem fluxo de "Aprovar/Solicitar Revisão" como líder** |
| 9 | Submeter para curadoria | ✅ | submit_for_curation RPC |
| 10 | Enviar comunicado para a tribo | ✅ | Broadcast tab na tribe page |
| 11 | Ver métricas de produtividade | ❌ | **NÃO EXISTE dashboard de tribo**. Líder não vê: quantos cards em cada status, tempo médio por card, quem está contribuindo mais, quem não registrou presença. |
| 12 | Gerenciar colunas do board | ✅ | admin_update_board_columns (W109) |
| 13 | Ver quem fez a trilha IA | ⚠️ | /#trail mostra global mas **não filtra por tribo** |

### Gaps identificados (P2)

| # | Gap | Severidade | Perspectiva |
|---|---|---|---|
| G2.1 | **Sem dashboard de tribo** — Líder não tem visão consolidada: cards por status, throughput, contribuição por membro. É o gap mais sentido. | Alta | Product Lead + PM Consultant |
| G2.2 | **Sem fluxo de aprovação do líder** — O Manual define "Revisão do Líder de Tribo" (etapa 6 das 7). Não existe no BoardEngine. O líder só move cards de coluna. | Alta | PM Consultant |
| G2.3 | **Trilha IA sem filtro por tribo** — Líder quer saber "dos 5 da minha tribo, quantos completaram a trilha?" Hoje vê o ranking global. | Média | CXO |
| G2.4 | **Sem alerta de inatividade** — Se um pesquisador não aparece em 3 reuniões consecutivas (protocolo do Manual, seção 3.7), o líder deveria ser alertado. | Média | PM Consultant |

---

## P3: GP — GERENTE DE PROJETO (Vitor)

### Jornada esperada

```
Login → Workspace → Ver KPIs gerais → Verificar saúde dos dados → 
Admin panel → Gestão de tribos → Ver curadoria → Ver relatório executivo →
Preparar apresentação para sponsors → Acompanhar certificações → 
Verificar parcerias → Gerenciar ciclos
```

### Simulação

| Step | Ação | Funciona? | Fricção |
|---|---|---|---|
| 1 | Workspace | ✅ | — |
| 2 | Ver KPIs na home | ✅ | 9 KPIs com quarterly targets |
| 3 | Admin → Saúde dos Dados | ✅ | W98 data anomaly detection |
| 4 | Admin → Gestão de Tribos | ✅ | Allocation, CRUD |
| 5 | Admin → Curadoria | ✅ | CuratorshipBoardIsland com dashboard |
| 6 | Admin → Relatório Executivo | ✅ | /admin/cycle-report com print PDF |
| 7 | Admin → Parcerias | ✅ | /admin/partnerships |
| 8 | Admin → Ciclos | ✅ | W111 cycle management |
| 9 | Admin → Analytics | ⚠️ | Existe mas **dados de analytics V2 não validados com dados reais** (carry-over do backlog) |
| 10 | Comparar performance entre tribos | ❌ | **NÃO EXISTE comparativo cross-tribe**. GP quer: "Qual tribo está produzindo mais? Qual tem mais presença? Qual está parada?" |
| 11 | Ver pipeline de artigos global | ⚠️ | Vê na curadoria mas **não vê os que ainda estão nas tribos** (pré-curadoria) |
| 12 | Acompanhar horas de impacto em tempo real | ✅ | KPI na home + attendance |
| 13 | Receber alerta de problemas | ⚠️ | Announcements existem mas **são manuais**. Sem alertas automáticos de: "Tribo 3 não teve reunião há 2 semanas", "Pesquisador X sumiu há 3 reuniões" |

### Gaps identificados (P3)

| # | Gap | Severidade | Perspectiva |
|---|---|---|---|
| G3.1 | **Sem comparativo cross-tribe** — GP não consegue ver de relance qual tribo está performando vs qual precisa de atenção. | Alta | PM Consultant + FP&A |
| G3.2 | **Pipeline de artigos global incompleto** — Vê curadoria (pós-submissão) mas não vê o que está em produção nas tribos. | Média | Product Lead |
| G3.3 | **Alertas automáticos de anomalias operacionais** — Inatividade de tribo, ausências consecutivas, SLAs vencidos não geram alerta proativo. | Alta | PM Consultant |
| G3.4 | **Analytics V2 não validado** — Carry-over persistente. Gráficos podem mostrar dados incorretos. | Média | Data Architect |

---

## P4: ADMIN DA PLATAFORMA (Superadmin técnico)

### Jornada

```
Verificar CI → Deploy → Aplicar migrations → Resolver tickets → 
Monitorar PostHog → Sync Credly → Verificar Edge Functions
```

### Simulação

| Step | Funciona? | Fricção |
|---|---|---|
| CI monitoring | ✅ | 7/7 checks, heartbeat ativo |
| Deploy | ✅ | Autodeploy via Cloudflare |
| Migrations | ✅ | Supabase CLI linkado |
| PostHog | ✅ | safePH guards, consent |
| Credly sync | ✅ | Edge Function ativa |
| Edge Functions | ⚠️ | **13 Edge Functions sem dashboard de health**. Sem saber se sync-comms-metrics rodou com sucesso ou falhou silenciosamente. |
| Logs | ❌ | **Sem centralização de logs**. Erros de Edge Functions vão para Cloudflare logs mas não há painel unificado. |

### Gaps (P4)

| # | Gap | Severidade | Perspectiva |
|---|---|---|---|
| G4.1 | **Sem health dashboard de Edge Functions** — 13 funções sem monitoramento. Se sync-credly-all falha, ninguém sabe até alguém reclamar. | Média | AI Engineer |
| G4.2 | **Sem centralização de logs** — Cada serviço (Cloudflare, Supabase, PostHog) tem seus logs separados. | Baixa | Data Architect |

---

## P5: SPONSOR / PRESIDENTE DE CAPÍTULO (Ivan, PMI-GO)

### Jornada

```
Abrir plataforma (raramente loga) → Ver KPIs → Comparar com acordo → 
Receber relatório do GP → Aprovar/questionar direcionamento
```

### Simulação

| Step | Funciona? | Fricção |
|---|---|---|
| Ver KPIs sem login | ✅ | /#kpis é público |
| Entender os números | ⚠️ | **Sem contexto de "esperado para este ponto do ano"** — vê 0/10 artigos e não sabe se é normal |
| Ver relatório executivo | ✅ | /admin/cycle-report (precisa login) |
| Comparar com acordo formal | ⚠️ | O KPI_AGREEMENT.md existe mas **não está acessível na plataforma** — é um arquivo no GitHub |
| Ver progresso do seu capítulo vs outros | ❌ | **NÃO EXISTE view por capítulo**. Ivan quer: "quantos membros do PMI-GO estão ativos? Quantos artigos vieram do GO?" |
| Aprovar decisões estratégicas | ❌ | **Sem workflow de aprovação na plataforma**. Decisões são via WhatsApp/reunião. |

### Gaps (P5)

| # | Gap | Severidade | Perspectiva |
|---|---|---|---|
| G5.1 | **KPIs sem contexto trimestral visível para público** — Q-targets existem na RPC mas não estão no card público da home. Sponsor vê meta anual sem saber o esperado para agora. | Alta | FP&A |
| G5.2 | **Sem view por capítulo** — Cada presidente quer ver a contribuição do seu capítulo. Número de membros, artigos produzidos, presenças, certificações — filtrado por chapter. | Alta | PM Consultant |
| G5.3 | **Acordo formal não acessível na plataforma** — KPI_AGREEMENT.md está no GitHub. Deveria ter link na seção KPIs ou no /admin. | Baixa | PM Consultant |

---

## P6: CHAPTER LIAISON / PONTO FOCAL (Ana Cristina, PMI-DF)

### Jornada

```
Login → Ver membros do seu capítulo → Acompanhar contribuições →
Reportar para presidente do capítulo → Facilitar novos membros
```

### Simulação

| Step | Funciona? | Fricção |
|---|---|---|
| Login | ✅ | — |
| Ver membros do capítulo | ⚠️ | Admin → Membros filtra por capítulo, mas **liaison não tem tier admin** (é chapter_liaison designation) |
| Acompanhar contribuições | ❌ | **Sem dashboard por capítulo** |
| Reportar para presidente | ❌ | Sem relatório filtrado por capítulo exportável |
| Facilitar novos membros | ⚠️ | Pode indicar mas **sem fluxo de indicação na plataforma** |

### Gaps (P6)

| # | Gap | Severidade | Perspectiva |
|---|---|---|---|
| G6.1 | **Sem acesso adequado ao admin para liaisons** — Precisam ver membros do seu capítulo mas não têm tier suficiente. Precisam de view filtrada. | Alta | Data Architect (RLS) |
| G6.2 | **Sem dashboard por capítulo** — Mesmo gap do sponsor mas do ponto de vista operacional. | Alta | PM Consultant |

---

## P7: TIME DE COMUNICAÇÃO (Mayanna, líder)

### Jornada

```
Login → Ver métricas de redes → Planejar conteúdo da semana →
Registrar métricas → Publicar material → Ver impacto
```

### Simulação

| Step | Funciona? | Fricção |
|---|---|---|
| Login → Workspace | ✅ | — |
| Ver métricas de redes | ✅ | /admin/comms-ops com trend charts (W94) |
| Registrar métricas manuais | ✅ | Formulário de fallback |
| Ver board de comunicação | ✅ | BoardEngine domain_key=communication |
| Criar cards de post | ✅ | CardCreate no board |
| Ver sugestão de post quando artigo é aprovado | ❌ | **Publication assist não implementado** — a spec do W94 mencionava "gerar cards no board de comms quando artigo aprovado" mas isso é automação que pode não ter sido implementada |
| Publicar direto da plataforma | ❌ | **Sem integração de publicação** — precisa ir manualmente a cada rede. Normal, mas oportunidade futura. |
| Ver impacto de um post específico | ⚠️ | Métricas são por semana/canal, **não por post individual** |

### Gaps (P7)

| # | Gap | Severidade | Perspectiva |
|---|---|---|---|
| G7.1 | **Publication assist não conectado** — Artigo aprovado deveria gerar card sugerido no board de comms automaticamente. | Média | AI Engineer (automação) |
| G7.2 | **Sem métricas por post individual** — Comms quer saber "qual post performou melhor?" Hoje só tem agregado semanal. | Baixa | Product Lead |

---

## P8: CURADOR (Fabricio Costa, Comitê de Curadoria)

### Jornada

```
Login → Ver items pendentes de curadoria → Ser designado como revisor →
Avaliar com rubrica (5 critérios) → Emitir parecer → Ver resultado do consenso
```

### Simulação

| Step | Funciona? | Fricção |
|---|---|---|
| Ver items pendentes | ✅ | /admin/curatorship dashboard |
| Ser designado como revisor | ✅ | assign_curation_reviewer RPC (W90) |
| Avaliar com rubrica | ✅ | 5 critérios + sliders (W90) |
| Emitir parecer | ✅ | submit_curation_review (W90) |
| Ver resultado do consenso | ⚠️ | Vê no card mas **sem notificação de que o outro revisor já emitiu parecer** |
| Ver histórico de pareceres emitidos | ❌ | **Sem "Meus Pareceres"** — curador não vê facilmente todos os items que já revisou |
| Ver métricas de curadoria (throughput, tempo médio) | ⚠️ | exec_cycle_report tem dados mas **curador não tem acesso ao cycle-report** (é admin only) |

### Gaps (P8)

| # | Gap | Severidade | Perspectiva |
|---|---|---|---|
| G8.1 | **Sem notificação de parecer do co-revisor** — Curador A não sabe que Curador B já revisou. Precisa verificar manualmente. | Média | CXO |
| G8.2 | **Sem "Meus Pareceres"** — Curador quer ver histórico do que já revisou para: comprovação profissional (Manual 3.9) e auto-avaliação. | Média | PM Consultant |

---

## P9: REPRESENTANTE PMI GLOBAL (avaliação para chancelamento)

### Jornada

```
Receber link → Navegar como visitante → Avaliar estrutura →
Verificar governança → Avaliar produção → Comparar com outros hubs →
Emitir parecer sobre chancelamento
```

### Simulação

| Step | Funciona? | Fricção |
|---|---|---|
| Acessar como visitante | ✅ | Sem login necessário para home |
| Ver estrutura (tribos, quadrantes) | ✅ | /#quadrants, /#tribes, /teams |
| Ver KPIs | ✅ | /#kpis público com progresso |
| Ver time | ✅ | /#team com fotos e roles |
| Ver governança documentada | ⚠️ | Manual R2 linkado em /#resources mas **é link externo (Canva)**. Não há seção de governança na plataforma. |
| Ver produção (artigos publicados) | ❌ | **NÃO EXISTE página pública de publicações**. /publications requer login. Um avaliador externo não vê os artigos produzidos. |
| Ver impacto quantificado | ⚠️ | KPIs mostram números mas **sem narrative/contexto**. Um avaliador quer ler "O Núcleo produziu X artigos citados Y vezes em plataformas Z" |
| Comparar com outros hubs | ❌ | **Sem benchmarking visível**. A seção /#vision menciona PMI Ireland/Germany/Sweden mas sem dados comparativos. |
| Ver em inglês | ✅ | /en/ existe |
| Emitir parecer | ❌ | **Sem mecanismo de feedback para avaliadores externos** |

### Gaps (P9)

| # | Gap | Severidade | Perspectiva |
|---|---|---|---|
| G9.1 | **Publicações não acessíveis publicamente** — Avaliador externo não vê a produção do Núcleo. Isso é o asset mais importante para chancelamento. | CRÍTICA | Product Lead + PM Consultant |
| G9.2 | **Sem narrative de impacto** — KPIs são números soltos. Falta um "About" ou "Impact Report" público que conte a história: "Desde 2024, X membros, Y artigos, Z horas..." | Alta | PM Consultant |
| G9.3 | **Governança não está na plataforma** — O Manual R2 está no Canva. Deveria existir uma seção /governance com resumo acessível. | Média | PM Consultant |
| G9.4 | **Sem mecanismo de feedback externo** — Para avaliação/chancelamento, o PMI Global precisa de um canal formal. | Baixa | Product Lead |

---

## P10: ACADÊMICO / PESQUISADOR EXTERNO

### Jornada

```
Encontrar o Núcleo (via Google, LinkedIn, PMI) → Avaliar credibilidade →
Ver publicações → Avaliar metodologia → Decidir se cita/colabora/apresenta
```

### Simulação

| Step | Funciona? | Fricção |
|---|---|---|
| Encontrar via Google | ⚠️ | SEO básico existe mas **sem meta tags acadêmicas** (Dublin Core, schema.org ScholarlyArticle) |
| Ver credibilidade (quem está por trás) | ✅ | /#team mostra time com capítulos PMI |
| Ver publicações | ❌ | **MESMO GAP DO P9 — /publications não é público** |
| Ver metodologia de pesquisa | ❌ | **Sem seção de metodologia**. O Manual define fluxo de 7 etapas mas não está visível para acadêmico externo. |
| Baixar artigos | ❌ | Artigos estão no ProjectManagement.com, não na plataforma. **Sem links diretos para publicações externas.** |
| Ver dados para citação | ❌ | **Sem BibTeX, DOI, ou referência bibliográfica formatada** |
| Propor colaboração | ⚠️ | Email nucleoiagp@gmail.com existe em /#resources. Sem formulário dedicado. |

### Gaps (P10)

| # | Gap | Severidade | Perspectiva |
|---|---|---|---|
| G10.1 | **Publicações não acessíveis publicamente** (mesmo G9.1) | CRÍTICA | Product Lead |
| G10.2 | **Sem metadados acadêmicos** — Para ser citável, precisa de: título, autores, data, abstract, keywords, DOI (se houver), BibTeX export | Alta | AI Engineer (structured data) |
| G10.3 | **Sem página de metodologia** — Acadêmico quer saber como a pesquisa é conduzida. O Manual de Governança seção 4.2 tem isso mas não está acessível. | Média | PM Consultant |

---

## P11: VISITANTE / POTENCIAL MEMBRO

### Jornada

```
Chegar na home → Entender o que é → Ver tribos → Ver requisitos →
Decidir participar → Encontrar como se inscrever
```

### Simulação

| Step | Funciona? | Fricção |
|---|---|---|
| Home carrega | ✅ | Hero, quadrantes, tribos |
| Entender o que é o Núcleo | ✅ | Hero section clara |
| Ver tribos e temas | ✅ | /#tribes com accordion |
| Ver requisitos | ⚠️ | **Requisitos de participação não estão na plataforma**. Manual seção 3 detalha mas é externo. |
| Ver KPIs e progresso | ✅ | Público |
| Se inscrever | ❌ | **NÃO EXISTE fluxo de candidatura online**. O Manual define processo seletivo (seção 3.4) com formulário, triagem, entrevista — nada disso está digitalizado. |
| Contato | ✅ | Email em /#resources |

### Gaps (P11)

| # | Gap | Severidade | Perspectiva |
|---|---|---|---|
| G11.1 | **Sem fluxo de candidatura online** — O potencial membro precisa de um formulário estruturado conforme o Manual (auto-avaliação, carta de motivação, portfólio). Hoje é tudo offline. | Alta | Product Lead + CXO |
| G11.2 | **Requisitos de participação não visíveis** — Filiação PMI, disponibilidade 4-6h/sem, etc. Deveria estar na plataforma antes do formulário. | Média | CXO |

---

## CONSOLIDAÇÃO: TOP GAPS PRIORIZADOS

### CRÍTICO (afeta credibilidade externa e KPIs)

| # | Gap | Personas | Recomendação |
|---|---|---|---|
| **G9.1/G10.1** | Publicações não acessíveis publicamente | P9, P10, P11 | Criar /publications como página pública com artigos publicados, links, autores, abstract. É o ASSET #1 do Núcleo. |
| **G5.2/G6.2** | Sem view por capítulo | P5, P6 | Dashboard filtrado por chapter: membros, artigos, horas, certificações. Sponsors precisam disso para justificar a parceria internamente. |

### ALTO (afeta operação diária)

| # | Gap | Personas | Recomendação |
|---|---|---|---|
| **G1.3** | Sem notificações | P1, P2, P8 | Sistema de notificações: assignment, review completada, SLA vencido. Pode ser in-app (badge no avatar) + email digest semanal. |
| **G2.1** | Sem dashboard de tribo | P2, P3 | Tribe analytics: cards por status, throughput, contribuição por membro, presença. Na tribe page como nova tab. |
| **G3.1** | Sem comparativo cross-tribe | P3, P5 | Tabela comparativa: por tribo, artigos/cards/presença/certificação. No /admin/portfolio ou cycle-report. |
| **G3.3** | Sem alertas automáticos operacionais | P3, P4 | Alertas: inatividade de tribo (sem reunião 2+ semanas), ausências consecutivas (3+), SLAs vencidos. Via data anomaly detection (expandir W98). |
| **G1.2/G2.2** | Sem fluxo guiado de peer review/aprovação do líder | P1, P2 | Status vocabulary com transições guiadas: botão "Submeter para Review" que move card + notifica reviewer. |
| **G9.2** | Sem narrative de impacto público | P9, P10 | Página /about ou /impact com história, números, depoimentos, links para publicações. One-pager digital. |

### MÉDIO (melhoria de experiência)

| # | Gap | Personas | Recomendação |
|---|---|---|---|
| **G1.1** | Sem "Pegar para mim" | P1 | Botão no card: auto-assign como author com 1 clique |
| **G1.4** | Sem "Meus Cards" | P1 | View no workspace: cards atribuídos ao membro across all boards |
| **G5.1** | Q-targets não visíveis na home | P5 | Adicionar "Q1: 0/1" abaixo de cada KPI card |
| **G8.2** | Sem "Meus Pareceres" | P8 | View no workspace para curadores: histórico de reviews |
| **G10.2** | Sem metadados acadêmicos | P10 | Structured data (schema.org) + BibTeX export nos artigos |
| **G11.1** | Sem candidatura online | P11 | Formulário digital com as etapas do Manual seção 3.4 |
| **G2.3** | Trilha IA sem filtro por tribo | P2 | Filtro no /#trail: "Ver só minha tribo" |
| **G2.4** | Sem alerta de inatividade | P2, P3 | Expandir data anomaly para detectar ausências 3+ consecutivas |

### BAIXO (oportunidade futura)

| # | Gap | Personas | Recomendação |
|---|---|---|---|
| G4.1 | Edge Functions health dashboard | P4 | Dashboard de status das 13 Edge Functions |
| G7.2 | Métricas por post individual | P7 | Requer API integration mais profunda |
| G9.4 | Feedback externo | P9 | Formulário para avaliadores |
| G10.3 | Página de metodologia | P10 | Seção /methodology com fluxo de 7 etapas visual |

---

## RECOMENDAÇÕES POR ESPECIALISTA

### 🎯 CXO (Experiência)
"O gap mais doloroso é a falta de notificações. Em 2026, uma plataforma colaborativa sem notificações é como um WhatsApp sem o sino. Os membros descobrem que têm tarefa nova na reunião semanal — isso é atraso sistêmico de 7 dias em cada handoff."

### 📊 PM Consultant / FP&A
"Os sponsors não têm view por capítulo. Isso é o mesmo que pedir a um VP para avaliar a performance da empresa sem P&L por business unit. Sem isso, a renovação de parceria dos capítulos fica baseada em feeling, não em dados."

### 🏗️ Data Architect
"O schema está sólido para suportar todos esses gaps. As tabelas existem, os dados existem. O que falta é: views filtradas por chapter (RLS policy), materialized views para dashboards de tribo, e um sistema de notificações (nova tabela notifications + preferências)."

### 🤖 AI Engineer
"A oportunidade mais interessante é a publication assist — artigo aprovado gera automaticamente posts para redes sociais. Com a API do Claude já disponível no projeto (Anthropic API in artifacts), podemos gerar copy inteligente por canal. LinkedIn = mais formal/técnico, Instagram = visual/resumo, YouTube = script para vídeo curto."

### 👔 Senior Product Lead
"O /publications público é o gap #1 inegociável. O Núcleo produz conhecimento — se esse conhecimento não é visível para o mundo, a iniciativa perde 80% do seu valor de impacto. Isso deveria ser a próxima wave, antes de qualquer dashboard interno."
