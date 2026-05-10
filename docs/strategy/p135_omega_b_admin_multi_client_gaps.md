# Ω-B Admin Sweep — Multi-Client / Whitelabel Gaps Report

**Sessão:** p135 Ω-B Trilingue Admin Boot
**Sub-agent:** admin-multi-client-mapper
**Escopo:** 43 admin pages + components admin/ + components governance/ específicos do admin scope
**Excluído:** Páginas públicas, `api/`, `en/`, `es/`, `oauth/`, `.well-known/` (cobertos em Ω-A `p134_omega_a_multi_client_gaps.md`)
**Estado de origem:** Núcleo IA Hub é vertical PMIS/SaaS multi-tenant by design. Admin scope é o **menos preparado** para 2nd chapter — depende 100% de RLS server-side, ZERO scoping explícito por organization no frontend admin, e contém **bloqueador legal hard** (CNPJ + entidade legal hardcoded em PDF Termo Voluntariado).

---

## Sumário

- **Páginas admin auditadas:** 43 (`*.astro` em `src/pages/admin/`)
- **Componentes admin auditados:** 29 (`src/components/admin/`) + 5 governance components consumidos por páginas admin
- **NEW HIGH severity findings:** 16
- **NEW MED severity findings:** 14
- **NEW LOW severity findings:** 7
- **Already-tracked overlaps com 11 hard blockers existentes:** 6 (cross-ref na seção 2)
- **Total NEW: 37 itens flagged**

### Stats brutos do grep (admin scope only)
- `Núcleo IA & GP` em texto/copy admin: **6 ocorrências** (cycle-report header/footer + GovernanceCRTable export + GovernanceBatchModal CCB note + AdminDashboardIsland title + report.astro subtitle default)
- `PMI-GO` / `pmigo` / `Goiás`: **20 ocorrências** específicas do admin scope (sustainability options + webinars hard codes + governance gate labels + member edit defaults + VolunteerAgreementPanel template + sponsor/liaison reports + cycle palette)
- `nucleoia.vitormr.dev` em admin: **2 ocorrências** (cycle-report.astro header/footer + reuso indireto via ChainPDFDocument já-tracked)
- `ldrfrvwhxsmgaabwmaik.supabase.co` em admin: **1 ocorrência** (`adoption.astro:662` posthog-proxy URL)
- **`organization_id` em RPC calls admin:** **0 ocorrências** (124 RPC calls inspecionados; 0 passam org_id explícito)
- **`organization_id` em queries `from('table')` admin:** **0 ocorrências** (~30 queries diretas)
- **`p_chapter` em RPC calls admin:** **8 ocorrências** (admin_update_member, exec_chapter_dashboard, get_selection_pipeline_metrics, exec_chapter_roi via analytics) — usa **TEXT chapter code (V3 legacy)**, NÃO `organization_id` (V4 ADR-0004)
- **`CNPJ`** hardcoded em admin: **1 ocorrência crítica** (`VolunteerAgreementPanel.tsx:336` — 06.065.645/0001-99 PMI Goiás)

---

## 1. Cross-reference com 11 hard blockers existentes (já-tracked)

| # | Existing Hard Blocker | Touched in admin scope? | Notes |
|---|------------------------|--------------------------|-------|
| 1 (CRIT) | cost_entries/revenue_entries/sustainability_kpi_targets sem organization_id | YES — `admin/sustainability.astro` é a UI primária que escreve nessas tabelas | Same blocker; admin reinforces RLS USING(true) exposure surface area |
| 2 (HIGH) | supabase.ts FALLBACK hardcoded `ldrfrvwhxsmgaabwmaik` | NOT NEW (lib-level); admin **reuses** the same fallback. ALSO new in admin: `adoption.astro:662` PROXY_BASE pinned to project ref | New finding NEW-A1 below tracks the proxy URL hardcoding |
| 3 (HIGH) | middleware.ts CANONICAL_HOST hardcoded | NOT in admin scope (middleware is global) | n/a |
| 4 (HIGH) | Governance PDFs PMI-GO footer (ChainPDFDocument.tsx:377,390,519,548) | YES — `/admin/governance/documents/[chainId]/export-pdf.astro` é a entry point. Já-tracked | Marked already-tracked; not duplicated |
| 5 (HIGH) | mcp_usage_log sem organization_id | YES — `admin/adoption.astro` lê `mcp_usage_log` (linha 54 description) | Same blocker; surface area for analytics; data is already missing org dimension |
| 6 (CRIT) | DPA Núcleo↔chapter — não existe | NOT in code (legal artifact) | n/a |
| 7 (HIGH) | revenue_entries sem event_id FK | YES — `admin/sustainability.astro` é a UI que cria revenue_entries; campo event_id não existe no form | Same blocker |
| 8 (HIGH) | sustainability_kpi_targets UNIQUE(cycle, kpi_name) blocks 2nd chapter | YES — `admin/sustainability.astro` "Targets" tab consome essa tabela (linha 687 update_sustainability_kpi RPC) | Same blocker; UI tab "Metas" só funciona para 1 chapter |
| 9 (MED) | anonymize_rejected_applicants sem p_organization_id | YES — invocado indiretamente via cron, mas admin NUNCA chama anonymize_* RPCs nas 43 pages (validar) | Listed; no NEW gap surfaced |
| 10 (MED) | pii_access_log sem org_id accessor/target | YES — `admin/audit-log.astro` consome `get_audit_log` que lê parcialmente desse log; também `MemberDetailIsland.tsx` triggers `get_my_pii_access_log` quando GP abre detalhe de membro | Same blocker |
| 11 (MED) | nucleo-guide prompt hardcoded chapter list | NOT in admin scope (MCP server-side) | n/a |

