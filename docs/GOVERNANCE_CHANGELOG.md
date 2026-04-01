# Governance Changelog — Núcleo IA & GP

## Registro de Decisões Arquiteturais e de Governança

Este documento registra formalmente as mudanças de estrutura organizacional, papéis, regras de negócio e processos operacionais da plataforma e do projeto. Cada entrada tem data, autor, decisão, justificativa e impacto técnico quando aplicável.

Referência normativa: Manual de Governança e Operações R2 (DocuSign B2AFB185-4FC7-42C5-82A5-615EC7BDC98A), Seção 7 — alterações ao manual requerem proposta da liderança dos capítulos com comunicação, revisão e aprovação.

---

## Decisões Implementadas

### GC-001 — Modelo de Papéis 3-Eixos
**Data:** 2026-03-07 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Substituir o campo único `role` por um modelo de 3 eixos independentes:
- **`operational_role`** — o que a pessoa FAZ no ciclo (hierarquia única, mutuamente exclusiva)
- **`designations[]`** — reconhecimentos que transcendem ciclos (acumuláveis)
- **`is_superadmin`** — acesso técnico à plataforma (independente de papel)

**Justificativa:** O campo `role` não comportava pessoas com múltiplas funções (ex: Fabricio Costa é deputy_manager + tribe_leader + embaixador + fundador + curador). O modelo anterior forçava a escolha de um único papel, gerando perda de informação e inconsistências.

**Impacto técnico:** Colunas `role` e `roles` eliminadas da tabela `members` (ver GC-005). Funções `compute_legacy_role()` e `compute_legacy_roles()` criadas para backward-compatibility com RPCs existentes. 3 views e 3 RLS policies recriadas para o novo modelo.

**Operational Roles (hierarquia, mutuamente exclusivos):**

| Nível | Código | Label PT |
|---|---|---|
| 1.0 | `sponsor` | Patrocinador (Presidente do capítulo) |
| 2.0 | `manager` | Gerente de Projeto |
| 2.5 | `deputy_manager` | Deputy PM |
| 3.0 | `tribe_leader` | Líder de Tribo |
| 4.0 | `researcher` | Pesquisador |
| 4.0 | `facilitator` | Facilitador de Eventos |
| 4.0 | `communicator` | Multiplicador de Conhecimento |
| — | `none` | Sem papel operacional ativo |

**Designações (acumuláveis, transcendem ciclos):**

| Código | Label PT | Descrição |
|---|---|---|
| `chapter_liaison` | Ponto Focal | Representante indicado pelo presidente do capítulo |
| `ambassador` | Embaixador | Promoção externa e parcerias |
| `founder` | Fundador | Equipe de Constituição Inicial (reconhecimento permanente) |
| `curator` | Curador | Membro do Comitê de Curadoria |
| `comms_team` | Comunicação | Membro do time de comunicação |
| `co_gp` | Co-GP | Co-Gerente de Projeto (designação associada ao deputy_manager) |
| `tribe_leader` | Líder de Tribo | Acumula com operational_role quando pessoa lidera tribo + tem outro papel |

---

### GC-002 — Deputy PM (Nível 2.5)
**Data:** 2026-03-07 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Criar o `operational_role = 'deputy_manager'` para formalizar o papel de Co-Gerente de Projeto. Fabricio Costa designado Deputy PM no Ciclo 3, com designações acumuladas: `co_gp`, `tribe_leader` (T06), `ambassador`, `founder`, `curator`.

**Esclarecimento de terminologia:**
- `deputy_manager` é o **operational_role** (o que a pessoa faz na hierarquia)
- `co_gp` é a **designação** (reconhecimento formal de que co-gerencia o projeto)
- São complementares: o deputy_manager pode existir sem ser co_gp em teoria, mas na prática atual Fabricio acumula ambos

**Justificativa:** Com a expansão para 5 capítulos e 44+ colaboradores, a gestão necessita de um braço operacional com acesso admin completo. O Deputy PM é visualmente diferenciado do GP na plataforma mas tem o mesmo nível de permissão técnica (superadmin).

---

### GC-003 — Ponto Focal dos Capítulos (chapter_liaison)
**Data:** 2026-03-07 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Atualizado:** 2026-03-14 — Correção de dados e mapa completo de representação

**Decisão:** Criar a designação `chapter_liaison` para representantes indicados pelas presidências dos capítulos. Diferencia-se do Patrocinador (sponsor), que é o próprio presidente. O Ponto Focal tem visibilidade no site (seção Patrocinadores & Pontos Focais) e acesso observer no admin, mas não é a autoridade institucional máxima do capítulo.

**Mapa de representação por capítulo (Ciclo 3):**

| Capítulo | Patrocinador (Presidente) | Ponto Focal (chapter_liaison) |
|---|---|---|
| PMI-GO | Ivan Lourenço | — (presidente acompanha diretamente) |
| PMI-CE | Jéssica Alcântara | Roberto Macêdo |
| PMI-DF | Matheus Frederico Rosa Rocha | Ana Cristina Fernandes Lima |
| PMI-MG | Felipe Moraes Borges | Rogério Peixoto |
| PMI-RS | Márcio Silva dos Santos | — (em definição) |

**Nota histórica:** Cristiano Oliveira foi presidente do PMI-CE durante o Ciclo 2 e início do Ciclo 3. Com a transição de presidência para Jéssica Alcântara, Cristiano passou a atuar como embaixador do Núcleo pelo PMI-CE.

**Justificativa:** Os capítulos PMI-CE, PMI-DF e PMI-MG indicaram representantes operacionais que não são presidentes. Sem a designação formal, esses representantes eram registrados como `sponsor`, confundindo a hierarquia institucional.

---

### GC-004 — Time de Comunicação
**Data:** 2026-03-07 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Atualizado:** 2026-03-14 — Composição Ciclo 3 confirmada, canais e ferramentas adicionados

**Decisão:** Criar a designação `comms_team` para membros do time de comunicação. O time é responsável pela gestão de canais de comunicação, engajamento digital, comunicação institucional e disseminação de conteúdo.

**Composição Ciclo 3:**
- Mayanna Duarte — Líder de Comunicação (comms_leader)
- Letícia Clemente — Pesquisadora + Comunicação (dual-role: researcher + comms_team)
- Andressa Martins — Pesquisadora + Comunicação (dual-role: researcher + comms_team)

**Canais sob gestão:**
- Instagram: @nucleo.ia.gp
- LinkedIn: /company/nucleo-ia
- YouTube: @nucleo_ia
- Linktree: nucleoia

**Ferramenta operacional:** BoardEngine — Hub de Comunicação (board específico na plataforma com 54 itens importados do Trello, DnD com @dnd-kit)

**Justificativa:** O time de comunicação existe desde o Ciclo 2 mas não estava registrado na plataforma. O papel da Mayanna vai além de postagens — ela é gestora de comunicação institucional, reforçando prazos, coordenando engajamento e representando o Núcleo nas redes.

---

### GC-005 — Hard Drop de Colunas Legadas
**Data:** 2026-03-07 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Eliminar definitivamente as colunas `role` (TEXT) e `roles` (TEXT[]) da tabela `members`. Decorre de GC-001 (Modelo 3-Eixos).

**Justificativa:** A tabela `members` deve ser tratada apenas como snapshot do momento atual. O tagueamento real é gerido via `member_cycle_history`. Manter colunas duplicadas era fonte de inconsistência — em várias ocasiões o `role` dizia uma coisa e o `operational_role` dizia outra.

**Impacto técnico:** Funções `compute_legacy_role()` e `compute_legacy_roles()` criadas para backward-compatibility em RPCs que dependiam do campo antigo. Migração irreversível.

---

### GC-006 — Política de Custo Zero e Alto Valor
**Data:** 2026-03-07 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Atualizado:** 2026-03-14 — Inventário de serviços e limites adicionado

**Decisão:** Formalizar a arquitetura "Zero-Cost, High-Value". O projeto opera exclusivamente com Free Tiers e prioriza construção interna sobre ferramentas pagas. Caso limites free tier sejam atingidos, a decisão de migração para plano pago será submetida à Liderança dos Capítulos.

**Inventário de serviços (março/2026):**

| Serviço | Uso | Limite Free Tier | Uso Atual | Risco |
|---|---|---|---|---|
| Cloudflare Workers | SSR hosting + CDN | Ilimitado | ~200 deploys/mês | Baixo |
| Supabase | PostgreSQL + Auth + Storage + Edge Functions | 500MB DB, 1GB storage, 50k auth | ~60MB DB, ~100MB storage | Médio |
| PostHog | Product analytics | 1M events/mês | ~10k events/mês | Baixo |
| GitHub | Repos + CI/CD (Actions) | Ilimitado para público, 2k min Actions | ~500 min/mês | Baixo |
| Google Workspace | Drive compartilhado | 15GB por conta | ~2GB | Baixo |

**Justificativa:** Como iniciativa voluntária ligada ao PMI, não há orçamento recorrente. A arquitetura deve ser replicável por outros capítulos sem custos. Referência: `docs/SUSTAINABILITY_FRAMEWORK.md` (W108) para estratégia completa de sustentabilidade.

---

## Propostas Pendentes de Aprovação

*As propostas abaixo foram elaboradas com base na experiência dos Ciclos 2 e 3, análise do processo seletivo (48 candidatos avaliados), mapeamento da jornada de onboarding via WhatsApp, e boas práticas de gestão de talentos em organizações de pesquisa. Requerem aprovação da Liderança dos Capítulos (Nível 1) conforme Seção 7 do Manual R2.*

---

### GC-007 — Normalização da Escala de Avaliação para 0-10
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Proposta (pendente aprovação Nível 1)

**Decisão:** Padronizar todas as escalas de avaliação (Tabelas 2 e 3 do Manual) para 0-10 com guia de calibração descritiva por faixa. Substitui escalas mistas atuais (0-1, 0-3, 0-5, 1-3, 1-4).

**Justificativa:** Escalas mistas dificultam comparabilidade entre critérios e avaliadores. No Ciclo 3, divergências de até 3 pontos entre avaliadores no mesmo critério evidenciam necessidade de calibração. A escala 0-10 com guia (0-3=não atende, 4-6=atende parcialmente, 7-8=atende bem, 9-10=supera) é padrão em processos seletivos estruturados e oferece maior granularidade para diferenciar candidatos em faixas intermediárias.

**Impacto técnico:** Schema `selection_cycles.objective_criteria` já suporta escalas configuráveis com campo `guide` por critério. Implementado em W124 Phase 1.

---

### GC-008 — Comitê de Seleção Configurável
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Proposta (pendente aprovação Nível 1)

**Decisão:** Formalizar o Comitê de Seleção: mínimo 2 avaliadores designados pelo GP por ciclo. Pode incluir Níveis 2-5 e Comitê de Curadoria, priorizando diversidade de capítulos. O GP valida decisões finais caso não integre diretamente o comitê.

**Justificativa:** No Ciclo 3, centralizar a avaliação de 48 candidatos em 2 pessoas (GP + Co-GP) gerou SLA de 26 dias vs meta de 14. Líderes de Tribo são avaliadores naturais por conhecerem as necessidades específicas de suas tribos. Comitês configuráveis são prática padrão em programas de voluntariado do PMI Global.

**Impacto técnico:** Tabela `selection_committee` criada em W124 Phase 1. Suporta roles: evaluator, lead, observer.

---

### GC-009 — Avaliação Blind (Às Cegas) Obrigatória
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Proposta (pendente aprovação Nível 1)

**Decisão:** Cada avaliador pontua isoladamente, sem visualizar notas dos demais até que todos tenham submetido. Divergências acima de 3 pontos sinalizadas automaticamente para calibração.

**Justificativa:** No Ciclo 3, ambos avaliadores pontuavam na mesma planilha — ao scrollar, um via as notas do outro (viés de ancoragem). Exemplo concreto: candidato Hayala Curto recebeu 0 de um avaliador e 3 do outro em Carta de Motivação. Avaliação blind é padrão ouro em peer review acadêmico (IEEE, ACM, PMI Global).

**Impacto técnico:** RPC `get_evaluation_form` retorna apenas draft do próprio avaliador. `get_evaluation_results` disponível somente após todas submissões. Implementado em W124 Phase 2.

---

### GC-010 — Vaga Unificada com Faixa de Líder
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Proposta (pendente aprovação Nível 1)

**Decisão:** Processo seletivo unificado. Candidato aplica uma vez com perguntas opcionais para líder. Conversão pesquisador→líder via 3 gates: pré-recomendação do sistema (score ≥ percentil 90 ou tag do avaliador) + aprovação do GP + aceite formal do candidato.

**Justificativa:** No Ciclo 3, 3 candidatos a pesquisador foram identificados informalmente como potenciais líderes (Alexandre Meirelles, Paulo Alves, Ana Carla Cavalcante) e convertidos via notas na planilha. A proposta formaliza uma prática existente, reduz fricção para o candidato (aplica uma vez) e elimina risco de perder bons líderes que não se candidataram por insegurança.

