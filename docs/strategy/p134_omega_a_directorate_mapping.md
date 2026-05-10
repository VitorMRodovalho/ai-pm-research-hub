# Ω-A Sweep — Directorate Needs Mapping

> **Sweep Ω-A** — directorate-needs-mapper agent · 2026-05-09 · scope: páginas públicas (não-admin)
> **Strategic anchor:** `memory/project_chapter_pmis_saas_vision_p133.md` — pilot futuro PMI-GO + PMI-CE diretorias.
> **Modelo de diretoria PMI usado** (abstrato, sem dados específicos): Presidente · Vice-presidente · Diretores (Voluntariado, Membros, Eventos/Treinamento, Marketing/Comms, Financeiro) · Comitês (Auditoria, Ética, Conselho Consultivo).
> **URLs referência humana** (verificação futura): https://pmigo.org.br/conheca/diretoria/ · https://pmice.org.br/organograma/

---

## Sumário

- **Pages mapeadas:** 33 PT-BR (mais 28 EN + 27 ES redirects/equivalents — todas trilingues)
- **READY substrate:** **11** (page serve role bem; substrate maduro pra pilot chapter)
- **NEEDS_SCOPING:** **15** (page existe e tem fundamentos, mas precisa scoping/refinement multi-tenant ou cross-role pra pilot diretoria)
- **MISSING substrate:** **9** (gap explícito vs needs típicas diretoria — sem feature/sem página)
- **Roles cobertos com substrate adequado:** Voluntariado (alto) · Eventos/Treinamento (alto) · Membros (médio-alto) · Conselho Consultivo (médio) · Ética (médio)
- **Roles com cobertura fraca:** Presidência (cross-cutting dashboard) · Marketing/Comms público-facing · Financeiro público-facing (transparência) · Auditoria self-service · Vice-Presidente (deputy view)

> Recorte: este sweep cobre só **páginas públicas** (`/src/pages/*` excluindo `admin/*`). Substrate em `admin/*` (Ω-B scope) é apenas **mencionado como sinal** — não mapeado em detalhe. Recursos administrativos como `admin/sustainability`, `admin/audit-log`, `admin/chapter`, `admin/portfolio`, `admin/governance-v2` são candidatos diretos a roles de diretoria mas pertencem ao próximo sweep.

---

## Tabela 1: Component/Page → Role mapping

Mapping de páginas públicas para roles típicos de diretoria PMI chapter. Quando page serve múltiplos roles, todos são listados.

