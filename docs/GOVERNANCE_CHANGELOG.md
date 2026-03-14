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
| Cloudflare Pages | SSR hosting + CDN | Ilimitado | ~200 deploys/mês | Baixo |
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

*Para adicionar uma nova entrada, use o formato acima. Cada decisão deve ter Data, Autor, Status, Decisão, Justificativa, e Impacto técnico quando aplicável. Propostas pendentes requerem aprovação da Liderança dos Capítulos conforme Seção 7 do Manual R2.*