**Impacto técnico:** Campo `role_applied` suporta 'researcher'|'leader'|'both'. Campos de conversão em `selection_applications`. Status 'converted' no pipeline.

---

### GC-011 — Métricas de Diversidade no Processo Seletivo
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Proposta (pendente aprovação Nível 1)

**Decisão:** Rastrear e reportar métricas de diversidade por ciclo: distribuição por capítulo, gênero, faixa etária, senioridade, setor (público/privado/acadêmico/terceiro setor), indústria e região. Dados agregados sem PII, em conformidade com LGPD. Utilizados para direcionar estratégias de captação em ciclos futuros.

**Justificativa:** Ciclo 3 mostra desequilíbrio: PMI-GO 15 membros, PMI-RS 2. Sem métricas formais, não há como direcionar esforços de captação. PMI Global valoriza D&I nas diretrizes estratégicas (PMI: NEXT). R&D de qualidade requer diversidade de perspectivas — idade, senioridade, indústria e setor influenciam diretamente a riqueza das análises produzidas.

**Impacto técnico:** Tabela `selection_diversity_snapshots` criada. Campos opcionais em `selection_applications`. Dashboard planejado para W124 Phase 4.

---

### GC-012 — Onboarding Estruturado em 7 Etapas com SLA
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Proposta (pendente aprovação Nível 1)

**Decisão:** Substituir a descrição genérica do onboarding (Seção 3.8.1 do Manual) por checklist de 7 etapas com SLA:

| # | Etapa | SLA | Evidência |
|---|---|---|---|
| 1 | Aceitar convite na plataforma | 48h | Registro no sistema |
| 2 | Completar perfil (bio, LinkedIn, disponibilidade) | 3 dias | Perfil ≥ 80% completo |
| 3 | Aceitar posição no PMI VEP | 7 dias | Print da confirmação |
| 4 | Completar curso Kickoff PMI (Preditivo ou Ágil) | 7 dias | Badge/certificado |
| 5 | Assinar Termo de Voluntariado | 14 dias | Documento assinado |
| 6 | Entrar nos canais de comunicação (WhatsApp geral + tribo) | 7 dias | Confirmação do líder |
| 7 | Participar do Kick-off do projeto | Até evento | Registro de presença |

Colaborador considerado "Ativo" somente após conclusão de todas as etapas obrigatórias.

**Justificativa:** Ciclo 2 (12 membros): onboarding em 4 dias. Ciclo 3 (44 membros): 22 dias. Análise do chat de WhatsApp revelou: confusão sobre o que é obrigatório vs opcional, emails perdidos, termos confeccionados manualmente um a um, e ausência de visibilidade sobre quem já concluiu cada etapa. O processo manual não escala.

**Impacto técnico:** Tabela `onboarding_progress` criada. Config `onboarding_steps` em `selection_cycles`. Notificações de SLA overdue via W116.

---

### GC-013 — SLA e Fórmula de Corte no Processo Seletivo
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Proposta (pendente aprovação Nível 1)

**Decisão:** Formalizar:

**SLA por etapa:**

| Etapa | Prazo |
|---|---|
| Período de inscrições | 14-21 dias (definido por ciclo) |
| Triagem de requisitos | 3 dias úteis |
| Avaliação objetiva | 7 dias úteis |
| Agendamento de entrevistas | 5 dias úteis |
| Realização das entrevistas | 7 dias úteis |
| Decisão final e comunicação | 3 dias úteis |
| **Total máximo** | **~35 dias úteis** |

**Fórmula de consolidação PERT:** `(2×Min + 4×Média + 2×Max) ÷ 8`

**Threshold de corte:** `Mediana × 0,75` — aplicado em dois gates: pós-objetiva (gate para entrevista) e pós-final (gate para aprovação).

Candidatos não aprovados recebem feedback estruturado e são elegíveis para recandidatura em ciclos futuros.

**Justificativa:** Ciclo 3 sem SLA formal levou 26 dias com picos de ociosidade entre etapas. A fórmula PERT (já usada informalmente) atenua outliers sem ignorá-los. Corte a 75% da mediana foi calibrado no Ciclo 3 e produziu resultados alinhados com o julgamento qualitativo. Feedback estruturado fortalece reputação do programa.

**Impacto técnico:** Campos `objective_cutoff_formula` e `final_cutoff_formula` em `selection_cycles`. RPCs `calculate_rankings` e `submit_evaluation` implementam auto-advance com cutoff. Implementado em W124 Phase 2.

---

### GC-014 — Deduplicação e Sanidade do Hub de Comunicação
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Arquivar 7 board_items duplicados na board "Hub de Comunicação" originados da fusão dos boards Trello "Comunicação Ciclo 3" e "Mídias Sociais". Versões `comunicacao_ciclo3` mantidas, versões `midias_sociais` arquivadas.

**Justificativa:** Importação de dois boards Trello com itens de referência sobrepostos gerava duplicidade visual e confusão para a equipe de comunicação.

**Impacto técnico:** UPDATE status='archived' em 7 board_items. Nenhuma exclusão de dados.

---

### GC-015 — Reclassificação de Tipos de Eventos
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Reclassificar 46 de 47 eventos tipados como `other` para tipos descritivos: `interview` (34), `general_meeting` (25), `leadership_meeting` (2), `external_event` (2), `kickoff` (1). Expandir constraint de tipos permitidos na tabela events.

**Justificativa:** 68% dos eventos estavam tipados como "other", eliminando valor analítico da dimensão tipo. Títulos dos eventos continham keywords claras para classificação automática (entrevista, reunião, alinhamento, kick-off, PMI Congress).

**Impacto técnico:** Migração inline + UPDATE direto. Constraint expandida via `expand_event_types_and_reclassify`.

---

### GC-016 — Arquivamento de 22 Tabelas Especulativas (z_archive)
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Criar schema `z_archive` e mover 22 tabelas com 0 registros que representavam features nunca implementadas: pipeline de ingestão (10), rollback/readiness (4), legacy/import (3), publicações/apresentações (2), misc (3).

**Justificativa:** 40% das tabelas do schema público estavam vazias. Tabelas especulativas poluem a interface do Supabase Studio, dificultam auditoria e geram falsos positivos em testes de contrato. Arquivamento é reversível via `ALTER TABLE z_archive.x SET SCHEMA public`.

**Impacto técnico:** Migração `20260319100035_w132_db_sanitation.sql`. Public tables: 93→71. Zero perda de dados.

---

### GC-017 — Bulk-Assign de Tribe Leaders como Assignee Padrão
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Atribuir automaticamente o tribe_leader ativo como assignee de board_items sem assignee em boards de tribos ativas. Itens sem dono geravam baixo accountability na produção.

**Justificativa:** 91% dos board_items (333/363) não tinham assignee. Apenas T8 (9/9 items) tinha cobertura completa após importação do Notion. O líder é o responsável natural pela produção da tribo e pode redelegar via UI.

**Impacto técnico:** UPDATE em migração. Board items unassigned: 333→0 em boards de tribos ativas.

---

### GC-018 — Expansão de Tipos de Hub Resources
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Expandir constraint `hub_resources_asset_type_check` de 4 para 9 tipos: adição de `article`, `presentation`, `governance`, `certificate`, `template`. Reclassificar 27 itens (11 certificates, 7 governance, 6 presentations, 3 articles). Desativar 43 itens junk (row numbers, filenames, single letters).

**Justificativa:** Tipo `reference` era catchall com 200+ itens. Granularidade insuficiente para filtragem, busca e navegação. Junk residual de importação de planilhas.

**Impacto técnico:** Migração inline. Hub resources ativos: 323→280.

---

### GC-019 — Extração e Preservação de Conteúdo Ciclo 2 (Miro + Drive + Notion)
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Documentar e preservar no repositório todo o conteúdo identificado no Miro board Ciclo 2, Google Drive compartilhado e workspaces Notion das tribos. Incluir mapeamento Ciclo 2 → Ciclo 3, inventário de artefatos de pesquisa e assessment de importação para BoardEngine.

**Justificativa:** Conteúdo do Ciclo 2 era acessível apenas via Miro (conta pessoal, risco de expiração) e Google Drive fragmentado. Tribo 6 tinha 187 itens incluindo artigo completo com framework EAA — risco de perda se conta Miro for desativada. Documentação preserva a memória institucional do projeto.

**Impacto técnico:** 3 docs committed: `MIRO_DRIVE_EXTRACTION_CICLO2.md`, `COMMS_TEAM_FRICTION_ANALYSIS.md`, `DB_AUDIT_AND_SANITATION_PLAN.md`. Miro board URL salvo em `site_config`. 6 Canva links vinculados como attachments em board_items. T8 importação de 9 items do Notion já concluída.

---

### GC-020 — Hub Resources Deep Classification — Junk Removal
**Data:** 2026-03-15 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Desativar 83 itens junk do hub_resources: 27 títulos numéricos (linhas de planilha), 25 exports WhatsApp Image, 8 nomes numerados (artefatos de lista de presença), 7 URLs LinkedIn como título, 4 timestamps de fotos, 3 exports analytics, 3 unnamed/untitled, 6 misc (chars avulsos, URLs bare, screenshots).

**Justificativa:** Importação bulk de planilhas e Miro trouxe artefatos que não são recursos de conhecimento. Poluem busca, navegação e métricas de produção. Items mantidos no DB com `is_active=false, curation_status='rejected'` para auditoria.

**Impacto técnico:** Hub resources ativos: 323→240. Nenhuma exclusão de dados.

---

### GC-021 — Hub Resources Tag Cleanup
**Data:** 2026-03-15 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Remover 3 tags bulk-import de todos os itens ativos: `meeting_minutes` (280+ itens), `archived`, `miro_library`. Tags devem carregar significado semântico, não metadados de processo.

**Justificativa:** Tag `meeting_minutes` estava em 280+ itens como artefato de importação — a maioria não era ata de reunião. `archived` duplica a coluna `is_active`. `miro_library` duplica a coluna `source`.

**Impacto técnico:** UPDATE em tags de todos os itens ativos. Tags passam a ser exclusivamente semânticas.

---

### GC-022 — Hub Resources Asset Type Expansion
**Data:** 2026-03-15 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Expandir constraint `hub_resources_asset_type_check` de 4 para 9 tipos (adição: article, presentation, governance, certificate, template). Reclassificar 141 itens "other" para tipos descritivos: 60→reference, 17→governance, 11→certificate, 6→presentation, 5→article, 2→course, 2→webinar.

**Justificativa:** 44% dos itens estavam tipados como "other", eliminando valor analítico. Granularidade insuficiente para busca, filtragem por tipo e dashboard de produção.

**Impacto técnico:** Migração `expand_hub_resources_asset_types`. Asset type "other": 141→0.

---

### GC-023 — Hub Resources 3-Level Taxonomy (Origin Tags)
**Data:** 2026-03-15 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Classificar todos os 240 itens ativos com tag de origem: `origin:nucleo` (53, 22%), `origin:pmi-global` (29, 12%), `origin:external` (158, 66%). Adicionar tags de conteúdo específicas: ai-agent, prototype, comms, publication-guide, ai-tool, survey-data, risk, agile.

**Justificativa:** Sem taxonomia de origem, não é possível distinguir produção interna do Núcleo de referências externas. A distinção é crítica para KPIs de produção (artigos produzidos vs citados) e para o dashboard de portfólio.

**Impacto técnico:** UPDATE em tags de todos os itens ativos. 100% de cobertura de origin tag.

---

### GC-024 — Hub Resources Author/Cycle Enrichment
**Data:** 2026-03-15 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Vincular 6 certificados a `author_id` (member UUID) via name matching no título. Atribuir `cycle_code` a 64 itens com base em tags existentes (ciclo-1, ciclo-2, ciclo-3). Expandir tribe assignment de 136 para 142 itens via keyword matching.

**Justificativa:** Certificados sem author_id não apareciam no perfil do membro. Itens sem cycle_code não podiam ser filtrados por período. Enriquecimento dimensional melhora busca, relatórios e perfil individual.

**Impacto técnico:** UPDATE em author_id (6 items), cycle_code (64 items), tribe_id (6 items adicionais).

---

### GC-025 — Board Items Metadata Enrichment
**Data:** 2026-03-15 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisão:** Enriquecer metadados de 327 board_items ativos em 6 boards: adicionar 46 descrições contextuais (Hub de Comunicação 20, T3 25, Publicações 1), 68 novos tags semânticos, limpar 26 tags junk `miro_section_` do T3, e garantir 100% de cobertura de cycle_code. Cross-reference com contexto de WhatsApp (Canva design IDs, datas de publicação, autoria) e conteúdo Miro Ciclo 2 (problem statements, article outlines, member workspaces).

**Justificativa:** Board items importados de Trello, Miro e Notion entraram sem descrições ou com tags não-semânticas (texto de sticky notes usado como tag). Sem metadados, os cards são opacos para membros que não participaram da criação original. Descrições e tags melhoram busca, onboarding de novos membros e rastreabilidade de produção.