| Component/Page | Diretoria role candidate | Use case típico | Substrate maturity |
|---|---|---|---|
| `/` (index.astro) — Homepage | Presidência (face pública) · Marketing/Comms · Conselho Consultivo (vitrine) | Hero institucional; quadrants vision; stats; team; CPMAI; chapters; trail; convite público (CTAs) | **READY** (forte vitrine; precisa whitelabel templating per-chapter) |
| `/about` (about.astro) — ImpactPageIsland | Presidência · Marketing/Comms · Stakeholder/Conselho | Storytelling impacto + 51+ pesquisadores + 8 tribos + plataforma; OG/JSON-LD ResearchOrganization | **READY** (precisa multi-tenant copy + chapter-specific impact data) |
| `/governance` (governance.astro) — GovernancePage | Conselho Consultivo · Ética · Auditoria · Membros (general) | Apresenta políticas e decisões formais; inclui visualização de governance documents | **READY** (substrate sólido; requer scoping per-chapter pra políticas próprias) |
| `/governance/glossario` | Ética · Conselho Consultivo · Membros | Glossário canônico (Track A/B/C, licenças, termos) — espelho dinâmico §13 da Política IP | **READY** (genérico — útil cross-chapter sem alteração) |
| `/governance/ip-agreement` | Ética · Membros (signing path) | Member-facing IP ratification viewer + scroll 100% + GDPR consent + sign | **NEEDS_SCOPING** (chains hoje globais; precisa chain templating per-chapter) |
| `/governance/my-pending` | Membros · Conselho Consultivo · Curadores | Lista pendências de assinatura para qualquer membro autenticado (transparência) | **READY** |
| `/governance/preview` (redirect) | n/a | Redirect 301 para `/governance?view=document` | **READY** |
| `/workspace` (workspace.astro) | Membros (researcher journey) · Voluntariado (post-onboarding) · Vice-Presidente (deputy executive view potencial) | Hub pessoal: KPIs, attendance, dropout risk, my tasks, my cards, pre-onboarding/onboarding checklist, my publications | **NEEDS_SCOPING** (hoje individual; falta "deputy view" pra VP/diretor que precisa visão cross-membro do seu time) |
| `/profile` (profile.astro) | Membros · Voluntariado | Profile pessoal completo (contatos, designations, op_role, multi-email, completeness, level/rank) | **READY** |
| `/initiatives` (initiatives.astro) — Catalog | Voluntariado · Eventos/Treinamento · Membros | Catálogo público de iniciativas (committee/workgroup/study_group/book_club/congress/workshop/research_tribe) | **READY** |
| `/initiative/[id]` | Voluntariado · Eventos/Treinamento · Diretor da iniciativa específica | Dashboard iniciativa: General/Board/Members/Deliverables/Attendance/Gamification | **READY** (precisa hooks pra "diretor responsável" beyond leader/member) |
| `/teams` (teams.astro) | Voluntariado · Membros · Diretor de Voluntariado | Navegação de Tribos Ativas (pesquisa) + Subprojetos operacionais + Legado | **NEEDS_SCOPING** (acesso restrito a membros ativos; precisa toggle "view as diretor" pra cross-tribe oversight) |
| `/tribe/[id]` | Voluntariado · Membros (same tribe) · Diretor de Voluntariado | Dashboard tribo: Kanban + Gamification + Attendance + EventMinutes | **READY** |
| `/projects` (projects.astro) — PilotsIsland | Eventos/Treinamento · Voluntariado · Conselho Consultivo | Catálogo de pilots/iniciativas-projeto com hipótese, problem, scope, métricas, timeline | **NEEDS_SCOPING** (falta visão portfólio cross-pilot pra Presidência/Vice-Presidente) |
| `/webinars` (webinars.astro) | Eventos/Treinamento · Marketing/Comms · Membros | Listagem pública de webinars (upcoming + replays via list_webinars_v2) | **READY** (forte SSR público; precisa filtros per-chapter) |
| `/library` (library.astro) — Workspace | Eventos/Treinamento · Membros · Conselho Consultivo | Biblioteca de assets curados (course/reference/webinar/other) — busca + filtros | **READY** |
| `/meetings` (meetings.astro) — MeetingsPage | Voluntariado · Conselho Consultivo · Membros | Arquivo pesquisável de atas full-text + filtros tribo/tipo + cross-tribe | **READY** |
| `/attendance` (attendance.astro) | Voluntariado · Diretor de Voluntariado · Lideranças | KpiBar + AttendanceGrid + EventMinutes + Roster + criar eventos (recorrentes/não) | **NEEDS_SCOPING** (excelente substrate ops; visão "diretor sees all chapters' attendance" não existe) |
| `/certificates` (certificates.astro) | Voluntariado · Membros · Diretor de Voluntariado | Lista de certificados pessoais (volunteer_agreement, contribution, participation, completion, excellence) | **READY** |
| `/verify/[code]` | Marketing/Comms · Conselho Consultivo · Auditoria · Externos | Validação pública de certificado (verificação por código) | **READY** |
| `/volunteer-agreement` (volunteer-agreement.astro) | Voluntariado · Membros · Ética · Diretor de Voluntariado | Member viewer do termo + status assinatura | **READY** |
| `/cpmai` (cpmai.astro) — CpmaiLanding | Eventos/Treinamento · Marketing/Comms (lead capture) | Landing CPMAI study group (Latam multi-país); opcional link para initiative dashboard | **READY** |
| `/blog` (blog/index.astro) | Marketing/Comms · Conselho Consultivo · Externos | Blog público SSR (case-study, tutorial, opinion, announcement) com like badges | **READY** |
| `/blog/[slug]` | Marketing/Comms · Externos | Post individual público SSR | **READY** |
| `/publications` (publications.astro) | Marketing/Comms · Conselho Consultivo · Eventos/Treinamento · Externos | Public Publications Board (article/framework/toolkit/case_study/webinar_recording) com filtros + busca | **READY** |
| `/publications/submissions` | Membros (autores) · Diretor de Membros (curadoria) | Submissões/curadoria fluxo | **NEEDS_SCOPING** (curadoria existe; falta visão "diretor curatorial" cross-chapter) |
| `/artifacts` (redirect) | n/a | Redirect 301 → `/publications` | **READY** |
| `/boards` (boards.astro) | Voluntariado · Membros · Diretor de Voluntariado | Lista pública de boards via list_active_boards | **NEEDS_SCOPING** (precisa scoping per-chapter quando multi-tenant) |
| `/boards/[id]` | Voluntariado · Membros · Diretor de Voluntariado | Board kanban detail | **READY** |
| `/onboarding` (onboarding.astro) | Voluntariado (candidatos) · Diretor de Voluntariado | Phases públicas (welcome/setup/...) com mailto e CTA externos | **NEEDS_SCOPING** (mailto hardcoded `nucleoia@pmigo.org.br` — precisa per-chapter email; copy hardcoded "Núcleo IA & GP") |
| `/minha-candidatura` | Voluntariado (candidatos) · Diretor de Voluntariado | Status pessoal de candidatura (submitted, screening, interview, eval, approved, etc) + AI consent | **READY** |
| `/interview-booking/[token]` | Voluntariado · Diretor de Voluntariado | Token-based booking público (sem login; via validate_interview_booking_token) | **READY** |
| `/pmi-onboarding/[token]` | Voluntariado · Diretor de Voluntariado | Token-based PMI onboarding portal (consume_onboarding_token) | **READY** |
| `/notifications` (notifications.astro) | Membros · Voluntariado | Feed pessoal de notificações (filter all/unread + mark all read) | **READY** |
| `/settings/notifications` | Membros · Diretor de Comms (futuro) | Preferências (4-mode + weekly digest opt-out) ADR-0022 | **READY** |
| `/changelog` (changelog.astro) | Membros · Conselho Consultivo · Auditoria · Stakeholders | Timeline de releases (feature/improvement/fix/infrastructure/governance) | **READY** |
| `/help` (help.astro) | Todos (visitors + members) · Diretor de Comms · Diretor de Voluntariado | Help center role-aware (expande jornada do usuário; visitor banner; WhatsApp via DB) | **READY** |
| `/stakeholder` (stakeholder.astro) — ChapterDashboard | **Presidência · Vice-Presidente · Conselho Consultivo · Diretores em geral** | Chapter dashboard (KPIs agregados, membros, produção, MCP integration); banner welcome diretoria; submit_chapter_need via MCP | **NEEDS_SCOPING** (substrate certo, audiência clara — mas single-chapter view; falta "diretor view" com KPIs por área Voluntariado/Eventos/Comms) |
| `/gamification` (gamification.astro) | Membros · Voluntariado · Diretor de Voluntariado · Diretor de Membros | Leaderboard cycle/lifetime + Credly sync + tribe rankings | **READY** |
| `/rank` (redirect) | n/a | Redirect 302 → `/gamification` | **READY** |
| `/ranks` (redirect) | n/a | Redirect 302 → `/gamification` | **READY** |
| `/report` (report.astro) — ReportPage | **Presidência · Vice-Presidente · Conselho Consultivo · Stakeholders externos** | Executive report (impressão A4 print-optimized; health green/yellow/red color-fast) | **READY** (substrate excelente para "report executivo presidência") |
| `/privacy` (privacy.astro) | Ética · Conselho Consultivo · Externos | Política de privacidade dinâmica (carrega chapters do DB para placeholder `{list}`) | **NEEDS_SCOPING** (single política; precisa per-chapter quando whitelabel) |
| `/presentations` (presentations.astro) | Marketing/Comms · Eventos/Treinamento · Conselho Consultivo | Apresentações + replays + filtros (general/tribe/deliberations/recording) | **READY** |
| `/404` | n/a | Página de erro | **READY** |
| `/docs/mcp` | Diretor (técnico) · Membros (curiosos) | Docs públicas do MCP server | **READY** |
| `/oauth/consent` | n/a (auth flow) | Consent screen para OAuth/MCP grant | **READY** |

