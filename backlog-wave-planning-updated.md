# Nucleo IA & GP — Backlog & Wave Planning
## Status: Marco 2026 (atualizado 2026-03-12)
## Sincronizado com producao: Git, Migracoes SQL (46/46 no repo + schema linkado auditado) e 13 Edge Functions

**Board de sprints**: [GitHub Project — AI PM Hub](https://github.com/users/VitorMRodovalho/projects/1/) · Regras: `docs/project-governance/PROJECT_GOVERNANCE_RUNBOOK.md`

---

## LATEST UPDATE (2026-03-12)

### Entregue em Waves 36-40
- **W36.1 Analytics Read-Only ACL Foundation**: `admin_analytics` deixa de ser admin-only absoluto e passa a aceitar leitura interna para `sponsor`, `chapter_liaison` e `curator`, sem abrir `admin_manage_actions` nem a trilha LGPD sensivel de `/admin/selection`.
- **W37.1 Engagement Funnel + Innovation Hours**: `/admin/analytics` ganha barra global de filtros (`cycle_code`, `tribe_id`, `chapter_code`) e passa a consumir `exec_funnel_v2` e `exec_impact_hours_v2`, entregando o primeiro slice de funil operacional e horas de inovacao.
- **W38-W40 Data Contracts**: nova migration `20260312110000_analytics_v2_internal_readonly_and_metrics.sql` adiciona `can_read_internal_analytics`, helper scope cycle-aware e os RPCs `exec_certification_delta`, `exec_chapter_roi` e `exec_role_transitions`, concluindo a tranche de certificacao delta, ROI por capitulo e jornada de senioridade.

### Wave 36-40 Audit Results (2026-03-12)
- **Build**: clean | **Tests**: 32/32 | **Browser guard**: OK | **Smoke**: routes OK
- **Site hierarchy / ACL**: `/admin/analytics` agora respeita audiencia interna read-only sem herdar permissao de escrita; `/admin/selection` e demais superficies LGPD continuam admin-only
- **Known follow-through**: validar os graficos V2 com dados reais do projeto linkado, especialmente calibracao da janela de atribuicao de filiacao e leitura do onboarding completo por ciclo

### Triagem de Diagnostico Externo (2026-03-11)
Entrada recebida com foco em gaps de estabilizacao, seguranca e operacao. Validacao feita contra estado atual do repo/board.

| Item do diagnostico | Leitura atual | Decisao |
|---|---|---|
| `.env` commitado no repo | **Confirmado** (`.env` esta versionado) | Tratar como **P0** imediato com hygiene de secrets + ajuste de CONTRIBUTING |
| Issue `#19` Admin Tribe Allocation Crash | **Confirmado** (aberta, `priority:critical`) | Prioridade maxima na proxima wave de estabilizacao |
| Issue `#1` Credly recorrente | **Confirmado** (aberta, `priority:critical`) | Priorizar junto com cobertura de regressao dedicada |
| Issue `#11` Rank vs Credly tiers | **Confirmado** (aberta, `priority:critical`) | Prioridade maxima na mesma wave P0 |
| Pipeline de PR parado (7 abertas; 3 Dependabot + 4 draft) | **Confirmado** | Tratar em wave de higiene de entrega/CI |
| "Testes insuficientes (13)" | **Parcial** (baseline atual > 13; ainda sem cobertura plena E2E de fluxos criticos) | Tratar como gap real de cobertura critica, nao de contagem bruta |
| SSR audit / data patch pendentes | **Parcial** (`#12` e `#13` seguem abertas, apesar de historico marcado como done) | Revalidar evidencias e fechar com checklist auditavel |
| Sem milestones | **Confirmado** | Criar milestones operacionais para ciclo/wave |
| Analytics V2 com validacao real pendente | **Confirmado** | Manter follow-through como prioridade de produto/operacao |

### Fila Priorizada — Proximas Waves

#### W41 — Stabilization Gate P0 (operacao primeiro)
| ID | Item | Prioridade | Fonte | Criterio de saida |
|---|---|---|---|---|
| W41.1 | Hygiene de secrets (`.env`) | Critical | Triagem externa | `.env` fora do tracking, `.gitignore` validado, CONTRIBUTING atualizado, varredura historica concluida e registrada |
| W41.2 | Fix crash alocacao de tribos | Critical | Issue `#19` | fluxo admin de alocacao sem crash + teste de regressao + smoke/manual validado |
| W41.3 | Alinhamento rank vs Credly tiers | Critical | Issue `#11` | superficies de rank/gamification coerentes com scoring backend + lock de regressao |
| W41.4 | Credly flow anti-recorrencia | Critical | Issue `#1` | save/verify estavel em teste dedicado (integration ou browser) e sem regressao no perfil |

#### W42 — Delivery Hygiene & CI Guardrails
| ID | Item | Prioridade | Fonte | Criterio de saida |
|---|---|---|---|---|
| W42.1 | Resolver PR backlog Dependabot (`#8,#9,#10`) | High | PR abertas | bumps avaliados/mergeados ou fechados com justificativa |
| W42.2 | Definir gate de entrega (trunk vs PR) | High | Triagem externa + Issue `#14` | politica formalizada em docs/runbook e aplicada no fluxo |
| W42.3 | Hardening CI em push/main | High | Issue `#14` | checks minimos (build, test, smoke) automatizados e executando de forma consistente |

#### W43 — Reliability Audit Closure
| ID | Item | Prioridade | Fonte | Criterio de saida |
|---|---|---|---|---|
| W43.1 | SSR safety audit revalidado | High | Issue `#12` | sweep concluido com evidencias, sem assumptions em SSR critico |
| W43.2 | Data patch follow-through auditavel | High | Issue `#13` | patches aplicados/confirmados com evidencias SQL + nota em release/governanca |
| W43.3 | Cobertura de regressao em fluxos operador | Medium | Triagem externa | checklist de fluxos criticos com testes automatizados minimos |

#### W44 — Scale Readiness & Governance
| ID | Item | Prioridade | Fonte | Criterio de saida |
|---|---|---|---|---|
| W44.1 | Milestones de ciclo e wave | Medium | Triagem externa | milestones criadas e vinculadas ao board |
| W44.2 | Strategy doc de sync dev/prod repos | Medium | Triagem externa | fluxo oficial documentado (quem, como, quando) |
| W44.3 | Analytics V2 validacao em dados reais | Medium | Follow-through W36-40 | validacao registrada com leitura partner-facing sem regressao de ACL |
| W44.4 | Bus-factor mitigation drill | Medium | Triagem externa | runbook de recovery validado por segundo operador |

### Execucao sequencial (2026-03-11) — status apos 6 sprints

| Sprint | Itens alvo | Status | Evidencia principal |
|---|---|---|---|
| Sprint 1 | W41.1 + W41.2 | **Done** | `.env` fora do tracking + hardening admin pending (`replace` safe) |
| Sprint 2 | W41.3 + W41.4 | **Done** | ranking lifetime alinhado com agregado real + retry 401 em verify Credly |
| Sprint 3 | W42.1 + W42.2 | **Done** | backlog de PRs encerrado + policy trunk-based formalizada |
| Sprint 4 | W42.3 + W43.3 | **Done** | CI com browser guard + novos regression locks operador |
| Sprint 5 | W43.1 + W43.2 | **Done** | SSR hardening + migration `20260314110000_member_data_sanity_patch.sql` aplicada |
| Sprint 6 | W44.1 + W44.2 + W44.4 | **Done** | milestones GitHub + repo sync strategy + drill pack no DR |

### Carry-over explicito

- **W44.3 Analytics V2 validacao em dados reais**: **Em aberto**.  
  Requer execucao partner-facing com usuario autorizado e evidencia de leitura real no ambiente vinculado.

### Entregue em Wave 35
- **W35.1 Dynamic Tribe Catalog Foundation**: `tribe/[id]` e os wrappers multilang deixam de bloquear ids acima de `8`, e o header da tribo passa a usar metadata runtime do banco com fallback estático apenas para o catálogo legado.
- **W35.2 Explicit Tribe Status + Admin Catalog Controls**: nova migration adiciona `tribes.is_active`, RPCs seguras para listar/criar/ativar-inativar tribos e o painel admin ganha catálogo runtime, criação de novas tribos e toggles de status.
- **W35.3 Runtime Name Fallbacks Across Surfaces**: `Nav`, `Workspace`, `Artifacts`, `Gamification` e `Hero` passam a consumir o catálogo runtime de tribos ou cair em fallback seguro, em vez de depender exclusivamente do conjunto fixo `01..08`.

### Wave 35 Audit Results (2026-03-12)
- **Build**: clean | **Tests**: 31/31 | **Browser guard**: OK | **Smoke**: não executado nesta tranche
- **Site hierarchy / ACL**: membros ativos continuam vendo apenas tribos ativas; Superadmin passa a manter leitura de inativas; gestão de projeto ganha abertura do catálogo sem expor histórico inativo a perfis comuns
- **Known follow-through**: a home pública (`TribesSection`) e o conteúdo editorial/i18n profundo das novas tribos ainda não foram convertidos integralmente para runtime

### Entregue em Wave 34
- **W34.1 Explore Tribes Active Access**: `Nav.astro` deixa de depender de `tribes.is_active` e passa a liberar `Explorar Tribos` para membros ativos+ usando o diretório atual de tribos + membros ativos do ciclo.
- **W34.2 Tribe Exploration Guardrails**: `tribe/[id].astro` agora falha fechada para visitantes/inativos, libera exploração view-only para membros ativos e mantém ações locais restritas à liderança/gestão.
- **W34.3 Lifecycle Access Expansion**: as operações de realocação, troca de liderança e encerramento de tribo foram reabertas para GP / Deputy Manager / `co_gp` no painel admin e nas RPCs de lifecycle já existentes.

### Wave 34 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 30/30 | **Browser guard**: OK | **Smoke**: routes OK
- **Site hierarchy / ACL**: `Explorar Tribos` agora respeita o requisito de exploração para membros ativos+; `/tribe/[id]` deixa de ficar implicitamente público; lifecycle operacional sobe de superadmin-only para a camada de gestão do projeto
- **Known follow-through**: abertura dinâmica de novas tribos ainda fica pendente, porque a rota `tribe/[id]` e parte do catálogo/i18n continuam ancorados no conjunto atual `1..8`

### Entregue em Wave 33
- **W33.1 Attendance Edit Assistant**: o handoff contextual em `attendance.astro` agora ajuda o operador dentro do modal de edição, focando o campo certo e exibindo orientação curta para meeting link ou replay.
- **W33.2 Comms Playbook Assist**: `admin/comms.astro` agora mostra um playbook rápido com assunto/mensagem-base copiáveis quando o contexto vier de um webinar.
- **W33.3 Regression Lock + Audit**: testes e docs foram atualizados para manter a nova camada de auxílio de autoria sem criar editor ou workflow paralelo.

### Entregue em Wave 32
- **W32.1 Attendance Contextual Landing**: `attendance.astro` agora aceita handoff por URL para webinars, com filtro, foco visual no evento e abertura opcional do modal de edição.
- **W32.2 Admin Comms Contextual Landing**: `admin/comms.astro` agora aceita contexto de webinar por URL, mostra banner orientado ao estágio de comunicação e filtra o histórico de broadcasts.
- **W32.3 Browser + Regression Lock**: `tests/ui-stabilization.test.mjs` e `tests/browser-guards.test.mjs` agora travam os handoffs contextuais para `Attendance` e `Admin Comms`.

### Wave 33 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 29/29 | **Browser guard**: OK | **Smoke**: routes OK
- **In-module aids**: `Attendance` e `Admin Comms` agora ajudam o operador a concluir a tarefa do webinar dentro do modulo de destino, sem criar fluxo paralelo
- **Site hierarchy / ACL**: nenhuma rota, tier ou exposicao LGPD mudou; a tranche adiciona apenas assistencia contextual em superficies ja existentes

### Entregue em Wave 31
- **W31.1 Contextual Webinar Handoffs**: `/admin/webinars` agora envia o operador para `Presentations` e `Workspace` com filtros de contexto do webinar, em vez de abrir destinos genéricos.
- **W31.2 Query-Driven Reuse Surfaces**: `presentations.astro` e `workspace.astro` passam a aceitar `q` e filtros via URL para suportar follow-through mais direto sem schema novo.
- **W31.3 Regression Lock**: `tests/ui-stabilization.test.mjs` trava os deep links contextuais entre `admin/webinars`, `presentations` e `workspace`.

### Wave 32 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 29/29 | **Browser guard**: OK | **Smoke**: routes OK
- **Focused reuse surfaces**: `/admin/webinars` agora tambem aterrissa `Attendance` e `Admin Comms` em estados contextualizados para o webinar selecionado
- **Site hierarchy / ACL**: as rotas continuam com os mesmos tiers e visibilidade; a tranche adiciona apenas estado inicial por URL e filtros locais, sem schema ou RLS novos

### Entregue em Wave 25
- **W25.1 Browser Coverage Expansion**: `tests/browser-guards.test.mjs` passa a validar não só o `HeroSection`, mas também os badges/notices runtime de `TribesSection` na home pública.
- **W25.2 Stable Browser Hooks**: `TribesSection.astro` recebe ids estáveis para o estado de seleção, badge de deadline e notice, permitindo regressão browser menos frágil.
- **W25.3 Runtime Guardrail**: o teste browser agora trava que o deadline badge não regride para o fallback fixo antigo e que o visitante continua vendo o prompt de login na área de tribos.

### Entregue em Wave 24
- **W24.1 Tribes Deadline Formatting**: `TribesSection.astro` passa a formatar o prazo de seleção com `Intl.DateTimeFormat` e timezone `America/Sao_Paulo`, em vez de manter cálculo manual de mês/hora.
- **W24.2 Stale Deadline Fallback Cleanup**: as strings `tribes.deadline` em PT/EN/ES deixam de guardar a data fixa antiga e passam a usar wording genérico do cronograma atual.
- **W24.3 Regression Lock**: `tests/ui-stabilization.test.mjs` agora trava a remoção do UTC math manual e dos fallbacks antigos de `tribes.deadline`.

### Entregue em Wave 23
- **W23.1 Hero Kickoff Runtime Truth**: `HeroSection.astro` passa a derivar o estado pós-kickoff de `home_schedule.kickoffAt`, em vez de depender da data do último registro em `events`.
- **W23.2 Optional Event Enrichment**: a leitura de `events` no hero permanece apenas como enriquecimento para replay/link de reunião, sem ser mais pré-requisito para a home pública sair do estado de kickoff agendado.
- **W23.3 Regression Lock**: `tests/ui-stabilization.test.mjs` agora trava a injeção de `kickoffAt`/`platformLabel` no payload do hero e a remoção do cálculo legado baseado em `ev.date`.

### Entregue em Wave 22
- **W22.1 Public Cycle Copy Cleanup**: labels visíveis da home (`hero.badge`, `cpmai.noCerts`, subtítulos de `TeamSection`) deixam de mencionar `Ciclo 3` e passam a usar wording genérico do ciclo atual.
- **W22.2 Regression Lock**: `tests/ui-stabilization.test.mjs` agora trava explicitamente a ausência das variantes antigas de `Cycle/Ciclo 3` nos textos públicos tocados nesta tranche.

### Entregue em Wave 21
- **W21.1 Resources Deadline Wiring**: `ResourcesSection.astro` passa a receber `deadlineIso` nas três home pages, mantendo o card fallback da playlist coerente com o mesmo cronograma runtime já usado por Hero, Agenda e Tribes.
- **W21.2 Localized Resource Fallbacks**: os cards fallback de recursos deixam de carregar textos fixos em português dentro do componente e passam a usar i18n nas locales PT/EN/ES.
- **W21.3 Regression Lock**: `tests/ui-stabilization.test.mjs` agora trava o repasse de `deadlineIso` para `ResourcesSection` e a remoção do texto legado `Sáb 12h`.

### Entregue em Wave 20
- **W20.1 Home Fallback Copy Cleanup**: os fallbacks localizados da home (`hero.date`, `hero.meetingSchedule`, `hero.recurringMeeting`, `agenda.item3.desc`) deixam de embutir datas/horarios de Marco e passam a apontar genericamente para o cronograma atual do ciclo.
- **W20.2 Hero Inline Fallback Hygiene**: `HeroSection.astro` remove os ultimos defaults inline com horario fixo de reuniao, reduzindo a chance de a home publica exibir informacao antiga quando `home_schedule` vier incompleto.
- **W20.3 Regression Lock**: `tests/ui-stabilization.test.mjs` agora trava explicitamente a ausencia das strings antigas de kickoff/reuniao nas locales e no fallback inline do hero.

### Entregue em Wave 19
- **W19.1 Agenda Runtime Deadline**: `AgendaSection.astro` passa a receber o deadline real da wave e remove a data fixa do item "Dinâmica das Tribos".
- **W19.2 Home Page Wiring**: `index` PT/EN/ES reaproveitam o mesmo `deadlineIso` runtime também na agenda, mantendo Hero e Agenda sincronizados.
- **W19.3 Regression Lock**: os testes textuais agora travam explicitamente que `AgendaSection` usa o deadline runtime nas três home pages.

### Entregue em Wave 18
- **W18.1 Runtime Home Schedule Reads**: `index` PT/EN/ES passam a resolver o objeto completo de `home_schedule`, não apenas o deadline.
- **W18.2 Hero Runtime Messaging**: `HeroSection.astro` usa `kickoff_at`, `platform_label` e metadados recorrentes do `home_schedule` para reduzir copy estático no badge inicial e nas mensagens de reunião.
- **W18.3 Post-Deadline Hero UX**: o status de ciclo na home aparece mesmo antes da inicialização do client Supabase, evitando a área vazia no estado pós-deadline.
- **W18.4 Browser Coverage Expansion**: a suíte browser agora valida tanto o guard anônimo de `/admin/selection` quanto o comportamento runtime principal da home pública.

### Entregue em Wave 17
- **W17.1 Live Supabase Audit Restored**: `supabase migration list` voltou a responder sem `--debug`; confirmado `44/44 local == remote` no projeto linkado.
- **W17.2 Home Schedule Hardening**: `schedule.ts` deixa de inventar o sentinel `2030`; home passa a tratar o prazo de seleção como estado real (`open` / `closed` / `pending`) vindo de `home_schedule`.
- **W17.3 Tribes UX Guardrail**: `TribesSection.astro` deixa de manter seleção artificialmente aberta sem cronograma; badges/notice refletem configuração real e links tocados saem de `onclick` inline.
- **W17.4 Browser Guard Coverage Base**: criada a primeira verificação browser real com Playwright para garantir que `/admin/selection` nega acesso a visitantes anônimos.

### Entregue em Wave 16
- **W16.1 Supabase Audit & Drift Fix**: contagem documental de migrations corrigida para `44`; `database.gen.ts` regenerado a partir do projeto linkado; nenhum schema novo aberto nesta tranche.
- **W16.2 Profile Stabilization**: `profile.astro` deixa de depender de rebinding pós-`renderProfile(...)` para normalização do campo Credly, usando listeners delegados.
- **W16.3 Selection Cycle Hardening**: `/admin/selection` troca tabs/título hardcoded por leitura runtime de ciclos via `loadCycles()`/`getCurrentCycle()`, preservando ACL `admin_selection` + `lgpdSensitive`.
- **W16.4 Shared Dialog Hygiene**: `ConfirmDialog.astro` remove o padrão mutável `btn.onclick` e passa a usar listener estável + callback armazenado.

### Entregue em Wave 15
- **W15.1 Cycle-Config Hardening**: `profile.astro` e `tribe/[id].astro` deixam de depender de `cycle_3` fixo e passam a resolver o ciclo corrente via `list_cycles`.
- **W15.2 Admin Cycle Hygiene**: `admin/index.astro` usa `loadCycles()`/maps locais em vez de `CYCLE_META`/`CYCLE_ORDER`; `src/lib/admin/constants.ts` deixa de manter mapas de ciclo legados.
- **W15.3 Docs & Compatibility Cleanup**: fallback genérico do dashboard de perfil, `cycles.ts` sem warning de import, e `PROJECT_ON_TRACK` realinhado com o estado atual.

### Entregue em Wave 14
- **W14.1 Doc Divergence Cleanup**: README, MIGRATION e CONTRIBUTING alinhados com produção atual (Chart.js nativo, smoke routes, 5-phase, repo/path corretos).
- **W14.2 Admin Hygiene**: Removidas referências antigas a PostHog/Looker do admin atual; primeira tranche de event delegation aplicada em `admin/index.astro` e shared UI.
- **W14.3 Deferred Structuring**: S23, S24, S-KNW7 e Webinars reclassificados por lane, dependências e critérios de saída do deferred.

### Wave 31 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 28/28 | **Browser guard**: OK | **Smoke**: routes OK
- **Contextual handoffs**: `/admin/webinars` agora abre `Presentations` e `Workspace` em visoes ja filtradas para o webinar selecionado
- **Site hierarchy / ACL**: rotas continuam com os mesmos tiers e visibilidade; a tranche adiciona apenas interoperabilidade via filtros de URL, sem schema ou RLS novos

### Wave 25 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 26/26 | **Browser guard**: OK | **Routes**: smoke OK

### Wave 24 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 26/26 | **Browser guard**: OK | **Routes**: smoke OK

### Wave 23 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 25/25 | **Browser guard**: OK | **Routes**: smoke OK

### Wave 22 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 24/24 | **Browser guard**: OK | **Routes**: smoke OK

### Wave 21 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 23/23 | **Browser guard**: OK | **Routes**: smoke OK

### Wave 20 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 22/22 | **Browser guard**: OK | **Routes**: smoke OK

### Entregue em Wave 13
- **W13.1 Doc Hygiene**: AGENTS.md Edge functions atualizado (sync-credly-all, sync-attendance-points presentes). PROJECT_ON_TRACK seção 3 e F1 atualizados; última verificação 2026-03-11.

### Entregue em Wave 12
- **W12.1**: AGENTS.md "Interação com agentes", SPRINT_IMPLEMENTATION_PRACTICES ref, AGENT_BOARD_SYNC repo (ai-pm-research-hub). Rotina 5-phase documentada para iniciar e encerrar sprint.
- **W12.2**: Workflow `release-tag.yml` — workflow_dispatch para criar tag vX.Y.Z (Semantic Versioning).
- **W12.3**: Script `screenshots-multilang.mjs` (S-SC1) — Playwright captura /, /en, /es (index, workspace, artifacts, gamification).

### Entregue em Waves 9-11
- **Wave 9**: `/admin/selection` (processo seletivo, LGPD), dashboards cross-source em analytics, RPCs `list_volunteer_applications` e `platform_activity_summary`. Reforma AGENTS.md, SPRINT_IMPLEMENTATION_PRACTICES (5-phase), DEPLOY_CHECKLIST.
- **Wave 10**: Nav `/admin/analytics`, route key `admin_curatorship`, PERMISSIONS_MATRIX secções 3.13-3.15. Announcement scheduling (starts_at/ends_at pickers, validacao, badge Agendado). Markdown preview toggle para corpo de avisos.

### Entregue em sessoes anteriores (Four Options Sprint)
- **S-KNW4 File Detective & Knowledge Sanitization**: Script `knowledge_file_detective.ts` para detectar apresentacoes orfas em `data/staging-knowledge/`. Artifacts page separada em "Artefatos Produzidos" vs "Materiais de Referencia". Botoes inline de edicao de tags para lideres/curadores via `curate_item` RPC.
- **S-KNW5 Kanban Curatorship Board**: `/admin/curatorship` refatorado de lista plana para board Kanban com 4 colunas (Pendente, Em Revisao, Aprovado, Descartado). Drag-and-drop com HTML5 API. Nova migration `list_curation_board` RPC.
- **S-OB1 Onboarding Intelligence**: Script `onboarding_whatsapp_analysis.ts` para NLP do chat WhatsApp de integracao (keyword extraction, FAQ detection, timeline analysis). Onboarding page redesenhada com progress tracker, accordion steps, fases (Boas-vindas/Configuracao/Integracao/Producao), e dicas data-driven.
- **S-AN1 Analytics 2.0**: Chart.js instalado. PostHog/Looker iframes substituidos por graficos nativos (Funnel bar, Radar spider, Impact doughnut, KPI cards, Cert Timeline line). Comms dashboard com bar chart de metricas por canal.

### Entregue anteriormente (CPO Production Audit)
- **S-HF10 Credly URL Persistence**: `saveSelf()` agora preserva `credly_url` existente quando campo nao e modificado; `verifyCredly()` persiste URL via `member_self_update` antes da verificacao. Fluxo completo: inserir URL → verificar → salvar funciona sem perda.
- **S-HF11 Gamification Toggle XP Vitalicio**: `setLeaderboardMode()` agora chama `ensureLifetimePointsLoaded()` antes de re-render; fix de conflito `bg-transparent`/`bg-navy` nos botoes de toggle (leaderboard + tribe ranking).
- **S-UX2 Explorar Tribos Universal**: Dropdown de tribos (desktop/drawer/mobile) carrega TODAS as tribos; tribos inativas aparecem com opacidade reduzida + icone de cadeado + tooltip "Tribo Fechada".
- **S-IA1 Help Publico**: `/admin/help` migrado para `/help` (publico para membros logados); topicos LGPD/Privacy ocultos para nao-admins; `/admin/help` redireciona 301 para `/help`.
- **S-IA2 Onboarding no Drawer**: Removido da navbar principal; movido para o Profile Drawer (grupo 'profile', `requiresAuth: true`, `minTier: 'member'`).
- **S-IA3 Webinars Placeholder**: `admin/webinars.astro` preenchido com UI "Em Breve" com 3 cards de features planejadas + access check admin.

### Entregue em sessoes anteriores (2026-03-09 a 2026-03-10)
- **UX Housekeeping**: Upload best practices banners (admin + artifacts), file validation 15MB, formatos expandidos (.pdf/.pptx/.png/.jpg)
- **ETL Pipeline**: Politica de governanca de dados (`DATA_INGESTION_POLICY.md`), pipeline 3 fases (prepare/curate/upload), quarentena AI Safety para .md, isolamento de .docx, flagging de copyright para PDFs
- **Documentacao**: RELEASE_LOG, PERMISSIONS_MATRIX e este backlog sincronizados com estado exato de producao

### Entregue em sessoes anteriores (2026-03-09 a 2026-03-10)
- **Sprint 4**: Seletor Global de Tribos (dropdown interativo Nav.astro) + Sistema de Notificacao de Alocacao (`send-allocation-notify` + Admin UI)
- **Sprint 2+3**: Filtros de artefatos por taxonomy_tags + Validacao de deliverables/My Week existentes
- **Sprint 1**: Leaderboard cycle-aware (VIEW + RPC), trail per-course status, XP por ciclo no perfil
- **Wave 4 Completa**: Governanca operacional, lifecycle management (4 RPCs), onboarding global, comms integration, webinars, curadoria
- **Wave 5 Fase 1**: Interface de curadoria `/admin/curatorship`, auto-tag, dynamic email signatures
- **P0 Bugfixes**: Tribe counter 0/6, curatorship logout, comms infinite loading
- **S-PRES1**: Presentation Module com ACL democratico
- **P2**: LGPD visual masks, native analytics, Superadmin navigation
- **P3**: Trello/Calendar import, PDF upload, webinar pipeline

---

## ROADMAP REORGANIZATION (2026-03-08)

Para eliminar execucao fora de sequencia e reduzir regressoes, o backlog opera com pacote pai -> atividades filhas.

### Pacotes Pai (EPICs)

1. `P0 Foundation Reliability Gate` (issue `#47`) — Concluido
2. `P1 Comms Operating System` (issue `#48`) — Concluido
3. `P2 Knowledge Hub Sequential Delivery` (issue `#49`) — Concluido (Wave 5 Fase 1)
4. `P3 Scale, Data Platform & FinOps` (issue `#50`) — Em progresso (Wave 6)

### Regra de execucao

- Nenhuma tarefa sai de `Backlog/Ready` para `In progress` sem:
  - vinculo com EPIC pai;
  - dependencias front/back/SQL/integrador explicitas;
  - criterios de entrada e saida definidos.
- Feature de frontend sem backend/API/SQL pronto nao avanca para desenvolvimento.
- Quando houver risco de regressao em producao, prioridade volta para `P0 Foundation`.

---

## COMPLETED / STABILIZED

| Sprint / Linha | Deliverable | Status |
|----------------|-------------|--------|
| S2 | Index migration: 10 sections + core data files | Production |
| S3 | Attendance page: KPIs, events, roster, modals | Production |
| S4 | Artifact tracking + enriched profile | Production |
| S5 | i18n infrastructure + PT EN ES public index | Production |
| S6 | Gamification base: leaderboard, points, certificates | Production |
| S7 | Admin dashboard: tribe management + member CRUD | Production |
| RM | LinkedIn OIDC login button | Production |
| RM | Member photo storage setup | Production |
| RM | Cloudflare Pages SPA fallback redirects | Production |
| RM | Legacy route aliases `/teams`, `/rank`, `/ranks` | Production |
| RM | SSR guard in `TribesSection.astro` for missing `deliverables` | Production |
| RM | Credly Edge Function with tier based badge scoring | Backend Production |
| RM | Initial release log discipline adopted | Documentation Governance |

---

## HOTFIX / STABILIZATION ITEMS (Todos Resolvidos)

| ID | Feature | Status | Resolucao |
|----|---------|--------|-----------|
| S-HF1 | Credly Mobile Paste Fix | Done | Credly URL normalizes/validates paste input. |
| S-HF2 | Rank UI Alignment with Credly Tiers | Done | Gamification UI surfaces Credly tier totals. |
| S-HF3 | Post Deploy Smoke Test | Done | Repeatable route smoke script. |
| S-HF4 | SSR Safety Audit | Done | SSR-safe guards/fallbacks. |
| S-HF5 | Data Patch Follow Through | Done | SQL pack executed. |
| S-HF6 | Source of Truth Drift (Trail vs Gamification) | Done | Reconciliation in `sync-credly-all`. |
| S-HF7 | Gamification Secondary Tabs Stuck on Loading | Done | Timeout + error fallback. |
| S-HF8 | Credly Legacy Sanitization & Dedup | Done | Tier 2 expansion + dedup hardening. |
| S-HF9 | Edge Functions no Repo | Done | Todas as 13 Edge Functions versionadas em `supabase/functions/`. |
| S-HF10 | Credly URL Persistence | Done | `saveSelf()` preserva URL existente; `verifyCredly()` persiste via RPC antes da verificacao. |
| S-HF11 | Gamification Toggle XP Vitalicio | Done | `ensureLifetimePointsLoaded()` pre-render + fix `bg-transparent` toggle conflict. |
| S-UX2 | Explorar Tribos Universal | Done | Dropdown carrega todas as tribos; inativas com opacidade + cadeado + tooltip. |
| S-IA1 | Help Publico (`/help`) | Done | Migrado de `/admin/help`; LGPD oculto para nao-admins; redirect 301. |
| S-IA2 | Onboarding no Drawer | Done | Removido da navbar principal; movido para Profile Drawer. |
| S-IA3 | Webinars Placeholder | Done | UI "Em Breve" com access check admin. |
| S-KNW4 | File Detective & Knowledge Sanitization | Done | Script + Produced/Reference sub-tabs + leader inline tag edit. |
| S-KNW5 | Kanban Curatorship Board | Done | 4-column Kanban com drag-and-drop + `list_curation_board` RPC. |
| S-OB1 | Onboarding Intelligence (WhatsApp NLP) | Done | Chat parser + redesigned onboarding com progress tracker. |
| S-AN1 | Analytics 2.0 (Chart.js) | Done | PostHog/Looker → native charts (funnel, radar, impact, cert timeline, comms). |

---

## WAVE 3: Profile, Gamification & UX Excellence — CONCLUIDA

| ID | Feature | Status |
|----|---------|--------|
| S-RM2 | Completeness Bar & Timeline | Done |
| S-RM3 | Gamification v2 (Cycle vs Lifetime) | Done |
| S-UX1 | Trilha Progress Clarity for Researchers | Done |
| S-PA1 | Product Analytics (iframe + consent) | Done |
| S8b | i18n Internal Pages | Done |
| S11 | UI Polish & Empty States | Done |
| S-AUD1 | TribesSection i18n | Done |
| S-CFG1 | MAX_SLOTS single source | Done |
| Sprint 1 | Cycle-aware leaderboard VIEW + get_member_cycle_xp RPC + per-course trail | Done |

---

## WAVE 4: Admin Tiers, Integrations & Comms — CONCLUIDA

| ID | Feature | Status |
|----|---------|--------|
| S-RM4 | Admin Tiers (ACL) — centralized + in-page guards | Done |
| S-REP1 | Exportacao VRMS (PMI) — CSV + i18n | Done |
| S-ADM2 | Leadership Training Progress Snapshot — filters + CSV export | Done |
| S-ADM3 | Member Lifecycle Management — 4 SECURITY DEFINER RPCs | Done |
| S10 | Credly Auto Sync — GitHub Action weekly | Done |
| S-AN1 | Announcements System — banners + CRUD + XSS | Done (rich editor pendente) |
| S-DR1 | Disaster Recovery Doc | Done |
| S-COM1 | Communications Team Integration — designations backfill | Done |
| S-COM6 | Dashboard Central de Midia — `/admin/comms` | Done |
| S-COM7 | Global Onboarding Broadcast Engine | Done |
| S-PA2 | Admin Executive Visual Dashboards | Done |
| W4.4 | Navigation Config integration (tier-based dynamic menus) | Done |
| W4.10 | Central de Ajuda do Lider (`/admin/help`) | Done |
| Sprint 4 | Global Tribe Selector (dropdown Nav.astro) | Done |
| Sprint 4 | Allocation Notification (`send-allocation-notify` + Admin UI) | Done |

---

## WAVE 5 FASE 1: Knowledge Hub — CONCLUIDA

| ID | Feature | Status |
|----|---------|--------|
| S-KNW1 | Repositorio Central de Recursos (`hub_resources`) | Done |
| S-KNW2 | Workspace publico (`/workspace`) | Done |
| S-KNW3 | Artifact Tag Filtering (taxonomy_tags) | Done |
| S-PRES1 | Presentation Module (ACL democratico, /presentations) | Done |
| Curadoria | Interface `/admin/curatorship` (approve/edit/discard) | Done |
| Auto-tag | Sugestao automatica de tags por keywords | Done |
| ETL | Pipeline 3 fases (prepare/curate/upload) + DATA_INGESTION_POLICY.md | Done |
| UX | Upload best practices banners + file validation 15MB | Done |

---

## WAVE 7: Data Ingestion Platform — CONCLUIDA
**Foco:** Ingerir todas as fontes de dados descentralizadas (Trello, Calendar, CSV Voluntarios, Miro) na plataforma como single source of truth.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W7.1 | Trello 5-Board Historical Import | High | Done | 5 boards → 119 cards imported (4 closed skipped). Boards: Comunicacao C3 (17), Articles (28), Artigos PM.com (3), Tribo 3 (34), Midias Sociais (37). |
| W7.2 | Google Calendar ICS Import | High | Done | 593 ICS events parsed → 87 Nucleo/PMI relevant → 67 imported (20 deduplicados). |
| W7.3 | Volunteer CSV Data Pipeline | High | Done | 6 CSVs → 143 aplicacoes (Ciclo 1: 8, Ciclo 2: 16, Ciclo 3: 119). 92 matched com membros existentes (64%). |
| W7.4 | Miro Board Links Import | Medium | Done | 445 linhas → 51 URLs unicas importadas para `hub_resources` (32 artigos ciclo 2, 6 noticias, 1 video, 1 curso, etc.). |
| W7.5 | Project Boards Schema | High | Done | Migration: `project_boards` + `board_items` tables com RLS, RPCs (`list_board_items`, `move_board_item`, `list_project_boards`). |
| W7.6 | Volunteer Applications Schema | High | Done | Migration: `volunteer_applications` table com RLS admin-only + `volunteer_funnel_summary` RPC. |

### Wave 7 Audit Results (2026-03-11)
- **Data totals**: 119 board items, 67 calendar events, 143 volunteer applications, 51 Miro links
- **RPC health**: `list_project_boards` (5 boards), `list_board_items` (OK), `volunteer_funnel_summary` (3 cycles)
- **Build**: clean | **Tests**: 13/13 | **Routes**: 16/16 → 200 | **Migrations**: 39/39 applied
- **Member matching**: 134 entries loaded, 92/143 volunteer apps matched (64%), Trello member match by name
- **Top certifications**: PMP (59), DASM (9), PMI-RMP (5), PMI-CPMAI (5)
- **Geographic spread**: MG (27), CE (20), GO (20), DF (16), 8 US-based, 2 Portugal

---

## WAVE 8: Reusable Kanban & UX Architecture — CONCLUIDA
**Foco:** Boards por tribo, analytics de processo seletivo, progressive disclosure tier-aware, legacy cleanup.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W8.1 | Universal Kanban Component | Low | Deferred | Refator para componente reutilizavel deferido ate segundo consumidor existir (tribo board reutiliza padrao visual). |
| W8.2 | Tribe Project Boards | High | Done | Aba "Quadro de Projeto" em `/tribe/[id]` com Kanban 5 colunas (backlog/todo/in_progress/review/done), drag-and-drop, create board. RPCs: `list_project_boards`, `list_board_items`, `move_board_item`. |
| W8.3 | Selection Process Analytics | High | Done | 4 graficos Chart.js na `/admin/analytics`: funil por ciclo, certs horizontais, geo treemap, snapshot diff Ciclo 3. Chama `volunteer_funnel_summary` RPC. |
| W8.4 | Tier-Aware Progressive Disclosure | Medium | Done | `getItemAccessibility()` retorna `{visible, enabled, requiredTier}`. Nav items desabilitados com opacity + lock icon + tooltip "Requer [tier]". LGPD-sensitive items permanecem ocultos. |
| W8.5 | Legacy Role Column Hard Drop | High | Done | Migration `20260312020000`: drop `role`, `roles` columns e `sync_legacy_role_columns` trigger. Frontend 100% em `operational_role` + `designations`. |

### Wave 8 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 13/13 | **Migrations**: 40/40
- **New features**: Tribe project boards (Kanban), Selection analytics (4 charts), Progressive disclosure (lock icons)
- **Tech debt resolved**: Legacy `role`/`roles` columns dropped, PostHog/Looker references superseded
- **Architecture**: `NavItem.lgpdSensitive` flag added, `ItemAccessibility` interface exported

---

## WAVE 9: Intelligence & Cross-Source Analytics — CONCLUIDA
**Foco:** Frontend processo seletivo, dashboards cross-source, reforma documental.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W9.1 | Selection Process Frontend | High | Done | `/admin/selection` com tabs por ciclo, KPI cards, tabela paginada com busca, snapshot comparison, guia de importacao CSV. Migration: `list_volunteer_applications` RPC. |
| W9.2 | Governance Change Request Journal | Medium | Deferred | Deferido — user chose `governance_later`. Sem schema pronto. |
| W9.3 | Busca Semantica (Embeddings) | Low | Deferred | pgvector sobre `artifacts`, `hub_resources`, `board_items`. Deferido para Wave 10+. |
| W9.4 | Cross-Source Analytics Dashboards | High | Done | "Visao Geral da Plataforma" em `/admin/analytics`: 6 KPI cards (membros, artefatos, eventos, Kanban, comms, candidaturas), doughnut de saude da plataforma, timeline de atividade mensal. Migration: `platform_activity_summary` RPC. |
| W9.5 | Documentation Reform | Medium | Done | AGENTS.md reformado (PostHog→Chart.js, role dropped, blocked agents removed, sprint closure added). SPRINT_IMPLEMENTATION_PRACTICES.md com 5-phase routine formalizada. DEPLOY_CHECKLIST.md atualizado. |

### Wave 9 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 13/13 | **Lint**: 0 errors | **Migrations**: 41/41
- **New pages**: `/admin/selection` (selection process management)
- **New RPCs**: `list_volunteer_applications` (paginated list), `platform_activity_summary` (cross-source)
- **New charts**: Platform health doughnut, Activity timeline, 6 cross-source KPIs
- **Docs reformed**: AGENTS.md, SPRINT_IMPLEMENTATION_PRACTICES.md, DEPLOY_CHECKLIST.md

---

## WAVE 10: Site-Hierarchy Integrity & UX Polish — CONCLUIDA
**Foco:** Correção de gaps de navegação, PERMISSIONS_MATRIX atualizada, scheduling e preview de avisos.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W10.1 | Admin Analytics Nav | High | Done | Entrada `/admin/analytics` em navigation.config.ts, AdminNav.astro, Nav.astro drawer, i18n. |
| W10.2 | Admin Curatorship Route Key | Medium | Done | `admin_curatorship` adicionado a AdminRouteKey e ROUTE_MIN_TIER. |
| W10.3 | PERMISSIONS_MATRIX Update | High | Done | Secções 3.13-3.15 (Tribe Kanban, Selection LGPD, Progressive disclosure). Mapeamento completo. |
| W10.4 | Announcement Scheduling UX | Medium | Done | Date-time pickers para `starts_at` e `ends_at`, validação start < end, badge "Agendado". |
| W10.5 | Announcement Markdown Preview | Low | Done | Toggle Editar/Visualizar, textarea + preview com **bold** *italic* `code` e quebras de linha. |

### Wave 10 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 13/13 | **Lint**: 0 errors
- **Site hierarchy**: admin-analytics nav entry added, admin_curatorship route key added
- **Announcements**: starts_at picker, start<end validation, scheduled badge, markdown preview toggle

### Wave 11 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 13/13 | **Migrations**: 42/42
- **Doc hygiene**: Tech debt S-AN1 atualizado, LATEST UPDATE, AGENTS 41, site hierarchy checkpoint
- **S-RM5**: site_config table, get/set RPCs, /admin/settings (superadmin)
- **Nav**: admin-settings (minTier superadmin), PERMISSIONS_MATRIX 3.16

---

## WAVE 12: Doc Agent Interaction, Release Workflow & Screenshots — CONCLUIDA
**Foco:** Rotina 5-phase documentada para agentes, workflow de release, screenshots multilíngues.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W12.1 | Agent Interaction Docs | High | Done | AGENTS.md "Interação com agentes", SPRINT_IMPLEMENTATION_PRACTICES ref, AGENT_BOARD_SYNC repo fix. |
| W12.2 | Semantic Versioning Workflow | Medium | Done | GitHub Actions `release-tag.yml` workflow_dispatch para criar tag vX.Y.Z. |
| W12.3 | S-SC1 Multilingual Screenshots | Low | Done | Script `screenshots-multilang.mjs` + `npm run screenshots:multilang`, Playwright. |
| S23 | Chapter Integrations | Medium | Deferred | Event-driven integrations; design pendente. |
| S24 | API for Chapters | Low | Deferred | Read-only API; design pendente. |
| S-KNW7 | Gemini Extraction Pipeline | Low | Deferred | Extrair `.docx` via Gemini API. |

### Wave 12 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 13/13 | **Site hierarchy**: OK (admin/* pages aligned)
- **Agent docs**: Interação com agentes, AGENT_BOARD_SYNC repo fix
- **Release workflow**: release-tag.yml workflow_dispatch
- **S-SC1**: screenshots-multilang.mjs, Playwright devDep

---

## WAVE 13: Doc Hygiene — CONCLUIDA
**Foco:** Corrigir docs obsoletos (Edge functions, PROJECT_ON_TRACK).

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W13.1 | Doc Hygiene | High | Done | AGENTS.md Edge functions; PROJECT_ON_TRACK seção 3 + F1; sync-credly-all e sync-attendance-points presentes. |

### Backlog futuro (deferred)
| ID | Feature | Status | Nota |
|----|----------|--------|------|
| S23 | Chapter Integrations | Deferred | Design pendente. |
| S24 | API for Chapters | Deferred | Design pendente. |
| S-KNW7 | Gemini Extraction Pipeline | Deferred | Baixa prioridade. |
| W13.2 | ResourcesSection → hub_resources | Partial | Já usa `hub_resources` client-side; fallback estático para SSR. Melhoria SSR deferida. |

### Wave 13 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 13/13
- **Doc hygiene**: AGENTS.md, PROJECT_ON_TRACK atualizados

---

## WAVE 14: Divergence Cleanup, Gap Audit & Deferred Structuring — CONCLUIDA
**Foco:** Corrigir divergência entre docs/guidelines e produção, limpar resquícios técnicos no admin e estruturar o backlog futuro por lane.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W14.1 | Doc Divergence Cleanup | High | Done | `README.md`, `docs/MIGRATION.md`, `CONTRIBUTING.md` atualizados para refletir Chart.js nativo, smoke routes, 5-phase e repo atual. |
| W14.2 | Admin Hygiene | High | Done | `admin/index.astro` sem refs antigas de PostHog/Looker; primeira tranche de event delegation aplicada; shared UI (`LangSwitcher`, `AuthModal`, `ConfirmDialog`) sem `onclick` inline; `admin_webinars` alinhado em `AdminRouteKey`. |
| W14.3 | Deferred Structuring | Medium | Done | S23, S24, S-KNW7 e `admin/webinars` classificados por lane, dependências e critério de saída do deferred. |

### Deferred backlog by lane

| ID | Item | Lane owner | Dependencies | Exit criteria from deferred |
|----|------|------------|--------------|-----------------------------|
| S23 | Chapter Integrations | Planning + Product | Definir casos de uso por chapter, entidades, ownership, integrações alvo | PRD curto aprovado + mapa de integrações + critérios de sucesso + decisão de fonte de verdade |
| S24 | API for Chapters | Planning + Backend | Resultado de S23, definição de escopo read-only, autenticação e filtros | Contrato API definido (resources, auth, filters, rate/ACL) + schema/RPC plan |
| S-KNW7 | Gemini Extraction Pipeline | Product + Data Governance + Integration | Política para `.docx`, revisão LGPD/copyright, pipeline staging | Prompt contract + governance approval + desenho de ingestão/curation/rollback |
| W14.4 | Webinars Module Discovery | Product + UI | Placeholder atual em `src/pages/admin/webinars.astro`, definição do fluxo operacional | Concluído em Wave 26: escopo aprovado em `docs/WEBINARS_MODULE_DISCOVERY.md`, com MVP `events`-first antes de qualquer schema novo |

### Benchmark notes (lightweight, not for cloning)
- **RBAC / admin**: `hubbleai/supabase-user-management-dashboard`, `point-source/supabase-tenant-rbac`
- **Knowledge hub / workspace**: `airbnb/knowledge-repo`, `jfmartinz/resourcehub`
- **Webinars / event ops**: `pretalx/pretalx`, `eventschedule/eventschedule`

### Wave 14 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 13/13 | **Smoke**: routes OK
- **Docs**: README, MIGRATION, CONTRIBUTING alinhados com produção
- **Site hierarchy / ACL**: rotas admin verificadas; `admin_webinars` alinhado em `AdminRouteKey`; sem rotas órfãs
- **Admin hygiene**: refs antigas removidas; tranche de event delegation aplicada em admin/shared UI

---

## WAVE 15: Cycle-Config Hardening — CONCLUIDA
**Foco:** reduzir hardcodes de ciclo nas superfícies operacionais mais sensíveis e consolidar `list_cycles` como fonte preferencial para leituras de ciclo.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W15.1 | Profile / Tribe Cycle Reads | High | Done | `profile.astro` e `tribe/[id].astro` agora resolvem ciclo corrente via `loadCycles()`/`getCurrentCycle()`, removendo dependência direta de `cycle_3` para My Week e deliverables. |
| W15.2 | Admin Cycle Hygiene | High | Done | `admin/index.astro` passa a usar meta/order/dates derivados de `list_cycles`; filtros e cycle history deixam de depender de datas fixas e de `CYCLE_META`/`CYCLE_ORDER`. |
| W15.3 | Compatibility + Docs Cleanup | Medium | Done | `profile.dashboardTitle` fica genérico por locale, `cycles.ts` usa tipo correto de client sem warning de build, e `PROJECT_ON_TRACK` corrige drift sobre edge functions e hardcodes de ciclo. |

### Wave 15 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 13/13 | **Smoke**: routes OK (`SMOKE_PORT=4335`)
- **Cycle config**: admin, profile e tribe leem ciclo corrente por `list_cycles`; sem `cycle_3` hardcoded nessas superfícies
- **Residual fallback**: permanecem apenas o fallback compartilhado em `src/lib/cycles.ts` e o label-compat em `src/lib/cycle-history.js`
- **Site hierarchy / ACL**: sem mudanças de tier; rotas auditadas continuam coerentes com `PERMISSIONS_MATRIX` e navegação atual

---

## WAVE 16: Supabase Audit, Attendance/Profile/Selection Stabilization — CONCLUIDA
**Foco:** comprovar o estado atual de schema/migrations sem abrir nova frente SQL, reduzir wiring frágil em superfícies antigas e manter ACL/LGPD alinhados.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W16.1 | Supabase Audit & Migration Drift Fix | High | Done | `supabase/migrations/` recontado em `44`; `npm run db:types` regenerou `src/lib/database.gen.ts` a partir do projeto linkado e confirmou a presença dos objetos mais recentes no schema remoto. |
| W16.2 | Profile Stabilization | High | Done | `profile.astro` remove o helper de rebinding do campo Credly e passa a usar normalização delegada (`focusout`, `paste`, `input`) resiliente a `renderProfile(...)`. |
| W16.3 | Selection Cycle Hardening | High | Done | `/admin/selection` carrega tabs e título de snapshots a partir de metadados runtime de ciclo, sem `Ciclo 1/2/3` hardcoded e sem alterar o guard `admin_selection` / `lgpdSensitive`. |
| W16.4 | Shared Dialog Callback Hygiene | Medium | Done | `ConfirmDialog.astro` deixa de mutar `btn.onclick`; callback é armazenado e consumido por um listener estável. |

### Wave 16 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 18/18 | **Smoke**: routes OK
- **Supabase audit**: repo em `44` migrations; schema linkado regenerado com sucesso em `src/lib/database.gen.ts`; `supabase migration list` nesta máquina requer refresh de credencial DB antes da próxima wave com write path de schema
- **Stabilization**: `profile` sem rebinding dedicado de Credly; `/admin/selection` cycle-aware; `ConfirmDialog` sem `btn.onclick` mutável
- **Site hierarchy / ACL**: `/admin/selection` continua `admin` + `lgpdSensitive`; sem regressão de visibilidade

---

## WAVE 17: Home Schedule Hardening & Browser Guard Base — CONCLUIDA
**Foco:** trocar fallbacks artificiais de prazo por estado runtime real na home e iniciar cobertura browser para guards internos sem abrir nova frente de schema.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W17.1 | Live Supabase Audit Restore | High | Done | `supabase migration list` voltou a funcionar normalmente no projeto linkado; estado confirmado em `44/44 local == remote`. |
| W17.2 | Home Schedule Hardening | High | Done | `src/lib/schedule.ts` passa a retornar `null` quando `home_schedule.selection_deadline_at` não está configurado; `HeroSection` e `TribesSection` deixam de depender do sentinel `2030`. |
| W17.3 | Tribes Availability Hygiene | High | Done | `TribesSection.astro` exibe estados `aberta` / `encerrada` / `pendente`, bloqueia seleção artificialmente aberta sem cronograma e remove os `onclick` inline ainda presentes nos links tocados. |
| W17.4 | Browser ACL Guard Base | Medium | Done | Novo script browser com Playwright valida que `/admin/selection` permanece negado para visitantes anônimos. |

### Wave 17 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 20/20 | **Browser guard**: OK | **Smoke**: routes OK
- **Supabase audit**: `supabase migration list` restaurado e confirmando `44/44 local == remote`
- **Home schedule**: sem deadline fictício `2030`; home usa estado real de cronograma
- **Site hierarchy / ACL**: `/admin/selection` continua `admin` + `lgpdSensitive`; novo teste browser trava esse guard

---

## WAVE 18: Home Runtime Messaging & Browser Coverage Expansion — CONCLUIDA
**Foco:** reduzir mais copy estático de cronograma na landing e consolidar cobertura browser para a home pública e guards sensíveis.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W18.1 | Home Schedule Runtime Model | High | Done | `src/lib/schedule.ts` expõe o objeto completo de `home_schedule`; `src/pages/index.astro`, `src/pages/en/index.astro` e `src/pages/es/index.astro` passam a compartilhar esse read único. |
| W18.2 | Hero Runtime Messaging | High | Done | `HeroSection.astro` deixa de depender apenas de strings estáticas para badge e schedule labels e passa a montar a mensagem inicial com `kickoff_at`, `platform_label`, `recurring_weekday`, `recurring_start_brt` e `recurring_end_brt`. |
| W18.3 | Post-Deadline Hero Visibility Fix | Medium | Done | O estado de ciclo é mostrado imediatamente quando a contagem já terminou, sem depender do bootstrap do Supabase client para trocar a UI. |
| W18.4 | Browser Coverage Expansion | Medium | Done | `tests/browser-guards.test.mjs` agora cobre `/admin/selection` anônimo e a home pública com runtime schedule ativo; `npm run test:browser:guards` permanece como entrada dedicada. |

### Wave 18 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 21/21 | **Browser guard**: OK | **Smoke**: routes OK
- **Home runtime**: badge e labels principais da home passam a refletir `home_schedule` real, não só fallback i18n
- **Post-deadline UX**: `hero-cycle-status` aparece sem depender de `navGetSb()` já estar pronto
- **Site hierarchy / ACL**: sem mudança de tier/visibilidade; `/admin/selection` continua protegido e agora também revalidado junto à home pública

---

## WAVE 19: Agenda Runtime Deadline Sync — CONCLUIDA
**Foco:** remover o próximo bolso de prazo fixo na home pública, mantendo Hero e Agenda alinhados ao mesmo `home_schedule`.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W19.1 | Agenda Runtime Deadline | High | Done | `src/components/sections/AgendaSection.astro` agora formata a deadline real da seleção e usa prefixos i18n em vez da data fixa anterior. |
| W19.2 | Home Wiring Reuse | High | Done | `src/pages/index.astro`, `src/pages/en/index.astro` e `src/pages/es/index.astro` passam `deadlineIso` também para `AgendaSection`, mantendo a home pública coesa em torno da mesma fonte runtime. |
| W19.3 | Regression Lock | Medium | Done | `tests/ui-stabilization.test.mjs` valida que as três home pages usam `AgendaSection deadline={deadlineIso}`. |

### Wave 19 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 21/21
- **Home runtime**: Hero e Agenda passam a compartilhar o mesmo deadline vindo de `home_schedule`
- **Scope**: nenhuma mudança de ACL, navegação ou schema nesta tranche

---

## WAVE 26: Webinars Module Discovery — CONCLUIDA
**Foco:** retirar `W14.4` do deferred definindo fonte de verdade, escopo MVP e limites operacionais antes de qualquer expansão de schema.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W26.1 | Webinars Source-of-Truth Decision | High | Done | O MVP recomendado passa a ser `events.type='webinar'`, reaproveitando `attendance` e evitando abrir uma segunda trilha operacional em cima da tabela `webinars`. |
| W26.2 | Scope / Non-Goals Definition | High | Done | Discovery formaliza agenda, speakers, attendance, recordings, certificates e analytics para a primeira entrega, deixando registro externo, speaker CRM e automações fora de escopo. |
| W26.3 | Governance / ACL / Migration Pack | Medium | Done | `docs/WEBINARS_MODULE_DISCOVERY.md`, `docs/MIGRATION.md`, `README.md`, `AGENTS.md` e `PERMISSIONS_MATRIX.md` alinhados ao caminho aprovado. |

### Wave 26 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 26/26 | **Smoke**: routes OK
- **Discovery outcome**: webinars seguem caminho `events`-first, member-first, com reuso de `attendance`, `presentations`, `workspace`, `comms` e analytics já existentes
- **Site hierarchy / ACL**: `/admin/webinars` continua `admin`; registro externo, speaker CRM e novas entidades LGPD-sensitive permanecem fora de escopo nesta fase

---

## WAVE 27: Admin Webinars Events-First MVP — CONCLUIDA
**Foco:** transformar `/admin/webinars` em superficie operacional real usando o backbone atual de eventos, presenca, replay e comms sem abrir schema novo.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W27.1 | Admin Webinars Operational Panel | High | Done | O placeholder foi substituido por um painel que carrega webinars via `get_events_with_attendance`, filtra `type='webinar'` e exibe sessoes atuais com KPIs e backlog operacional. |
| W27.2 | Cross-Module Orchestration | High | Done | A pagina agora aponta explicitamente para `Attendance`, `Admin Comms`, `Presentations` e `Workspace`, reforcando o MVP sobre o stack existente em vez de abrir CRUD paralelo. |
| W27.3 | Regression Lock + Docs | Medium | Done | `tests/ui-stabilization.test.mjs` trava a direcao `events`-first; backlog, governance, permissions, release log e README atualizados para refletir a nova surface. |

### Wave 27 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 27/27 | **Smoke**: routes OK
- **Webinars MVP**: `/admin/webinars` deixa de ser placeholder e passa a operar em cima de `events.type='webinar'`, com metricas, fila de follow-up e atalhos para os modulos existentes
- **Site hierarchy / ACL**: rota continua `admin`; nao houve mudanca de tier, visibilidade ou schema/RLS nesta tranche

---

## WAVE 28: Webinars Replay Publication Follow-Through — CONCLUIDA
**Foco:** tornar visivel no admin/webinars se o replay de cada webinar ja chegou em `Presentations` e `Workspace`, ainda sem abrir schema novo.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W28.1 | Replay Publication Correlation | High | Done | `admin/webinars` agora cruza `get_events_with_attendance` com `list_meeting_artifacts` e `hub_resources` para mostrar o status de publicacao do replay entre as superficies existentes. |
| W28.2 | Operator Visibility Upgrade | High | Done | O painel passa a explicitar lacunas de handoff entre eventos, replay e biblioteca, reduzindo checagem manual entre modulos. |
| W28.3 | Regression Lock + Docs | Medium | Done | Testes e docs atualizados para manter o caminho `events`-first e a leitura de publication status sem derivar para schema/CRUD paralelo. |

### Wave 28 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 27/27 | **Smoke**: routes OK
- **Replay follow-through**: `/admin/webinars` agora mostra se o replay do webinar ja foi encontrado em `Presentations`, `Workspace`, em ambos ou ainda em nenhum
- **Site hierarchy / ACL**: continua `admin`; nenhuma mudanca de tier, visibilidade, schema ou RLS nesta tranche

---

## WAVE 29: Webinars Browser Coverage — CONCLUIDA
**Foco:** validar em browser o novo fluxo `/admin/webinars`, cobrindo ACL admin e os sinais visuais de publication status do replay.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W29.1 | Webinars Anonymous Guard | High | Done | `tests/browser-guards.test.mjs` agora valida que `/admin/webinars` nega visitantes anonimos e `webinars.astro` deixa de ficar preso em loading sem sessao. |
| W29.2 | Mocked Admin Browser Path | High | Done | O suite browser injeta contexto admin controlado e dados fake de webinars, artefatos e workspace para validar os sinais de publication status em `Presentations` e `Workspace`. |
| W29.3 | Browser Harness Hardening | Medium | Done | O runner browser passou a reservar uma porta realmente livre antes de subir o Astro, reduzindo falhas espurias por conflito de porta em execucoes repetidas. |

### Wave 29 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 27/27 | **Browser guard**: OK | **Smoke**: routes OK
- **Browser coverage**: `/admin/webinars` agora esta coberto para denial anonimo e rendering admin mockado com sinais de publication status
- **Site hierarchy / ACL**: rota continua `admin`; a melhoria foi de validacao e fail-closed para anonimos, sem mudanca de tier, schema ou RLS

---

## WAVE 30: Webinars Operator Actions — CONCLUIDA
**Foco:** reduzir o custo operacional do fluxo de webinars com proximas acoes explicitas, mantendo o painel como orquestrador leve sobre os modulos ja existentes.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W30.1 | Per-Webinar Next Action | High | Done | Cada card de webinar agora deriva a “proxima acao” com base no estado do evento, replay e publicacao, apontando para o modulo certo sem precisar de inferencia manual. |
| W30.2 | Prioritized Quick Actions | High | Done | O topo do painel agora mostra uma fila priorizada de acoes rapidas, destacando handoffs como completar meeting link, publicar replay ou refletir o conteudo em `Presentations` / `Workspace`. |
| W30.3 | Regression Lock + Docs | Medium | Done | Testes e docs atualizados para manter a camada de operator guidance em cima do modelo `events`-first, sem abrir novo schema ou CRUD paralelo. |

### Wave 30 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 27/27 | **Smoke**: routes OK
- **Operator guidance**: `/admin/webinars` agora transforma status em proxima acao sugerida, reduzindo contexto manual entre `Attendance`, `Admin Comms`, `Presentations` e `Workspace`
- **Site hierarchy / ACL**: rota continua `admin`; nenhuma mudanca de tier, visibilidade, schema ou RLS nesta tranche

---

## WAVE 31: Webinars Contextual Handoffs — CONCLUIDA
**Foco:** reduzir mais uma camada de context switching no fluxo de webinars fazendo os handoffs cairem em views ja filtradas nos modulos reutilizados.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W31.1 | Filtered Presentations Handoff | High | Done | `admin/webinars` agora monta deep links para `presentations` com `q` e contexto de tribo/filtro, permitindo abrir o replay ja no subconjunto relevante. |
| W31.2 | Filtered Workspace Handoff | High | Done | `admin/webinars` passa a apontar para `workspace?type=webinar&q=...`, e `workspace.astro` aceita estado inicial por URL para reduzir busca manual. |
| W31.3 | Query-State Regression Lock + Docs | Medium | Done | `presentations.astro`, `workspace.astro`, testes e docs foram atualizados para manter o padrao de handoff contextual sem abrir schema ou CRUD paralelo. |

### Wave 31 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 28/28 | **Browser guard**: OK | **Smoke**: routes OK
- **Contextual handoffs**: os atalhos de `/admin/webinars` agora levam o operador para listas ja filtradas em `Presentations` e `Workspace`, reduzindo busca manual
- **Site hierarchy / ACL**: rotas continuam com os mesmos tiers e visibilidade; nao houve mudanca de schema, RLS ou exposicao publica nesta tranche

---

## WAVE 32: Webinars Attendance And Comms Handoffs — CONCLUIDA
**Foco:** reduzir o context switching nas duas superficies operacionais restantes do fluxo de webinars, mantendo o modelo `events`-first e sem abrir workflow local paralelo.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W32.1 | Focused Attendance Handoff | High | Done | `admin/webinars` agora envia o operador para `attendance` com tipo `webinar`, busca, `eventId` e opcionalmente `edit=1`, enquanto `attendance.astro` filtra, destaca e pode abrir o modal certo. |
| W32.2 | Focused Admin Comms Handoff | High | Done | `admin/webinars` agora envia o operador para `admin/comms` com foco contextual de webinar, e `admin/comms.astro` consome esse estado para orientar o estágio da comunicação e filtrar o histórico relevante. |
| W32.3 | Browser / Regression Lock + Docs | Medium | Done | Testes e docs foram expandidos para manter o padrão de handoff contextual também em `Attendance` e `Admin Comms`, sem abrir schema ou CRUD paralelo. |

### Wave 32 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 29/29 | **Browser guard**: OK | **Smoke**: routes OK
- **Focused reuse surfaces**: `/admin/webinars` agora aterrissa `Attendance` e `Admin Comms` em estados contextualizados para o webinar selecionado, reduzindo mais uma camada de busca manual
- **Site hierarchy / ACL**: rotas continuam com os mesmos tiers e visibilidade; nao houve mudanca de schema, RLS ou exposicao publica nesta tranche

---

## WAVE 33: Webinars In-Module Authoring Aids — CONCLUIDA
**Foco:** reduzir o esforco operacional dentro dos modulos de destino com auxilios de autoria e QA contextual, sem duplicar fluxo nem criar schema novo.

| ID | Feature | Priority | Status | Description |
|----|---------|----------|--------|-------------|
| W33.1 | Attendance Edit Assistant | High | Done | O fluxo contextual de `attendance` agora permite abrir o modal do webinar focado com orientacao especifica para completar meeting link ou `youtube_url`, incluindo foco no campo relevante. |
| W33.2 | Admin Comms Draft Playbook | High | Done | `admin/comms` agora renderiza um playbook rapido por contexto de webinar, com assunto e mensagem-base copiaveis para convite, lembrete ou follow-up. |
| W33.3 | Audit / Regression Lock + Docs | Medium | Done | Testes e docs foram expandidos para manter a nova camada de assistencia dentro de `Attendance` e `Admin Comms`, sem abrir editor paralelo nem alterar ACL. |

### Wave 33 Audit Results (2026-03-11)
- **Build**: clean | **Tests**: 29/29 | **Browser guard**: OK | **Smoke**: routes OK
- **In-module aids**: `Attendance` e `Admin Comms` agora ajudam o operador a concluir a tarefa do webinar dentro do proprio modulo de destino, sem criar fluxo paralelo
- **Site hierarchy / ACL**: nenhuma rota, tier ou exposicao LGPD mudou; a tranche adiciona apenas assistencia contextual em superficies ja existentes

---

## TECHNICAL DEBT & DEVOPS

| Issue | Impact | Status | Mitigation Plan |
|-------|--------|--------|-----------------|
| README History Lost | High | Addressed | Restored in docs refresh. |
| No Release Log | High | Addressed | `docs/RELEASE_LOG.md` mantido ativamente. |
| Semantic Versioning Missing | Medium | Addressed | Workflow `release-tag.yml` (workflow_dispatch) cria tag vX.Y.Z (W12.2). |
| No Security Scanning | High | Done | Dependabot + CodeQL habilitados. |
| Hardcoded strings | Medium | Done | i18n migration complete (400+ keys PT/EN/ES). |
| Legacy role columns | High | Done | `role`/`roles` dropped in Wave 8 (migration `20260312020000`). Frontend 100% on `operational_role`/`designations`. |
| PostHog/Looker dashboards | Medium | Superseded | Native Chart.js analytics replaced external iframes (S-AN1 + W8.3). |
| S-AN1 Rich Editor | Low | Partial | Markdown preview (W10.5) cobre **bold** *italic* `code`; WYSIWYG tipTap/Quill deferido. |
| S-AN1 Scheduling UX | Low | Done | Date-time pickers starts_at/ends_at, validacao, badge Agendado (W10.4). |

---

## DATA / ARCHITECTURE FOUNDATIONS

### Approved architectural direction

- `members` is the current snapshot for identity, contact, auth, and current state.
- `member_cycle_history` is the historical fact table for role, tribe, and cycle participation.
- `operational_role` and `designations` are the target fields.
- `role` and `roles` have been dropped (Wave 8, migration `20260312020000`).
- The Hub remains the only source of truth for gamification and operational metrics.
- `DATA_INGESTION_POLICY.md` governs all ETL operations (sensitive data never uploaded).

### Required next technical steps

- [x] Complete frontend reads from `operational_role` and `designations`.
- [x] Render cycle history timeline from `member_cycle_history`.
- [x] Add and validate `deputy_manager` visual treatment and ordering rules.
- [x] Define hard drop window for `role` and `roles`.
- [x] Consent-aware analytics instrumentation without leaking PII.
- [x] Execute hard drop of `role` and `roles` columns (Wave 8, migration `20260312020000`).
- [x] Provision production analytics (PostHog/Looker superseded by native Chart.js — S-AN1 + W8.3).

---

## ANALYTICS GOVERNANCE

### Internal product analytics
Native Chart.js dashboards powered by Supabase RPCs:
- **Executive panel**: `exec_funnel_summary` (member engagement), `exec_skills_radar` (tribe comparison), `exec_cert_timeline` (cert progression)
- **Selection process**: `volunteer_funnel_summary` (cycle funnel, certs, geography) — LGPD admin-only
- **Communications**: Comms metrics bar charts in `/admin/comms`
- PostHog iframes **superseded** by native charts (S-AN1, Wave 8)

### Required analytics rules
- use `member_id` or at most `operational_role`
- do not send email or full name unless strictly required
- selection process data (`volunteer_applications`) restricted to admin tier via RLS + RPC guard
- maintain operational delete path for right to be forgotten
- restrict `/admin/analytics` by tier
- `lgpdSensitive` nav items remain fully hidden for non-authorized users

### External communication metrics
Native Supabase-based comms metrics replaced external Looker dependency. YouTube/LinkedIn/Instagram metrics managed via `comms_metrics` table and admin dashboard.

---

## PRODUCTION STATE SUMMARY (2026-03-11)

### Infrastructure
- **Git**: `origin/main` is the canonical deploy branch in this clone; optional `production` remote only when explicitly configured
- **SQL Migrations**: 44 tracked in repo / linked schema refreshed from Supabase — Wave 7-9 data/RPCs, Wave 11 site_config
- **Edge Functions**: 13 active in production (all `--no-verify-jwt`)
- **Frontend**: Deployed via Cloudflare Pages (auto-deploy from main)
- **Storage**: `documents` bucket active with public read + authenticated upload

### Data Ingestion Scripts (Wave 7) — Executed 2026-03-11
- `scripts/trello_board_importer.ts`: 5 boards → 119 cards in `project_boards` + `board_items`
- `scripts/calendar_event_importer.ts`: ICS → 67 events in `events` (source=calendar_import)
- `scripts/volunteer_csv_importer.ts`: 6 CSVs → 143 applications in `volunteer_applications` (92 matched)
- `scripts/miro_links_importer.ts`: CSV → 51 links in `hub_resources` (source=miro_import)

### Navigation (`navigation.config.ts`)
- 22 items covering all routes with tier-based ACL
- Home anchors (10), Tools (5), Member (2), Profile (1), Admin (8)
- Progressive disclosure: disabled items with lock icon + tooltip for insufficient tier
- LGPD-sensitive items fully hidden for non-authorized (new `lgpdSensitive` flag)
- No orphan routes (legacy aliases `/teams`, `/rank`, `/ranks` are intentional redirects)

### Schema Changes (Wave 8-9)
- Dropped `role`, `roles` columns and `trg_sync_legacy_role` trigger from `members`
- New `NavItem.lgpdSensitive` flag and `ItemAccessibility` interface in `navigation.config.ts`
- New RPCs: `list_volunteer_applications`, `platform_activity_summary`

### Documentation
- `docs/RELEASE_LOG.md`: Up to date (2026-03-11)
- `docs/PERMISSIONS_MATRIX.md`: Up to date (2026-03-11)
- `AGENTS.md`: Reformed (2026-03-11) — stale conventions fixed, sprint closure routine added
- `docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md`: 5-phase routine formalized
- `docs/project-governance/PROJECT_ON_TRACK.md`: Edge functions verificadas (Wave 13)
- `backlog-wave-planning-updated.md`: This file — synchronized

---

## PRÓXIMAS 10 SPRINTS (FILA PRIORIZADA)

> Base atual: Waves 27-33 concluídas.  
> Próxima esteira recomendada para execução contínua: **W34-W43**.

| Sprint | Foco | Priority | Status | Description |
|---|---|---|---|---|
| W34 | CI Runtime Hardening | High | Planned | Reduzir flakiness e tempo de pipeline com cache determinístico, retries controlados e matriz de jobs crítica. |
| W35 | E2E Auth Critical Paths | High | Planned | Cobrir fluxos autenticados end-to-end (admin/member/curatorship/webinars) com Playwright estável e dados mockados. |
| W36 | Supabase RPC Integration Contracts | High | Planned | Validar contratos de RPC em ambiente controlado (payload, ACL e regressão de assinatura). |
| W37 | Admin Modularization Phase 3 | Medium | Planned | Extrair blocos de render/handlers do admin por domínio para reduzir risco de regressão em arquivo monolítico. |
| W38 | Knowledge Hub Phase B Ops SLA | High | Planned | Definir e instrumentar SLA operacional da curadoria (tempo de triagem/publicação e backlog aging). |
| W39 | Comms Integration Phase 2 | High | Planned | Avançar operação híbrida Trello -> Hub com meta >80% de origem Hub e evidências de adoção. |
| W40 | Analytics V2 Partner Real Validation | High | Planned | Executar pacote executivo com leitura real partner-facing e checklist de evidências de contrato SQL. |
| W41 | Branch Protection + Release Readiness Automation | Medium | Planned | Automatizar auditoria de branch protection e gate de readiness de release em rotina contínua. |
| W42 | Bus-Factor Drill Assisted | Medium | Planned | Rodar drill assistido com operador secundário executando runbook completo com evidências. |
| W43 | Bus-Factor Drill Blind + Gap Closure | Medium | Planned | Rodar drill cego, consolidar lacunas e abrir plano de ação com owners e prazos fechados. |

### Sequência operacional sugerida
- Executar na ordem **W34 -> W43** sem pular gates técnicos (`npm test`, `npm run build`, `npm run smoke:routes`).
- Onde houver impacto de schema/RPC, aplicar `supabase db push` na fase de audit da sprint.
- Encerrar cada sprint com atualização de `docs/RELEASE_LOG.md` e checkpoint deste backlog.

---

## Notes for the dev team

This backlog now reflects the actual state of production. All items marked Done have been verified against deployed code, applied migrations, and active Edge Functions. Items marked "Planned" are genuine future work with no code in the repository.