**Impacto técnico:** UPDATE em descriptions (46 items), tags (68 items), cycle_code (30 items). 1 card duplicado arquivado. Cobertura: descriptions 25%→39%, tags 79%→99.7%, cycle 91%→100%.

---

### GC-026: Análise cruzada WhatsApp — 15 grupos, 18.338 mensagens

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code — Supabase MCP)
**Status:** Aplicado em produção

**Decisão:** Analisar 15 grupos de WhatsApp (operacionais, tribos, governança, arquivo) para extrair dados estruturados, identificar padrões de fricção e oportunidades de melhoria para o portal.

**Justificativa:** Links, agendas e artefatos de pesquisa ficam enterrados no scroll do WhatsApp, gerando 156 sinais de fricção de acesso. A análise cruzada permite enriquecer dados de produção (meeting_links, horários, recursos) e identificar funcionalidades do portal que substituem comunicação informal.

**Impacto técnico:** 4 tribe meeting_links populados (T01, T02, T06, T07). 3 meeting schedules definidos (T06, T07, T08). T02 miro_url adicionado. 8 hub_resources criados (5 protótipos Lovable, 3 artefatos Claude). 156 sinais de fricção catalogados. 7 oportunidades de backlog/change-request identificadas (CR-01 a CR-07).

---

### GC-027: Importação histórica de attendance — 783 registros (Ciclo 1, 2 e kickoff C3)

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code — Supabase API)
**Status:** Aplicado em produção

**Decisão:** Importar dados históricos de presença de planilha Excel (Nucleo_AI_2025_Participantes.xlsx) e 5 screenshots de Google Meet, cobrindo fevereiro a dezembro de 2025 e kickoff/reunião de março de 2026.

**Justificativa:** A tabela attendance tinha apenas 38 registros manuais, insuficiente para calcular métricas de engajamento, retenção e participação por tribo/ciclo. Sem dados históricos, KPIs como taxa de presença e impact_hours ficam imprecisos.

**Impacto técnico:** 783 attendance records total (era 38, aumento de 20.6x). 96 eventos cobertos: 24 Geral C1, 8 Geral C2, 3 Liderança C2, 29 T3, 17 T4, 5 T5, 15 T6. 41 kickoff C3 attendees extraídos de screenshots. 23 Reunião Geral 12/mar attendees de screenshot. 56 membros distintos. ON CONFLICT DO NOTHING para idempotência.

---

### GC-028: W134a — Formulário de registro de presença

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Aplicado em produção

**Decisão:** Implementar formulário de registro de presença em lote na página /workspace, visível para GP e líderes de tribo. Inclui RPCs `register_attendance_batch`, `update_event_duration` e `get_recent_events`.

**Justificativa:** O registro de presença era manual e não tinha interface. GP e líderes precisam registrar presenças de forma eficiente para alimentar métricas de engajamento.

**Impacto técnico:** 3 RPCs criados (SECURITY DEFINER). 4 site_config entries (thresholds/pesos). React component AttendanceForm com seletor de evento, lista de membros com checkboxes, busca, duração real. Migration `20260319100036`.

---

### GC-029: W134b — Dashboard de presença (3 visões)

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Aplicado em produção

**Decisão:** Implementar dashboard de presença com 3 visões condicionais: GP (tabela completa, filtro por tribo, alertas de risco), Líder (auto-filtrado para sua tribo), Pesquisador (visão pessoal com comparativo tribo/geral).

**Justificativa:** Transparência de participação conforme decisão D5 do núcleo. Pesquisadores veem apenas seus próprios dados + médias comparativas. GP e líderes veem indicadores de risco de dropout.

**Impacto técnico:** RPC `get_attendance_summary` com fórmula combinada (40% geral + 60% tribo). React component AttendanceDashboard. Indicadores: verde ≥75%, amarelo 50-74%, vermelho <50%, preto 0%.

---

### GC-030: W104 — Dashboard de KPIs do portfólio

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Aplicado em produção

**Decisão:** Implementar dashboard de KPIs com 6 métricas ao vivo (horas de impacto, certificação CPMAI, pilotos IA, artigos, webinars, capítulos) na página /workspace, visível para todos os membros autenticados.

**Justificativa:** KPIs do Ciclo 3 precisam ser visíveis e acompanhados em tempo real. Sem dashboard, as metas ficam em planilhas sem visibilidade.

**Impacto técnico:** RPC `get_kpi_dashboard` retorna JSONB com 6 métricas + progresso linear do ciclo. React component KpiDashboard com cards coloridos (verde on-track, amarelo slightly behind, vermelho critical). Migration `20260319100036`.

---

### GC-031: W105 — Relatório executivo do ciclo aprimorado

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Aplicado em produção

**Decisão:** Aprimorar `exec_cycle_report` para usar `get_kpi_dashboard` (dados mais precisos) e incluir seção de presença por tribo. Adicionar tabela de attendance no cycle-report com métricas por tribo e membros em risco. Redirecionar /report → /admin/cycle-report.

**Justificativa:** O relatório executivo existente não incluía dados de presença. Com 783 attendance records, o relatório agora mostra participação comparativa entre tribos, permitindo decisões informadas sobre engajamento.

**Impacto técnico:** `exec_cycle_report` reescrito para usar `get_kpi_dashboard` e `get_attendance_summary`. Nova seção "Presença por Tribo" na página cycle-report. Migration `20260319100037`. Redirect `/report` adicionado.

---

### GC-032: W134c — Banner de alerta de risco de dropout

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Aplicado em produção

**Decisão:** Implementar banner de alerta na /workspace mostrando membros em risco de dropout (3+ reuniões consecutivas sem presença). Visível para GP e líderes de tribo. Líderes veem apenas membros da própria tribo.

**Justificativa:** Dados históricos mostram 3 ondas de dropout previsíveis (no-show 1ª semana, fadiga do meio, recuperação pré-encerramento). Detectar membros com 3 faltas consecutivas permite intervenção antes da perda se consolidar. Threshold configurável via site_config.attendance_risk_threshold.

**Impacto técnico:** RPC `get_dropout_risk_members` com CROSS JOIN LATERAL para calcular eventos esperados por membro × presenças reais. React component DropoutRiskBanner com toggle expandível. Migration `20260319100038`.

---

### GC-033: W135 — Homepage journey redesign com hero condicional

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Aplicado em produção

**Decisão:** Redesenhar a homepage com hero condicional (visitante vs membro logado). Visitantes veem contadores de impacto (58 pesquisadores, 8 tribos, 876h) e CTA de entrada. Membros logados veem saudação personalizada, card da próxima reunião geral com link do Meet, card da tribo com horário e link, e miniatura de assiduidade. Adicionadas 3 novas seções scrolláveis: "O Núcleo" (contadores animados), "Agenda Semanal" (reuniões de tribo agrupadas por dia da semana), e "Capítulos PMI" (5 capítulos integrados com CTA de expansão). Removidos: banner estático do kickoff e seção Breakout Rooms.

**Justificativa:** Homepage serve duas jornadas distintas — visitantes precisam de credibilidade em 10 segundos (números de impacto), membros precisam do link do Meet a 1 clique. Banner de kickoff e breakout rooms eram conteúdo estático que já passou. Agenda semanal dinâmica nunca fica desatualizada pois puxa do banco.

**Impacto técnico:** RPC pública `get_homepage_stats()` (sem auth, GRANT TO anon). Componentes: HomepageHero.astro (hero condicional com client-side auth), NucleoSection.astro (contadores com IntersectionObserver), WeeklyScheduleSection.astro (tribe_meeting_slots agrupados por dia), ChaptersSection.astro. site_config entries: general_meeting_link, general_meeting_day, general_meeting_time. Migration `20260319100039`.

---

### GC-034: W136 — Nav menu cleanup + YouTube enrichment

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Aplicado em produção

**Decisão:** Limpar o avatar dropdown (menu de perfil) de 25+ itens para max 15. Remover do dropdown: Onboarding, Notificações, Ajuda, Apresentações, Webinars, IA Pilots, Blog, Comms Ops, Portfólio, Governança de Boards, Curadoria, Parcerias, Relatório por Capítulo, Sustentabilidade, Cross-Tribos, Dashboard de Tribo, Campanhas. Essas páginas continuam acessíveis via URL e admin panel, apenas não aparecem no dropdown. Removida duplicata "Explorar Tribos" (aparecia em minha-tribo E explorar). Adicionadas traduções i18n faltantes no jsI18n do Nav.astro. Relatório do Ciclo aponta para /report.

**Justificativa:** Menu com 25+ itens causa paralisia de escolha e inclui features não finalizadas. Regra: dropdown mostra apenas features prontas e de uso frequente. Itens administrativos acessíveis via painel admin. Links quebrados (i18n não traduzido) prejudicam credibilidade.

**Impacto técnico:** Modificado `navigation.config.ts` — items removidos do drawer via `section: 'main'` (preserva config para uso futuro). Adicionadas 9 traduções faltantes ao `jsI18n` em Nav.astro. Cycle report href `/admin/cycle-report` → `/report`. SQL: `is_recorded=true` em eventos pós 25/fev. site_config: `youtube_channel_url`.

---

### GC-035: W136b — Events pagination + interview visibility filter

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Aplicado em produção

**Decisão:** Adicionar paginação de 20 eventos por página na listagem de presenças com botão "Carregar mais". Esconder eventos do tipo `interview` (35 entrevistas de processo seletivo) de usuários não-gerentes. Gerentes/superadmin veem toggle "Mostrar entrevistas" (desligado por default). Adicionados filtros de tipo para kickoff e liderança.

**Justificativa:** 148 eventos sem paginação degradam performance e UX. Entrevistas são dados sensíveis do processo seletivo e não devem ser visíveis para pesquisadores comuns. A regra de visibilidade usa `CAN_MANAGE` (tier >= leader) já existente.

**Impacto técnico:** Modificado `attendance.astro` — `filteredEvents()` exclui `type='interview'` para não-gerentes, pagination via `VISIBLE_COUNT` + `PAGE_SIZE=20`, RPC limit aumentado de 40 para 200, novos tipos no dropdown (kickoff, leadership_meeting), toggle de entrevistas visível apenas para managers.

---

### GC-036: W136c — Help link accessibility + welcome popup persistence

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Aplicado em produção

**Decisão:** Restaurar link "Central de Ajuda" no avatar dropdown (seção Meu Espaço) para todos os usuários logados. Adicionar botão "?" persistente na barra de navegação ao lado do avatar. Persistir dismiss do popup de boas-vindas no banco de dados (`onboarding_dismissed_at`) ao invés de `sessionStorage` (que resetava ao fechar aba).

**Justificativa:** W136 removeu agressivamente o link de ajuda do dropdown, tornando /help inacessível para pesquisadores. O popup de boas-vindas reaparecia porque `sessionStorage` não persiste entre sessões. Membros existentes já viram o popup múltiplas vezes — migração marca todos como dismissed.

**Impacto técnico:** `navigation.config.ts`: `help` item mudado de `section: 'main'` para `section: 'both'` com `drawerSection: 'meu-espaco'`. Nav.astro: botão "?" adicionado antes do avatar. `help.astro`: popup usa `member.onboarding_dismissed_at` do DB em vez de `sessionStorage`. Nova migração: coluna `onboarding_dismissed_at timestamptz` em members, RPC `dismiss_onboarding()`. Todos os membros ativos marcados como dismissed na migração.

---

### GC-037: W137 — Email delivery via Resend Edge Function

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Aplicado em produção

**Decisão:** Ativar entrega real de emails de campanhas via Resend API + Supabase Edge Function `send-campaign`. GP pode enviar campanhas para membros ativos com templates i18n, variáveis dinâmicas, e link de unsubscribe. Frontend agora aguarda resultado da entrega e mostra status (entregues/erros).

**Justificativa:** Sistema de campanhas existia (templates, preview, audiência) mas não entregava emails. Resend free tier (3000/mês, 100/dia) suficiente para 53 membros. Edge Function executa com service role key para acessar recipients via RLS bypass.

**Impacto técnico:** Edge Function `send-campaign` deployada. RESEND_API_KEY configurado como secret. Frontend campaigns.astro: send flow aguarda Edge Function response, mostra delivery stats (entregues/erros), recarrega histórico após envio. Sender: `nucleoia@pmigo.org.br`.

---

### GC-038: W138 — Pre-Beta quality audit

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Aplicado em produção

**Decisão:** Auditoria completa pré-Beta: corrigir RPCs quebrados por referência à coluna `role` (dropped), resolver transparência do editor de campanhas, adicionar toggle de membros inativos, e inventário de facades frontend.