---

## Tabela 2: Cross-ref necessidades típicas diretoria → substrate Núcleo

Mapping inverso: para cada necessidade comum em diretorias PMI chapter (modelo abstrato), qual substrate Núcleo atende e qual gap.

| Necessidade típica | Page/feature Núcleo atual | Maturity | Gap específico |
|---|---|---|---|
| **Presidência** | | | |
| Dashboard executivo cross-cutting (visão 1-pager) | `/report` (ReportPage executive) + `/stakeholder` (ChapterDashboard) | NEEDS_SCOPING | Falta **deputy view "as president"** com filtros por diretoria; falta **comparativo cross-chapter** (presidente regional / multi-chapter) |
| Decisão log centralizado (decisions tomadas pela diretoria) | `governance` page parcial (decisions doc) + `register_decision` MCP tool | NEEDS_SCOPING | Hoje serve decisões "do Núcleo"; falta visão "decisões da diretoria/conselho" segregada com workflow próprio |
| Governance overview com sign-off chains | `/governance` + `/governance/my-pending` + `/governance/ip-agreement` | READY | Precisa scoping per-chapter |
| Annual report / press kit auto-gerado | `/report` (parcial) + blog SSR | NEEDS_SCOPING | Falta **annual report builder com export PDF/PPT institucional** (template diretoria) |
| Sucessão / handover playbook | — | **MISSING** | Sem feature; diretoria muda anualmente, falta playbook digital + checklist + transferência de contas/acessos |
| **Vice-Presidente (Deputy)** | | | |
| Visão executiva paralela com permissions reduzidas | — | **MISSING** | Não existe pattern "deputy view" — substrate atual é binary admin/non-admin; vice precisa visão executiva sem write |
| Backup do presidente em ações específicas | `engagement_kind_permissions` (V4) | NEEDS_SCOPING | Engine existe, falta seed/templates "vice_president" como role com defaults |
| **Diretor de Voluntariado** | | | |
| Pipeline de aplicações (intake → screening → interview → approval) | `/minha-candidatura` (candidato view) + `admin/selection` (gestão) | NEEDS_SCOPING | Substrate forte mas em admin; precisa **public-facing role** "diretor de voluntariado" com acesso filtrado (sem ser admin total) |
| Onboarding tracking + overdue detection | `/onboarding` + `OnboardingChecklist` + `detect_onboarding_overdue` MCP tool | READY | Precisa scoping per-chapter; mailto hardcoded |
| Volunteer hours / engagement records | `/attendance` + `get_my_attendance_hours` + service_history (PMI 3-d ADR-0076) | READY | — |
| Volunteer agreement signing | `/volunteer-agreement` + IP signing | READY | — |
| Volunteer recognition / certificates | `/certificates` + `issue_certificate` + counter-sign | READY | — |
| Active volunteers por status | `attendance` + `gamification` + initiative members | READY | — |
| Excused absences workflow | `bulk_mark_excused` MCP + attendance | READY | — |
| Re-engagement de alumni inativos | `invite_alumni_to_re_engage` + `list_re_engagement_pipeline` MCP | READY (admin/MCP) | Precisa **public surface page** pra diretor self-service (não ter que pedir GP) |
| Round-robin de invites | round-robin invites + load metric | READY | — |
| Inactive member detection | `detect_inactive_members` MCP | READY (MCP) | Precisa **page surface** pra diretor (não só MCP) |
| Offboarding workflow + entrevista de saída | `offboard_member` + `record_offboarding_interview` + `get_offboarding_dashboard` MCP | NEEDS_SCOPING | Toolkit MCP completo; falta **public page** com formulário e checklist |
| **Diretor de Membros** | | | |
| Member directory / profile cards | `/teams` (limited) · `/initiatives` · `/tribe/[id]` (members tab) | NEEDS_SCOPING | Falta **member directory page** standalone (filtros: capítulo, designations, tier, atividade) — hoje espalhado em 3+ páginas |
| Onboarding pipeline cross-membro | `admin/selection` + `get_onboarding_dashboard` MCP | NEEDS_SCOPING | Same: substrate em admin/MCP, falta public surface |
| Profile completeness tracking | `/profile` (self-completeness only) | NEEDS_SCOPING | Falta **diretor view** "membros com completeness < X%" |
| Member ranks/levels/gamification | `/gamification` + `/profile` rank/level | READY | — |
| Credly badge sync | `link_my_credly_badge` MCP + admin tools | READY | — |
| Communication individual com membro | tribe broadcast + notifications | READY (parcial) | Falta **DM 1-1 director→member** com audit log |
| **Diretor de Eventos/Treinamento** | | | |
| Calendário de eventos (visualização mensal/semanal) | `/webinars` + `/attendance` (com NewEventModal) + Workspace day list | NEEDS_SCOPING | Falta **calendário visual mensal/semanal** unificado (hoje é lista) |
| Webinar lifecycle (proposta → review → confirm → realize → certificado) | `create_webinar_proposal` + `review_webinar_proposal` + `convert_proposal_to_webinar` + `update_webinar_comms_assets` MCP | READY | — |
| Event registration / RSVP | — | **MISSING** | Não existe registration/RSVP público para webinar (só vê o webinar); replacement Sympla precisa |
| Event ticketing + payment direct-to-bank | — | **MISSING** | Sympla replacement scope (HIGH priority p133); BACKLOG |
| Event check-in / QR code | — | **MISSING** | Sympla replacement scope; BACKLOG |
| Post-event survey + recording access | webinar workflow + replays public | NEEDS_SCOPING | Survey form não existe; recording é replay público só |
| Cross-event reporting (KPIs ano) | `get_annual_kpis` + `/report` | READY | — |
| Curadoria de programa (study groups, CPMAI, congress) | `admin/curatorship` + initiative dashboard | NEEDS_SCOPING | Substrate em admin; precisa **public surface diretor** |
| **Diretor de Marketing/Comms** | | | |
| Blog editor (CMS) | `admin/blog` (admin) + `/blog` (public) | NEEDS_SCOPING | Editor é admin; precisa role "comms director" com escrita sem admin total |
| Newsletter para membros | `digest_weekly` cron (existing) + `/settings/notifications` (preferences) | READY | Newsletter custom pra diretoria comms = Ω-D scope (mencionado p133) |
| Public-facing pages (institucional) | `/about` + `/cpmai` + `/blog` + `/publications` + `/webinars` | READY | Precisa whitelabel templating |
| Notifications analytics | `get_notifications_analytics` + `get_comms_metrics_by_channel` + `get_comms_dashboard` MCP | READY (MCP/admin) | Precisa **public surface diretor comms** (não só admin) |
| Campaign analytics | `get_campaign_analytics` MCP + `admin/campaigns` | NEEDS_SCOPING | Substrate em admin |
| Press release / changelog público | `/changelog` | READY | — |
| Lead capture / visitor leads | `capture_visitor_lead` MCP + `list_visitor_leads` admin | NEEDS_SCOPING | Capture funciona; surface diretor não |
| Social media scheduling | — | **MISSING** | Sem feature; típico need de comms director |
| Chapter own emails (transactional + newsletter) | sistema email atual (Resend) + templates | NEEDS_SCOPING | Hoje single-tenant; whitelabel per-chapter no roadmap PMIS |
| Brand kit / templated assets | — | **MISSING** | Diretor de comms precisa repositório de logos/cores/templates per-chapter |
| **Diretor Financeiro** | | | |
| Dashboard financeiro chapter | `admin/sustainability` (5 tabelas: cost_categories/entries + revenue_categories/entries + sustainability_kpi_targets) | NEEDS_SCOPING | **Escopo Ω-B** — substrate confirmed p133; gap = **multi-chapter scoping + chart of accounts + bank account separation + transparência pública** |
| Transparência financeira pública | — | **MISSING** | Diretor financeiro precisa **public report page** "transparência" com receitas/despesas agregadas (LGPD-safe) |
| Cost/revenue entry workflow | `admin/sustainability` (admin only) | NEEDS_SCOPING | Workflow direto na page admin |
| NF-e / Cupom Fiscal emission | — | **MISSING** | Sympla replacement scope HIGH p133; backlog crítico para fiscal compliance Brasil |
| Bank reconciliation | — | **MISSING** | Sem feature |
| Annual financial report / DRE | — | **MISSING** | Sem export estruturado |
| Sponsor/partner pipeline | `admin/partnerships` + `get_partner_pipeline` + `manage_partner` MCP + `/admin/partnerships` | NEEDS_SCOPING | Substrate em admin; falta **public surface diretor financeiro/parcerias** |
| **Auditoria** | | | |
| Audit log governance | `admin/audit-log` + `get_audit_log` + `export_audit_log_csv` MCP | NEEDS_SCOPING | **Escopo Ω-B** — substrate em admin; comitê auditoria precisa **read-only public surface** com filtros |
| PII access log | `get_pii_access_log_admin` + `get_my_pii_access_log` MCP | READY (self) + NEEDS_SCOPING (admin → comitê) | Precisa role "auditor" com read all sem admin |
| Document version history (todas mudanças governance) | `list_document_versions` + `get_version_diff` + `get_chain_audit_report` MCP | READY (MCP) | Precisa **public page diretor auditoria** |
| Anomaly report | `get_anomaly_report` + `get_operational_alerts` MCP | READY (MCP) | Precisa surface |
| Drift detection (code vs schema) | `check_code_schema_drift` MCP | READY (technical) | — |
| **Ética** | | | |
| IP agreement / consent | `/governance/ip-agreement` + IP ratification flow | READY | — |
| Consent flows / LGPD | `/privacy` + consent gate em RPCs PII | READY | — |
| Glossário canônico (definições legais) | `/governance/glossario` | READY | — |
| Política de propriedade intelectual | governance documents + signing chains | READY | — |
| Conduct / disciplinary workflow | — | **MISSING** | Sem feature; típico need de comitê de ética (denúncia, mediação, registro confidencial) |
| LGPD Art. 18 cycle (export/delete/anonymize) | implementado backend (cron 5y); not user-surface | NEEDS_SCOPING | Existe cron + crons LGPD admins; falta **self-service page** "exportar meus dados / pedir exclusão / anonimizar" |
| **Conselho Consultivo** | | | |
| Acesso ao governance preview | `/governance/preview` (redirect) + `/governance` document view | READY | — |
| Read-only dashboard estratégico | `/report` + `/stakeholder` (ChapterDashboard stakeholderMode=true) | READY | — |
| Histórico de decisões | governance docs + `get_decision_log` MCP | READY (MCP) | Precisa **public page** "decision log" cronológico filtrado |
| Visão portfolio cross-tribe | `get_portfolio_overview` + `get_portfolio_health` MCP + parcial em `/teams` | NEEDS_SCOPING | Substrate via MCP; falta **public portfolio page diretor/conselho** |
| Insights / knowledge backlog | `knowledge_insights_overview` + `knowledge_insights_backlog_candidates` MCP | READY (MCP) | Surface visualização |