**Subtotal already-tracked overlaps: 6 admin pages reforçam 11 blockers existentes** (sustainability page é o coração de blockers #1, #7, #8; adoption/audit-log para #5, #10; governance PDF route para #4).

---

## 2. NEW gaps — admin-specific findings

Tabela detalhada (severity descending, then alphabetical):

| # | File | Line | Issue | Type | Sev | Target ADR |
|---|------|------|-------|------|-----|------------|
| **A1** | `src/pages/admin/adoption.astro` | 662 | `PROXY_BASE = 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/posthog-proxy'` — analytics proxy hardcoded ao project Núcleo. 2nd chapter em deploy isolado quebra. Same root cause as Hard Blocker #2 mas nova ocorrência | URL/infra | **CRITICAL** | ADR-NEW-D (Per-chapter MCP/EF endpoint) |
| **A2** | `src/components/admin/VolunteerAgreementPanel.tsx` | 331-347, 391 | **CNPJ 06.065.645/0001-99 PMI Goiás + entidade legal "Seção Goiânia, Goiás — Brasil do PMI" + "Assinatura do Diretor do PMI Goiás" hardcoded em template do Termo de Compromisso de Voluntariado**. Documento legal vinculante (Lei 9.608/98) — bloqueador hard para PMI-CE assinar termo (CNPJ diferente, jurisdição diferente). Atualmente é JSON `template.content` parsed em runtime mas o WRAPPER (header + preamble + signature block) é JSX hardcoded | Legal/PDF/Brand | **CRITICAL** | ADR-NEW-E (Per-chapter privacy/legal docs) ou novo ADR-NEW-H (Multi-tenant legal templates) |
| **A3** | `src/pages/admin/sustainability.astro` | 235-239 | `<select id="cost-paid-by">` com `<option value="chapter_pmigo">PMI-GO Chapter</option>` + 4 outros chapters fixos em option values **e** descrição. Quebra (a) se chapter novo não-listado for onboarded, (b) value semântico (`chapter_pmigo`) é texto livre que vira string em DB sem FK | Hardcoded chapter list | **HIGH** | ADR-NEW-B (chapter_registry-driven dropdowns) |
| **A4** | `src/pages/admin/webinars.astro` | 6, 165-169, 346, 422, 524, 559, 631, 650, 689 | Multiple: (a) `const CHAPTERS = ['CE','DF','GO','MG','RS','ALL']` array fixo; (b) `<option value="GO">PMI-GO</option>` × 5 chapters; (c) display logic `'PMI-' + w.chapter_code` quando ≠ ALL; (d) PostHog event tracking inclui `chapter: w.chapter_code`; (e) RPC `upsert_webinar({ p_chapter_code })` recebe TEXT — V3 legacy. Webinar é entidade chapter-scoped por design (governance multi-entity badge linha 22) — sem chapter_registry-driven dropdown 2nd chapter quebra ao criar webinar | Hardcoded chapter list + V3 RPC | **HIGH** | ADR-NEW-B + ADR-NEW-F |
| **A5** | `src/pages/admin/cycle-report.astro` | 18, 106-108, 290, 472 | (a) Print header: `<div>Núcleo de Estudos e Pesquisa em IA & Gerenciamento de Projetos</div>` hardcoded; (b) Print footer: `<div>Documento gerado automaticamente pela plataforma digital do Núcleo de Estudos e Pesquisa em IA & GP</div>` + `<div>nucleoia.vitormr.dev · Verificável via código do relatório</div>`; (c) `FOUNDING_CHAPTER_PALETTE: { 'PMI-GO': '#0F6E56', ... }` 5 chapters hardcoded (com fallback HSL deterministic — bom design); (d) Screen footer: `Gerado em ... · Núcleo IA & GP · nucleoia.vitormr.dev` | Brand + URL | **HIGH** | ADR-NEW-A + ADR-NEW-B |
| **A6** | `src/pages/admin/campaigns.astro` | 153 | `<input id="aud-chapters" placeholder="PMI-GO, PMI-CE">` audience filter — placeholder não-quebra, mas (a) UI assume free-text input de chapter codes em vez de multi-select scoped, (b) mantém PMI-GO como exemplo default; campanhas escritas com este filtro devem ser audit-logged | Audience filter | **HIGH** | ADR-NEW-B (chapter dropdown) |
| **A7** | `src/components/admin/VolunteerAgreementPanel.tsx` | 54-152 | All 3 i18n bundles ("pt-BR", "en-US", "es-LATAM") usam termo "PMI Goiás" indiretamente via `templateTitle` resolved a database (text). MAS o **wrapper UI** (header + preamble + signature block lines 331-393) hardcoded em PT-BR ignora i18n — termo é mostrado em PT-BR mesmo se usuário em /en ou /es. Para PMI-CE em ES-LATAM, mostrarem termo PT-BR de PMI-GO é unacceptable | i18n bypass + brand | **HIGH** | ADR-NEW-G (i18n chapter overlay) |
| **A8** | `src/components/admin/members/MemberDetailIsland.tsx` | 108 | `setEditChapter(m.chapter \|\| 'PMI-GO')` — fallback default chapter "PMI-GO" quando member.chapter é null. Em multi-tenant, esse default é wrong para 2nd chapter operations | Default chapter | **HIGH** | ADR-NEW-B (default from session.organization_id) |
| **A9** | `src/components/admin/members/MemberListIsland.tsx` | 184 | Mesmo padrão `setEditChapter(m.chapter \|\| 'PMI-GO')` na lista de membros. Idêntico A8 mas em route diferente (/admin/members vs /admin/members/[id]) | Default chapter | **HIGH** | ADR-NEW-B |
| **A10** | `src/pages/admin/governance/documents.astro` | 66, 77, 88 | `gateLabels` map hardcoded em 3 idiomas: `president_go: 'PMI-GO presidency'` / `'Presidencia PMI-GO'` / `'Presid. PMI-GO'`. Esses labels são gates do approval workflow — `president_go` é o gate canônico do schema. Em multi-tenant, label deveria resolver via chapter context (e.g. "Presidência PMI-CE") | Gate label hardcoded | **HIGH** | ADR-NEW-G + DB schema work (gate kinds chapter-scoped?) |
| **A11** | `src/pages/admin/governance/ip-ratification.astro` | 127 | `var GATE_LABELS = { president_go: 'pres. GO', ... }` — mesmo padrão A10 mas em outra page. Inline gate labels hardcoded | Gate label | **HIGH** | ADR-NEW-G + DB schema |
| **A12** | `src/pages/admin/chapter-report.astro` | 121, 192, 230, 258, 268-275 | `exec_chapter_dashboard({ p_chapter: chapter })` + `get_selection_pipeline_metrics({ p_chapter: chapter })` + `exec_chapter_comparison()` — todos consomem `p_chapter` TEXT (V3 legacy). Page popula chapter dropdown via `from('public_members').select('chapter')` sem filtro de organization. Para PMI-CE pilot, dropdown mostraria chapters PMI-GO/CE/DF/MG/RS misturados — sem scoping | V3 chapter RPC | **HIGH** | ADR-NEW-F + V4 RPC migration |
| **A13** | `src/pages/admin/analytics.astro` | 293, 436, 488-499, 524 | `filters = { ..., chapter: '' }` + `p_chapter: filters.chapter` + `populateSelect('analytics-filter-chapter', CHAPTER_OPTIONS.map(c => ({ value: c.code })))`. Analytics page consome `CHAPTER_OPTIONS` window global resolved at SSR — assumed loaded from `chapter_registry`, mas filter logic é V3 (TEXT chapter code), não V4 organization_id. Multi-tenant não tem barrier entre analytics de chapters | Analytics V3 chapter | **HIGH** | ADR-NEW-F |
| **A14** | `src/pages/admin/member/[id].astro` | 121, 217, 237, 252 | Member edit page tem campo "Capítulo" hardcoded como label + RPC `admin_update_member({ p_chapter: ... })` + insert direto na tabela `members` com coluna `chapter:params.p_chapter`. Em V4, member.chapter é uma TEXT column (V3 legacy) e member.organization_id é o V4 source of truth — mas frontend só edita o TEXT, não o organization_id | V3 chapter persistence | **HIGH** | ADR-NEW-F + DB migration |
| **A15** | `src/pages/admin/selection.astro` | 154 | `<input id="opp-chapter" placeholder="PMI-GO">` — VEP opportunity creation form com chapter free-text input (single line) + placeholder PMI-GO. Mesmo padrão A6 (placeholder example) mas em form de criação de opportunity | Selection chapter input | **HIGH** | ADR-NEW-B |
| **A16** | `src/pages/admin/report.astro` | 86, 90-95, 123 | (a) `from('site_config').select('value').eq('key', 'report_config').maybeSingle()` — site_config é singleton GLOBAL (anti-pattern já noted em Ω-A); (b) Default `subtitle: 'Núcleo de Estudos e Pesquisa em IA & Gestão de Projetos'` hardcoded; (c) Default chapters resolved via `loadChapters(sb).map(c => c.display_code).join(' · ')` — bom! Resolves dynamic. MAS save grava em `site_config` global key | Singleton config + brand | **HIGH** | ADR-NEW-B + organization_settings table |
| **B1** | `src/components/admin/dashboard/AdminDashboardIsland.tsx` | 17, 144, 148 | KPI card "Capítulos" usa `kpis.chapters_current/chapters_target` — `chapters_target` é resolved via RPC `get_admin_dashboard` que provavelmente lê de `site_config.kpi_targets_cycle_3` (singleton) ou `sustainability_kpi_targets` (UNIQUE blocker #8). Para 2nd chapter, target deveria ser per-tenant | KPI dashboard target | MED | ADR-NEW-B |
| **B2** | `src/components/admin/dashboard/AdminDashboardIsland.tsx` | 162 | `<h1>{t('comp.adminDash.title', 'Dashboard do Núcleo')}</h1>` — fallback "Dashboard do Núcleo" hardcoded em PT-BR. i18n key existe mas fallback assume Núcleo | Brand fallback | MED | ADR-NEW-B + i18n fix |
| **B3** | `src/components/admin/GovernanceBatchModal.tsx` | 131 | `t('governance.ccb_note', 'As aprovações implementam tecnicamente decisões do Comitê de Controle de Mudanças (CCB) do Núcleo IA & GP.')` — i18n key existe mas fallback diz "Núcleo IA & GP" | Brand fallback | MED | ADR-NEW-B |
| **B4** | `src/components/admin/GovernanceCRTable.tsx` | 20 | `const header = 'Relatório de Change Requests — Núcleo IA & GP — Gerado em ${date} — Documento interno\n\n'` — CSV export header hardcoded ao Núcleo. Não é i18n-aware | Brand in export | MED | ADR-NEW-B |
| **B5** | `src/components/admin/GovernanceAdminIsland.tsx` | 85 | `t('governance.admin_scope_disclaimer', 'Este fluxo cobre a governança de conteúdo do Manual (produto). A governança estratégica do Núcleo é tratada pelo Steering Committee multi-capítulos.')` — fallback i18n key menciona "Núcleo" e assume Steering Committee multi-capítulos config (Núcleo-specific governance structure, não generalizado) | Brand fallback + governance assumption | MED | ADR-NEW-B |
| **B6** | `src/components/admin/AdminSidebar.tsx` | 77, 78, 130-136 | Sidebar item "Meu Capítulo" e "Painel do Capítulo" estão visible para qualquer member com `admin.analytics.chapter` perm — não há scoping per-organization na visibilidade do menu. Em 2nd chapter pilot, sponsor PMI-CE veria menu items genericamente | Menu scoping | MED | ADR-NEW-F (session-aware menu) |
| **B7** | `src/components/governance/ChainAuditReportIsland.tsx` | 58, 60 | Embedded em `/admin/governance/documents/[chainId]/audit-report.astro` — JSX heading `<h2>Relatório de Auditoria — Conselho Fiscal PMI-GO</h2>` e parágrafo descreve "auditoria externa pelo Conselho Fiscal PMI-GO" hardcoded. Para PMI-CE chapter, conselho fiscal é entidade jurídica diferente | Brand + Brazilian gov body | **HIGH** | ADR-NEW-B + ADR-NEW-E |
| **B8** | `src/components/governance/ReviewChainIsland.tsx` | 35, 47 | Embedded em `/admin/governance/documents/[chainId].astro` — `gateLabels: { president_go: 'Presid. PMI-GO' }` e `signLabels: { president_go: 'Assinar como presidência PMI-GO' }`. Mesmo padrão A10/A11 mas em React island | Gate label | MED | ADR-NEW-G |
| **B9** | `src/components/governance/DocumentVersionEditor.tsx` | 41 | Embedded em `/admin/governance/documents/[docId]/versions/new.astro` — `president_go: 'Presid. PMI-GO'` em map de gate labels para WYSIWYG editor | Gate label | LOW (mostly internal) | ADR-NEW-G |
| **B10** | `src/pages/admin/audit-log.astro` (via AuditLogIsland) | (component-level) | `get_audit_log` RPC NÃO recebe `p_organization_id`. Audit log é cross-tenant — em multi-tenant, GP de chapter X veria audit entries de chapter Y. Already-tracked overlap com #10 mas reforça o padrão de "0 RPCs admin passam org_id" | RPC scoping | MED | ADR-NEW-F |
| **B11** | `src/pages/admin/comms-ops.astro` | 233 | `${href}` link gerado para `/admin/comms-ops?context=webinar&title=${...}` — chapter context não preservado no URL. Em multi-tenant, breadcrumb chain quebra | URL routing | MED | ADR-NEW-A |
| **B12** | `src/pages/admin/sustainability.astro` (multiple) | 551, 600, 687, 784, 805 | RPCs `get_cost_entries`, `get_revenue_entries`, `update_sustainability_kpi`, `create_cost_entry`, `create_revenue_entry` — TODAS sem `p_organization_id`. Direct write à tabelas com RLS USING(true) (Hard Blocker #1). Cada chapter precisa CRUD scoped por org. Already-tracked but admin UI is the surface | RPC scoping (CRITICAL via #1) | **HIGH** | Hard Blocker #1 + ADR-NEW-F |
| **B13** | `src/pages/admin/comms.astro` | 270, 274, 373, 404, 460, 519, 544, 600 | `comms_metrics_latest_by_channel`, `comms_top_media`, `comms_channel_status` — todas RPCs sem org filter. Channel config (Resend, WhatsApp, SendGrid keys) global single-tenant. Each chapter needs separate channel | Comms infra | **HIGH** | ADR-NEW-D |
| **B14** | `src/pages/admin/partnerships.astro` | 191 | `pmi_chapter: 'PMI Chapter'` em TYPE_LABELS — não diretamente um problem mas reflete que partnerships taxonomy assume PMI ecosystem | Taxonomy | LOW | n/a (cosmetic) |
| **C1** | `src/pages/admin/audit-log.astro` | full file | Page is a thin wrapper for AuditLogIsland; SSR doesn't filter audit calls per organization. Already-tracked | RPC scoping | LOW | tracked via #10 |
| **C2** | `src/pages/admin/blog.astro` | 224, 227, 253 | `from('blog_posts').update/insert/select` direto sem org filter. Blog é compartilhado cross-tenant ou per-tenant? Sem decisão arquitetural — tabela `blog_posts` precisa coluna `organization_id` se per-tenant | Blog scoping decision pending | LOW | ADR-NEW-? (blog tenancy decision) |
| **C3** | `src/pages/admin/curatorship.astro` | (delegated to CuratorshipBoardIsland) | Page só cria denial-fallback gate; toda lógica em React island. Curatorship workflow é cross-tenant? — sem decisão | Curation scoping decision pending | LOW | ADR-NEW-? |
| **C4** | `src/pages/admin/index.astro` | 36-37, 91 | Hardcoded "Próxima Reunião Geral" + button "Criar próxima quinzenal" — assume Núcleo-specific cadência semanal/quinzenal. RPC `create_next_geral_meeting` não recebe org_id; uses `site_config` singleton para Meet/YouTube URL defaults | Cadence assumption + singleton | LOW | ADR-NEW-B (organization_settings) |
| **C5** | `src/pages/admin/portfolio.astro` | 241 | `get_annual_kpis({ p_cycle: 3, p_year: 2026 })` — cycle hardcoded a "3" e year a "2026". Multi-cycle multi-year é design intent (cycles table existe), mas cycle/year aqui é literal. Para PMI-CE com cycle diferente, quebra | Cycle/year hardcoded | LOW | refactor cycle resolution |
| **C6** | `src/components/admin/dashboard/AdminDashboardIsland.tsx` | 35-43, 47 | `timeAgo()` e `fmtDateTime()` usam strings PT-BR fixas ("há Xmin" / "há Xh" / "há Xd") + locale 'pt-BR'. Module-scope helper; i18n deferred mas é gap para EN/ES | i18n deferred | LOW | tracked como TODO |
| **C7** | `src/components/admin/members/MemberListIsland.tsx` | 31-49 | `OPROLE_LABELS`, `DESIG_LABELS`, `DESIG_COLORS` module-scope com strings PT-BR. NOTE comment já reconhece como gap. Color choices PMI-Brasil specific (`#FF610F` orange) | i18n deferred + brand colors | LOW | ADR-NEW-G |

---

## 3. Findings agrupados por dimensão

### Dim 1. RPC Organization Scoping (NEW gap density: 18 admin pages)

**Estado:** Em 124 chamadas `.rpc()` em admin pages, **0 passam `p_organization_id`**. Em ~30 queries `.from('table')` diretas, **0 filtram por `organization_id`**. Defesa contra cross-tenant leak depende **100%** de RLS policies server-side.

**Crítico:** 9 RPCs admin escrevem dados diretamente:
- `admin_update_member` → tabela `members` (`p_chapter` TEXT, não org_id)
- `admin_inactivate_member` / `admin_reactivate_member` → `members`
- `admin_update_setting` → `platform_settings` (cross-tenant)
- `admin_manage_cycle` → `cycles` (cross-tenant)
- `set_site_config` → `site_config` singleton (anti-pattern)
- `admin_send_campaign` → campaign_sends (sem org_id)
- `create_cost_entry` / `create_revenue_entry` / `update_sustainability_kpi` → finance tables com RLS USING(true) (Hard Blocker #1)

Se RLS está bem configurada, runtime é OK. Mas os contracts não documentam organization_id como requirement → ADR de defense-in-depth necessário (ADR-NEW-F).

**Findings:** A12, A13, A14, B6, B10, B12, B13, C1.

### Dim 2. Hardcoded Brand Strings (NEW: 12 admin pages/components)

**Estado:** 6 ocorrências "Núcleo IA & GP" em admin code (cycle-report header/footer, GovernanceCRTable export, GovernanceBatchModal CCB note, AdminDashboardIsland title fallback, report.astro subtitle default), 20 ocorrências PMI-GO/Goiás (sustainability options, webinars hard codes, governance gate labels, member edit defaults, VolunteerAgreementPanel, sponsor/liaison reports, cycle palette).

**Críticos:**
- A2: VolunteerAgreementPanel CNPJ + entidade legal (CRITICAL — bloqueador legal)
- A5: cycle-report.astro print header/footer + chapter palette
- A10/A11/B7/B8/B9: gate labels `president_go` em 5 lugares diferentes
- A8/A9: default `'PMI-GO'` em member edit forms
- A3: sustainability paid-by chapter options

**Findings:** A2, A3, A5, A6, A7, A10, A11, A15, B2, B3, B4, B5, B7, B8, B9, C7.

### Dim 3. URL/Infra Hardcoding (NEW: 1 admin-specific URL)

**Estado:** Em admin scope, `nucleoia.vitormr.dev` é referenciada **2 vezes** (cycle-report.astro print/screen footer + reuso indireto via ChainPDFDocument já-tracked). Plus:

- A1: `https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/posthog-proxy` — analytics proxy URL fixed to project Núcleo (CRITICAL via Hard Blocker #2 cascade)

**Findings:** A1, A5, B11.

### Dim 4. V3 Chapter (TEXT) vs V4 organization_id (NEW: 6 admin pages — STRUCTURAL)

**Estado crítico inteiramente novo:** `members.chapter` é uma TEXT column V3 legacy ("PMI-GO", "PMI-CE", etc.). `members.organization_id` é V4 source of truth (ADR-0004 introduced organization_id em ~40+ tables). Frontend admin **só edita o TEXT**, não o organization_id, e usa `p_chapter` TEXT em RPCs analytics/reports.

**Implicação:** Em multi-tenant, mismatch entre `members.chapter` ("PMI-GO") e `members.organization_id` (UUID) é silent corruption pathway. RPCs como `exec_chapter_dashboard(p_chapter TEXT)` resolvem chapter via TEXT column, não via organization_id.

**Findings:** A4 (webinars upsert), A12 (chapter-report), A13 (analytics), A14 (member edit), B12 (sustainability tables com RLS true), B13 (comms RPCs).

### Dim 5. Singleton Config Anti-Pattern (NEW: 4 admin pages)

**Estado:** `site_config` é tabela key/value singleton GLOBAL (já noted em Ω-A finding #16-anti-pattern). Em admin scope:

- `admin/settings.astro` → `set_site_config('group_term', ...)`, `set_site_config('cycle_default', ...)`, `set_site_config('webhook_url', ...)`
- `admin/report.astro` → `from('site_config').select('value').eq('key', 'report_config')` + `set_site_config('report_config', ...)`
- `admin/index.astro` → indirectly via `create_next_geral_meeting` que lê site_config para Meet/YouTube
- `admin/sustainability.astro` Targets tab → indirectly (kpi_targets em sustainability_kpi_targets, but config defaults em site_config)

**Findings:** A16, B1, C4, mais cross-cutting noted in `admin/settings.astro:loadConfig` and `loadPlatformSettings` (linha 372 `from('platform_settings').select('*')`).

### Dim 6. i18n Bypass / Brand Lock-in (NEW: 8 admin pages/components)

**Estado:** i18n bundles ~150+ keys com brand hardcoded já-tracked em Ω-A (#60). Em admin scope, problemas adicionais:

- A7: VolunteerAgreementPanel JSX wrapper PT-BR-only mesmo se locale=es-LATAM
- A10/A11: gate labels per-locale com PMI-GO hardcoded em 3 idiomas
- B2/B3/B4/B5: i18n fallback strings ("Núcleo de Estudos", "Núcleo IA & GP") quando key não existe
- C6: `timeAgo()` PT-BR-only
- C7: `OPROLE_LABELS`/`DESIG_LABELS` PT-BR module-scope

**Findings:** A7, A10, A11, B2, B3, B4, B5, C6, C7.

### Dim 7. Brazilian Governance Body Assumptions (NEW: 3 admin pages)

**Estado:** Admin assume governance bodies **brasileiros**:
- "CCB" (Comitê de Controle de Mudanças) em GovernanceBatchModal + GovernanceAdminIsland
- "Conselho Fiscal" (PMI-GO) em ChainAuditReport (B7)
- "Steering Committee multi-capítulos" em GovernanceAdminIsland disclaimer (B5)
- Lei 9.608/98 (volunteer law BR) em VolunteerAgreementPanel ANEXO (A2)

PMI-CE pilot teria os mesmos bodies (BR jurisdiction), mas estrutura específica de cada chapter pode variar. Para PMIs internacionais, assumptions quebram.

**Findings:** A2 (Lei 9.608), A10/A11/B7/B8 (gate labels), B5 (Steering Committee), B7 (Conselho Fiscal).

### Dim 8. Cycle/Year/Targets Hardcoded (NEW: 2 admin pages)

**Estado:**
- `admin/portfolio.astro:241`: `p_cycle: 3, p_year: 2026` literal
- `AdminDashboardIsland chapters_target` resolved via singleton `site_config`
- `admin/sustainability.astro` cycle 3 default

Each chapter has own cycle structure; hardcoding breaks 2nd chapter.

**Findings:** B1, C5.

---

## 4. Severity matrix consolidada

| Severity | Count | Notes |
|----------|-------|-------|
| **CRITICAL** | **2 NEW** | A1 (proxy URL Hard Blocker #2 cascade) + A2 (CNPJ legal blocker) |
| **HIGH** | **14 NEW** | Brand/V3 chapter/sustainability writes/comms infra |
| **MED** | **14 NEW** | i18n fallback/sidebar scoping/cycle hardcode/audit log |
| **LOW** | **7 NEW** | Cosmetic/pending decision items |
| **Already-tracked** | 6 overlaps | Reinforce existing 11 hard blockers |

---

## 5. Recommended ordering for ADR-NEW-A/B/C/D execution

Baseando-se em (a) dependências entre ADRs, (b) PMI-CE pilot blocking factor, (c) effort/complexity:

### Wave 1 — Pre-pilot blockers (must ship before 2nd chapter onboarding)

1. **ADR-NEW-A: Multi-tenant URL routing strategy** — admin URLs (e.g. `/admin/governance/documents/[chainId]`) precisam preserve chapter context. Decisão PM: subdomain (`pmi-ce.nucleoia.app`) vs path prefix vs separate deploys. **Affects:** A5, A12, A13, B11, ChainPDFDocument cascading. **Effort: L**

2. **ADR-NEW-D: Per-chapter MCP/EF/proxy endpoint** — `posthog-proxy`, `comms` channels, MCP server. Decisão: shared+JWT-scoped vs separate EFs vs hybrid. **Affects:** A1, B13. **Effort: L**

3. **NEW: ADR-NEW-H: Multi-tenant legal templates** (or extend ADR-NEW-E) — Volunteer Agreement template + CNPJ + entidade legal por chapter. CRITICAL legal blocker. **Affects:** A2. **Effort: M** (DB schema `chapter_legal_templates` + JSX wrapper resolution).

### Wave 2 — Pre-pilot enablement

4. **ADR-NEW-B: chapter_registry-driven config schema** — `chapter_registry.brand_config jsonb` + chapter_registry.contact_email + sustainability paid-by chapter list dynamic + member default chapter from session + Webinar chapter dropdown + analytics chapter options dynamic + cycle palette dynamic. **Affects:** A3, A6, A8, A9, A15, A16, B1, B2, B3, B4, B5, C4. **Effort: M**

5. **ADR-NEW-F: Frontend defense-in-depth — RPCs DEVEM passar `p_organization_id`** + admin RPCs migrated from V3 `p_chapter` TEXT to V4 `p_organization_id` UUID. **Affects:** A4, A12, A13, A14, B6, B10, B12, B13. **Effort: L** (server-side RPC migrations + frontend convention + lint rule).

### Wave 3 — Polish

6. **ADR-NEW-G: i18n bundles chapter-aware** — extract brand keys to per-chapter overlay; Volunteer Agreement JSX wrapper i18n-aware; OPROLE_LABELS/DESIG_LABELS per-locale; gate labels per-chapter. **Affects:** A7, A10, A11, B7, B8, B9, C6, C7. **Effort: XL** (split phases: extract → overlay → per-chapter packaging).

7. **NEW: organization_settings table** (replace site_config singleton) — `(organization_id, key, value)` PK. Migrate `general_meeting_link`, `whatsapp_gp`, `youtube_channel_url`, `kpi_targets_cycle_3`, `report_config`. **Affects:** Hard Blocker singleton anti-pattern. **Effort: M** (DB migration + read/write helpers + RPC updates).

### Quick wins (S effort, immediate sprint)

- A8/A9 (member default chapter): replace `\|\| 'PMI-GO'` with `\|\| getCurrentChapter()` resolved from session/window
- A6/A15 (placeholder examples): change PMI-GO placeholder to dynamic from chapter_registry
- B2/B3/B4/B5 (i18n fallbacks): pass non-Núcleo PT-BR strings or use Astro.url.host
- A3 (sustainability paid-by): replace static `<option>` with dynamic loop over `loadChapters()`
- B11 (URL context): preserve `?chapter=X` in cross-page links
- C5 (cycle/year hardcoded): resolve via `get_current_cycle` RPC

---

## 6. Critical observations

### 6a. Volunteer Agreement legal blocker (A2) é HARD STOP

Sem template per-chapter para o Termo de Voluntariado, **nenhum membro de PMI-CE pode assinar termo na plataforma sem fraude legal**. CNPJ 06.065.645/0001-99 é PMI Goiás, não PMI Ceará. Atualmente o JSON `template.content` é parsed do DB (boa idea), mas o WRAPPER JSX (header + preamble + signature block + Lei 9.608 ANEXO) é hardcoded. Para PMI-CE: precisa template de DB com {{cnpj}} {{entidade_legal}} {{diretor_label}} placeholders + JSX wrapper 100% i18n/data-driven.

### 6b. V3 chapter TEXT vs V4 organization_id é structural debt

Em ADR-0004 (V4) introduziu `organization_id UUID` em ~40+ tables. Em V3 legacy, `members.chapter` TEXT survived. Frontend admin **operates exclusively on V3 TEXT** em forms, RPCs, displays. Em multi-tenant pilot, isso é silent corruption pathway:
- GP de PMI-CE edita member, sets chapter='PMI-CE' (TEXT)
- `admin_update_member` updates `members.chapter` TEXT only
- `members.organization_id` (UUID) permanece pointing a Núcleo organization
- RLS depende de organization_id; member fica visible para Núcleo, hidden para PMI-CE

ADR-NEW-F deve ser **acoplado** a server-side migration: `admin_update_member` deve receber `p_organization_id` e atualizar **ambos** chapter TEXT (display) e organization_id (V4 source of truth) atomicamente.

### 6c. site_config singleton + sustainability RLS USING(true) reinforça Hard Blocker #1

Admin scope tem **dois** caminhos críticos para 2nd chapter:
1. `admin/sustainability.astro` (B12) escreve direto em `cost_entries`/`revenue_entries`/`sustainability_kpi_targets` — todas com RLS USING(true) (Hard Blocker #1) → cross-tenant data leak.
2. `admin/settings.astro` + `admin/report.astro` + `admin/index.astro` (A16, C4) escrevem em `site_config` singleton → cross-tenant config leak.

ADR-NEW-B (chapter_registry-driven config) e Hard Blocker #1 fix (organization_id em finance tables) **devem** ship juntos pre-pilot. Sem isso, GP-CE consegue apagar metas KPI de Núcleo (UNIQUE constraint Hard Blocker #8) e ler campos custo/receita do Núcleo.

### 6d. Audit log + governance é cross-tenant por design errado

`get_audit_log` (B10) e `mcp_usage_log` (Hard Blocker #5) são cross-tenant. Em multi-tenant, GP de chapter X poderia ver:
- Quem editou members em chapter Y
- Quais RPCs foram chamados por usuários de chapter Y
- Quais chains de governance estão em revisão em chapter Y (via `admin_list_archived_board_items` em governance-v2.astro:118)

Não é só feature gap — é **invariant violation pre-pilot** (data segregation entre chapters).

### 6e. Council recommendation alinhamento com Ω-A

Ω-A já propôs 7 ADRs (A-G). Ω-B confirma esses ADRs e adiciona:
- **Reinforce A2 → CRITICAL** (não é só brand, é legal/CNPJ)
- **NEW ADR-NEW-H** ou extension ADR-NEW-E (multi-tenant legal templates)
- **NEW: organization_settings table** (B6 do Ω-A flagged singleton mas não propôs migration explícita)
- **NEW: V4 RPC migration** (Dim 4 — V3 chapter TEXT → V4 organization_id) tem que ser sub-bloco de ADR-NEW-F

---

## 7. Sugestões pra Ω-E consolidation

Para consolidação no sub-agent E (synthesis):

1. **`ADMIN_MULTI_TENANT_READINESS_AUDIT.md`** — gap matrix admin-only complementando o doc Ω-A, com:
   - Coluna 1: dimension (1-8 listadas)
   - Coluna 2: % readiness por dimension
   - Coluna 3: blocker count (admin scope)
   - Coluna 4: ADR draft mapping
   - Coluna 5: estimated effort

2. **`PMI_CE_PILOT_GO_NO_GO_CHECKLIST.md`** — boolean checklist crítico:
   - [ ] CNPJ template per-chapter (A2)
   - [ ] sustainability_kpi_targets UNIQUE migration (Hard Blocker #8)
   - [ ] cost_entries/revenue_entries organization_id (Hard Blocker #1)
   - [ ] V4 RPC migration `admin_update_member(p_organization_id)` (A14)
   - [ ] site_config → organization_settings (A16, C4)
   - [ ] Audit log per-org filter (B10)
   - [ ] Webinar chapter dropdown dynamic (A4)
   - [ ] Posthog/Sentry per-tenant (A1)

3. **Critical observation pra PM**: o admin scope é **estruturalmente menos pronto** que o public scope para 2nd chapter onboarding. Public scope tem 60 issues, mas a maioria é brand strings (cosméticos). Admin scope tem 37 issues, dos quais **2 CRITICAL hard stops** (A1 proxy + A2 CNPJ) e **14 HIGH** que afetam data integrity (cross-tenant leak via RLS USING(true), V3/V4 desync, audit log cross-tenant). Wave 1 ADRs (A + D + H + organization_settings) **devem** ship pre-pilot, sem opção.

4. **Dependency tree**:
   - **ADR-NEW-A** (URL routing) é precondition para ADR-NEW-D (per-chapter EF endpoint) — host resolution feed
   - **ADR-NEW-B** (chapter_registry brand config) é precondition para ADR-NEW-G (i18n chapter overlay) — overlay reads brand_config
   - **ADR-NEW-F** (RPC org_id) é precondition para Hard Blocker #1 fix (sustainability RLS) — RLS policy depende de organization_id resolution
   - **ADR-NEW-H** (legal templates) é independente — pode ship em paralelo

5. **Cross-track impact**:
   - V4 ADR-0004 (organization_id introduction) é **upstream** de ADR-NEW-F, mas frontend admin não consumiu (V3 path lives on)
   - LGPD Art. 18 cycle (consent + export + delete + anonymize) é **upstream** de ADR-NEW-H — privacy policy per-chapter (Ω-A finding #9) cascateia sobre legal templates
   - V4 ADR-0007 `can_by_member()` é compatible com per-chapter authority via `engagement_kind_permissions` — mas seed expansion é anti-pattern (`feedback_v4_authority_audit_methodology.md`); per-chapter authority precisa nova matrix per-chapter, não seed expansion

---

## Fim do report

**Total NEW findings:** 37 (2 CRITICAL + 14 HIGH + 14 MED + 7 LOW)
**Cross-ref already-tracked:** 6 (sustainability/audit-log/governance PDF/mcp_usage_log)
**ADRs propostos NEW:** 1 (ADR-NEW-H legal templates) + extensions/reinforcements de A-G
**Critical blockers para PMI-CE pilot:** 2 hard stops (A1 + A2) + Hard Blocker #1 #5 #8 já-tracked → **5 blockers Wave 1**
**Quick wins (S effort, < 2h cada):** 6 itens listed (A8, A9, A6, A15, B2-B5, B11, C5)