**Justificativa:** Preparação para anúncio Beta a 53+ membros. 5 overloads de funções (create_event ×2, update_event ×2, create_recurring_weekly_events) referenciavam `members.role` ao invés de `operational_role` e crashariam com 400. As funções get_board, auto_publish_approved_article, mark_interview_status e submit_interview_scores foram verificadas e não estavam quebradas (referenciam `board_item_assignments.role`, coluna existente). CSS aliases (`--surface`, `--fg`, `--fg-muted`, `--border`) estavam ausentes no theme, causando backgrounds transparentes em modais/editors de múltiplas páginas.

**Impacto técnico:** Migration `20260319100041_w138a_fix_role_refs.sql`: 5 function overloads re-criados com `.operational_role`. CSS `theme.css`: aliases adicionados em `:root` e `[data-theme="dark"]`. Campaigns: checkbox "Incluir membros inativos" passa `include_inactive` no audience filter. Facades identificadas: sustainability.astro (puro mockup), projects.astro (botão registro sem handler). Sweep de 63 páginas: zero 500s, zero `getLangFromURL(Astro.url)` incorretos.

---

### GC-039: W139 — Platform Integrity Audit (Pre-Beta)

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Documentação concluída

**Decisão:** Auditoria completa de integridade da plataforma: 42 rotas únicas, 117 RPCs, 74 tabelas, 14 Edge Functions, 13 componentes React com Supabase. Metodologia: cross-reference automatizado frontend→DB com validação manual por agentes de auditoria.

**Justificativa:** Garantir que nenhum usuário Beta encontre páginas quebradas, RPCs inexistentes, ou features enganosas. O `/admin/comms` era suspeito de facade — confirmado funcional (8 RPCs, dados reais). Dois achados P1 identificados: view `active_members` e tabela `publication_submission_events` inexistentes, causando falhas silenciosas em `/workspace` e `/publications`.

**Impacto técnico:** 4 documentos de auditoria em `docs/audit/`: MASTER_SUMMARY.md, ROUTE_INVENTORY.md, RPC_INVENTORY.md, TABLE_INVENTORY.md, DEPENDENCY_MAP.md. Zero P0 blockers. Zero dead links. Zero referências a colunas dropadas. 89 funções DB órfãs documentadas (42 pipeline legítimo, 16 candidatas a UI, 5 deprecated). Plataforma confirmada pronta para Beta com 2 fixes P1 pendentes.

---

### GC-040: W139-1 — Active Member Definition

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Definicao formal de "membro ativo": `members.is_active = true`. View `active_members` criada como `SELECT * FROM members WHERE is_active = true`.

**Justificativa:** `/workspace` (tribe member counts) e attendance module (member list) referenciavam `active_members` que nao existia, causando contagem zero e lista vazia silenciosamente. Fix identificado na auditoria W139 como P1.

**Impacto tecnico:** View `active_members` criada com GRANT SELECT para authenticated e anon. 53 membros retornados (validado).

---

### GC-041: W139-2 — Publication Submission Tracking

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Schema tipado para tracking de submissoes de publicacoes a conferencias e periodicos PMI. Tabela `publication_submission_events` recriada no schema public (estava em z_archive), tabelas `publication_submissions` e `publication_submission_authors` criadas.

**Justificativa:** Tabela `publication_submission_events` foi arquivada para z_archive mas frontend e RPCs continuavam referenciando o schema public, causando falha silenciosa. Alem do fix, criado schema completo para tracking estruturado de submissoes (Cycle 3 deliverable).

**Impacto tecnico:** 3 tabelas, 2 enums (`submission_status`, `submission_target_type`), 3 RPCs SECURITY DEFINER (`create_publication_submission`, `update_publication_submission_status`, `get_publication_submissions`), 2 RPCs existentes corrigidos (return type de z_archive para public, `auth_user_id` corrigido para `auth_id`).

---

### GC-042: W139-4/W108 — Sustainability Framework

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Modulo de sustentabilidade financeira com schema real, substituindo mockup hardcoded. Stakeholders podem registrar custos e receitas durante Beta.

**Justificativa:** `/admin/sustainability` era 4 cards hardcoded com "Planning". Para Beta, necessario ter framework real onde gestores podem inserir dados — mesmo que inicialmente zerados. Alinhado com W108 (sustainability module).

**Impacto tecnico:** 5 tabelas (`cost_categories`, `cost_entries`, `revenue_categories`, `revenue_entries`, `sustainability_kpi_targets`), 3 RPCs (`create_cost_entry`, `create_revenue_entry`, `get_sustainability_dashboard`), seeded com 8 categorias de custo, 7 categorias de receita, 5 KPI targets Ciclo 3. Frontend reescrito com dashboard real + modais de registro.

---

### GC-043: W139-5 — Deprecated Function Cleanup

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** 4 funcoes deprecated removidas apos verificacao: `comms_metrics_latest`, `kpi_summary`, `move_board_item_to_board`, `finalize_decisions`. DDL backed up em `docs/audit/DEPRECATED_FUNCTIONS_BACKUP.sql`.

**Justificativa:** Funcoes identificadas na auditoria W139 como deprecated (substituidas por versoes mais recentes). Verificado: zero trigger bindings, zero chamadas frontend, uma dependencia inter-funcao encontrada (`exec_funnel_v2` chamado por `exec_analytics_v2_quality`) — mantida.

**Impacto tecnico:** 4 funcoes removidas com CASCADE. `exec_funnel_v2` mantida (usada por analytics). Schema catalog mais limpo.

---

### GC-044: W139C — Technical Debt Inventory

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Documentacao concluida

**Decisao:** Inventario completo de divida tecnica pre-Beta: npm audit, outdated packages, TypeScript strict, hardcoded values, TODOs, security check.

**Justificativa:** Baseline de qualidade tecnica para o Beta. Documenta o estado da plataforma para reference pos-Beta.

**Impacto tecnico:** 10 vulnerabilities npm (todas dev-time), 18 TypeScript strict errors (nao-bloqueantes), 0 TODOs, 0 secrets hardcoded, 0 localhost refs. Plataforma limpa para Beta.

---

### GC-045: W139-3 — Admin Orphan Page Links

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Paginas orfas `/admin/board/[id]` e `/admin/member/[id]` agora acessiveis via links na UI admin.

**Justificativa:** Auditoria W139 identificou que essas rotas existiam mas nenhum link apontava para elas. Membros no painel admin agora linkam para detalhe via nome clicavel. Boards listados em `/admin/portfolio` com links para detalhe.

**Impacto tecnico:** Nome do membro em `/admin/index.astro` agora e `<a>` para `/admin/member/[id]`. Lista de boards ativos adicionada em `/admin/portfolio.astro` com links para `/admin/board/[id]`.

---

### GC-049: W141-1 — Comms Board Navigation

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Hub de Comunicacao e Publicacoes boards acessiveis via avatar dropdown e /workspace.

**Justificativa:** Comms team (Mayanna, Leticia, Andressa) nao conseguia acessar boards globais pela navegacao. Boards orphaned em `/admin/board/[id]` sem entry points.

**Impacto tecnico:** Dois novos NavItems em `navigation.config.ts` com `drawerSection: 'producao'`. Dois novos cards em workspace subprojects section. Aceito por membros com designations comms_leader, comms_member, curator, co_gp.

---

### GC-050: W141-2 — PMBOK 8 Date Model for Cards

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Cards tem 3 datas: Baseline (pactuada, imutavel), Forecast (previsao, auto-calculada de checklist MAX ou manual), Actual (conclusao, auto-populated quando ALL checklist items complete). Roll-up: card.forecast = MAX(checklist_items.target_date). Variancia: Forecast - Baseline. Verde (<=0), Amarelo (1-7 dias), Vermelho (>7 dias).

**Justificativa:** Alinhamento com PMBOK 8 para Schedule Performance Measurement. Permite identificar desvios de prazo e gerar SPI por tribo.

**Impacto tecnico:** Colunas baseline_date, forecast_date, actual_completion_date em board_items. Trigger `recalculate_card_dates` auto-atualiza forecast/actual baseado em checklist changes. Trigger `log_forecast_change` registra alteracoes em board_lifecycle_events. CHECK constraint expandido para incluir forecast_update, actual_completion, mirror_created.

---

### GC-051: W141-3 — Checklist Item Assignments

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Cada item de checklist pode ter 1 membro responsavel + data alvo. Conclusao registra quem e quando completou.

**Justificativa:** Accountability de sub-tarefas dentro de cards. Checklist migrado de JSON em board_items.checklist para tabela board_item_checklists com dados estruturados.

**Impacto tecnico:** Tabela board_item_checklists com assigned_to, target_date, completed_at, completed_by. RPCs assign_checklist_item e complete_checklist_item. CardDetail.tsx atualizado com dropdowns de membro e data por item.

---

### GC-052: W141-4 — Board View Modes

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** 4 views adicionais: Tabela (sortable columns), Lista Agrupada (por tag/membro/status), Calendario (mensal por forecast_date), Timeline/Gantt (barras baseline-forecast com progresso). Todas compartilham mesmos dados e filtros.

**Justificativa:** Diferentes views para diferentes audiencias: tribo dia-a-dia (kanban), GP review (tabela), planejamento (calendario), executivo (timeline).

**Impacto tecnico:** ViewToggle.tsx, TableView.tsx, GroupedListView.tsx, CalendarView.tsx, TimelineView.tsx criados. BoardEngine.tsx integra toggle e renderiza view ativa condicionalmente. Zero novas dependencias (CSS Grid + SVG nativo).

---

### GC-053: W141-5 — Mirror Cards Cross-Board

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Cards podem ser espelhados para outros boards com links bidirecionais. Source mantem status atual; mirror inicia no backlog do board destino.

**Justificativa:** Habilita fluxo de handoff: Tribo -> Curadoria -> Comunicacao -> Publicacao. Rastreabilidade bidirecional entre boards.

**Impacto tecnico:** Colunas mirror_source_id, mirror_target_id, is_mirror em board_items. RPCs create_mirror_card e get_mirror_target_boards. CardDetail.tsx mostra links de espelho e dialogo "Criar Espelho" com selecao de board destino.

---

### GC-054: W140-1 — Unified Tag System

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Sistema unificado de tags com 3 tiers (system/administrative/semantic), multi-domain (event/board_item/all), tabela unica `tags` com junction tables por dominio (`event_tag_assignments`, `board_item_tag_assignments`).

**Justificativa:** Substituir classificacao rigida por tipo (`events.type`) com sistema flexivel de tags multi-valor. Permite multi-tag por evento (ex: kickoff + general_meeting), tags compartilhadas entre eventos e boards, e criacao de tags semanticas por lideres.

**Impacto tecnico:** Enums `tag_tier` e `tag_domain`. Tabela `tags` com UNIQUE(name, domain) e coluna gerada `is_system`. Junction tables com RLS. Seed de 30 tags (sistema + administrativas + gates + ciclo). RPCs: `create_tag`, `delete_tag`, `assign_event_tags`, `get_tags`, `get_event_tags`. UI: multi-tag picker em modais de evento, tag chip filter na lista de eventos, aba "Tags" no admin panel com CRUD.

---

### GC-055: W140-2 — Event Audience Rules

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Regras de audiencia por evento com `event_audience_rules` (grupo) + `event_invited_members` (individual). Target types: all_active_operational, tribe, role, specific_members. Definicao formal: `all_active_operational = is_active AND (tribe_id IS NOT NULL OR operational_role IN ('manager','deputy_manager'))`.

**Justificativa:** Modelo anterior usava `audience_level` generico que nao capturava regras reais de quem deveria participar. Sponsors e liaisons nao devem ser contados como mandatory. Cada evento precisa de regras granulares.

**Impacto tecnico:** Tabelas `event_audience_rules` (partial unique indexes para NULL handling) e `event_invited_members` (UNIQUE event+member). RPCs: `set_event_audience`, `set_event_invited_members`, `get_event_audience`. Migracao automatica dos 161 eventos existentes baseada em `events.type`. Modais de evento atualizados com dropdown de audiencia: todos operacionais, tribo, papel, membros especificos.

---

### GC-056: W140-3 — Attendance Calculation Correction

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Calculo de presenca corrigido com denominador personalizado. Funcao `is_event_mandatory_for_member(event, member)` verifica regras de audiencia. `get_attendance_panel()` retorna split geral/tribo com percentuais individuais e flag de dropout risk (<50% combined).

**Justificativa:** Calculo anterior dividia presencas pelo total de eventos, penalizando membros que nao eram publico-alvo de certos eventos. Novo calculo conta apenas eventos mandatory para cada membro.

**Impacto tecnico:** Funcao `is_event_mandatory_for_member` consulta `event_audience_rules` + `event_invited_members`. RPC `get_attendance_panel` com CTEs para general_events (tag general_meeting) e tribe_events (tag tribe_meeting), cross join com membros ativos, calculo de percentual por membro.

---

### GC-057: W140-4 — Spec-vs-Deployed Audit as Standard Practice

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Auditoria spec-vs-deployed estabelecida como pratica padrao apos cada sprint. Documento gerado em `docs/audit/` comparando spec com implementacao real, identificando divergencias e medindo cobertura.