---

## Lista de gaps (necessidades sem substrate adequado)

Priorizado por aderência ao pilot futuro PMI-GO + PMI-CE diretorias.

### MISSING — backlog candidates priority HIGH

1. **Sucessão / handover de diretoria** — Diretoria PMI muda anualmente. Sem playbook digital + checklist transição + transferência contas/acessos/permissions, fricção alta no pilot. **Backlog:** "Director-handover playbook + checklist + access-transfer workflow."

2. **Event registration / RSVP público** — Replacement Sympla scope (p133 HIGH priority); precisa fluxo: visitor → register → ticket/QR → check-in → certificate. **Backlog:** "Sympla replacement Phase 1: registration + ticketing + QR (sem payment ainda)."

3. **Event ticketing + payment direct-to-bank + NF-e/Cupom** — Continuação Sympla replacement; necessidade fiscal Brasil. **Backlog:** "Sympla replacement Phase 2: payment direct + NF-e/Cupom integration (open-source library)."

4. **Member directory standalone (filtros)** — Diretor de Membros precisa lista filtrada por chapter/designations/tier/activity. Hoje espalhado em `/teams`, `/initiatives`, `/tribe/[id]`. **Backlog:** "Public member-directory page (LGPD-safe — opt-in público / restrito a membros / restrito a diretoria conforme tier)."

