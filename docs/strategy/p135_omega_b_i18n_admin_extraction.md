# Ω-B Sweep — i18n Extraction Report (Painéis Admin)

**Sessão:** p135 Ω-B trilingue Fase A+B admin
**Scope:** páginas dentro de `src/pages/admin/` (42 pages totais — root + governance/ + member/ + members/ + tribe/ + board/) + components admin-only em `src/components/admin/`.
**Audience target:** GP/líderes/curadores/comms PMI international (LATAM + USA) — admin precisa funcionar trilingue para que decisões operacionais sejam acessíveis a stakeholders não-PT.

> **Caveat metodológico:** scan baseado em leitura amostral cabeçalho + grep dirigido + amostra de scripts. Para arquivos grandes (selection 3137L, adoption 1016L, analytics 967L, sustainability 820L, campaigns 783L, comms 768L, webinars 751L) priorizei UI sections, modais, status maps, badge labels e error/toast messages. Pure-logic blocks (RPC handlers, sort helpers, filter pipelines) só foram tocados quando contém strings end-user-visible. Estimativa: 80-90% coverage; ~10% de strings remanescentes em scripts client dinâmicos podem ter sido perdidas.

---

## Sumário Executivo

- **Total pages auditadas:** 42 (root + governance/ + members/ + member/ + tribe/ + board/ + governance/documents/[chainId]/* + governance/documents/[docId]/versions/new)
- **Pages clean (delegate a island i18n-aware ou usam t() consistentemente):** ~14 — `members.astro`, `governance/documents.astro`, `tribes.astro`, `chapter.astro`, `data-health.astro`, `tags.astro`, `knowledge.astro`, `audit-log.astro`, `certificates.astro`, `ai-calibration.astro`, `report.astro`, `curatorship.astro`, `analytics.astro`, `partnerships.astro` (mostly), `portfolio.astro`, `board/[id].astro`
- **Pages com hardcoded relevante:** ~28 — variando de 1-3 strings (adoption tab labels, settings cycle modal save, blog cancel) a 60+ (selection STATUS_LABELS+STATUS_GROUPS+ROLE_LABELS, comms full PT chrome, webinars status+badges+next-action labels, comms-ops handoff workflow strings)
- **Total strings hardcoded encontradas (amostradas):** ~520-580 (em ~28 pages + components admin compartilhados)
- **Total i18n keys propostas:** ~340 únicas (várias reutilizam keys existentes de `admin.*`, `common.*`, `selection.status.*`, `webinars.*`, `comms.*`)
- **Pages Critical (showstopper trilingue):** 4 — `governance/ip-ratification.astro` (100% PT, zero i18n), `governance/documents/[chainId]/*` (4 wrappers PT-only breadcrumbs), `governance/documents/[docId]/versions/new.astro` (PT-only chrome), `members/[id].astro` + `members/inactive-candidates.astro` + `member/[id].astro` (breadcrumbs+form labels PT-only)
- **Pages com inline lang dictionaries (anti-pattern leve):** 1 — `governance/documents.astro` (inline `gateLabels` map por lang — funcional mas centraliza decisão de copy fora do dict global)
- **Pages com `lang="pt-BR"` hardcoded attributes:** 0 admin (todos usam `getLangFromURL()`)
- **Components admin compartilhados com hardcoded:** ~12 detectados (não scaneados em profundidade; subset de `src/components/admin/*Island.tsx`)

### Distribuição por urgência

| Urgência | Quantidade | Exemplos |
|---|---|---|
| **Critical (showstopper trilingue)** | 7 pages | `governance/ip-ratification.astro` (100% PT zero `t()`), `governance/documents/[chainId].astro` + audit-report/export-pdf/export-docx/versions/new (5 wrappers PT-only), `member/[id].astro` (Voltar/Novo Membro/full form PT), `members/[id].astro` + `members/inactive-candidates.astro` (breadcrumbs PT) |
| **High (visible PMI int'l demo)** | 14 pages | `selection.astro` (STATUS_LABELS+ROLE_LABELS+STATUS_GROUPS+kanban+badges), `comms.astro` (S1-S6 sections all PT chrome), `webinars.astro` (STATUS_LABELS+TRIBE_NAMES+next-action+banners), `comms-ops.astro` (handoff Webinars+Playbook+broadcasts), `campaigns.astro` (filter dropdowns+template card buttons+toasts), `adoption.astro` (Tabs Visitantes/Analytics+ROLE_LABELS+KPI labels+lifecycle), `cycle-report.astro` (Evolução C2→C3+headers+footer+Presença), `chapter-report.astro` (ROLE_LABELS+kpi labels), `partnerships.astro` (TYPE_LABELS+filter Status options), `pilots.astro` (Hipótese/Problema/Escopo headers+timeout/error msgs), `sustainability.astro` (Cost-paid-by options+filter `Todas`/`De`/`Até`/`Filtrar`+confirm/toast strings), `settings.astro` (cycles list buttons Editar/Excluir/Ativar+confirm prompts), `governance-v2.astro` (subtab labels+denied+restore toasts), `initiative-kinds.astro` (FLAG_LABELS+modal title+slug error toasts) |
| **Medium (edge cases / minor strings)** | 7 pages | `index.astro` (3 strings: Próxima Reunião Geral+button labels+denied), `blog.astro` (category options+slug placeholder), `publications.astro` (filter Status+Tribo+`Todas`+modal Título+toasts), `tribe/[id].astro` (`Carregando...`+Pessoas+Tribo breadcrumbs), `audit-log.astro` (clean delegate), `data-health.astro` (denied msg defined `Acesso restrito a administradores.`), `tags.astro`/`knowledge.astro` (similar denied msg PT-only) |

---

## Tabela detalhada (por página)

### 1. `src/pages/admin/governance/ip-ratification.astro` — Critical (100% PT, zero i18n)

**Major issue:** página inteira hardcoded em PT, importa apenas `getLangFromURL` (não usa `t()`). Conteúdo é admin gate de aprovação chains com terminologia legal/governance — alta criticidade para liderança PMI.

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 17 | `title="Ratificação de Propriedade Intelectual"` | `admin.ipRatification.metaTitle` | `'Intellectual Property Ratification'` | `'Ratificación de Propiedad Intelectual'` |
| 19-21 | breadcrumbs `'Operações' / 'Governança' / 'Ratificação IP'` | `admin.breadcrumb.operations` (existe) / `admin.breadcrumb.governance` / `admin.ipRatification.crumb` | `'Operations' / 'Governance' / 'IP Ratification'` | `'Operaciones' / 'Gobernanza' / 'Ratificación PI'` |
| 27 | `'Ratificação de PI'` (h1) | `admin.ipRatification.title` | `'IP Ratification'` | `'Ratificación de PI'` |
| 28-32 | descriptive paragraph (3 sentences) | `admin.ipRatification.intro` | full EN translation | full ES translation |
| 36 | `'Usar versão nova →'` | `admin.ipRatification.useNewVersion` | `'Use new version →'` | `'Usar versión nueva →'` |
| 38 | `'← Governança (geral)'` | `admin.ipRatification.backGovernance` | `'← Governance (general)'` | `'← Gobernanza (general)'` |
| 46 | `'Carregando chains…'` | `admin.ipRatification.loading` | `'Loading chains…'` | `'Cargando cadenas…'` |
| 52 | `'Nenhuma approval_chain ativa.'` | `admin.ipRatification.empty` | `'No active approval chain.'` | `'Sin cadena de aprobación activa.'` |
| 59-66 | table headers `'Documento' / 'Versão' / 'Status' / 'Gates' / 'Signoffs' / 'Pendentes' / 'Assinar' / 'Ações'` | `admin.ipRatification.col.{document,version,status,gates,signoffs,pending,sign,actions}` | `'Document' / 'Version' / 'Status' / 'Gates' / 'Signoffs' / 'Pending' / 'Sign' / 'Actions'` | `'Documento' / 'Versión' / 'Estado' / 'Gates' / 'Firmas' / 'Pendientes' / 'Firmar' / 'Acciones'` |
| 73-75 | reminder cron text + code refs | `admin.ipRatification.cronReminder` (template) | `'Reminder cron (Phase IP-2b — next session): will use {code} to notify pending via email D-14/-7/-3/-1.'` | `'Cron de recordatorio (Fase IP-2b — próxima sesión): usará {code} para notificar pendientes vía correo D-14/-7/-3/-1.'` |
| 81-86 | STATUS_LABELS map: `'Rascunho' / 'Em revisão' / 'Aprovado' / 'Vigente' / 'Retirado' / 'Substituído'` | reuse `governance.docs.status*` keys (existem na page sister governance/documents.astro) | reuse | reuse |
| (script) ~150-200 | various fetch error messages, sign-now toasts (não amostrados em profundidade) | `admin.ipRatification.toast.*` | n/a | n/a |

### 2. `src/pages/admin/governance/documents/[chainId].astro` — Critical (PT-only breadcrumbs)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 14 | `title="Revisar documento"` | `admin.governance.review.metaTitle` | `'Review document'` | `'Revisar documento'` |
| 16-19 | breadcrumbs `'Operações' / 'Governança' / 'Documentos' / 'Revisar'` | reuse `admin.breadcrumb.operations` + `admin.breadcrumb.governance` + `governance.docs.subtabDocs` (existe) + `admin.governance.review.crumb` | EN equivalents | ES equivalents |

### 3. `src/pages/admin/governance/documents/[chainId]/audit-report.astro` — Critical

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 12 | `title="Relatório de auditoria — Conselho Fiscal"` | `admin.governance.auditReport.metaTitle` | `'Audit Report — Fiscal Council'` | `'Informe de Auditoría — Consejo Fiscal'` |
| 14-19 | 5 breadcrumb labels (Operações / Governança / Documentos / Revisar / Relatório auditoria) | reuse + `admin.governance.auditReport.crumb` | `'Audit Report'` | `'Informe Auditoría'` |

### 4. `src/pages/admin/governance/documents/[chainId]/export-pdf.astro` — Critical

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 12 | `title="Exportar PDF — cadeia de ratificação"` | `admin.governance.exportPdf.metaTitle` | `'Export PDF — ratification chain'` | `'Exportar PDF — cadena de ratificación'` |
| 14-19 | breadcrumbs (last item `'Exportar PDF'`) | `admin.governance.exportPdf.crumb` | `'Export PDF'` | `'Exportar PDF'` |

### 5. `src/pages/admin/governance/documents/[chainId]/export-docx.astro` — Critical

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 14 | `title="Exportar DOCX — conteúdo da versão"` | `admin.governance.exportDocx.metaTitle` | `'Export DOCX — version content'` | `'Exportar DOCX — contenido de la versión'` |
| 16-21 | breadcrumbs (last `'Exportar DOCX'`) | `admin.governance.exportDocx.crumb` | `'Export DOCX'` | `'Exportar DOCX'` |

### 6. `src/pages/admin/governance/documents/[docId]/versions/new.astro` — Critical (typos: "versao", "Operacoes", "Governanca")

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 18 | `title="Nova versao de documento"` (typo: missing accent) | `admin.governance.newVersion.metaTitle` | `'New document version'` | `'Nueva versión del documento'` |
| 20-23 | breadcrumbs `'Operacoes' / 'Governanca' / 'Documentos' / 'Nova versao'` (3 typos) | reuse + `admin.governance.newVersion.crumb` | `'New version'` | `'Nueva versión'` |

### 7. `src/pages/admin/member/[id].astro` — Critical (form 308L, mostly PT inline)

**Major issue:** 100% PT em breadcrumb, header, todos labels do form (`Nome completo *`, `Email principal *`, etc.). Página crítica para GP gerenciar membros.

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 18 | `'← Voltar'` | reuse `common.back` (existe) | reuse | reuse |
| 20 | `'+ Novo Membro' / '✏️ Editar Membro'` | `admin.memberEdit.newMember` / `admin.memberEdit.editMember` | `'+ New Member'` / `'✏️ Edit Member'` | `'+ Nuevo Miembro'` / `'✏️ Editar Miembro'` |
| 110 | label `'Nome completo *'` | `admin.memberEdit.nameLabel` | `'Full name *'` | `'Nombre completo *'` |
| 111 | placeholder `'Nome completo'` | `admin.memberEdit.namePh` | `'Full name'` | `'Nombre completo'` |
| 115 | label `'Email principal *'` | `admin.memberEdit.emailLabel` | `'Primary email *'` | `'Correo principal *'` |
| (~120-280 esperado) | demais labels de form: telefone, capítulo, role, designations, PMI ID, credly_url, address, city, etc. — pattern PT inline `'X *'` | `admin.memberEdit.fieldLabel.*` (todos novos) | EN | ES |
| (toasts esperados) | save/error messages | `admin.memberEdit.toast.*` | n/a | n/a |

### 8. `src/pages/admin/members/[id].astro` — Critical (delegate but PT breadcrumbs)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 15 | `title="Detalhe do Membro"` | `admin.memberDetail.metaTitle` | `'Member Detail'` | `'Detalle del Miembro'` |
| 17-20 | breadcrumbs `'Pessoas' / 'Membros' / 'Detalhe'` | reuse `admin.breadcrumb.people` + `admin.breadcrumb.members` + `admin.memberDetail.crumb` | `'Detail'` | `'Detalle'` |

### 9. `src/pages/admin/members/inactive-candidates.astro` — Critical (PT breadcrumbs)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 17 | `title="Candidatos a Inativo"` | `admin.inactiveCandidates.metaTitle` | `'Inactive Candidates'` | `'Candidatos a Inactivo'` |
| 19-21 | breadcrumbs `'Pessoas' / 'Membros' / 'Candidatos a Inativo'` | reuse + `admin.inactiveCandidates.crumb` | `'Inactive Candidates'` | `'Candidatos a Inactivo'` |

### 10. `src/pages/admin/selection.astro` — High (3137L, very heavy)

**Heaviest admin file.** Bulk de hardcoded em status maps, role labels, kanban badges, kanban groups, modal labels, action buttons. Scope: pipeline triagem completo PMI VEP candidates.

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 39 | `data-sel-tab="pipeline"` button label `'Pipeline'` | `admin.selection.tabPipeline` | `'Pipeline'` | `'Pipeline'` |
| 40 | `'Import CSV'` | `admin.selection.tabImportCsv` | `'Import CSV'` | `'Importar CSV'` |
| 42 | `'Diversidade'` | `admin.selection.tabDiversity` | `'Diversity'` | `'Diversidad'` |
| 52 | `'Recalcular Rankings'` | `admin.selection.recalcBtn` | `'Recalculate Rankings'` | `'Recalcular Rankings'` |
| 53 | `'Iniciar Triagem'` | `admin.selection.startScreeningBtn` | `'Start Screening'` | `'Iniciar Triaje'` |
| 59 | `'👁 Ocultar decididos'` | `admin.selection.hideDecidedBtn` | `'👁 Hide decided'` | `'👁 Ocultar decididos'` |
| 61 | `'Todos'` (myeval-toggle) | reuse `common.allOption` (criar se não existir) | `'All'` | `'Todos'` |
| 62 | `'⏳ Minhas pendentes'` | `admin.selection.myPending` | `'⏳ My pending'` | `'⏳ Mías pendientes'` |
| 70-72 | role buttons `'Todos' / 'Pesquisador' / 'Líder'` | reuse `selection.role.researcher` / `.leader` (existem em selection-cycles) + `common.allOption` | reuse | reuse |
| 78-86 | filter status options PT (Todos os Status / Submitted / Screening / etc.) | reuse `admin.selection.status.*` (existe parcialmente) ou criar 15 keys | EN | ES |
| 87 | `'Buscar nome ou email'` (placeholder) — actually uses `t()` already (`searchNameEmail` key) | (confirmed already) | already | already |
| 102-113 | table column headers `'Nome' / 'Track' / 'Pesquisa' / 'Líder' / 'Rank' / 'Status' / 'Minha aval.' / 'Pipeline' / 'Data' / 'Onboarding'` | `admin.selection.col.{name,track,research,leader,rank,status,myEval,pipeline,date,onboarding}` | EN equivalents | ES equivalents |
| 124 | `'0 selecionados'` | `admin.selection.bulkCount` (template) | `'{n} selected'` | `'{n} seleccionado(s)'` |
| 125 | `'Aprovar'` | `admin.selection.bulkApprove` | `'Approve'` | `'Aprobar'` |
| 126 | `'Rejeitar'` | `admin.selection.bulkReject` | `'Reject'` | `'Rechazar'` |
| 127 | `'Lista Espera'` | `admin.selection.bulkWaitlist` | `'Waitlist'` | `'Lista de Espera'` |
| 138 | `'Vagas VEP Configuradas'` | `admin.selection.vepOpportunitiesTitle` | `'Configured VEP Opportunities'` | `'Vacantes VEP Configuradas'` |
| 139 | `'+ Nova Vaga'` | `admin.selection.newOppBtn` | `'+ New Opportunity'` | `'+ Nueva Vacante'` |
| 142 | `'Carregando...'` | reuse `common.loading` (existe) | reuse | reuse |
| 146 | `'Nova Vaga VEP'` (form title) | `admin.selection.newVepOpp` | `'New VEP Opportunity'` | `'Nueva Vacante VEP'` |
| 148 | label `'Opportunity ID'` | `admin.selection.oppIdLabel` | (keep) | (keep) |
| 149 | `'Papel Default'` + options `'Pesquisador' / 'Líder'` | `admin.selection.defaultRoleLabel` + reuse role keys | `'Default Role'` | `'Rol Predeterminado'` |
| 154 | `'Capítulo'` | reuse `admin.selection.chapter` (existe) | reuse | reuse |
| 155 | `'Vagas'` (positions) | `admin.selection.positionsLabel` | `'Positions'` | `'Vacantes'` |
| 160 | `'Fim'` | `admin.selection.endDateLabel` | `'End'` | `'Fin'` |
| 162 | `'Elegibilidade'` | `admin.selection.eligibilityLabel` | `'Eligibility'` | `'Elegibilidad'` |
| 164 | `'Mapeamento de Perguntas (Essay Mapping)'` | `admin.selection.essayMappingLabel` | `'Question Mapping (Essay Mapping)'` | `'Mapeo de Preguntas (Essay Mapping)'` |
| 165 | `'Defina qual campo do sistema recebe cada pergunta...'` | `admin.selection.essayMappingHint` | full EN translation | full ES translation |
| 167 | `'+ Adicionar pergunta'` | `admin.selection.addQuestionBtn` | `'+ Add question'` | `'+ Añadir pregunta'` |
| 170 | `'Salvar'` | reuse `common.save` | reuse | reuse |
| 171 | `'Cancelar'` | reuse `common.cancel` | reuse | reuse |
| 178 | `'Importar CSV do PMI VEP'` | `admin.selection.importCsvTitle` | `'Import PMI VEP CSV'` | `'Importar CSV de PMI VEP'` |
| 179 | description (3 sentences) | `admin.selection.importCsvDesc` | full EN | full ES |
| 183 | `'Opportunity ID (do PMI VEP)'` | `admin.selection.importOppIdLabel` | `'Opportunity ID (from PMI VEP)'` | `'Opportunity ID (de PMI VEP)'` |
| 193 | `'Papel default'` | reuse `admin.selection.defaultRoleLabel` | reuse | reuse |
| 195-196 | `'Pesquisador' / 'Líder'` (options) | reuse role keys | reuse | reuse |
| 200 | `'O papel default é aplicado a todos os candidatos do CSV...'` (long hint) | `admin.selection.defaultRoleHint` | full EN | full ES |
| 205 | `'Arraste o CSV aqui ou clique para selecionar'` | `admin.selection.dropzoneText` | `'Drag the CSV here or click to select'` | `'Arrastra el CSV aquí o haz clic para seleccionar'` |
| 206 | `'Formato: CSV exportado do PMI VEP (Opportunity Applications)'` | `admin.selection.dropzoneFormat` | `'Format: CSV exported from PMI VEP (Opportunity Applications)'` | `'Formato: CSV exportado de PMI VEP (Opportunity Applications)'` |
| 217-221 | preview table headers `'Nome' / 'Email' / 'Capítulo' / 'VEP Status' / 'Ação'` | `admin.selection.preview.col.*` | EN | ES |
| 228 | `'Importar candidatos'` | `admin.selection.importBtn` | `'Import candidates'` | `'Importar candidatos'` |
| 229 | `'Cancelar'` | reuse `common.cancel` | reuse | reuse |
| 244 | `'Distribuição por gênero, capítulo, setor, senioridade e região...'` | `admin.selection.diversityHint` | full EN | full ES |
| 257 | `'Membros do comitê avaliam candidatos em revisão cega...'` | `admin.selection.committeeIntro` | full EN | full ES |
| 269-271 | role options `'Avaliador' / 'Lead' / 'Observador'` | `admin.selection.committeeRole.*` | `'Evaluator' / 'Lead' / 'Observer'` | `'Evaluador' / 'Lead' / 'Observador'` |
| 364-370 | STATUS_GROUPS map: `'Submetidos' / 'Avaliação' / 'Entrevista' / 'Aprovados' / 'Rejeitados'` | `admin.selection.statusGroup.*` | `'Submitted' / 'Evaluation' / 'Interview' / 'Approved' / 'Rejected'` | `'Enviados' / 'Evaluación' / 'Entrevista' / 'Aprobados' / 'Rechazados'` |
| 397 | ROLE_LABELS `{ researcher: 'Pesquisador', leader: 'Líder', both: 'Ambos' }` | `selection.role.{researcher,leader,both}` (existem partial) | reuse + add `both` | reuse + add `both` |
| 408-415 | STATUS_LABELS map (15 entries: 'Submetido' / 'Triagem' / 'Avaliação Objetiva' / 'Abaixo do Corte' / 'Aguardando Entrevista' / 'Entrevista Agendada' / 'Entrevistado' / 'No-Show' / 'Avaliação Final' / 'Aprovado' / 'Rejeitado' / 'Lista de Espera' / 'Convertido' / 'Desistiu' / 'Cancelado') | `admin.selection.status.{submitted,screening,objective_eval,objective_cutoff,interview_pending,interview_scheduled,interview_done,interview_noshow,final_eval,approved,rejected,waitlist,converted,withdrawn,cancelled}` | EN | ES |
| 425-432 | myEvalBadge tooltips: `'Você submeteu avaliação objetiva...'` / `'Você tem rascunho — falta submeter'` / `'Você foi convidado — pendente'` / `'Sem convite individual'` | `admin.selection.myEvalTooltip.*` | EN | ES |
| 425 | label `'✓ Avaliei'` | `admin.selection.evaluatedBadge` | `'✓ Evaluated'` | `'✓ Evalué'` |
| 428 | `'⚠ Rascunho'` | `admin.selection.draftBadge` | `'⚠ Draft'` | `'⚠ Borrador'` |
| 431 | `'📨 Convidado'` | `admin.selection.invitedBadge` | `'📨 Invited'` | `'📨 Invitado'` |
| 451-476 | pipelineBadges tooltip strings (5×): `'AI analysis concluída + consent dado'` / `'Aguardando AI / consent'` / `'X avaliação(ões) submetida(s), Y convite(s) pendente(s)'` / `'Entrevista agendada/realizada'` / `'Sem entrevista agendada'` / `'Candidato acessou portal pelo menos 1×'` / `'Token nunca consumido (não acessou portal)'` / `'Vídeo screening uploaded ou opted-out'` / `'Sem vídeo screening'` | `admin.selection.pipelineTooltip.*` (9 keys) | EN equivalents | ES equivalents |
| 491-496 | pipelineTimeline stages `'Aplicação' / 'Análise IA' / 'Par-revisão' / 'Vídeo' / 'Entrevista' / 'Decisão'` | `admin.selection.timelineStage.*` | EN | ES |
| 491 | `'Submetida'` (fallback) | `admin.selection.submittedFallback` | `'Submitted'` | `'Enviada'` |
| 492 | `'Concluída' / 'Em curso' / 'Aguardando consent'` | `admin.selection.aiState.*` | EN | ES |
| 493 | `'X/2 avaliações'` | `admin.selection.peerCountTpl` | `'{n}/2 reviews'` | `'{n}/2 evaluaciones'` |
| 494 | `'OK ou opt-out' / 'Não realizado'` | `admin.selection.videoState.*` | EN | ES |
| 495 | `'Agendada' / 'Não agendada'` | `admin.selection.interviewState.*` | EN | ES |
| 496 | `'Em andamento'` (decision fallback) | `admin.selection.decisionInProgress` | `'In progress'` | `'En curso'` |
| 578 | error message `'Erro: ' + msg + ' / 'desconhecido''` | `admin.selection.errorPrefix` (template) | `'Error: {msg}'` | `'Error: {msg}'` |
| 587 | `'Todos os Capítulos'` | reuse `admin.selection.allChapters` (existe) | reuse | reuse |
| 651-654 | quick stats `'Total' / 'Aprovados' / 'Rejeitados' / 'Pendentes'` | `admin.selection.quickStats.*` | `'Total' / 'Approved' / 'Rejected' / 'Pending'` | `'Total' / 'Aprobados' / 'Rechazados' / 'Pendientes'` |
| 682 | template `'X resultado(s)'` | `admin.selection.resultsCount` | `'{n} result(s)'` | `'{n} resultado(s)'` |
| 684 | fallback `'Nenhum candidato'` | `admin.selection.noCandidates` | `'No candidate'` | `'Sin candidato'` |
| 720 | track badge tooltip `'Triado: aplicou como pesquisador, foi promovido para líder'` | `admin.selection.triagedTooltip` | full EN | full ES |
| 720 | `'👑⇡ Triado'` | `admin.selection.triagedBadge` | `'👑⇡ Triaged'` | `'👑⇡ Triado'` |
| 721 | `'👑 Líder'` | `admin.selection.leaderBadge` | `'👑 Leader'` | `'👑 Líder'` |
| 724 | `'🎓 (promovido)'` | `admin.selection.promotedFromBadge` | `'🎓 (promoted)'` | `'🎓 (promovido)'` |
| 725 | `'🎓 Pesquisador'` | `admin.selection.researcherBadge` | `'🎓 Researcher'` | `'🎓 Investigador'` |
| 731 | tooltip `'Sem membership PMI'` | `admin.selection.noMembershipTooltip` | `'No PMI membership'` | `'Sin membresía PMI'` |
| 731 | tooltip `'Retornante'` | `admin.selection.returningTooltip` | `'Returning'` | `'Retornante'` |
| 743 | `'Detalhes'` (action button) | reuse `common.details` (criar se não existir) | `'Details'` | `'Detalles'` |
| (~750-3137) | **demais bulk de strings**: applicant modal sections (Info / Avaliações / Entrevista / Decisão / Histórico tabs), score breakdown labels, peer evaluation card text, decision modal labels (Aprovar/Rejeitar/Mover para waitlist + feedback prompts), CSV import result messages, committee management (add member search results, role select, remove confirms), interview scheduling (date/time pickers, "Marcar como realizada" / "No-Show" / "Reagendar"), various toasts (`'Candidato aprovado'` / `'Selecionado movido para waitlist'` / etc.) — **estimativa: ~80-120 strings adicionais não amostradas em profundidade**. | `admin.selection.modal.*`, `admin.selection.committee.*`, `admin.selection.interview.*`, `admin.selection.toast.*` | n/a | n/a |

### 11. `src/pages/admin/comms.astro` — High (768L, dashboard PT-only chrome)

**Major issue:** S1-S6 sections, KPI cards, charts, tables — todos hardcoded em PT (com typos sem acento: "Audiencia", "Engagement Medio", "Tendencia", "Aguardando aprovacao", etc.).

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 58 | `'Audiencia Total'` (KPI) | `admin.comms.kpiAudienceTotal` | `'Total Audience'` | `'Audiencia Total'` |
| 63 | `'Alcance (7d)'` | `admin.comms.kpiReach7d` | `'Reach (7d)'` | `'Alcance (7d)'` |
| 68 | `'Engagement Medio'` | `admin.comms.kpiEngagementAvg` | `'Avg Engagement'` | `'Engagement Promedio'` |
| 73 | `'Posts Totais'` | `admin.comms.kpiPostsTotal` | `'Total Posts'` | `'Posts Totales'` |
| 83 | `'Tendencia por Canal'` | `admin.comms.trendByChannel` | `'Trend by Channel'` | `'Tendencia por Canal'` |
| 84 | `'Audiencia e alcance ao longo do tempo'` | `admin.comms.trendDesc` | `'Audience and reach over time'` | `'Audiencia y alcance a lo largo del tiempo'` |
| 87 | `'Audiencia'` (option) | `admin.comms.metricAudience` | `'Audience'` | `'Audiencia'` |
| 88 | `'Alcance'` (option) | `admin.comms.metricReach` | `'Reach'` | `'Alcance'` |
| 103 | `'Carregando...'` | reuse `common.loading` | reuse | reuse |
| 110 | `'Carregando...'` | reuse | reuse | reuse |
| 117 | `'Aguardando aprovacao da API'` (LinkedIn) | `admin.comms.linkedinPending` | `'Awaiting API approval'` | `'Esperando aprobación de API'` |
| 124 | `'Top Content'` | `admin.comms.topContent` | (keep) | (keep) |
| 125 | `'Posts com melhor performance nos ultimos 30 dias'` | `admin.comms.topContentDesc` | `'Best performing posts in the last 30 days'` | `'Posts con mejor desempeño en los últimos 30 días'` |
| 133 | `'Melhor Horario para Postar'` | `admin.comms.bestTimeTitle` | `'Best Time to Post'` | `'Mejor Hora para Publicar'` |
| 134 | `'Quando seus seguidores do Instagram estao online (por hora do dia)'` | `admin.comms.bestTimeDesc` | `'When your Instagram followers are online (by hour of day)'` | `'Cuándo tus seguidores de Instagram están en línea (por hora del día)'` |
| 146 | `'Historico de Metricas'` | `admin.comms.metricsHistoryTitle` | `'Metrics History'` | `'Historial de Métricas'` |
| 147 | `'Dados diarios por canal (ultimos 14 dias)'` | `admin.comms.metricsHistoryDesc` | `'Daily data by channel (last 14 days)'` | `'Datos diarios por canal (últimos 14 días)'` |
| 150 | `'Exportar CSV'` | `admin.comms.exportCsvBtn` | `'Export CSV'` | `'Exportar CSV'` |
| 151 | `'Exportar PDF'` | `admin.comms.exportPdfBtn` | `'Export PDF'` | `'Exportar PDF'` |
| 155 | `'Carregando...'` | reuse | reuse | reuse |
| 156 | `'Nenhuma metrica encontrada.'` | `admin.comms.noMetrics` | `'No metric found.'` | `'Sin métrica encontrada.'` |
| 160-165 | table headers `'Data' / 'Canal' / 'Audiencia' / 'Alcance' / 'Engagement' / 'Fonte'` | `admin.comms.col.*` | EN | ES |
| 182 | `'Integracao de Canais'` | `admin.comms.channelIntegrationTitle` | `'Channel Integration'` | `'Integración de Canales'` |
| 183 | `'Status de tokens e configuracao de API'` | `admin.comms.channelIntegrationDesc` | `'Token status and API configuration'` | `'Estado de tokens y configuración de API'` |
| 186 | `'Carregando...'` | reuse | reuse | reuse |
| 194 | `'Configurar Canal'` | `admin.comms.configureChannelTitle` | `'Configure Channel'` | `'Configurar Canal'` |
| 199 | placeholder `'YouTube Data API v3 key'` | n/a (technical) | (keep) | (keep) |
| (rest of file) | demais channel modal labels (placeholder strings, save/cancel buttons, validation messages, toast feedbacks) | `admin.comms.channelModal.*` | n/a | n/a |

### 12. `src/pages/admin/comms-ops.astro` — High (410L, contextual handoff PT-only)

**Major issue:** Webinar handoff context, playbook templates, broadcast history columns, history filters — todos PT.

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 17 | `'Acesso restrito a gestao/comunicacao.'` | `admin.commsOps.denied` | `'Access restricted to leadership/communications.'` | `'Acceso restringido a gestión/comunicación.'` |
| 24 | `'Comunicacao'` (h1) | `admin.commsOps.title` | `'Communications'` | `'Comunicación'` |
| 25 | `'Operacional: tarefas, webinars pendentes e historico de disparos'` | `admin.commsOps.subtitle` | `'Operational: tasks, pending webinars, and broadcast history'` | `'Operativo: tareas, webinars pendientes e historial de envíos'` |
| 28 | `'Midia Social →'` | `admin.commsOps.linkSocial` | `'Social Media →'` | `'Redes Sociales →'` |
| 36 | `'Handoff contextual'` | `admin.commsOps.handoffTitle` | `'Contextual handoff'` | `'Handoff contextual'` |
| 41 | `'Voltar para Webinars'` | `admin.commsOps.backWebinars` | `'Back to Webinars'` | `'Volver a Webinars'` |
| 48 | `'Playbook rapido do webinar'` | `admin.commsOps.playbookTitle` | `'Quick webinar playbook'` | `'Playbook rápido del webinar'` |
| 49 | `'Assunto e copy-base para acelerar a comunicacao.'` | `admin.commsOps.playbookDesc` | `'Subject and copy-base to speed up communication.'` | `'Asunto y copy-base para agilizar la comunicación.'` |
| 56 | `'Pipeline de Conteudo'` | `admin.commsOps.pipelineTitle` | `'Content Pipeline'` | `'Pipeline de Contenido'` |
| 64 | `'Webinars pendentes de campanha'` | `admin.commsOps.pendingCampaignsTitle` | `'Webinars awaiting campaign'` | `'Webinars pendientes de campaña'` |
| 65 | `'Webinars confirmados ou realizados que precisam de acao de comunicacao'` | `admin.commsOps.pendingCampaignsDesc` | `'Confirmed or completed webinars needing comms action'` | `'Webinars confirmados o realizados que necesitan acción de comunicación'` |
| 67 | `'Ver todos'` | reuse `common.viewAll` (criar se não existir) | `'View all'` | `'Ver todos'` |
| 75 | `'Calendario de Publicacoes'` | `admin.commsOps.calendarTitle` | `'Publication Calendar'` | `'Calendario de Publicaciones'` |
| 76 | `'Itens do board com data planejada (proximos 30 dias)'` | `admin.commsOps.calendarDesc` | `'Board items with planned date (next 30 days)'` | `'Items del board con fecha planeada (próximos 30 días)'` |
| 90 | `'Historico de Disparos'` | `admin.commsOps.broadcastHistoryTitle` | `'Broadcast History'` | `'Historial de Envíos'` |
| 91 | `'Notificacoes enviadas por tribo'` | `admin.commsOps.broadcastHistoryDesc` | `'Notifications sent by tribe'` | `'Notificaciones enviadas por tribu'` |
| 95 | placeholder `'Buscar assunto, tribo ou remetente'` | `admin.commsOps.broadcastSearchPh` | `'Search subject, tribe or sender'` | `'Buscar asunto, tribu o remitente'` |
| 98 | `'Carregando...'` | reuse `common.loading` | reuse | reuse |
| 99 | `'Nenhum disparo encontrado.'` | `admin.commsOps.noBroadcasts` | `'No broadcast found.'` | `'Sin envío encontrado.'` |
| 103-107 | table headers `'Assunto' / 'Tribo' / 'Destinatarios' / 'Enviado em' / 'Enviado por'` | `admin.commsOps.broadcast.col.*` | EN | ES |
| 168-171 | stageLabel map: `'preparar convite e lembrete' / 'revisar lembrete operacional' / 'organizar follow-up e divulgacao posterior'` | `admin.commsOps.stageLabel.*` | EN | ES |
| 172-173 | template `'Contexto atual: ... do webinar X. Data de referencia: Y.'` | `admin.commsOps.contextTpl` | full EN | full ES |
| 190 | `'Copiar assunto'` | `admin.commsOps.copySubjectBtn` | `'Copy subject'` | `'Copiar asunto'` |
| 191 | `'Copiar mensagem'` | `admin.commsOps.copyMessageBtn` | `'Copy message'` | `'Copiar mensaje'` |
| 195 | `'Assunto sugerido'` | `admin.commsOps.suggestedSubject` | `'Suggested subject'` | `'Asunto sugerido'` |
| 196 | `'Mensagem base'` | `admin.commsOps.baseMessage` | `'Base message'` | `'Mensaje base'` |
| (script ~200-410) | demais playbook/broadcast strings: copy success toast, search filter labels, follow-up date format, broadcast row actions | `admin.commsOps.toast.*`, `admin.commsOps.followup.*` | n/a | n/a |

### 13. `src/pages/admin/webinars.astro` — High (751L)

**Major issue:** TRIBE_NAMES inline + STATUS_LABELS PT-only + nextAction labels + modal forms PT chrome.

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 22 | `'Webinar Governance'` | `admin.webinars.governanceBadge` | (keep) | (keep) |
| 23 | `'Multi-Entity'` | `admin.webinars.multiEntityBadge` | (keep) | (keep) |
| 25 | `'Webinars'` (h1) | reuse `nav.adminWebinars` (existe) | reuse | reuse |
| 26-29 | description paragraph (3 sentences PT) | `admin.webinars.intro` | full EN | full ES |
| 33 | `'+ Novo Webinar'` | `admin.webinars.newWebinarBtn` | `'+ New Webinar'` | `'+ Nuevo Webinar'` |
| 36 | `'Attendance'` (link) | reuse `admin.attendance.title` (existe) | reuse | reuse |
| 46-50 | filter status options `'Todos os status' / 'Planejado' / 'Confirmado' / 'Realizado' / 'Cancelado'` | `admin.webinars.status.*` (`all,planned,confirmed,completed,cancelled`) | EN | ES |
| 53 | `'Todos os capitulos'` | `admin.webinars.allChapters` | `'All chapters'` | `'Todos los capítulos'` |
| 54 | `'Geral (ALL)'` | `admin.webinars.generalLabel` | `'General (ALL)'` | `'General (ALL)'` |
| 64 | `'Acoes prioritarias'` | `admin.webinars.priorityActionsTitle` | `'Priority actions'` | `'Acciones prioritarias'` |
| 65 | `'Proxima acao sugerida por webinar'` | `admin.webinars.priorityActionsDesc` | `'Next suggested action per webinar'` | `'Próxima acción sugerida por webinar'` |
| 74 | `'Proximos webinars'` | `admin.webinars.upcomingTitle` | `'Upcoming webinars'` | `'Próximos webinars'` |
| 80 | `'Fila de follow-up'` | `admin.webinars.followupQueue` | `'Follow-up queue'` | `'Cola de follow-up'` |
| 89 | `'Fluxo operacional'` | `admin.webinars.operationalFlow` | `'Operational flow'` | `'Flujo operacional'` |
| 94 | `'Planejar'` (step 1) | `admin.webinars.flow.plan` | `'Plan'` | `'Planificar'` |
| 95 | `'Crie o webinar aqui com capitulo, tribo e organizador.'` | `admin.webinars.flow.planDesc` | full EN | full ES |
| 99 | `'Confirmar'` (step 2) | `admin.webinars.flow.confirm` | `'Confirm'` | `'Confirmar'` |
| 100 | `'Mude para Confirmado — Comms e lider recebem notificacao.'` | `admin.webinars.flow.confirmDesc` | full EN | full ES |
| 104 | `'Sessao'` (step 3) | `admin.webinars.flow.session` | `'Session'` | `'Sesión'` |
| 105 | `'Crie o evento em Attendance para check-in e presenca.'` | `admin.webinars.flow.sessionDesc` | full EN | full ES |
| 109 | `'Realizar'` (step 4) | `admin.webinars.flow.execute` | `'Execute'` | `'Ejecutar'` |
| 110 | `'Marque como Realizado — follow-up e replay entram na fila.'` | `admin.webinars.flow.executeDesc` | full EN | full ES |
| 114 | `'Publicar'` (step 5) | `admin.webinars.flow.publish` | `'Publish'` | `'Publicar'` |
| 115 | `'Replay em Presentations e Workspace fecha o ciclo.'` | `admin.webinars.flow.publishDesc` | full EN | full ES |
| 123 | `'Todos os webinars'` | `admin.webinars.allWebinarsTitle` | `'All webinars'` | `'Todos los webinars'` |
| 132 | `'Acesso restrito a liderancas, comms, curadoria e facilitadores convidados.'` | `admin.webinars.denied` | full EN | full ES |
| 133 | `'Voltar'` | reuse `common.back` | reuse | reuse |
| 139 | `'Novo Webinar'` (modal title) | reuse `admin.webinars.newWebinarBtn` (without +) | EN | ES |
| 143 | `'Titulo'` | reuse `common.titleField` (criar) | `'Title'` | `'Título'` |
| 147 | `'Descricao'` | reuse `common.descriptionField` (criar) | `'Description'` | `'Descripción'` |
| 152 | `'Data e hora'` | `admin.webinars.dateTimeLabel` | `'Date and time'` | `'Fecha y hora'` |
| 156 | `'Duracao (min)'` | `admin.webinars.durationLabel` | `'Duration (min)'` | `'Duración (min)'` |
| 162 | `'Capitulo PMI'` | `admin.webinars.chapterLabel` | `'PMI Chapter'` | `'Capítulo PMI'` |
| 164 | `'Geral'` | reuse `admin.webinars.generalLabel` | reuse | reuse |
| 173 | `'Status'` | reuse `common.status` | (existe?) | (existe?) |
| 175-178 | status options `'Planejado' / 'Confirmado' / 'Realizado' / 'Cancelado'` | reuse `admin.webinars.status.*` | reuse | reuse |
| 183 | `'Tribo responsavel'` | `admin.webinars.tribeLabel` | `'Responsible tribe'` | `'Tribu responsable'` |
| 185 | `'— Opcional —'` | `admin.webinars.optionalOption` | `'— Optional —'` | `'— Opcional —'` |
| 189 | `'Link da reuniao'` | `admin.webinars.meetingLinkLabel` | `'Meeting link'` | `'Enlace de reunión'` |
| 193 | `'URL do YouTube (replay)'` | `admin.webinars.youtubeUrlLabel` | `'YouTube URL (replay)'` | `'URL de YouTube (replay)'` |
| 197 | `'Observacoes'` | `admin.webinars.notesLabel` | `'Notes'` | `'Observaciones'` |
| 201 | `'Co-gestores'` | `admin.webinars.coManagersLabel` | `'Co-managers'` | `'Co-gestores'` |
| 209 | `'Historico'` | reuse `common.history` (criar) | `'History'` | `'Historial'` |
| 215 | `'Criar sessao Attendance'` | `admin.webinars.createAttendanceSession` | `'Create Attendance session'` | `'Crear sesión Attendance'` |
| 220 | `'Cancelar'` | reuse `common.cancel` | reuse | reuse |
| 223 | `'Salvar'` | reuse `common.save` | reuse | reuse |
| 237-241 | TRIBE_NAMES map: `'Radar Tecnologico' / 'Agentes Autonomos' / 'TMO & PMO do Futuro' / 'Cultura & Change' / 'Talentos & Upskilling' / 'ROI & Portfolio' / 'Governanca & Trustworthy AI' / 'Inclusao & Colaboracao'` | reuse from DB jsonb `tribes.name_i18n` (já existe) — refactor a usar `tribesCatalog.buildTribeLabel({...t, name: t.name_i18n?.[langKey]})` | reuse | reuse |
| 243-244 | STATUS_LABELS PT — already mapped above | reuse `admin.webinars.status.*` | reuse | reuse |
| 297 | `'Confirmar webinar'` (action) | `admin.webinars.action.confirm` | `'Confirm webinar'` | `'Confirmar webinar'` |
| 300 | `'Criar sessao Attendance'` (action) | reuse | reuse | reuse |
| 303 | `'Adicionar link da reuniao'` | `admin.webinars.action.addMeetingLink` | `'Add meeting link'` | `'Añadir enlace de reunión'` |
| 306 | `'Preparar divulgacao'` | `admin.webinars.action.prepareDistribution` | `'Prepare distribution'` | `'Preparar divulgación'` |
| 309 | `'Marcar como realizado'` | `admin.webinars.action.markCompleted` | `'Mark as completed'` | `'Marcar como realizado'` |
| 312 | `'Publicar replay'` | `admin.webinars.action.publishReplay` | `'Publish replay'` | `'Publicar replay'` |
| 315 | `'Follow-up Comms'` | `admin.webinars.action.followupComms` | `'Comms follow-up'` | `'Follow-up Comms'` |
| 317 | `'Completo'` | `admin.webinars.action.complete` | `'Complete'` | `'Completo'` |
| 330-333 | stat cards `'Planejados' / 'Confirmados' / 'Realizados' / 'Total presentes'` | `admin.webinars.stats.*` | EN | ES |
| 346 | `'Geral' / 'PMI-' + chapter_code` | `admin.webinars.generalLabel` (above) | reuse | reuse |
| 349-350 | `'Sessao vinculada' / 'Sem sessao'` | `admin.webinars.session.linked` / `.notLinked` | EN | ES |
| 352 | `'Co-gestores: ...'` | `admin.webinars.coManagersPrefix` | `'Co-managers: '` | `'Co-gestores: '` |
| 354 | `'Replay'` | `admin.webinars.replayBtn` | `'Replay'` | `'Replay'` |
| 355 | `'Entrar'` | `admin.webinars.joinBtn` | `'Join'` | `'Entrar'` |
| 369 | `'X presentes'` (template) | `admin.webinars.attendeesCountTpl` | `'{n} attendees'` | `'{n} asistentes'` |
| 370 | `'Org: '` | `admin.webinars.organizerPrefix` | `'Org: '` | `'Org: '` |
| 373 | `'Card: '` (board item) | `admin.webinars.cardPrefix` | `'Card: '` | `'Card: '` |
| 379 | `'Editar'` | reuse `common.edit` | reuse | reuse |
| 381 | `'Comms'` | n/a (keep brand) | (keep) | (keep) |
| (rest) | demais form save/error toasts, modal lifecycle messages | `admin.webinars.toast.*` | n/a | n/a |

### 14. `src/pages/admin/campaigns.astro` — High (783L)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 56 | `'Filtrar:'` (history) | `admin.campaigns.filterLabel` | `'Filter:'` | `'Filtrar:'` |
| 58 | `'Todas categorias'` | `admin.campaigns.allCategories` | `'All categories'` | `'Todas las categorías'` |
| 59-62 | category options `'Onboarding' / 'Operacional' / 'Comunicado' / 'Newsletter'` | `admin.campaigns.category.{onboarding,operational,announcement,newsletter}` | EN equivalents | ES equivalents |
| 65 | `'Todas origens'` | `admin.campaigns.allSources` | `'All sources'` | `'Todas las orígenes'` |
| 66-69 | source options `'PMI VEP sync (welcomes)' / 'Reagendamento entrevista' / 'Cron failure' / 'Manual'` | `admin.campaigns.source.*` | EN | ES |
| 93 | category select options PT (Operational/Onboarding/Announcement/Newsletter) — duplicate vs filters | reuse `admin.campaigns.category.*` | reuse | reuse |
| 100 | `'Variables'` (already EN) | n/a | (keep) | (keep) |
| 120 | placeholder `'Escreva o conteúdo do email...'` | `admin.campaigns.bodyPlaceholder` | `'Write the email content...'` | `'Escribe el contenido del correo...'` |
| 144 | `'Incluir membros inativos (ex-pesquisadores)'` | `admin.campaigns.includeInactive` | `'Include inactive members (ex-researchers)'` | `'Incluir miembros inactivos (ex-investigadores)'` |
| 149 | placeholder `'researcher, tribe_leader'` | n/a (technical) | (keep) | (keep) |
| 153 | placeholder `'PMI-GO, PMI-CE'` | n/a (technical) | (keep) | (keep) |
| 195 | `'×'` (close icon) | n/a | (keep) | (keep) |
| 381 | toast `'Nome obrigatório'` | reuse `admin.requiredField` (criar) | `'Name required'` | `'Nombre requerido'` |
| 409 | toast `'Template salvo'` | `admin.campaigns.toast.templateSaved` | `'Template saved'` | `'Plantilla guardada'` |
| 432 | empty fallback `'No template.'` (uses `ai18n-nor`, OK) | reuse | reuse | reuse |
| 437 | template card `'Todos os membros ativos'` | `admin.campaigns.allActiveMembersDesc` | `'All active members'` | `'Todos los miembros activos'` |
| 437 | `'Audiência personalizada'` | `admin.campaigns.customAudience` | `'Custom audience'` | `'Audiencia personalizada'` |
| 450 | `'Editar'` | reuse `common.edit` | reuse | reuse |
| 451 | `'Preview'` | n/a (keep) | (keep) | (keep) |
| 452 | `'Enviar →'` | `admin.campaigns.sendBtn` | `'Send →'` | `'Enviar →'` |

### 15. `src/pages/admin/adoption.astro` — High (1016L)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 27 | `'Exportar Relatório'` | `admin.adoption.exportReportBtn` | `'Export Report'` | `'Exportar Reporte'` |
| 32 | tab `'Membros'` | `admin.adoption.tabMembers` | `'Members'` | `'Miembros'` |
| 33 | tab `'👻 Visitantes'` | `admin.adoption.tabVisitors` | `'👻 Visitors'` | `'👻 Visitantes'` |
| 34 | tab `'Analytics'` | `admin.adoption.tabAnalytics` | (keep) | (keep) |
| 54 | `'Status por rota — auto-descoberta via mcp_usage_log'` | `admin.adoption.mcpHealthDesc` | full EN | full ES |
| 61-65 | table headers `'Rota' / 'Calls' / 'OK' / 'Fail' / 'Erro%'` | `admin.adoption.col.*` | EN | ES |
| 100 | column `'Total'` | reuse `common.total` | reuse | reuse |
| 121 | `'Total'` (table) | reuse | reuse | reuse |
| 136 | `'Ciclo de Vida dos Membros'` | `admin.adoption.lifecycleTitle` | `'Member Lifecycle'` | `'Ciclo de Vida de los Miembros'` |
| 140 | `'Stakeholders & Founders'` | `admin.adoption.stakeholdersTitle` | (keep) | (keep) |
| 153 | `'Todos'` | reuse `common.allOption` | reuse | reuse |
| 183 | column `'Nome'` | reuse `common.nameField` | reuse | reuse |
| 189 | column `'Status'` | reuse | reuse | reuse |
| 202 | h2 `'👻 Visitantes Externos'` | `admin.adoption.externalVisitorsTitle` | `'👻 External Visitors'` | `'👻 Visitantes Externos'` |
| 213 | `'LGPD: dados de auth.users — consentidos via login OAuth'` | `admin.adoption.lgpdNote` | full EN | full ES |
| 219-225 | columns Email / Provider / Primeiro Acesso / Último Login / Match / Ação | `admin.adoption.visitor.col.*` | EN | ES |
| 234 | info box (ℹ️ block — long PT text) | `admin.adoption.visitorsInfoBox` | full EN | full ES |
| 242 | h2 `'Analytics'` | (keep) | (keep) | (keep) |
| 243 | `'Dados de uso da plataforma via PostHog'` | `admin.adoption.analyticsDesc` | `'Platform usage data via PostHog'` | `'Datos de uso de la plataforma vía PostHog'` |
| 261 | `'Visitantes Ativos'` | `admin.adoption.activeVisitorsTitle` | `'Active Visitors'` | `'Visitantes Activos'` |
| 263 | `'Sem dados de visitantes'` | `admin.adoption.noVisitorData` | `'No visitor data'` | `'Sin datos de visitantes'` |
| 266 | `'Cliques de Frustracao'` | `admin.adoption.rageClicksTitle` | `'Rage Clicks'` | `'Clics de Frustración'` |
| 274 | `'Paginas Mais Visitadas'` | `admin.adoption.topPagesTitle` | `'Most Visited Pages'` | `'Páginas Más Visitadas'` |
| 276 | `'Sem dados de navegacao'` | `admin.adoption.noNavData` | `'No navigation data'` | `'Sin datos de navegación'` |
| 279 | `'Fontes de Trafego'` | `admin.adoption.trafficSourcesTitle` | `'Traffic Sources'` | `'Fuentes de Tráfico'` |
| 281 | `'Sem dados de referencia'` | `admin.adoption.noReferralData` | `'No referral data'` | `'Sin datos de referencia'` |
| 287 | `'Retencao Semanal'` | `admin.adoption.weeklyRetentionTitle` | `'Weekly Retention'` | `'Retención Semanal'` |
| 293 | `'Detalhes dos insights PostHog'` | `admin.adoption.posthogDetailsLabel` | `'PostHog insights details'` | `'Detalles de insights PostHog'` |
| 319-323 | ROLE_LABELS map (10 entries) — same as in chapter-report and other files | `role.{researcher,tribe_leader,...}` (existem partial) | reuse | reuse |
| 354 | template `'agora' / '${mins}min' / '${hrs}h' / '${days}d' / '${m}m'` | `admin.adoption.relativeTime.*` | EN equivalents | ES equivalents |
| 367-371 | KPI card labels: `'Membros ativos' / 'Ativos 7d' / 'Ativos 30d' / 'Nunca acessou' / 'Sessões/membro'` | `admin.adoption.kpi.*` | EN | ES |
| 367 | `'X com login'` | `admin.adoption.withLoginTpl` | `'{n} with login'` | `'{n} con inicio de sesión'` |
| 384-390 | lifecycle cards `'Total histórico' / 'Ativos C3' / 'Alumni/Inativos' / 'Observers ativos' / 'Retenção C2→C3' / 'Founders ativos'` | `admin.adoption.lifecycle.*` | EN | ES |
| 410-412 | bars `'Sponsors (Presidentes)' / 'Pontos Focais' / 'Founders'` | `admin.adoption.bar.*` | EN | ES |
| 410 | `'X/Y com auth'` | `admin.adoption.withAuthTpl` | `'{n}/{total} with auth'` | `'{n}/{total} con auth'` |
| 483 | MCP card `'MCP (IA Assistente)'` | `admin.adoption.mcpTitle` | `'MCP (AI Assistant)'` | `'MCP (Asistente IA)'` |
| 485-487 | `'Chamadas' / 'Usuarios' / 'Top Tool'` | `admin.adoption.mcp.*` | EN | ES |
| 491 | `'No leader connected yet. MCP server: 64 tools.'` (mixed EN+digit) | `admin.adoption.mcpEmpty` | full EN | full ES |
| 499-501 | `'Chamadas' / 'Usuarios' / '7 dias'` | reuse + `admin.adoption.mcp.7days` | EN | ES |
| 503 | template `'Top: X (Y x, Zuser)'` | `admin.adoption.mcpTopTpl` | n/a | n/a |
| 504 | `'Taxa de erro: X%'` | `admin.adoption.errorRateTpl` | `'Error rate: {n}%'` | `'Tasa de error: {n}%'` |
| 574 | `'Provedores de Auth'` | `admin.adoption.authProvidersTitle` | `'Auth Providers'` | `'Proveedores de Auth'` |
| 575 | `'X sessões de login'` | `admin.adoption.loginSessionsTpl` | `'{n} login sessions'` | `'{n} sesiones de inicio'` |
| 578 | `'X visitante(s) externo(s)'` | `admin.adoption.externalVisitorsTpl` | `'{n} external visitor(s)'` | `'{n} visitante(s) externo(s)'` |
| 579 | `'X com login secundario'` | `admin.adoption.secondaryLoginTpl` | `'{n} with secondary login'` | `'{n} con inicio de sesión secundario'` |
| 657 | toast template `'Erro: '` | reuse `common.errorPrefix` | reuse | reuse |
| 866-869 | KPI cards `'👻 Total Ghosts' / '🕐 Últimos 30d' / '🔗 Match c/ Membro' / '🔑 Top Provider'` | `admin.adoption.ghostKpi.*` | EN | ES |
| 868 | `'login duplicado?'` | `admin.adoption.duplicateLogin` | `'duplicate login?'` | `'¿inicio duplicado?'` |
| 878 | `'Nenhum visitante externo encontrado'` | `admin.adoption.noVisitors` | `'No external visitor found'` | `'Sin visitante externo'` |
| 889 | tooltip `'Membro existente com mesmo email'` | `admin.adoption.duplicateEmailTooltip` | `'Existing member with same email'` | `'Miembro existente con mismo correo'` |
| 892 | `'Vincular auth'` | `admin.adoption.linkAuthBtn` | `'Link auth'` | `'Vincular auth'` |
| 893 | `'Candidato'` | `admin.adoption.candidateLabel` | `'Candidate'` | `'Candidato'` |
| 907 | template `'Erro: '` | reuse | reuse | reuse |

### 16. `src/pages/admin/cycle-report.astro` — High (572L)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 18 | `'Núcleo de Estudos e Pesquisa em IA & Gerenciamento de Projetos'` | `admin.cycleReport.brandFull` | (keep PT canonical brand?) ou `'AI & PM Study and Research Hub'` | `'Núcleo de Estudios e Investigación en IA y Gestión de Proyectos'` |
| 19 | `'Relatório de Evolução — Ciclo 3 (2026/1)'` | `admin.cycleReport.printTitle` (template) | `'Evolution Report — Cycle 3 (2026/1)'` | `'Reporte de Evolución — Ciclo 3 (2026/1)'` |
| 20 | `'Emitido por: Vitor Maia Rodovalho (Gerente de Projeto)'` | `admin.cycleReport.issuedByTpl` | full EN | full ES |
| 22 | `'Data de geração: '` | `admin.cycleReport.generatedAtLabel` | `'Generated at: '` | `'Fecha de generación: '` |
| 23 | `'Código: '` | `admin.cycleReport.codeLabel` | `'Code: '` | `'Código: '` |
| 40 | `'Evolução C2 → C3'` | `admin.cycleReport.evolutionTitle` | `'C2 → C3 Evolution'` | `'Evolución C2 → C3'` |
| 96 | `'Presença por Tribo'` | `admin.cycleReport.attendanceByTribe` | `'Attendance by Tribe'` | `'Asistencia por Tribu'` |
| 106 | `'Documento gerado automaticamente pela plataforma digital do Núcleo de Estudos e Pesquisa em IA & GP'` | `admin.cycleReport.footerGenerated` | full EN | full ES |
| 107 | `'Verificável via código do relatório'` | `admin.cycleReport.footerVerifiable` | `'Verifiable via report code'` | `'Verificable vía código del reporte'` |
| 108 | `'PMI®, PMBOK®, PMP® e PMI-CPMAI™ são marcas registradas do PMI, Inc.'` | `admin.cycleReport.footerTrademarks` | full EN | full ES |
| 139-142 | KPI labels `'Membros Ativos' / 'Artigos em Pipeline' / 'Horas de Participação' / 'CPMAI Certificados'` | `admin.cycleReport.kpi.*` | EN | ES |
| 173 | `'Falha ao gerar relatório do ciclo.'` | `admin.cycleReport.errorMsg` | `'Failed to generate cycle report.'` | `'Error al generar el reporte del ciclo.'` |

### 17. `src/pages/admin/chapter-report.astro` — High (338L)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 100-104 | ROLE_LABELS map (8 entries: `'Pesquisador' / 'Líder de Tribo' / 'Líder de Comunicação' / 'Gerente' / 'Vice-Gerente' / 'Comunicador' / 'Facilitador' / 'Convidado' / 'Sem papel'`) | reuse `role.*` keys (existem) | reuse | reuse |
| 127 | toast `'Erro: '` | reuse `common.errorPrefix` | reuse | reuse |
| 139-142 | KPI labels `'Membros Ativos' / 'Artigos em Pipeline' / 'Horas de Participação' / 'CPMAI Certificados'` | `admin.chapterReport.kpi.*` | EN | ES |
| 139 | template `'de X'` | `admin.chapterReport.ofTotalTpl` | `'of {n}'` | `'de {n}'` |
| 140 | template `'X aprovados'` | `admin.chapterReport.approvedCountTpl` | `'{n} approved'` | `'{n} aprobados'` |
| 141 | template `'X eventos'` | `admin.chapterReport.eventsCountTpl` | `'{n} events'` | `'{n} eventos'` |
| (rest) | role percentage labels, role bars, tribe badges — most use t() already | n/a | n/a | n/a |

### 18. `src/pages/admin/sustainability.astro` — High (820L, mostly clean but with key gaps)

**Note:** mostly i18n-clean via `t('sustainability.*')`. Issues identified:

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 128 | filter `<option value="">Todas</option>` | reuse `common.allOption` | reuse | reuse |
| 132 | `'De'` (date filter) | `sustainability.dateFromLabel` | `'From'` | `'Desde'` |
| 136 | `'Até'` | `sustainability.dateToLabel` | `'To'` | `'Hasta'` |
| 139 | `'Filtrar'` button | `sustainability.filterBtn` | `'Filter'` | `'Filtrar'` |
| 174-177 | revenue filter same `'Todas'` / `'Filtrar'` | reuse | reuse | reuse |
| 201 | `' — Ciclo 3'` (literal in title) | move to template `sustainability.tabTargetsTpl` (`'{tab} — Cycle 3'`) | `' — Cycle 3'` | `' — Ciclo 3'` |
| 234-242 | paid-by select options: `'Zero-cost (gratuito)' / 'PMI-GO Chapter' / 'PMI-CE Chapter' / 'PMI-DF Chapter' / 'PMI-MG Chapter' / 'PMI-RS Chapter' / 'Membro' / 'Patrocinador'` | `sustainability.paidBy.*` (`zero_cost`, `chapter_*`, `member`, `sponsor`) | EN | ES |
| 444 | `'A definir'` (KPI fallback) | `sustainability.toBeDefined` | `'TBD'` | `'A definir'` |
| 451 | `'Meta: '` (target) | reuse `common.targetLabel` (criar) | `'Target: '` | `'Meta: '` |
| 451 | `'Atual: '` (current) | reuse `common.currentLabel` | `'Current: '` | `'Actual: '` |
| 482-495 | projection cards `'YTD Total' / 'Média Mensal' / 'Custo/Membro/Mês' / 'X meses' / 'X membros'` | `sustainability.projection.*` | EN | ES |
| 512-515 | table headers `'Mês' / 'Custo Projetado' / 'Custo/Membro' / 'Acumulado'` | `sustainability.projTable.col.*` | EN | ES |
| 530 | fallback `'No items.'` (already EN) | reuse | reuse | reuse |
| 575 | tooltip `'Excluir'` | reuse `common.delete` (existe?) | reuse | reuse |
| 584 | confirm prompt `'Tem certeza que deseja excluir este registro?'` | reuse `common.confirmDelete` (criar) | `'Are you sure you want to delete this record?'` | `'¿Estás seguro de eliminar este registro?'` |
| 589 | toast `'Registro excluído!'` | `sustainability.toast.deleted` | `'Record deleted!'` | `'¡Registro eliminado!'` |
| 612 | fallback `'No records.'` | reuse `sustainability.noRecords` (existe) | reuse | reuse |
| 638 | confirm prompt | reuse | reuse | reuse |
| 643 | toast | reuse | reuse | reuse |
| 656 | `'Fórmula: '` (KPI) | `sustainability.formulaLabel` | `'Formula: '` | `'Fórmula: '` |
| 660 | `'Meta'` (label) | reuse `common.targetLabel` | reuse | reuse |
| 667 | `'Atual'` (label) | reuse `common.currentLabel` | reuse | reuse |
| 672 | `'Notas'` | `sustainability.notesLabel` | reuse `sustainability.notes` (já existe?) | reuse |
| 677 | `'Salvar'` | reuse `common.save` | reuse | reuse |
| 693 | toast `'Meta atualizada!'` | `sustainability.toast.targetUpdated` | `'Target updated!'` | `'¡Meta actualizada!'` |
| 714, 719 | `'Todas'` (filter dropdowns) | reuse | reuse | reuse |
| 783 | toast `'Preencha todos os campos obrigatórios'` | reuse `admin.fillRequiredFields` (criar) | `'Fill all required fields'` | `'Completa todos los campos requeridos'` |
| 788 | toast `'Custo registrado!'` | `sustainability.toast.costSaved` | `'Cost recorded!'` | `'¡Costo registrado!'` |
| 804 | toast same as above | reuse | reuse | reuse |
| 809 | toast `'Receita registrada!'` | `sustainability.toast.revenueSaved` | `'Revenue recorded!'` | `'¡Ingreso registrado!'` |

### 19. `src/pages/admin/publications.astro` — High (605L)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 46 | `'Status'` (label) | reuse `common.status` | reuse | reuse |
| 48 | `'Todos'` | reuse `common.allOption` | reuse | reuse |
| 60 | `'Tribo'` | reuse `common.tribe` (criar) | `'Tribe'` | `'Tribu'` |
| 62 | `'Todas'` | reuse `common.allOptionFem` (criar) | reuse | reuse |
| 65 | `'Filtrar'` | reuse | reuse | reuse |
| 81 | column `'Título'` | reuse | reuse | reuse |
| 84 | column `'Status'` | reuse | reuse | reuse |
| 117 | label `'Título'` | reuse | reuse | reuse |
| 142 | label `'URL do CFP'` | `publications.cfpUrlLabel` | `'CFP URL'` | `'URL del CFP'` |
| 152 | `'Tribo'` | reuse | reuse | reuse |
| (script ~190+) | STATUS_COLORS, status badge mappings, modal detail strings, toasts (`'Submissão criada'` / `'Status atualizado'` / etc.) | `publications.toast.*` | n/a | n/a |

### 20. `src/pages/admin/partnerships.astro` — High (514L)

**Mostly clean i18n** but inline status options + interaction-type select PT.

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 22 | `'Pipeline'` | n/a (keep) | (keep) | (keep) |
| 23 | `'CRUD'` | n/a (technical) | (keep) | (keep) |
| 41-48 | type options: `'PMI Chapter' / 'Academia' / 'Academic' / 'Governo' / 'Empresa' / 'Community' / 'Research' / 'Association' / 'Outro'` | `partnerships.type.*` | EN | ES |
| 53-57 | status options `'Prospect' / 'Contact' / 'Negotiation' / 'Active' / 'Inactive' / 'Churned'` | `partnerships.status.*` (some EN already in DB schema) | (keep EN) | (keep EN) |
| 77-85 | duplicate type options in modal | reuse same keys | reuse | reuse |
| 99-105 | modal status options | reuse | reuse | reuse |
| 129-134 | interaction-type select PT options: `'Email' / 'WhatsApp' / 'LinkedIn'` (technical, keep) + `'Call' / 'Meeting' / 'Note'` (already use t() partially) | partial reuse | reuse | reuse |
| 149 | `'Timeline'` | n/a (keep) | (keep) | (keep) |
| 190-196 | TYPE_LABELS PT map | reuse `partnerships.type.*` | reuse | reuse |

### 21. `src/pages/admin/pilots.astro` — High (493L)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 171 | `'Timeout — recarregue a página.'` | `admin.pilots.timeout` | `'Timeout — reload the page.'` | `'Timeout — recarga la página.'` |
| 297 | toast `'Error saving pilot'` (already EN) | reuse | reuse | reuse |
| 318 | toast `'Error deleting pilot'` (already EN) | reuse | reuse | reuse |
| 382 | `'Sem métricas definidas'` | `admin.pilots.noMetricsDefined` | `'No metrics defined'` | `'Sin métricas definidas'` |
| 407 | label `'Hipótese:'` | reuse `pilots.hypothesis` (existe) + add `:` separator | reuse | reuse |
| 408 | label `'Problema:'` | reuse `pilots.problem` (existe) | reuse | reuse |
| 409 | label `'Escopo:'` | reuse `pilots.scope` (existe) | reuse | reuse |
| 412 | `'Ver Board →'` | `admin.pilots.viewBoardBtn` | `'View Board →'` | `'Ver Board →'` |
| 488 | error msg `'Error loading pilots'` (already EN) | reuse | reuse | reuse |

### 22. `src/pages/admin/settings.astro` — High (422L)

**Mostly i18n-clean.** Issues:

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 27 | `'Altere e salve. Apenas Superadmin pode editar.'` | `admin.settings.parametersHint` | `'Change and save. Only Superadmin can edit.'` | `'Cambia y guarda. Solo Superadmin puede editar.'` |
| 41 | label `'Webhook URL'` | reuse `admin.settings.webhookUrlLabel` (criar) | `'Webhook URL'` | `'Webhook URL'` |
| 67 | `'Criar, editar e definir ciclo ativo.'` | `admin.settings.cycleManagementHint` | `'Create, edit, and set the active cycle.'` | `'Crear, editar y definir el ciclo activo.'` |
| 92 | label `'Nome'` (cycle modal) | reuse `common.nameField` | reuse | reuse |
| 101 | label `'Cor'` | `admin.settings.colorLabel` | `'Color'` | `'Color'` |
| 121 | `'Salvar'` (cycle modal) | reuse `common.save` | reuse | reuse |
| 241 | `'Ativo'` (badge) | `admin.settings.activeBadge` | `'Active'` | `'Activo'` |
| 243 | `'em andamento'` | `admin.settings.inProgress` | `'in progress'` | `'en curso'` |
| 246 | `'Ativar'` (button) | `admin.settings.activateBtn` | `'Activate'` | `'Activar'` |
| 247 | `'Editar'` | reuse `common.edit` | reuse | reuse |
| 248 | `'Excluir'` | reuse `common.delete` | reuse | reuse |
| 265 | confirm prompt template `'Definir "X" como ciclo ativo?'` | `admin.settings.confirmActivateCycleTpl` | `'Set "{code}" as active cycle?'` | `'¿Definir "{code}" como ciclo activo?'` |
| 269 | toast `'Ciclo ativo atualizado'` | `admin.settings.toast.cycleActiveUpdated` | `'Active cycle updated'` | `'Ciclo activo actualizado'` |
| 271, 284 | toast `'Erro: '` | reuse `common.errorPrefix` | reuse | reuse |
| 278 | confirm template `'Excluir ciclo "X"? Esta ação não pode ser desfeita.'` | `admin.settings.confirmDeleteCycleTpl` | `'Delete cycle "{code}"? This action cannot be undone.'` | `'¿Eliminar ciclo "{code}"? Esta acción no puede deshacerse.'` |
| 282 | toast `'Ciclo excluído'` | `admin.settings.toast.cycleDeleted` | `'Cycle deleted'` | `'Ciclo eliminado'` |
| 296 | modal title `'Editar Ciclo'` / `'Novo Ciclo'` | reuse `admin.settings.cycleNewTitle` (existe) + `cycleEditTitle` | EN | ES |
| 324 | toast `'Preencha código, nome, abreviação e data início'` | `admin.settings.cycleRequired` | full EN | full ES |
| 343 | toast `'Ciclo atualizado' / 'Ciclo criado'` | `admin.settings.toast.cycle{Updated,Created}` | EN | ES |
| 362-364 | SETTING_LABELS map: `'Pesquisadores por tribo' / 'Máximo de tribos ativas' / 'Grace period baseline (dias)'` + 3 desc strings | `admin.settings.platformLabel.*` (3 keys) + `admin.settings.platformDesc.*` (3 keys) | EN | ES |
| 383 | `'Último ajuste: '` | `admin.settings.lastAdjusted` | `'Last adjusted: '` | `'Último ajuste: '` |
| 387 | button `'Salvar'` | reuse `common.save` | reuse | reuse |
| 396 | prompt `'Razão da alteração (obrigatório):'` | `admin.settings.changeReasonPrompt` | `'Reason for change (required):'` | `'Razón del cambio (requerido):'` |
| 397 | toast `'Razão obrigatória.'` | `admin.settings.reasonRequired` | `'Reason required.'` | `'Razón requerida.'` |
| 402 | toast `'Configuração atualizada!'` | `admin.settings.toast.configUpdated` | `'Configuration updated!'` | `'¡Configuración actualizada!'` |

### 23. `src/pages/admin/governance-v2.astro` — High (295L)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 22 | `'Change Requests & Boards'` | `admin.governance.subtabCRs` | (keep) | (keep) |
| 25 | `'Ratificação de documentos (IP)'` | `admin.governance.subtabIpDocs` | `'IP Document Ratification'` | `'Ratificación de Documentos (PI)'` |
| 30 | `'👁 Preview Stakeholder'` | `admin.governance.previewStakeholder` | `'👁 Stakeholder Preview'` | `'👁 Preview Stakeholder'` |
| 70 | `'Acesso restrito a gestão de projeto.'` | `admin.governance.deniedPM` | `'Access restricted to project management.'` | `'Acceso restringido a gestión de proyecto.'` |
| 73 | `'Governança de Boards Arquivados'` | `admin.governance.archivedBoardsTitle` | `'Archived Boards Governance'` | `'Gobernanza de Boards Archivados'` |
| 108 | fallback `'Sem título'` | `admin.governance.noTitle` | `'No title'` | `'Sin título'` |
| 109 | fallback `'Board' / 'scope' / 'domain'` | n/a (technical placeholders) | (keep) | (keep) |
| 111 | `'Restaurar'` button | reuse `common.restore` (criar) | `'Restore'` | `'Restaurar'` |
| 127 | RPC reason `'Restored from board governance page'` (server-side, EN already) | (keep) | (keep) | (keep) |
| 144 | denied msg `'Acesso restrito a gestão de projeto.'` | reuse `admin.governance.deniedPM` | reuse | reuse |
| 168 | toast `'Card restaurado com sucesso.'` | `admin.governance.toast.restored` | `'Card successfully restored.'` | `'Card restaurado exitosamente.'` |
| 171 | toast `'Falha ao restaurar card.'` | `admin.governance.toast.restoreFailed` | `'Failed to restore card.'` | `'Error al restaurar card.'` |
| (orgChart section ~180-294) | mostly uses `oc('i18n-oc-*')` keys (already i18n) | reuse existing | reuse | reuse |
| 230 | `'GP' / 'Deputy'` (badge extras for tier1) | `admin.governance.role.{gp,deputy}` | EN | ES |
| 265 | `'inativa'` (curator) | `admin.governance.inactive` | `'inactive'` | `'inactiva'` |
| 287 | template `'⚠️ X stakeholders sem auth'` | `admin.governance.stakeholderGapTpl` | `'⚠️ {n} stakeholders without auth'` | `'⚠️ {n} stakeholders sin auth'` |

### 24. `src/pages/admin/initiative-kinds.astro` — High (319L)

**Issues confirmed:**

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 10 | breadcrumb `'Operações'` | reuse `admin.breadcrumb.operations` | reuse | reuse |
| 45 | label `'Slug'` | n/a (technical) | (keep) | (keep) |
| 76 | `'Board'` | n/a | (keep) | (keep) |
| 121-122 | FLAG_LABELS map: `'Board' / 'Atas' / 'Entregas' / 'Presença' / 'Certificado'` | `admin.initiativeKinds.flag.*` | EN | ES |
| 150 | `'Nenhum tipo cadastrado.'` | `admin.initiativeKinds.empty` | `'No kind registered.'` | `'Sin tipo registrado.'` |
| 176 | `'Editar'` | reuse `common.edit` | reuse | reuse |
| 191 | `'Erro ao carregar.'` | reuse `admin.loadError` (existe) | reuse | reuse |
| 198 | modal title template `'Editar Tipo' / 'Novo Tipo'` | `admin.initiativeKinds.modal.{edit,new}Title` | `'Edit Kind' / 'New Kind'` | `'Editar Tipo' / 'Nuevo Tipo'` |
| 231 | toast `'Slug e nome são obrigatórios'` | `admin.initiativeKinds.slugNameRequired` | `'Slug and name are required'` | `'Slug y nombre son requeridos'` |
| 237 | toast `'Slug deve ser snake_case (ex: book_club)'` | `admin.initiativeKinds.slugFormat` | `'Slug must be snake_case (e.g., book_club)'` | `'Slug debe ser snake_case (ej., book_club)'` |
| 245 | toast `'JSON inválido em campos customizados'` | `admin.initiativeKinds.invalidJson` | `'Invalid JSON in custom fields'` | `'JSON inválido en campos personalizados'` |
| 268 | toast `'Tipo atualizado'` | `admin.initiativeKinds.toast.updated` | `'Kind updated'` | `'Tipo actualizado'` |
| 271 | toast `'Tipo criado'` | `admin.initiativeKinds.toast.created` | `'Kind created'` | `'Tipo creado'` |

### 25. `src/pages/admin/index.astro` — Medium (98L)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 36 | `'Próxima Reunião Geral'` | `admin.index.nextGeneralMeeting` | `'Next General Meeting'` | `'Próxima Reunión General'` |
| 37 | `'Cria evento type=geral em last+14 dias. Reusa Meet recorrente; YouTube live opcional.'` | `admin.index.nextGeneralMeetingDesc` | full EN | full ES |
| 41 | `'Criar próxima quinzenal'` | `admin.index.createBiweeklyBtn` | `'Create next biweekly'` | `'Crear próxima quincenal'` |
| 55 | prompt `'Meet URL (obrigatório, ex: ...):'` | `admin.index.meetUrlPrompt` | `'Meet URL (required, e.g., ...):'` | `'URL de Meet (requerida, ej., ...):'` |
| 57 | prompt `'YouTube live URL (opcional, deixe em branco se ainda não existir):'` | `admin.index.youtubeUrlPrompt` | full EN | full ES |
| 59 | `'Criando...'` (button text) | `admin.index.creating` | `'Creating...'` | `'Creando...'` |
| 70 | template `'Criado: <strong>X</strong> em <strong>Y</strong>'` | `admin.index.createdSuccess` (template) | `'Created: {title} on {date}'` | `'Creado: {title} en {date}'` |
| 76 | template `'Erro: '` | reuse `common.errorPrefix` | reuse | reuse |
| 80 | `'Criar próxima quinzenal'` (reset) | reuse | reuse | reuse |
| 93 | `'Acesso restrito a administradores.'` | `admin.deniedAdmins` | `'Access restricted to administrators.'` | `'Acceso restringido a administradores.'` |

### 26. `src/pages/admin/blog.astro` — Medium (298L)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 42 | label `'Slug'` | n/a (technical) | (keep) | (keep) |
| 48-51 | category options `'Case Study' / 'Tutorial' / 'Announcement' / 'Opinion'` (technical EN) | (keep) | (keep) | (keep) |
| 66 | label `'Tags (comma separated)'` | `admin.blog.tagsLabel` | (keep) | `'Etiquetas (separadas por coma)'` |
| 200 | toast `'Slug obrigatório'` (uses t() partial) | reuse `admin.blog.slugRequired` (existe?) | reuse | reuse |

### 27. `src/pages/admin/tribe/[id].astro` — Medium (71L)

| Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|
| 13 | breadcrumbs `'Pessoas' / 'Tribo'` | reuse `admin.breadcrumb.people` (existe) + reuse `admin.tribe.crumb` (criar) | EN | ES |
| 31 | `'Carregando...'` | reuse `common.loading` | reuse | reuse |

### 28. `src/pages/admin/data-health.astro`, `tags.astro`, `knowledge.astro` — Medium (delegate but PT denied msg)

| File | Line | Current string | Suggested key | EN-US | ES-LATAM |
|---|---|---|---|---|---|
| data-health | 26 | `'Acesso restrito a administradores.'` | reuse `admin.deniedAdmins` | reuse | reuse |
| tags | 26 | (same) | reuse | reuse | reuse |
| knowledge | 27 | (same — uses `deniedMsg` define:vars) | already i18n via `t('admin.knowledge.denied')` | reuse | reuse |

### 29. `src/pages/admin/audit-log.astro`, `members.astro`, `chapter.astro`, `ai-calibration.astro`, `report.astro`, `curatorship.astro`, `analytics.astro`, `portfolio.astro`, `board/[id].astro`, `governance/documents.astro` — Clean

These are well-structured i18n delegates. Already use either:
- React island with i18n props (`<MemberListIsland />`, `<DataHealthIsland />`, etc.)
- Pre-built i18n bundle via `buildPageI18n()` + `<script id="page-i18n">` (consumed by usePageI18n() hooks in islands)
- Direct `t()` calls in SSR + define:vars for client scripts

No action needed. (Caveat: these delegate to React islands; islands themselves likely have their own scoped i18n issues — not in this scope.)

---

## Components admin compartilhados (não scaneados em profundidade)

Identificados como possivelmente contendo hardcoded strings (referenciados pelas pages):

- `src/components/admin/dashboard/AdminDashboardIsland.tsx`
- `src/components/admin/PlatformHealthWidget.tsx`
- `src/components/admin/SyncHealthWidget.tsx`
- `src/components/admin/VolunteerComplianceWidget.tsx`
- `src/components/admin/CrossTribeWidget.tsx`
- `src/components/admin/ResearchPipelineWidget.tsx`
- `src/components/admin/CommsDashboard.tsx`
- `src/components/admin/GovernanceAdminIsland.tsx`
- `src/components/admin/BoardMembersPanel.tsx`
- `src/components/admin/VolunteerAgreementPanel.tsx`
- `src/components/admin/blog/BlogEditorIsland.tsx`
- `src/components/admin/audit/AuditLogIsland.tsx`
- `src/components/admin/members/MemberListIsland.tsx`
- `src/components/admin/members/MemberDetailIsland.tsx`
- `src/components/admin/members/InactiveCandidatesIsland.tsx`
- `src/components/admin/DataHealthIsland.tsx`
- `src/components/admin/TagManagementIsland.tsx`
- `src/components/admin/KnowledgeIsland.tsx`
- `src/components/admin/AiCalibrationIsland.tsx`
- `src/components/portfolio/PortfolioDashboard.tsx`
- `src/components/portfolio/PlannedVsActualSection.tsx`
- `src/components/governance/ReviewChainIsland.tsx`
- `src/components/governance/ChainAuditReportIsland.tsx`
- `src/components/governance/ChainPDFExportIsland.tsx`
- `src/components/governance/ChainDocxExportIsland.tsx`
- `src/components/governance/DocumentVersionEditor.tsx`
- `src/components/selection/DiversityDashboard.tsx`
- `src/components/boards/CuratorshipBoardIsland.tsx`
- `src/components/islands/BoardEngine.tsx`
- `src/components/islands/CrossTribeIsland.tsx`
- `src/components/islands/TribeDashboardIsland.tsx`
- `src/components/islands/PartnerPipelineIsland.tsx`
- `src/components/chapter/ChapterDashboard.tsx`

**Recomendação:** sweep separado em components admin por domínio. Most components consume `usePageI18n(['namespace'], lang)` hooks — verificar cobertura por namespace nos 3 dictionaries.

---

## Duplicações detectadas (mesma string em N+ pages — candidata a key shared)

- **`'Carregando...'`** — duplicado em 5+ admin pages (comms, comms-ops, partnerships, tribe/[id], pilots, settings, sustainability, publications). Já existe `common.loading`. Replace inline.
- **`'Salvar'` / `'Save'`** — duplicado em 10+ pages (sustainability, settings, webinars, partnerships, pilots, blog, etc.). Já existe `common.save`. Replace inline.
- **`'Cancelar'` / `'Cancel'`** — duplicado em 8+ pages. Já existe `common.cancel`. Replace inline.
- **`'Editar'` / `'Edit'`** — duplicado em 6+ pages (sustainability, settings, partnerships, pilots, initiative-kinds, webinars). Já existe `common.edit`. Replace inline.
- **`'Excluir'` / `'Delete'`** — duplicado em 4+ pages. Já existe `common.delete`. Replace inline.
- **`'Erro: '`** — toast prefix duplicado em 10+ pages. Criar `common.errorPrefix` (template `'{msg}'`) + replace inline.
- **`'Todos'` / `'Todas'` / `'All'`** — duplicado em 8+ filter dropdowns (campaigns, comms-ops, partnerships, sustainability, publications, adoption, selection, webinars). Criar `common.allOption` + `common.allOptionFem` (PT gendered).
- **`'Filtrar'` / `'Filter'`** — duplicado em 5+ pages (sustainability, comms-ops, publications). Criar `common.filterBtn`.
- **`'De' / 'Até'`** (date range) — sustainability + adoption + selection. Criar `common.dateFrom` / `common.dateTo`.
- **`'Status'`** (column header / label) — 8+ pages. Já existe `common.status`? confirmar e reuse.
- **`'Erro ao carregar.'`** — duplicado. Já existe `admin.loadError`. Replace inline.
- **`'Tem certeza...?'`** confirm prompts — duplicado em pelo menos 3 (sustainability cost/revenue, settings cycle delete, partnerships delete). Criar `common.confirmDelete` template.
- **ROLE_LABELS map**: `'Pesquisador' / 'Líder de Tribo' / 'Líder de Comunicação' / 'Gerente' / 'Vice-Gerente' / 'Comunicador' / 'Facilitador' / 'Convidado' / 'Sponsor' / 'Chapter Liaison' / 'Sem papel'` — duplicado em **adoption.astro:319-323** + **chapter-report.astro:100-104** + parcial em **selection.astro:397**. Já existem keys `role.*` na maioria. Replace inline com lookup helper.
- **STATUS_LABELS map** (selection 408-415, webinars 243-244, partnerships ~199-200, publications ~196-203): cada page tem seu próprio. Consolidar em `<feature>.status.*` namespacing já estabelecido — replace inline.
- **`'Operações' / 'Operations'` / `'Governança' / 'Governance'`** — breadcrumb duplicado em 6+ governance/* pages. Já existe `admin.breadcrumb.operations` (verificado em vários files). PT-only governance subdir pages (ip-ratification, documents/[chainId]/*, versions/new) precisam migrar para reuse.

---

## Convenção sugerida pra novas keys (admin scope)

### Namespace por seção
- **Por página:** `admin.<section>.*` (ex: `admin.selection.*`, `admin.webinars.*`, `admin.commsOps.*`)
- **Sub-namespacing por componente:** `admin.<section>.<feature>.*` (ex: `admin.selection.kanban.*`, `admin.webinars.flow.*`, `admin.adoption.kpi.*`)
- **Por elemento estrutural:** `admin.<section>.{title,subtitle,denied,empty,loading,col,modal,toast,confirm,filter,action,status,role,kpi}` — convenção já estabelecida
- **Compartilhadas:** `common.*` (ex: `common.loading`, `common.save`, `common.errorPrefix`, `common.allOption`, `common.confirmDelete`)

### Templates com placeholders (admin scope)
- `'X selecionado(s)'` → `admin.<section>.bulkCount` template `'{n} selected'`
- `'há X dias'` → reuse `common.time.daysAgo` (proposto em Ω-A)
- `'X resultado(s)'` → `admin.<section>.resultsCount` template `'{n} result(s)'`
- Mais templates: `'X de Y'` → `'{n} of {total}'`; `'Definir "X" como ciclo ativo?'` → `'Set "{code}" as active cycle?'`; `'Excluir ciclo "X"? Esta ação não pode ser desfeita.'` → confirm template

### Anti-pattern a evitar
- `STATUS_LABELS = { submitted: 'Submetido', ... }` mapas inline PT-only — sempre migrar para `t()` com lookup helper (já fazemos isso parcialmente em `governance/documents.astro` via gateLabels — mas é inline lang dict que é ele próprio anti-pattern leve)
- ROLE_LABELS, TYPE_LABELS, FLAG_LABELS hardcoded inline — extract to dictionary lookups
- Mixed PT/EN strings (e.g., comms.astro line 491: `'No leader connected yet. MCP server: 64 tools.'` — half EN half hardcoded number)
- Inline strings para format placeholders (ex: `'YouTube Data API v3 key'`) — keep technical placeholders, mas PT-text placeholders (`'PMI Global Summit 2026'`) devem usar `t()` ou ser brand-canonical
- Confirm prompts hardcoded (`'Tem certeza...'`, `'Deseja...'`) — sempre template via i18n
- Error fallbacks hardcoded (`'Erro: '`, `'Falha ao...'`) — sempre via key

---

## Recomendações de priorização para sweep aplicação

### Fase 1 (Critical — vai pra demo PMI international)
1. **`governance/ip-ratification.astro`** — refactor 100% PT inline → adicionar `t()` calls + reuse `governance.docs.status*` keys que já existem em `governance/documents.astro`. ~20 strings, 1-2h.
2. **`governance/documents/[chainId].astro`** + **`audit-report.astro`** + **`export-pdf.astro`** + **`export-docx.astro`** + **`versions/new.astro`** — 5 wrapper pages com PT-only breadcrumbs (4-5 strings cada). Criar `admin.governance.{review,auditReport,exportPdf,exportDocx,newVersion}.*` namespaces. ~30 strings totais, 1h.
3. **`member/[id].astro`** + **`members/[id].astro`** + **`members/inactive-candidates.astro`** — 3 page de membro com PT breadcrumbs + form labels. `member/[id].astro` é heavy (308L de form inline). ~30-50 strings. 2-3h.

**Fase 1 total:** ~80-100 strings, 4-6h.

### Fase 2 (High — exposição admin/dashboards)
4. **`comms.astro`** — KPI cards + section titles + descriptions + table headers + channel modal. ~40 strings, 2h.
5. **`comms-ops.astro`** — Webinar handoff + playbook templates + broadcasts. ~30 strings, 1.5h.
6. **`webinars.astro`** — TRIBE_NAMES (refactor para DB jsonb) + STATUS_LABELS + nextAction + form modal. ~40 strings, 2h.
7. **`campaigns.astro`** — filters + audience + send modal + preview. ~25 strings, 1.5h.
8. **`adoption.astro`** — Tab Visitantes/Analytics + ROLE_LABELS + KPI labels + lifecycle + ghost KPIs. ~50 strings, 2.5h.
9. **`selection.astro`** — STATUS_GROUPS + STATUS_LABELS + ROLE_LABELS + Kanban + bulk + import CSV + committee + modals. **Heavy (3137L).** ~80-120 strings. 4-6h dedicada — considerar break em multiple commits por sub-feature.
10. **`cycle-report.astro`** — Print headers + section titles + KPI cards + footer brand. ~25 strings, 1.5h.
11. **`chapter-report.astro`** — KPI labels + ROLE_LABELS reuse. ~10 strings, 0.5h.
12. **`partnerships.astro`** — type/status options + interaction-type select. ~15 strings, 1h.
13. **`pilots.astro`** — Hipótese/Problema/Escopo headers + timeout/error msgs. ~10 strings, 0.5h.
14. **`sustainability.astro`** — paid-by options + filter buttons + projection table + KPI labels + confirm/toast. ~35 strings, 1.5h.
15. **`settings.astro`** — cycle list buttons + confirm prompts + cycle modal labels + platform_settings labels. ~25 strings, 1.5h.
16. **`governance-v2.astro`** — subtab labels + denied + restore toasts + tier extras (GP/Deputy badges). ~15 strings, 1h.
17. **`initiative-kinds.astro`** — FLAG_LABELS + modal title + slug error toasts. ~15 strings, 1h.

**Fase 2 total:** ~410-470 strings, 22-28h.

### Fase 3 (Medium — polish)
18. **`index.astro`** — 6 strings hardcoded (Próxima Reunião Geral block + denied). 0.5h.
19. **`blog.astro`** — category options + slug placeholder. 0.5h.
20. **`publications.astro`** — filter Status options + modal labels + toasts. ~15 strings, 1h.
21. **`tribe/[id].astro`** — breadcrumbs PT + Carregando. 5 strings, 0.25h.
22. **`data-health.astro`**, **`tags.astro`**: replace `'Acesso restrito a administradores.'` with `t('admin.deniedAdmins')`. 0.25h cada.

**Fase 3 total:** ~30 strings, 2-3h.

### Verify (need closer scan)
- **`selection.astro`** lines 750-3137 (não amostradas): applicant detail modal sections (Info / Avaliações / Entrevista / Decisão / Histórico tabs), score breakdown labels, peer evaluation card text, decision modal labels, CSV import result messages, committee management UI, interview scheduling. **Estimativa: 80-120 strings adicionais.**
- **`comms.astro`** lines 200-768 (Channel modal save handlers + token alerts + stale banner + per-channel config flow toasts). ~30 strings.
- **`webinars.astro`** lines 400-751 (event creation form, lifecycle history, follow-up queue cards, attendance modal). ~40 strings.
- **`comms-ops.astro`** lines 200-410 (calendar render + webinar pending list + broadcast filter). ~20 strings.
- **`adoption.astro`** lines 600-1016 (analytics chart loaders + posthog query helpers + Phase 1 details). ~30 strings.
- **`campaigns.astro`** lines 380-783 (preview modal + analytics modal + send modal validation). ~30 strings.
- All **components admin** in `src/components/admin/` (subset of ~30+ components) — separate sweep recommended.

---

## Estimativa de esforço (admin scope)

- **Fase 1 (critical):** ~6h (8 pages, ~80-100 strings novas + refactor estrutural de ip-ratification 100% PT)
- **Fase 2 (high):** ~28h (14 pages, ~410-470 strings, sweep heavy em selection 3137L)
- **Fase 3 (medium):** ~3h (5 pages, ~30 strings simples)
- **Verify (additional sweeps):** ~10h (selection deep + components admin)
- **Add to dictionaries:** ~340 keys × 3 línguas = ~1020 entries em pt-BR/en-US/es-LATAM
- **Test:** `npx astro build` + visual smoke por página em /pt /en /es + `npm test` (i18n parity test deve passar)

**Total estimado p135 Ω-B admin:** ~37-50h aplicação + 5h dictionaries write + 2h smoke testing.

---

## Recomendação de commit grouping

Sugerido para evitar PR gigante e facilitar review/revert por área:

### Commit 1: Governance critical (Fase 1)
- **Files:** `governance/ip-ratification.astro` + `governance/documents/[chainId].astro` + 4 children (audit-report, export-pdf, export-docx, versions/new)
- **Keys added:** `admin.ipRatification.*` (~25), `admin.governance.{review,auditReport,exportPdf,exportDocx,newVersion}.*` (~30)
- **Risk:** Critical — IP ratification chain UI exposed to liderança PMI.
- **Smoke:** `/admin/governance/ip-ratification`, `/admin/governance/documents/<chainId>` (each subpage), `/en/admin/governance/...`, `/es/admin/governance/...`.

### Commit 2: Member detail pages (Fase 1)
- **Files:** `member/[id].astro` + `members/[id].astro` + `members/inactive-candidates.astro`
- **Keys added:** `admin.memberEdit.*` (~30), `admin.memberDetail.*` (~5), `admin.inactiveCandidates.*` (~3)
- **Risk:** Critical — member CRUD core admin flow.
- **Smoke:** `/admin/member/<id>`, `/admin/members/<id>`, `/admin/members/inactive-candidates` × 3 langs.

### Commit 3: Selection pipeline (Fase 2 heavy)
- **Files:** `selection.astro` (3137L) — split em multiple smaller commits OK:
  - 3a: STATUS_GROUPS + STATUS_LABELS + ROLE_LABELS maps refactor to t()
  - 3b: Kanban + table column headers + quick filters
  - 3c: VEP import CSV section + Committee management
  - 3d: Applicant detail modal (deferred — verify scope first)
- **Keys added:** `admin.selection.*` (~80-120)
- **Risk:** High — selection cycle critical for cycle 4 onboarding.
- **Smoke:** `/admin/selection` (Pipeline / Import / Committee / Diversity tabs) × 3 langs.

### Commit 4: Comms + Webinars + Comms-Ops (Fase 2)
- **Files:** `comms.astro` + `webinars.astro` + `comms-ops.astro`
- **Keys added:** `admin.comms.*` (~40), `admin.webinars.*` (~50), `admin.commsOps.*` (~30)
- **Risk:** Medium-High — comms/webinars are visible to GP + tribe leaders + curators.
- **Smoke:** `/admin/comms`, `/admin/webinars`, `/admin/comms-ops` × 3 langs.

### Commit 5: Reports + Analytics + Adoption (Fase 2)
- **Files:** `cycle-report.astro` + `chapter-report.astro` + `adoption.astro` + `campaigns.astro`
- **Keys added:** `admin.cycleReport.*` (~25), `admin.chapterReport.*` (~10), `admin.adoption.*` (~50), `admin.campaigns.*` (~25)
- **Risk:** Medium — analytical/dashboard pages visible to GP.
- **Smoke:** `/admin/cycle-report`, `/admin/chapter-report`, `/admin/adoption`, `/admin/campaigns` × 3 langs.

### Commit 6: Settings + Governance + Operations (Fase 2)
- **Files:** `settings.astro` + `governance-v2.astro` + `initiative-kinds.astro` + `partnerships.astro` + `pilots.astro` + `sustainability.astro`
- **Keys added:** `admin.settings.*` (~25), `admin.governance.*` (~15), `admin.initiativeKinds.*` (~15), `partnerships.type.*` (~10), `admin.pilots.*` (~10), `sustainability.*` (~35)
- **Risk:** Medium — operational config pages.
- **Smoke:** all 6 pages × 3 langs.

### Commit 7: Polish (Fase 3) + common keys consolidation
- **Files:** `index.astro` + `blog.astro` + `publications.astro` + `tribe/[id].astro` + `data-health.astro` + `tags.astro`
- **Keys added:** `admin.index.*` (~6), `admin.blog.*` (~3), `publications.toast.*` (~5), various reuses, plus new `common.*` keys consolidated (`common.allOption`, `common.allOptionFem`, `common.filterBtn`, `common.dateFrom`, `common.dateTo`, `common.confirmDelete`, `common.errorPrefix`, `common.tribe`, `common.history`, `common.viewAll`, `common.restore`, `common.targetLabel`, `common.currentLabel`, `common.nameField`, `common.descriptionField`, `common.titleField`)
- **Risk:** Low.
- **Smoke:** all pages × 3 langs (full sweep test).

### Commit 8: components admin sweep (separate, post-pages)
- **Files:** `src/components/admin/*Island.tsx`, `src/components/portfolio/*Dashboard.tsx`, `src/components/governance/*Island.tsx`, `src/components/selection/DiversityDashboard.tsx`, `src/components/boards/CuratorshipBoardIsland.tsx`, others
- **Risk:** Medium-High depending on island consumed by multiple pages.
- **Recommendation:** separate audit/sweep — fora do scope p135 Ω-B (deferir para Ω-C ou follow-up).

---

## Notas de cautela

- **Heavy duplications**: ROLE_LABELS, STATUS_LABELS, TRIBE_NAMES inline maps duplicam-se entre adoption, chapter-report, selection, webinars. Recomenda-se criar **helper functions** em `src/lib/labels.ts` que façam lookup via `t()` + dict — evita drift entre páginas.
- **Brand canonical strings**: `'PMI®'`, `'PMBOK®'`, `'PMP®'`, `'PMI-CPMAI™'`, `'Núcleo'`, chapter codes (`'PMI-GO'`, etc.) — manter PT canonical mesmo em EN/ES (per `feedback_pmi_brand_canonical.md` p88).
- **Print-only blocks**: cycle-report.astro tem print:block sections com brand text PT canonical. Em PT manter. Em EN/ES traduzir descritivos mas manter `'Núcleo IA & GP'` brand. PMI trademarks notice (`'PMI®... são marcas registradas do PMI, Inc.'`) deve ser i18n na descrição mas keep marks.
- **Inline lang dict pattern em `governance/documents.astro`** (linha 60-94): `gateLabels: lang === 'en-US' ? {...} : lang === 'es-LATAM' ? {...} : {...}` — funcional mas centraliza copy decision em page-level. Considerar migrar para keys `admin.gateLabel.*` em dict global. Não é blocker, é nice-to-have.
- **`buildPageI18n()` arrays must be updated** para cada page novo namespace adicionado — race conditions podem acontecer se key adicionada ao dict mas namespace não está no `buildPageI18n` array. Validation manual depois de cada commit.
- **Selection.astro e webinars.astro**: ambos têm complex modal flows (applicant detail modal 6 tabs, webinar lifecycle modal) que serão pesados. Considerar split em sub-commits durante aplicação.
- **DB jsonb columns** (`tribes.name_i18n`, `cycles.cycle_label`, `governance_documents.title`, `webinars.title`, etc.): código já lê `[langKey] || ['pt'] || fallback` — não tocar. Issue só nos chrome/labels da page.
- **Admin gates**: `hasPermission(member, 'admin.X')` checks return permission errors — these come from `lib/permissions.ts`, não da page. Toast messages que mostram "Acesso restrito" devem migrar para keys, mas a permission check itself não muda.
- **Test impact**: cada commit deve rodar `npm test` (i18n parity test verifica que todas as keys em pt-BR.ts existem em en-US.ts e es-LATAM.ts) e `npx astro build` (deve passar com 0 errors novos).
- **MCP/server-side messages**: muitos toasts vêm de RPC errors (`error.message`). Estes são server-side e não afetam i18n da page. Frontend só prefixa com `'Erro: '` ou `'Error: '`. Replace só do prefix.

---

## Próximos passos sugeridos (post-relatório)

1. **PM revisa este report** + decide priorização (Fase 1 only? ou full Fase 1+2+3+verify?)
2. Para cada página priorizada:
   - Add keys em `src/i18n/pt-BR.ts`, `en-US.ts`, `es-LATAM.ts` (mesmas keys nos 3 dicts — invariante GC-097)
   - Use Edit tool (não sed) para refactor das pages
   - Atualizar `buildPageI18n([...])` arrays se namespace novo for criado
   - Smoke `npx astro build` após cada página/commit
3. Para os 7 critical pages (`ip-ratification`, 5 governance/documents wrappers, member detail trio): full structural rewrite com `t()` calls + breadcrumbs i18n.
4. Em commit final, rodar `npm test` (i18n parity test deve passar) e `npx astro build`.
5. **Componentes admin**: deferir para sweep separado (Ω-C ou follow-up sessão), audit dedicada por componente.
6. **Smoke visual**: cada page testada em /pt /en /es no browser real, comparar 3 layouts side-by-side.

---

## Notas adicionais sobre cobertura

**Não auditados em profundidade neste relatório (recommend separate sweep):**
- `src/components/admin/dashboard/AdminDashboardIsland.tsx` (referenced by `index.astro`)
- `src/components/admin/CommsDashboard.tsx` (referenced by `comms-ops.astro`)
- `src/components/admin/GovernanceAdminIsland.tsx` + `BoardMembersPanel.tsx` (referenced by `governance-v2.astro`)
- `src/components/admin/blog/BlogEditorIsland.tsx` (RichText editor wrapping)
- `src/components/admin/audit/AuditLogIsland.tsx` (full audit log UI)
- `src/components/admin/members/MemberListIsland.tsx` + `MemberDetailIsland.tsx` + `InactiveCandidatesIsland.tsx`
- `src/components/admin/AiCalibrationIsland.tsx` (AI scoring calibration UI)
- `src/components/admin/DataHealthIsland.tsx` + `TagManagementIsland.tsx` + `KnowledgeIsland.tsx`
- `src/components/admin/PlatformHealthWidget.tsx` + `SyncHealthWidget.tsx` + `VolunteerComplianceWidget.tsx` + `CrossTribeWidget.tsx` + `ResearchPipelineWidget.tsx`
- `src/components/admin/VolunteerAgreementPanel.tsx`
- `src/components/portfolio/PortfolioDashboard.tsx` + `PlannedVsActualSection.tsx`
- `src/components/governance/ReviewChainIsland.tsx` + `ChainAuditReportIsland.tsx` + `ChainPDFExportIsland.tsx` + `ChainDocxExportIsland.tsx` + `DocumentVersionEditor.tsx`
- `src/components/selection/DiversityDashboard.tsx`
- `src/components/boards/CuratorshipBoardIsland.tsx`
- `src/components/islands/BoardEngine.tsx` + `CrossTribeIsland.tsx` + `TribeDashboardIsland.tsx` + `PartnerPipelineIsland.tsx`
- `src/components/chapter/ChapterDashboard.tsx`

**Why deferred:** components consumed by multiple pages and have their own scoped i18n via `usePageI18n(['namespace'], lang)` hooks — coverage por namespace is the right unit of audit, not per-component.

**Recommendation:** após commits 1-7 das pages serem aplicados e estabilizados, fazer audit dedicada por namespace de componente (`comp.adminDash`, `comp.memberList`, `comp.memberDetail`, `comp.dataHealth`, `comp.knowledge`, `comp.aiCalibration`, `comp.governance`, `comp.curation`, `comp.board`, `comp.card`, `comp.tribe`, `comp.cross`, `comp.commsDash`, `comp.governanceAdmin`, `comp.boardMembers`, `comp.diversity`, `comp.boardEngine`, etc.) verificando se todas as keys têm valores nas 3 línguas.

---

## Conclusão

Admin scope tem **520-580 strings hardcoded** em **~28 pages com issues** (de 42 totais). Distribuição por urgência:

- **Critical (showstopper):** 7 pages, ~80-100 strings — `ip-ratification` (100% PT), 5 wrappers `governance/documents/...`, 3 member pages
- **High (visible PMI int'l):** 14 pages, ~410-470 strings — `selection` (heavy 3137L), `comms`/`webinars`/`comms-ops` (full PT chrome), `campaigns`/`adoption` (filters+labels), `cycle-report`/`chapter-report`/`partnerships`/`pilots`/`sustainability`/`settings`/`governance-v2`/`initiative-kinds`
- **Medium (polish):** 7 pages, ~30 strings — `index`, `blog`, `publications`, `tribe/[id]`, `data-health`, `tags`, `knowledge`

**Effort:** 37-50h aplicação + 5h dictionaries + 2h smoke = ~45-60h total (Ω-B admin only, components separate sweep).

**Suggested commit count:** 7-8 commits (1 Critical + 6 High + 1 Polish + optional Components sweep deferred).

**Strategic anchor (per PM p135 boot):** PMI-GO scoped pilot first → admin trilingue é prerequisite para that demo. Critical fase = unblock IP ratification chain UI + member CRUD em EN/ES.