**Justificativa:** Audit W139/W141 encontrou 3 divergencias que teriam passado despercebidas sem verificacao sistematica. Pratica garante integridade entre spec e codigo.

**Impacto tecnico:** Template de audit em `docs/audit/SPEC_VS_DEPLOYED_*.md` com categorias de findings (layout, schema, features), status tracking (partial/full/N-A), e scorecard de cobertura percentual.

---

### GC-058: W142 — GP Portfolio Dashboard

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Dashboard consolidado para o GP mostrando todos 56 entregaveis de lider das 8 tribos com Gantt, heatmap, filtros por tribo/tipo/status/saude/periodo, e cards de resumo por tribo.

**Justificativa:** GP precisava de visao unica para todos entregaveis das tribos. Antes, era necessario visitar cada board individualmente. Dashboard permite decisoes data-driven em reunioes gerais e apresentacoes para sponsors.

**Impacto tecnico:** RPC `get_portfolio_dashboard` com calculos de health/variance. Componente React `PortfolioDashboard` com 4 visoes (tabela, Gantt SVG, heatmap tribo x mes, cards de tribo). Zoom: Ano/Trimestre/Mes/Semana. Filtros: tribo, tipo, status, saude, quarter. Rota: `/admin/portfolio`.

---

### GC-059: W143 — Gamification Category Reclassification

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Reclassificacao de todas as 210 entradas de gamificacao em taxonomia refinada: trail (20 XP, 7 cursos PMI obrigatorios), cert_pmi_senior (50), cert_cpmai (45), cert_pmi_mid (40), cert_pmi_practitioner (35), cert_pmi_entry (30), specialization (25), knowledge_ai_pm (20), course (15, apenas CDBA), badge (10). Hierarquia de 5 niveis de certificacao substituindo sistema flat anterior.

**Justificativa:** Sistema anterior classificava tudo como "course" a 15 XP. Nova taxonomia valoriza corretamente certificacoes PMI Senior vs Entry, separa trilha obrigatoria de cursos complementares, e distingue especializacoes de badges comunitarios. CDBA_INTRO removido da trilha obrigatoria (sem Credly badge). Duplicata CPMAI v7 de Pedro Henrique resolvida.

**Impacto tecnico:** CHECK constraint expandido para 13 categorias. sync_attendance_points trail-aware com verificacao dual-category. gamification_leaderboard VIEW com learning_points, cert_points, badge_points. get_member_cycle_xp com cycle_learning e cycle_certs. Frontend: CATEGORY_META expandido, TRAIL_TOTAL=7, pontos legend atualizado.

### GC-060: W144 — Centralized Permissions + Tier Viewer

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado (Fase 1+2)

**Decisao:** All access control centralized in permissions.ts with hasPermission(). Superadmins can simulate any tier/designation/tribe combination to preview member journeys. Writes during simulation execute with real superadmin permissions + info toast.

**Justificativa:** ~158 direct role checks spread across 40+ components made it impossible to audit or test permission changes. GP needed a way to verify member journeys without maintaining multiple test accounts. Centralizing permissions in one file enables single-point changes and full audit trail.

**Impacto tecnico:** permissions.ts: 11 operational tiers x 7 designations x ~45 permission strings. SimulationContext (React) + cookie sync for Astro SSR pages. TierViewerBar in BaseLayout (superadmin only). AdminNav, useBoardPermissions migrated to hasPermission(). Phase 3 backlog: migrate remaining ~130 direct checks.

### GC-062: W107 — AI Pilot Registration Framework

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** 3-pilot annual KPI tracked via `pilots` table. Pilot #1 (Hub SaaS) registered with 9 auto-calculated metrics. /projects shows public summary with expandable detail; /admin/pilots enables GP management. Release system with version in footer.

**Justificativa:** Hub SaaS platform counts as AI Pilot #1 toward annual KPI. Structured tracking enables evidence-based reporting to sponsors and chapter liaisons. Auto-calculated metrics eliminate manual data collection.

**Impacto tecnico:** `pilots` table (8 PMI fields + success_metrics jsonb with auto_query). `releases` table (version tracking with is_current flag). RPCs: get_pilot_metrics (auto-calc 9 metrics), get_pilots_summary (KPI progress 1/3), get_current_release (footer version). Routes: /projects (public), /admin/pilots (GP management).

### GC-063: Terminology — Tribo mantida (W140-GOV revert)

**Data:** 2026-03-15
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Migracao Tribe→Community of Practice (CoP) cancelada. Termo "Tribo" consolidado e sem friccao. Infraestrutura de permissoes permanece pronta caso revisitada.

**Impacto tecnico:** Zero mudancas no banco ou frontend. GC-039 (Org Chart v4) atualizado: referencias a CoP sao informativas, nao operacionais.

### GC-064: W104 — Annual KPI Calibration

**Data:** 2026-03-16
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** 13 annual KPIs across 5 categories (delivery, engagement, learning, financial, growth). Auto-calculated from existing DB tables. Scorecard integrated into Portfolio Dashboard.

**Justificativa:** GP and sponsors need real-time progress against annual targets. Manual tracking via spreadsheets doesn't scale. Auto-calculation eliminates reporting overhead.

**Impacto tecnico:** `annual_kpi_targets` table with 13 seeded KPIs. `get_annual_kpis` RPC auto-calculates 11/13 from: pilots, board_items+tags, events+tags, attendance, course_progress, members. 2 manual (infra cost, chapters). `update_kpi_target` RPC for GP to adjust targets. Portfolio KPI Health section now uses get_annual_kpis with health indicators (achieved/on_track/at_risk/behind).

---

### GC-065 — Executive Cycle Report (W105)

**Data:** 2026-03-16
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Auto-generated executive cycle report from platform data. Accessible at /report (all authenticated members) with PDF export via browser print. Seven sections: overview, KPIs, tribe performance, pilots, gamification, events, platform stats. Admin configuration at /admin/report allows GP to toggle sections and add notes.

**Justificativa:** GP previously compiled cycle reports manually from 6 different sources (~4h/week). With all data in the Hub, the report auto-generates in real time. Sponsors and PMI Global get accurate data snapshots without manual intervention.

**Impacto tecnico:** `get_cycle_report(p_cycle)` RPC aggregates all 7 sections from existing tables (members, tribes, board_items, events, attendance, gamification_points, pilots, releases). Frontend renders print-optimized React island with inline SVG charts (tribe bars, event timeline). Zero external PDF libraries — uses @media print CSS with window.print(). Report config stored in site_config table via set_site_config RPC.

---

### GC-066 — Financial Sustainability CRUD + Projections (W108)

**Data:** 2026-03-16
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Full CRUD UI for cost and revenue tracking. 4 tabs: Dashboard (with projections + infra breakdown), Costs (CRUD table with filters), Revenue/Value (CRUD table), Targets (KPI editor). Zero-cost seed: 7 infrastructure items registered at R$0, documenting free tier usage.

**Justificativa:** Hub operates at zero-cost but had no data tracking this. Financial transparency is required for sponsors and PMI Global reporting. Projections enable proactive budgeting if/when costs arise.

**Impacto tecnico:** 6 new RPCs: `get_cost_entries`, `get_revenue_entries` (list with filters), `delete_cost_entry`, `delete_revenue_entry` (manager/superadmin only), `update_sustainability_kpi` (edit targets), `get_sustainability_projections` (6-month forecast). Uses existing W139 schema (5 tables). `infra_cost_monthly` KPI (W104) now auto-calculated from `cost_entries`. Cycle Report (W105) includes `sustainability` section. Permission: `admin.sustainability` (manager + deputy_manager).

---

### GC-067 — Publication Submissions Pipeline UI

**Data:** 2026-03-16
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Full publication submission pipeline: admin 3-tab UI (pipeline kanban, list table, metrics dashboard), researcher self-service on /publications, workspace "Minhas Publicacoes" card. 5 new RPCs for detail, authors CRUD, update, pipeline summary. Seed 8 existing board items into publication_submissions table.

**Justificativa:** Publication KPI is central to Cycle 3 (10 submissions + 5 academic articles). Existing board-only tracking lacked structured metadata (target type, co-authors, costs, dates). Pipeline view gives curators and GP visibility into submission flow.

**Impacto tecnico:** 5 new RPCs: `get_publication_submission_detail`, `add_publication_submission_author`, `remove_publication_submission_author`, `update_publication_submission`, `get_publication_pipeline_summary`. Admin page `/admin/publications` with permission `admin.publications` (manager/curator). Researcher self-service on `/publications` with `content.submit_publication` permission. Workspace card shows own submission counts by status. Admin nav entry added. 46 i18n keys across 3 locales.

---

### GC-068 — Gamification Auto-Sync Cron (W-CRON)

**Data:** 2026-03-16
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** pg_cron schedules automatic Credly badge sync and attendance points sync every 5 days at 3:00/3:15 UTC (midnight BRT). Eliminates dependency on manual superadmin button click.

**Justificativa:** Manual sync was error-prone (forgotten clicks, potential rate-limiting from repeated clicks). Automated scheduling ensures gamification data stays current without GP overhead.

**Impacto tecnico:** Extensions enabled: pg_cron 1.6.4, pg_net 0.20.0. Service role key stored in Supabase vault. 2 cron jobs: `sync-credly-all` (0 3 */5 * *) and `sync-attendance-points` (15 3 */5 * *). Both call Edge Functions via pg_net HTTP POST with vault-stored service_role auth. Edge Functions already accept service_role_key as valid auth. New RPC `get_cron_status()` (superadmin only) for monitoring. Manual sync button remains as fallback. Zero-cost: pg_cron included in Supabase free tier.

---

### GC-069 — W144 Phase 3: Complete Permission Migration

**Data:** 2026-03-16
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** All remaining direct role/superadmin/designation permission checks migrated to `hasPermission()` from `src/lib/permissions.ts`. ~25 files modified. Only `is:inline` script blocks (where ES imports are unavailable) retain direct checks.

**Justificativa:** Centralized permission system enables Tier Viewer simulation across all pages. Direct role checks scattered across the codebase made it impossible to simulate different tiers. With `hasPermission()`, adding a new role or changing access requires editing only `permissions.ts`.

**Impacto tecnico:** 25+ files migrated across admin pages, board components, workspace components, content pages, and lib helpers. All `.tsx` components and regular `<script>` blocks in `.astro` pages now use `hasPermission()`. Remaining direct checks are in `is:inline` scripts (4 admin pages) which cannot use ES imports, type definitions, data display, and DB queries. `canAccessWebinarsWorkspace()` and `canAccessPublicationsWorkspace()` in `lib/admin/constants.ts` now delegate to `hasPermission()`. `canManageTribeLifecycle()` and `canSeeInactiveTribes()` in `lib/tribes/access.ts` now use `hasPermission()`.

---

### GC-070 — Member Activity Tracking for Adoption Analytics

**Data:** 2026-03-16
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Lightweight activity tracking via `record_member_activity()` RPC called on each pageview (throttled 5min client-side). Stores `last_seen_at`, daily session count, and last 5 pages on members table. Admin-only dashboard at `/admin/adoption` with KPI cards, daily activity chart, breakdowns by tribe/tier, and sortable member list.

**LGPD:** Base legal = legitimo interesse (Art. 7, IX) para gestao operacional. Dados minimos: timestamp + page count. Sem tracking de tempo de permanencia. Sem dados expostos a outros membros. Politica de Privacidade ja cobre analytics (PostHog). Acesso somente admin/GP.

**Impacto tecnico:** 3 columns on `members` (last_seen_at, total_sessions, last_active_pages). New `member_activity_sessions` table (daily granularity, RLS admin-only read). `record_member_activity()` SECURITY DEFINER RPC. `get_adoption_dashboard()` returns summary + by_tier + by_tribe + daily_chart + member_list. Activity tracker in `BaseLayout.astro` (non-blocking, fire-and-forget). `/admin/adoption` page with full dashboard. GC-070.

---

### GC-071 — Resend Webhook Analytics (W-CAMP-ANALYTICS)

**Data:** 2026-03-17
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Resend webhooks integrated for real-time email delivery tracking. Funnel visualization (sent→delivered→opened→clicked) in /admin/campaigns Stats view. Per-recipient status with role/tribe breakdown. Edge Function `resend-webhook` receives Resend events, `process_email_webhook` RPC updates `campaign_recipients` tracking columns idempotently, `get_campaign_analytics` RPC returns funnel + breakdown data.

**LGPD:** Open/click tracking is standard for transactional email analytics. No additional PII stored beyond existing campaign_recipients data. `email_webhook_events` audit table is admin-only (RLS). Complained events auto-unsubscribe the recipient.

**Zero-cost:** Resend webhooks are free. No additional services needed.

**Impacto tecnico:** New columns on `campaign_recipients` (resend_id, delivered_at, opened_at, open_count, clicked_at, click_count, bounced_at, bounce_type, complained_at). New `email_webhook_events` table with RLS. New Edge Function `resend-webhook` (deployed --no-verify-jwt). `send-campaign` updated to store resend_id. `get_campaign_analytics` RPC returns funnel + by_role + recipients. Stats panel in `/admin/campaigns` with funnel cards, role breakdown table, and recipient status table. Manual step: configure webhook URL in Resend dashboard.