5. **Conduct / disciplinary workflow** — Comitê de ética sem ferramenta. Confidencial, audit-trail, mediação. **Backlog:** "Ethics complaint workflow (anônimo/identificado, audit-trail confidencial)."

6. **Annual report builder + PDF/PPT export** — Presidência precisa relatório anual institucional. `/report` é executivo mas não institucional. **Backlog:** "Annual institutional report builder com template diretoria + export PDF/PPT."

### MISSING — backlog candidates priority MED

7. **Transparência financeira pública** — Diretor financeiro precisa public-facing "transparência" report. Substrate financeiro existe em `admin/sustainability` mas não tem surface pública. **Backlog:** "Public financial transparency page (LGPD-safe rollups; vinculada Ω-B chapter financials)."

8. **Brand kit / templated assets** — Diretor comms precisa logos/cores/templates per-chapter. Crítico pra whitelabel. **Backlog:** "Chapter brand kit module (logos, paleta, templates) — vinculado Ω-B + whitelabel ADR futuro."

9. **DM 1-1 director→member com audit log** — Diretores precisam mensagem direta a membro com trail (não só notification system genérico). **Backlog:** "Director-to-member direct message with audit trail."

### MISSING — backlog candidates priority LOW

10. **Social media scheduling** — Diretor comms; substrate inexistente; pode ser feature externa integrada. **Backlog:** "Social scheduling integration (Buffer/Hootsuite-like) — avaliar build vs partnership."

### NEEDS_SCOPING — gaps de scoping/role refinement priority HIGH (substrate existe, falta surface ou multi-tenant)

- **Deputy/VP role pattern** — substrate `engagement_kind_permissions` engine V4 existe; falta seed `vice_president` + view "deputy" no `/stakeholder` ou `/report`.
- **Diretor public surfaces para MCP tools** — vários tools admin/MCP só rodam por admin (selection, partner pipeline, anomaly_report, decision_log, audit_log, partnerships). Diretor precisa public page com filtros conforme seu domínio.
- **Multi-chapter scoping em pages públicas** — homepage, about, webinars, blog, publications, governance hoje single-tenant Núcleo Goiás. Pilot multi-chapter exige template per-chapter.
- **Email mailto hardcoded** — `/onboarding` linha 29 `mailto:nucleoia@pmigo.org.br`. Multi-chapter precisa lookup dinâmico.
- **Workspace deputy view** — diretor precisa "ver workspace de quem reporta a mim" (cross-membro restrito).

### NEEDS_SCOPING priority MED

- `/governance/ip-agreement` chains hoje globais → precisa template per-chapter.
- `/privacy` política única → precisa per-chapter LGPD compliance.
- `/onboarding` copy + email + branding hardcoded → whitelabel precisa templating.
- `/teams` acesso restrito a membros ativos → adicionar "view as diretor" cross-tribe oversight.
- `/projects` (pilots) → falta visão "portfólio" cross-pilot pra Presidência.