---

### GC-072 — Help Content Update + Collapsed UX

**Data:** 2026-03-17
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Help floating panel FAQ items collapsed by default. Users scan all questions, expand on demand. Intro section always visible. 26 FAQ items across 5 sections (Getting Started 5, Workspace 6, Leaders 6, Admin 6, Troubleshooting 4). All trilingual (inline per-item). New troubleshooting section with common issues. Section headers with emojis. Links section with Privacy, GitHub, contact.

**Impacto tecnico:** HelpFloatingButton.tsx refactored from 3 separate language arrays to single multilingual FAQ_ITEMS array (26 items). Added troubleshooting section visible to all. Section emojis. Fixed accent on "Política de Privacidade/Privacidad". i18n keys: help.intro, help.privacy, help.version, help.contact.

### GC-073 — TipTap Refinement + Reusable RichTextEditor

**Data:** 2026-03-17
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Created reusable RichTextEditor component with 3 toolbar presets (full, basic, minimal). Applied to blog (full) and campaign templates (basic). Principle: no user should need to know HTML to use any Hub feature. Blog editor refactored to thin wrapper around shared component. Campaign template body_html textarea replaced with WYSIWYG editor.

**Impacto tecnico:** src/components/shared/RichTextEditor.tsx wraps TipTap with toolbar presets. src/components/shared/RichTextEditorIsland.tsx provides generic Astro island bridge using richtext:{field}:set/change events. BlogEditor.tsx now thin wrapper with toolbar="full". campaigns.astro uses RichTextEditorIsland with toolbar="basic" for body_html editing. Focus ring added on editor border. Audit confirmed only blog and campaigns needed WYSIWYG — announcements, board items, and publications use plain text.

### GC-074 — Admin Panel Modernization Phase 1: Technical Refactor

**Data:** 2026-03-17
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Phase 1 of 6-phase admin modernization. Eliminated duplicate function definitions (avatar, memberTags, memberTribeTag) by importing from constants.ts. Updated constants.ts to use CSS variables for dark mode compatibility. Extracted 4 modals to Astro components (AllocateTribeModal, EditMemberModal, CycleHistoryModal, NotifyAllocationModal). Created typed interfaces (Member, Tribe, AdminStats, AuditLogEntry). Created admin_audit_log table with RLS (superadmin read, actor-scoped insert) for Phase 5. Zero visual change — pure refactor.

**Impacto tecnico:** admin/index.astro reduced from 4383 to 4178 lines (-205). Modals in src/components/admin/modals/. Types in src/lib/admin/types.ts. admin_audit_log table deployed with 3 indexes. constants.ts memberTags/memberTribeTag now use CSS vars (bg-[var(--surface-section-cool)], text-[var(--text-muted)]) instead of hardcoded Tailwind for dark mode.

### GC-075 — Admin Panel Modernization Phase 2: AdminLayout + Sidebar

**Data:** 2026-03-17
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** New AdminLayout.astro with collapsible sidebar replaces pill navigation. 5 categories: Overview, People, Content, Reports, Operations. 24 admin pages migrated (21 top-level + 3 sub-routes). Desktop: 240px open / 64px collapsed with localStorage persistence. Mobile: drawer overlay with hamburger trigger. Breadcrumbs on all pages. Sidebar labels trilingual (inline). Permission-aware: items hidden based on member permissions via hasPermission().

**Impacto tecnico:** AdminLayout.astro extends BaseLayout, adds AdminSidebar (React island) + breadcrumbs + mobile hamburger. AdminSidebar.tsx uses lucide-react icons, 5 SECTIONS with permission-based visibility. Collapse state in localStorage (hub_admin_sidebar_collapsed). Mobile drawer with backdrop + Escape close. AdminNav.astro retained for test backward-compat but no longer imported by any page.

### GC-076 — Admin Panel Modernization Phase 3: Dedicated Members Page

**Data:** 2026-03-17
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Created dedicated /admin/members page with React MemberListIsland. Features: stat cards (total, active, inactive, no-tribe, no-auth), search by name/email, filters (role, tribe, status), member table with avatar/tags/tribe/chapter/status/last-seen, inline edit modal (3-axis: operational role, designations, superadmin + chapter + status), checkbox column for future bulk ops. admin_list_members RPC for server-side filtering with admin-only access. Sidebar updated with separate Members link under People.

**Impacto tecnico:** /admin/members.astro + MemberListIsland.tsx (React island). admin_list_members RPC (SECURITY DEFINER, joins tribes for tribe_name, supports search/tier/tribe/status filters). Sidebar: added /admin/members entry in People section. admin/index.astro preserved (other tabs still needed). No regression.

---

### GC-077 — Admin Panel Modernization Phase 4: Member Detail + Dashboard

**Data:** 2026-03-17
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Member detail page /admin/members/[id] with 7 sections (header, edit form, cycles, gamification, attendance, publications, audit log). Edit uses admin_update_member_audited RPC which updates member + auto-logs changes to admin_audit_log. get_member_detail RPC returns all sections in one call (member info, cycle history, gamification points/rank, attendance rate + recent events, publications, audit trail). Admin dashboard added to /admin with 6 KPI cards (active members, adoption 7d, deliverables, impact hours, CPMAI, chapters), operational alerts (no-tribe, no-auth stakeholders, dropout risk), and activity feed (audit log + campaigns + publications). get_admin_dashboard RPC returns KPIs, alerts, and recent activity.

**Impacto tecnico:** /admin/members/[id].astro + MemberDetailIsland.tsx (React island). AdminDashboardIsland.tsx added to admin/index.astro. Two new RPCs: get_member_detail (SECURITY DEFINER, joins tribes/cycles/gamification/attendance/publications/audit), admin_update_member_audited (update + audit trail). get_admin_dashboard RPC (SECURITY DEFINER, KPIs from members/board_items/events/gamification_points/annual_kpi_targets, alerts from data quality checks, activity from audit_log/campaign_sends/publication_submissions). MemberListIsland link updated to /admin/members/[id]. No regression.

---

### GC-078 — Admin Panel Modernization Phase 5: Audit Log System

**Data:** 2026-03-18
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** All member-editing RPCs instrumented with admin_audit_log: admin_inactivate_member, admin_reactivate_member, admin_move_member_tribe, admin_deactivate_member, admin_change_tribe_leader. New /admin/audit-log page with filterable table (actor, action, date range) and pagination. Superadmin-only access via get_audit_log RPC. Added to sidebar under Operações with ClipboardList icon.

**Impacto tecnico:** Migration 20260319100066 replaces 5 RPCs preserving original logic + adding audit INSERT. get_audit_log RPC (SECURITY DEFINER, superadmin-only, pagination, actor/action/date filters). AuditLogIsland.tsx (React island). /admin/audit-log.astro page. AdminSidebar updated with ClipboardList icon + audit-log link.

---

### GC-079 — Admin Panel Modernization Phase 6: Bulk Operations

**Data:** 2026-03-18
**Autor:** Vitor Rodovalho (via Claude Code)
**Status:** Implementado

**Decisao:** Checkbox selection in /admin/members with sticky bulk action bar when 1+ selected. Two bulk operations: Allocate to Tribe (modal with tribe dropdown + confirmation) and Change Status (modal with activate/deactivate radio + confirmation). Each operation creates N audit log entries with _bulk suffix. admin_bulk_allocate_tribe and admin_bulk_set_status RPCs with admin-only access.

**Impacto tecnico:** MemberListIsland.tsx enhanced with bulk state, handlers, and two confirmation modals. Migration 20260319100067 creates admin_bulk_allocate_tribe and admin_bulk_set_status RPCs (SECURITY DEFINER, loop over member IDs, individual audit entries per member). No regression.

---

### GC-080 — Privacy Policy LGPD Rewrite v2.0
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisao:** Privacy Policy reescrita para padrao LGPD formal v2.0. Expandida de 10 para 13 secoes. Adicionadas secoes: transferencia internacional de dados (Art. 33), decisoes automatizadas (Art. 20), publico-alvo e menores (Art. 14), contato e ANPD (Art. 18 §1). Declarados dados anteriormente nao informados: activity tracking (last_seen_at, total_sessions, last_active_pages, member_activity_sessions), email analytics (campaign_recipients opens/clicks, email_webhook_events), admin audit log (admin_audit_log), Credly sync (credly_badges). Processadores adicionados: Resend (email), Credly/Pearson VUE (certificacoes). Corrigida afirmacao factualmente incorreta sobre anonimizacao de analytics.

**Justificativa:** Compliance gap ativo — a plataforma coletava dados pessoais identificados (activity tracking, email tracking) sem declarar na politica de privacidade, violando LGPD Art. 7. Secoes obrigatorias pela LGPD (transferencia internacional, decisoes automatizadas, menores, ANPD) estavam ausentes.

**Impacto tecnico:** Reescrita completa de privacy.astro (10→13 secoes, 2 tabelas HTML responsivas). Substituicao do bloco privacy.* em 3 arquivos i18n (~70→~130 keys cada: pt-BR.ts, en-US.ts, es-LATAM.ts). Tabelas S3 (finalidade × base legal) e S6 (retencao) com overflow-x-auto para mobile. CSS variables para dark mode. Noindex mantido. Zero migrations SQL.

---

### GC-081 — XP Mass Correction + Publication Data Fix
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisao:** Correcao em massa de 116 rows em gamification_points across 7 categorias para valores XP corretos por tier (trail=20, knowledge_ai_pm=20, specialization=25, course=15, cert_pmi_practitioner=35, cert_pmi_mid=40, cert_pmi_entry=30). Publication submissions tribe_id: nao corrigido automaticamente — board central nao tem tribe_id, requer atribuicao manual.

**Justificativa:** W143 reclassificou categorias mas reteve valores XP originais do Credly (10/15) em 53% dos rows. Rankings distorcidos para 13 membros incluindo 4 lideres de tribo e o GP. Edge Function sync-credly-all identificada com 3 bugs que reverteriam o fix na proxima sync (category hardcoded como 'course', XP trail=15 em vez de 20, nomes de categoria desatualizados).

**Impacto tecnico:** 7 UPDATEs em transacao unica no Supabase. Zero alteracoes de schema, view ou functions (ja corretas pelo W143). Total de rows: 219 antes = 219 depois. Edge Function `sync-credly-all` corrigida e deployed (v33): `classifyBadge()` reescrita com 10 categorias W143 e XP corretos, `upsertCredlyPoints()` agora aceita e persiste `category` (antes hardcoded como 'course'), `analyzeBadges()` corrigida para usar category names W143. Proxima execucao pg_cron preservara os valores corrigidos.

### GC-082 — Admin Monolith Cleanup
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisao:** Migrar 3 tabs unicas do admin/index.astro (4.178 linhas) para React islands standalone, remover 4 tabs duplicadas, reduzir index a redirect. Padrao React islands consolidado como unico padrao admin.

**Justificativa:** admin/index.astro era um monolito com 7 tabs e script block monolitico misturando funcoes de todas as tabs. 4 tabs ja tinham paginas standalone duplicadas. Manutenibilidade comprometida.

**Impacto tecnico:** 3 novos React islands criados (KnowledgeIsland.tsx, DataHealthIsland.tsx, TagManagementIsland.tsx) com 3 paginas Astro correspondentes (knowledge.astro, data-health.astro, tags.astro). AdminSidebar.tsx atualizado com 3 novos links (Biblioteca de Recursos, Data Health, Tags). admin/index.astro reduzido de 4.178 para 7 linhas (redirect). Build green. Zero regressoes.

---

### GC-083 — Edge Function Inventory Audit + Testing
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisao:** Auditoria completa de 16 Edge Functions. 3-layer testing (unit, static contracts, integration smoke). 4 shared modules extraidos. 2 orphan EFs reconstruidos no repo. 2 legacy EFs undeployed. verify-credly atualizado para W143 (10 categorias).

**Justificativa:** Zero cobertura de teste para EFs. 2 EFs deployed sem codigo no repo (get-comms-metrics v13, sync-knowledge-youtube v10). 2 EFs de migracao one-time ainda deployed desnecessariamente. verify-credly usava classificacao tier-based obsoleta (pre-W143).

**Impacto tecnico:** 4 shared modules criados em _shared/ (classify-badge.ts, attendance-xp.ts, email-utils.ts, webhook-parser.ts). 5 EFs atualizados para importar de _shared/ (sync-credly-all, verify-credly, sync-attendance-points, send-campaign, resend-webhook). verify-credly migrado de tier-based para W143 10-category system. 2 orphan EFs reconstruidos no repo (get-comms-metrics, sync-knowledge-youtube). 2 legacy EFs undeployed (import-trello-legacy, import-calendar-legacy) com _DEPRECATED.md. 174 novos testes (57 unit + 112 contract + 5 smoke). Suite total: 784 testes, 771 pass, 8 pre-existing fail, 5 smoke skipped. Todos 5 EFs modificados deployed com sucesso.