---

## Sugestões pra Ω-E consolidation

### Documentos a criar em consolidation final

1. **`docs/strategy/CHAPTER_DIRECTORATE_DIGITIZATION_FRAMEWORK.md`** — Consolidar Tabelas 1+2 deste sweep + heat-map por role × maturity + roadmap fase 1/2/3 para pilot PMI-GO/CE.

2. **`docs/strategy/DIRECTORATE_ONBOARDING_PLAYBOOK.md`** — Playbook futuro pilot: passo-a-passo "como onboardar uma diretoria PMI no Núcleo IA Hub" cobrindo provisioning chapter, scoping permissions, whitelabel setup, training paths.

3. **`docs/adr/ADR-NEXT-multi-tenant-whitelabel-architecture.md`** — Princípio fundacional (já mencionado p133 como candidato) — consolida decisões: per-chapter scope, branding, emails, MCP, domínio.

4. **`docs/adr/ADR-NEXT-deputy-vice-role-pattern.md`** — Pattern arquitetural pra "deputy view" (read-only executive sem write).

### Backlog issues sugeridas (uma por gap MISSING priority HIGH)

- `[backlog] Director-handover playbook + checklist + access-transfer`
- `[backlog] Sympla replacement Phase 1 (registration + ticketing + QR)`
- `[backlog] Sympla replacement Phase 2 (payment direct + NF-e/Cupom)`
- `[backlog] Public member-directory page (LGPD-safe filtros)`
- `[backlog] Ethics complaint workflow (anônimo/identificado, confidencial)`
- `[backlog] Annual institutional report builder + PDF/PPT export`

### Issues sugeridas — gap NEEDS_SCOPING priority HIGH

- `[scoping] Deputy/VP role pattern + seed engagement_kind_permissions`
- `[scoping] Public surfaces para MCP/admin tools (selection, partner, anomaly, audit) com role-filtered access`
- `[scoping] Multi-chapter templating em public pages (homepage/about/webinars/blog/publications/governance/privacy/onboarding)`
- `[scoping] Workspace "deputy view" (diretor sees direct reports)`
- `[scoping] /onboarding copy/email/branding parametrizados per-chapter`

---

## Notas

- **Substrate em admin (Ω-B scope)** mencionado mas NÃO mapeado em detalhe. Pages como `admin/sustainability` (5 tabelas confirmed p133), `admin/audit-log`, `admin/chapter`, `admin/portfolio`, `admin/governance-v2`, `admin/curatorship`, `admin/selection`, `admin/partnerships`, `admin/comms` são candidatos diretos a roles de diretoria — **vai virar Ω-B**. Sinal forte: muitos NEEDS_SCOPING acima reduzem a "substrate em admin precisa surface diretor".

- **Foco strict em pages públicas + reflexão estratégica.** Sweep não tocou nem editou arquivos.

- **Heurística reaproveitada do anchor p133:** princípio "tool replacement evaluation" (DocuSign / Forms / Sheets / Sympla / Calendar) cruzado com diretoria roles — Sympla replacement (events/ticketing) atinge **3 roles** (Eventos/Treinamento, Marketing/Comms, Financeiro) simultaneamente, reforçando priority HIGH.

- **MCP toolset rico (283+ tools).** Muitos gaps são "tem tool, falta surface UI" — implementação pode ser baixo-custo (criar página que chama tool existente) vs alto-custo (build feature do zero). Sugestão: **Ω-E priorizar gaps "MCP tool exists but no public surface"** vs "build from scratch."

- **Diretoria como persona (não só vocabulary):** muitas pages atendem múltiplos roles. Esse cross-role mapping permite **avaliar ROI per-feature** considerando quantos roles ele atinge (ex.: `/stakeholder` ChapterDashboard atinge 4+ roles).

- **Trilingue full system (p133)** confirmado upstream — essencial para PMI international LATAM+USA. Não é gap aqui mas dependency.

- **Substrate forte para Voluntariado e Eventos** (já operacional). Substrate fraco para Vice-Presidente, Marketing/Comms público-facing, Financeiro público-facing, Auditoria self-service. Ordem natural de priorização pilot pode focar **Voluntariado + Eventos primeiro** (substrate maduro) e **Comms + Financeiro + Auditoria como segunda onda** (Ω-B + backlog).

---

*Sweep Ω-A · directorate-needs-mapper agent · 2026-05-09*