---

### GC-084 — Database Backup Strategy via GitHub Actions
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisao:** Backup automatico semanal do banco via GitHub Actions. pg_dump do schema public (excluindo schemas internos Supabase), comprimido com gzip, armazenado como artifact do GitHub Actions. Retencao: 8 backups mais recentes (~2 meses). Custo zero (free tier).

**Justificativa:** Supabase free tier nao tem backup automatico. Base tem 52 membros, 430 board_items, 219 gamification_points, 161 eventos. Um DELETE acidental ou incidente Supabase = perda de dados irrecuperavel.

**Impacto tecnico:** Workflow `.github/workflows/backup-database.yml` (semanal domingo 23:00 UTC). Procedimento de restore documentado em `docs/RESTORE_DATABASE.md`. Requer secret `SUPABASE_DB_URL` configurado no GitHub (connection string session mode). Schemas excluidos: auth, storage, supabase_functions, extensions, graphql, realtime, pgsodium, vault, supabase_migrations.

---

### GC-085 — Tribe Names i18n via Parallel Columns
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisao:** Internacionalizacao dos nomes de tribos e quadrantes via colunas paralelas jsonb (name_i18n, quadrant_name_i18n). 8 tribos x 3 locales (pt, en, es) populadas. 16 componentes frontend atualizados para usar name_i18n?.[lang] || name. 44 RPCs nao tocados (continuam usando name como PT-BR).

**Justificativa:** Nomes de tribos apareciam em PT-BR nas paginas /en/ e /es/. Abordagem de colunas paralelas evita blast radius nos 44 RPCs e 47 functions que referenciam tribes.name.

**Impacto tecnico:** Migration `20260319100068_gc085_tribe_names_i18n.sql` adiciona name_i18n e quadrant_name_i18n jsonb. Helper `getLocalizedName()` em `src/i18n/utils.ts`. 16 componentes atualizados: selects incluem name_i18n, rendering usa fallback pattern. Zero alteracoes em RPCs.

---

### GC-086 — PostHog Custom Events + Sentry Global Handler
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisao:** Ativacao completa de observabilidade: Sentry global error handlers (window.onerror + unhandledrejection) adicionados ao BaseLayout. PostHog custom event taxonomy (10 eventos) instrumentada: board_card_created, board_card_moved, gamification_viewed, leaderboard_filtered, publication_submitted, credly_verified, workspace_visited, report_exported, campaign_sent, member_searched. Helper trackEvent() com silent-fail pattern.

**Justificativa:** Sentry so capturava erros de React islands via ErrorBoundary, ignorando erros globais de scripts inline e async. PostHog tinha zero custom events — so autocapture, insuficiente para medir feature adoption.

**Impacto tecnico:** `src/lib/analytics.ts` (novo helper). Global error handlers em BaseLayout.astro. 10 eventos instrumentados em 8 arquivos (TribeKanbanIsland, gamification, profile, workspace, cycle-report, chapter-report, campaigns, publications, MemberListIsland). Todos com try/catch — analytics nunca quebra o app. Nenhum PII nos eventos.

---

### GC-087 — W139 Active Members View + Publication Tracking Schema
**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Criar view `active_members` e tabela `publication_submissions` para tracking de publicações por tribo.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-088 — RPC Column Fixes + CI Hardening
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Corrigir colunas em get_member_detail (full_name→name, credly_username→credly_url), atualizar .nvmrc para Node 24, habilitar CodeQL upload, adicionar release-tag gate no CI.
**Impacto tecnico:** 4 ficheiros alterados. CI agora falha se tag de release não corresponder ao CHANGELOG.

---

### GC-089 — Security Hardening Sprint (search_path + SSR + CSP)
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** (1) Adicionar `SET search_path = 'public', 'pg_temp'` a todas as SECURITY DEFINER functions. (2) Implementar security headers via middleware SSR (CSP, HSTS, X-Frame-Options). (3) Dark mode audit (45 bugs visuais corrigidos). (4) Extrair 35 hardcoded PT-BR strings para i18n.
**Impacto tecnico:** 3 commits: security headers, dark mode fixes, i18n extraction. CODEOWNERS adicionado. Board SLA defaults configurados.

---

### GC-090 — Dark Mode Implementation Completion
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Completar implementação de dark mode em toda a plataforma. 45 bugs visuais identificados e corrigidos durante audit.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-091 — P0 Field Triage (Jefferson, Fabricio, Vitor)
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Corrigir 8 colunas inexistentes em RPCs detectadas em campo por Jefferson (T8), Fabricio (deputy), e Vitor (GP). Resolver ambiguidade em create_event (2 overloads), admin RPCs com schema mismatch, e broken links no admin sidebar.
**Impacto tecnico:** Systematic column reference cleanup em todos os admin RPCs. Legacy admin_list_members 6-param overload removida.

---

### GC-092 — Trilingual Admin Islands
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Completar cobertura i18n trilingual em todos os React islands do admin: TribeKanban, PublicationsBoard, AdminDashboard, MemberList.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-093 — Systematic RPC Overload Cleanup
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Eliminar todas as ambiguidades de overload em RPCs PostgreSQL. Zero ambiguidade restante após cleanup.
**Impacto tecnico:** exec_cycle_report corrigido (designations ?| → && para text[] overlap, jsonb_array_length → array_length).

---

### GC-094 — Tier 3 Read-Only Access + KPI Filters + Leader Features
**Data:** 2026-03-18 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** (1) Sponsor/chapter_liaison obtêm acesso read-only a painéis executivos. (2) KPIs filtrados por capítulo. (3) Overdue badges em entregáveis. (4) Leader attendance grid.
**Impacto tecnico:** P1-1 a P1-7 implementados. Pilots CRUD (create/edit/delete RPCs + admin UI).

---

### GC-095 — Create Event Form + Governance Schema Alignment
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Alinhar formulário de criação de eventos com schema de governança. Corrigir FK violation (auth.uid() vs members.id) e i18n key attendance.modal.advanced.
**Impacto tecnico:** create_event RPC reescrita para fazer lookup de member_id via auth_id. i18n keys adicionadas em 3 locales.

---

### GC-096 — Homepage Agenda Section Fix
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Corrigir seção de agenda do homepage: (1) Hero card "Próxima Geral" usa dados reais do DB em vez de "quarta 20:00" hardcoded. (2) Horário corrigido para "quinta 19:30". (3) Dead code removido.
**Impacto tecnico:** 5 gaps corrigidos: meeting data, time format, attendance, quick actions, presentation. 3 commits.

---

### GC-097 — Pre-Deploy Validation Gate (QA Gate)
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Estabelecer gate de validação obrigatório antes de todo deploy. Regras codificadas em CLAUDE.md: verificar FKs, auth.uid() vs members.id, column names, i18n em 3 locales, rotas i18n, RPC signatures (DROP+CREATE). Build deve passar com 0 novos erros.
**Justificativa:** 4 incidentes em campo (GC-091, GC-090, GC-095) revelaram que bugs em RPCs e i18n chegavam a produção sem detecção.
**Impacto tecnico:** CLAUDE.md atualizado com regras. docs/GC097_QA_GATE_PRE_DEPLOY.md criado com checklist detalhado.

---

### GC-098 — Selection Pipeline Dashboard Phase A
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Implementar dashboard de pipeline de seleção para ciclo C3.
**Impacto tecnico:** Selection dashboard com RPCs filtradas por RLS. fix(P0): RLS blocks direct queries → use RPC instead.

---

### GC-099 — Cycle Report Charts Fix (i18n + Dark Mode)
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Corrigir gráficos do relatório de ciclo: role labels i18n, cores por capítulo, suporte dark mode.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-100 — Project Skill + Chart Infinite Loop Fix
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Criar `skills/nucleo-ia/SKILL.md` com 10 regras críticas derivadas de bugs anteriores. Corrigir infinite loop em Chart.js (container height + destroy + requestAnimationFrame). Corrigir race condition em pilots page (aguardar sb AND member).
**Impacto tecnico:** Novo ficheiro SKILL.md. Chart.js cycle-report fix. Pilots boot fix.

---

### GC-101 — Pilots Schema Alignment
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Resolver métricas via `get_pilot_metrics` (auto_query values). Date inputs no edit modal (p_started_at/p_completed_at). Team member names resolvidos na detail view.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-102 — Org Chart + Workspace Audit
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Criar `get_org_chart()` RPC com estrutura interativa de 3 dimensões. Criar `get_my_onboarding()` RPC (substitui query direta em tabela deny-all). Workspace audit: zero violações encontradas.
**Impacto tecnico:** 2 novas RPCs SECURITY DEFINER.

---

### GC-103 — Microsoft OAuth (Azure Provider)
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Adicionar "Entrar com Microsoft" como terceiro provider OAuth. Permite stakeholders (sponsors de capítulos) fazerem login com emails institucionais @pmi*.org.
**Justificativa:** Sponsors utilizam contas Microsoft institucionais. Sem este provider, não conseguiriam acessar a plataforma.
**Impacto tecnico:** Azure provider configurado no Supabase Auth (App ID: aea7f167, tenant: common). Scopes: email, profile, openid. Botão adicionado ao auth modal.

---

### GC-104 — Enable Gamification + Attendance Tabs
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Ativar tabs de gamificação e presença no tribe dashboard. switchTab() e validTabs arrays atualizados.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-105 — Tribe Navigation + Access Matrix
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** (105) Workspace hero card "Acesso a todas as tribos" para admins sem tribe_id. (105b) getTribePermissions() helper com 18 permission flags. Cross-tribe viewing banner (azul para membros, roxo para curadores).
**Impacto tecnico:** 2 commits: hero card fix + permissions helper + cross-tribe banner.

---

### GC-106 — Tribe Dashboard Events Timeline
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Adicionar blocos "Próximos Eventos" e "Reuniões Anteriores" na tab Geral do tribe dashboard. Meeting link para hoje/amanhã, attendance fractions, recording links. Botão "Criar Evento" (permission-gated).
**Impacto tecnico:** get_tribe_events_timeline RPC com agenda_text nos upcoming events. i18n em 3 locales.

---

### GC-107 — Attendance Interaction Layer
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Implementar layer de interação para presença: useAttendance hook (fetchGrid, toggleMember, selfCheckIn, batchToggle), AttendanceCell (5 estados visuais), AttendanceGrid (sticky cols, filtros, summary cards), SelfCheckInButton, toggle com toast + undo.
**Impacto tecnico:** 4 componentes React. Optimistic updates com rollback.

---

### GC-108 — Visual Review Sprint (3 Frontend Fixes)
**Data:** 2026-03-19 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** 3 correções de frontend identificadas em revisão visual.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-109 — Admin Attendance Grid Fix
**Data:** 2026-03-20 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Esconder eventos futuros distantes do grid de presença admin. Corrigir visibilidade de colunas.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-110 — Attendance Rate Fix + Minutes/Agenda READ
**Data:** 2026-03-20 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** (1) Célula `scheduled` para eventos futuros (📅, não clicável). (2) Normalização de taxa (0-1 → 0-100%). (3) EventContentBadges + ExpandableContent reutilizáveis. (4) agenda_text no get_tribe_events_timeline.
**Impacto tecnico:** 4 RPCs corrigidas para boundar queries com `AND e.date <= CURRENT_DATE`.

---

### GC-111 — Tribe Grid Visual Parity
**Data:** 2026-03-20 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Implementar week grouping headers, formato dd/MMM, event type letter badges no grid de presença da tribo.
**Impacto tecnico:** CI fix: ui-stabilization test atualizado para get_selection_dashboard.

---

### GC-112 — TipTap Meeting Minutes Editor
**Data:** 2026-03-20 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Criar EventMinutesEditor modal com TipTap rich text (reutiliza RichTextEditor). EventMinutesIsland React island para comunicação Astro ↔ React. Eventos passados mostram "Adicionar/Editar ata" (permission-gated). Renderização com prose class.
**Impacto tecnico:** Novo React island + modal. Reuso do RichTextEditor criado anteriormente.

---

### GC-113 — Future Events Denominator Fix (4 RPCs)
**Data:** 2026-03-20 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Corrigir denominador de eventos futuros em 4 RPCs: exec_cross_tribe_comparison (6 queries), exec_tribe_dashboard (5 queries), get_annual_kpis (LEAST com CURRENT_DATE), get_portfolio_dashboard (status overdue).
**Justificativa:** KPIs inflados por contarem eventos futuros no denominador.
**Impacto tecnico:** Todas as queries de eventos limitadas a CURRENT_DATE.

---

### GC-114 — /attendance Events List Redesign
**Data:** 2026-03-20 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Redesenhar lista de eventos em /attendance: seções colapsáveis por tipo (7 públicas + 3 GP-only), eventos passados primeiro, futuros limitados a 3 com "Ver todos", dropdowns de tipo + tribo + search (gerados dinamicamente). Seções GP-only visíveis apenas para GP/superadmin.
**Impacto tecnico:** 2 commits: layout base + substituição de pill filters por dropdowns + search.

---

### GC-115 — Attendance Production Stabilization
**Data:** 2026-03-20 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Resolver erros de produção na tab Presença: React error #310 (week grouping), week headers removidos para unblock tab.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-116 — Governance Change Management Infrastructure
**Data:** 2026-03-20 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Criar infraestrutura de Change Management para governança: tabela manual_sections (33 seções R2 com hierarquia, títulos bilíngues PT/EN, refs de página), 12 novos campos em change_requests (cr_type, impact_level, manual_section_ids, approval workflow, implementation tracking, version tracking), 5 RPCs SECURITY DEFINER, 13 CRs candidatos (draft), RLS manual_sections read-only.
**Justificativa:** Necessário para o fluxo de aprovação de Change Requests conforme Manual R2 Seção 7.
**Impacto tecnico:** manual_sections table. change_requests com 12 novos campos. 5 novas RPCs. João Santos (PMI-RS) designado como chapter_liaison.

---

### GC-117 — Governance Frontend (Manual Browser + Change Requests)
**Data:** 2026-03-20 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Criar frontend de governança: browser do manual R2, lista de change requests, formulário de submissão, ações de revisão.
**Impacto tecnico:** 3 commits: base + hotfix (sidebar link, submit button, review actions) + i18n key fix.

---

### GC-118 — Governance Batch (Documents Table + 8 CRs + Corrections)
**Data:** 2026-03-21 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Criar tabela governance_documents, adicionar 8 novos CRs, implementar quadrants view, corrigir dados de CRs existentes.
**Impacto tecnico:** governance_documents table populada. CRs corrigidos e expandidos.

---

### GC-119 — Governance Documents Tab + PDF
**Data:** 2026-03-21 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Adicionar tab de documentos na página de governança com link para PDF e display de conteúdo.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-120 — CPMAI Prep Course (Board + Schema + Landing)
**Data:** 2026-03-21 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Implementar curso preparatório CPMAI: design board no BoardEngine, schema DB, RPCs, landing page frontend.
**Impacto tecnico:** 2 commits: schema + RPCs, frontend landing page.

---

### GC-121 — Boards Pages + Nav Link
**Data:** 2026-03-21 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Desbloquear BoardEngine para todos os membros via páginas dedicadas e link na navegação.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-122 — Sentry Issue Resolution Sprint
**Data:** 2026-03-21 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Resolver issues Sentry: workspace TDZ, tribe tab guards, DOM null safety.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-123 — BoardEngine Governance (Baseline Lock + Activity Permissions)
**Data:** 2026-03-23 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Implementar governance no BoardEngine: baseline lock, activity permissions, portfolio flag, activity views.
**Impacto tecnico:** Portfolio filter by is_portfolio_item. CI attendance-ui test atualizado.

---

### GC-124 — Member Offboarding System
**Data:** 2026-03-23 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Implementar sistema de offboarding de membros com transições observer/alumni/inactive. Marcel → alumni, Leandro/Maurício → observer.
**Justificativa:** Necessário para manter dados limpos e distinguir membros ativos de inativos/alumni.
**Impacto tecnico:** member_status_transitions table. RPCs de transição. Configurable tribe limits + unified audit log RPCs.

---

### GC-125 — Partnership Interaction Tracking + Blog Posts
**Data:** 2026-03-23 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Implementar tracking de interações com parcerias (timeline, modal CRUD) e atualizar blog posts.
**Impacto tecnico:** Partnership pipeline modal com interaction tracking, timeline, CRUD, bidirectional move.

---

### GC-126 — Historical Data Preservation Audit (D39-D44)
**Data:** 2026-03-23 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Audit de preservação de dados históricos. T8 attendance issues corrigidos (missing event, leader toggle, meeting schedule, legend). Admin members com todos os statuses, badges, per-member history log.
**Nota:** Detalhes completos a serem adicionados durante curadoria de governança.

---

### GC-127 — Homepage + Profile UX Sprint
**Data:** 2026-03-24 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** (1) Homepage tribe counts corrigidos, inactive tribe banner, observer section. (2) CardDetail participant tabs (curator filter, role badges). (3) Blog likes (heart toggle). (4) Self-service profile editing (name, photo, state, country). (5) Partnership attachments (upload, download, delete).
**Impacto tecnico:** Múltiplos componentes atualizados. File name sanitization para attachments.

---

### GC-128 — Planned vs Actual Dashboard + i18n Structural Remediation
**Data:** 2026-03-24 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** (1) Dashboard Planned vs Actual com timeline. (2) Rotas internacionais para governance. (3) i18n structural remediation: locale persistence, link propagation, content gaps, import pattern for EN stubs.
**Impacto tecnico:** 8+ commits para resolver bugs i18n em cascata. Board column labels fully locale-aware.

---

### GC-129 — Governance Changelog in Admin + Notifications + Onboarding
**Data:** 2026-03-25 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** (1) Governance changelog visível no admin panel. (2) Notification system v1 (bell + dropdown + 5 tipos + preferences). (3) Structured onboarding system (7 steps, trilingual, auto-detect).
**Impacto tecnico:** 3 features implementadas em sequência. Onboarding bugs fixados (DB overload dropped, null guard on step_key).

---

### GC-130 — Chapter Dashboard + Platform Health Monitor
**Data:** 2026-03-25 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** (1) Chapter dashboard com 7 métricas, comparison chart, member table, trilingual, print-ready. (2) Platform health monitor com usage tracking e sustainability tier display.
**Impacto tecnico:** Sidebar reports reorganizados. Report Builder renomeado.

---

### GC-131 — Certificate Issuance System v2/v3
**Data:** 2026-03-25 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Implementar sistema completo de emissão de certificados: multi-cycle, role-based, trilingual PDF, verification code, lifecycle management (revocation, draft mode), GP manage tab, download tracking, portrait layout, description fields, profile signature upload.
**Impacto tecnico:** Múltiplos commits. Board permissions modelo C (researcher creates/moves own cards, leader completes). Bulk certificate issuance RPC + UI.

---

### GC-132 — W-MCP-1 Phase 1: MCP Server for Tribe Leaders
**Data:** 2026-03-26 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Criar MCP server custom para líderes de tribo acessarem dados da plataforma via Claude/ChatGPT. Phase 1: 10 read-only tools (get_my_profile, get_my_tribe_members, get_my_board_status, search_board_cards, get_my_xp_and_ranking, get_upcoming_events, get_my_notifications, get_hub_announcements, get_my_tribe_attendance, get_meeting_notes).
**Justificativa:** Líderes de tribo precisam acessar dados operacionais rapidamente sem navegar pela plataforma. MCP permite integração com assistentes AI.
**Impacto tecnico:** nucleo-mcp Edge Function. OAuth 2.1 authentication. skills/nucleo-ia/SKILL.md com tool definitions.

---

### GC-133 — W-ASTRO6: Astro 5→6 Migration + Workers
**Data:** 2026-03-26 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Migrar plataforma de Astro 5 + Cloudflare Pages para Astro 6 + Cloudflare Workers SSR. @astrojs/cloudflare v13 dropped Pages support, requiring Workers migration.
**Justificativa:** @astrojs/cloudflare v13 (required by Astro 6) only supports Workers mode. CSP headers moved from _headers to middleware. Env access changed to `import { env } from 'cloudflare:workers'`.
**Impacto tecnico:** astro.config.mjs, wrangler.toml, deploy.yml rewritten. Vite 7 upgrade included. Build and deploy verified.

---

### GC-134 — W-MCP-1 Phase 2: Write Tools + Workers Proxy
**Data:** 2026-03-26 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado
**Decisao:** Adicionar 5 write tools ao MCP server (create_board_card, update_card_status, register_attendance, send_notification_to_tribe, create_meeting_notes). Implementar Workers proxy para OAuth discovery (ChatGPT requer /.well-known no domínio raíz). Publicar blog post #8 sobre MCP.
**Justificativa:** Phase 2 completa o ciclo de escrita para líderes de tribo. Proxy necessário porque ChatGPT não suporta MCP endpoints em subpaths.
**Impacto tecnico:** nucleo-mcp Edge Function atualizada. Workers proxy em wrangler.toml. Blog post adicionado ao DB.

---

### GC-135 — Offboarding Daniel Bittencourt → Observer
**Data:** 2026-03-26 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisao:** Daniel Bittencourt transicionado de researcher para observer por desligamento voluntario (novo desafio profissional). Mantém is_active=true para acesso de leitura à plataforma, current_cycle_active=false.

**Justificativa:** Desligamento voluntário comunicado pelo membro. Segue padrão GC-124 (Marcel→alumni, Leandro/Maurício→observer).

**Impacto tecnico:** UPDATE members SET operational_role='observer', current_cycle_active=false. Transição registada em member_status_transitions (reason_category='professional'). Tribo 2 mantém 6 membros ativos — acima do mínimo operacional.

---

### GC-136 — Selection Pipeline V2: Mid-Cycle Recruitment + VEP Import
**Data:** 2026-03-31 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisao:** Implementar pipeline digital completo de selecao com suporte a recrutamento mid-cycle. Ciclo de pesquisa != ciclo de selecao — selecao ocorre em batches assincronos sem disrupcao do time ativo. Batch 2 (Mid-Cycle 2026) aberto para 8 novos candidatos da vaga PMI VEP 64967.

**Justificativa:** 2 membros convertidos para observers (Marcel, Leandro) + 1 tribe leader inativando (Daniel). Necessidade de recrutar substituicoes sem afetar qualidade de entrega pactuada. CBGP em ~28 dias trara mais candidatos.

**Impacto tecnico:**
- Schema: `partner_chapters` (dinamico, 5 capitulos), `selection_membership_snapshots` (fatos temporais), `vep_opportunity_id` em selection_applications
- RPCs: `import_vep_applications` (RFC 4180 parser, dedup por vep_application_id, skip Active/OfferNotExtended/observers/offboarded, snapshot membership dimensional), `admin_update_application`, `finalize_decisions` (bulk approve/reject + member creation + onboarding auto-trigger + diversity snapshot + notifications), `manage_selection_committee`, `get_selection_cycles`, `get_selection_committee`, `get_application_interviews`
- Frontend: /admin/selection com tabs (Pipeline | Import CSV | Comite), evaluation modal com blind review + sliders 0-10, interview scheduling, bulk actions, cycle picker
- Pre-onboarding gamification: 5 steps (450 XP), auto-detection via `check_pre_onboarding_auto_steps`, triggered on approval

---

### GC-137 — VEP Import Logic: Inactive/Observer Member Protection
**Data:** 2026-04-01 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisao:** O import de CSV do PMI VEP deve detectar e pular membros inativos/offboarded/observers, nao apenas membros ativos. Caso Leandro Mota: offboarded em 18/Mar como observer, porem VEP status "Submitted" no CSV — import criava aplicacao duplicada.

**Justificativa:** O VEP mantem o status "Submitted" para candidatos que nao tiveram offer extended ou que reaplied, independente do status interno na plataforma. A protecao deve ser bidirecional: checar tanto o VEP status quanto o status interno do membro.

**Impacto tecnico:** `import_vep_applications` RPC atualizada: check `members` table por email com ANY status (active, inactive, offboarded). Membros inativos/offboarded geram log em `data_anomaly_log` (tipo `selection_import_skipped_inactive`) para auditoria. Leandro removido do Batch 2.

**Change Request:** Manual de Governanca R2 Secao 3 — adicionar regra: "Candidatos que ja possuem registro de membro (ativo, inativo ou observer) na plataforma devem ser revisados manualmente pelo GP antes de reingressar no pipeline de selecao, mesmo que reaplicem via VEP."

---

### GC-138 — Attendance Default Tribe Filter for Non-GP Users
**Data:** 2026-03-31 · **Autor:** Vitor Maia Rodovalho (GP) · **Status:** Implementado

**Decisao:** A pagina /attendance agora faz default do filtro de tribo para a tribo do usuario logado quando o usuario nao e GP-level (manager/deputy_manager/superadmin). Resolvido report do Jefferson Pinto (tribe leader) que via eventos de todas as tribos.

**Justificativa:** Tribe leaders acessam /attendance (rota admin global) em vez da aba Presenca na pagina da tribo. O layout e filtros padrao "Todas as Tribos" nao era adequado para users non-GP.

**Impacto tecnico:** Apos popular o dropdown de tribos, verifica `isGPLevel()` e `MEMBER.tribe_id`. Se non-GP com tribo, pre-seleciona e re-renderiza.

---

*Para adicionar uma nova entrada, use o formato acima. Cada decisao deve ter Data, Autor, Status, Decisao, Justificativa, e Impacto tecnico quando aplicavel. Propostas pendentes requerem aprovacao da Lideranca dos Capitulos conforme Secao 7 do Manual R2.*
