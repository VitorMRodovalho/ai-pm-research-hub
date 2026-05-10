# Ω-A Sweep — Tools Opportunities + DB + NF-e Research Report

**Sweep:** Páginas públicas (lang roots: `/`, `/en/`, `/es/`)
**Date:** 2026-05-09 (p134)
**Scope:** Triple-track — (1) external tool replacement evaluation, (2) DB FK/index/composite RPC opportunities, (3) Brazilian fiscal compliance research stub
**Strategic anchor:** `memory/project_chapter_pmis_saas_vision_p133.md` (Núcleo IA Hub = vertical PMIS/SaaS para PMI chapters)

---

## Executive summary (TL;DR)

- **External tools touched on public pages: 9** (Google Calendar, YouTube, Sympla, DocuSign-equivalent, Google Forms, Google Meet, WhatsApp, Airmeet, Credly).
- **HIGH-priority replacements identified: 5** — Sympla (ticketing+payment), Google Calendar (booking), Google Forms (lead/registration capture), DocuSign (lightweight signing), Airmeet (multi-language webinar).
- **DB gaps identified: 3 major** — cost/revenue tables WITHOUT `organization_id` (chapter scoping blocker), missing composite `(type, date)` index on `events` (hero burns ~1.16M tup_read on common filter), 1 RPC composite candidate covering 6 sequential calls in homepage hero.
- **NF-e research:** 3 viable Node.js libraries identified for NF-e/NFC-e modelo 55/65; for NFS-e (services — chapter use case predominante) the 2026 nacional padrão único é game-changer e elimina necessidade de integração city-by-city. Recomendação: começar com NFS-e nacional API (REST direct, sem lib), adicionar NFeWizard-io para NFC-e/NF-e quando ticketing scale.

---

## Track 1: Tool Replacement Evaluation

### Sumário

- Components/pages tocados na sweep: **18** (index.astro + 8 sections + about.astro + cpmai.astro + help.astro + webinars.astro + onboarding.astro + interview-booking/[token].astro + library.astro + governance.astro + initiatives.astro + teams.astro + publications.astro + admin/sustainability.astro)
- Tools external identificados como replaceable: **9**
- HIGH priority replacements: **5**

### Tabela de mapeamento

| Component/Page | Tool external substituído | Gap to parity | Effort (S/M/L/XL) | Backlog priority |
|---|---|---|---|---|
| `src/pages/interview-booking/[token].astro` (linhas 36, 124) | **Google Calendar** (https://calendar.app.google/gh9WjefjcmisVLoh7) | Slot picker UI + auto-add committee + Calendar provider sync (#92/#116 BLOCKED) | L | HIGH |
| `src/components/sections/HomepageHero.astro` (lines 224-272) | **Google Meet** (`meeting_link` external) | Internal video room (Jitsi/Daily.co self-host); auto-record→YouTube swap | XL | LOW (defer) |
| `src/components/sections/HeroSection.astro` (line 271, 275) + `webinars.astro` (line 86, 112) | **YouTube** (recording playback) | Token-gated video tier (paying attendees only); MP4 storage (R2 bucket) | M | LOW |
| `src/components/sections/ResourcesSection.astro` (lines 37, 45) + `TribesSection.astro` (line 254) | **YouTube playlist** (PLQJVKrw1fcr...) hardcoded | Internal video carousel from `events.youtube_url` indexed by tribe | S | LOW |
| `src/pages/webinars.astro` (line 86) — `w.meeting_link` | **Google Meet/Zoom** (webinar live) | Same as Hero — self-host video infra | XL | LOW |
| `src/pages/webinars.astro` + `webinars.sympla_event_url` column existing | **Sympla** (ticketing) | Internal ticket emission + payment direct-to-chapter-bank + NF-e/NFS-e + ticket QR + check-in + cert auto | XL | **HIGH (econômico)** |
| `src/pages/onboarding.astro` (line 83) → i18n `onboarding.step1.link` = `https://volunteer.pmi.org` | **External PMI VEP** (mandatory upstream) | N/A (PMI infra, fora de escopo replace) | — | N/A |
| `src/components/sections/ChaptersSection.astro` (lines 67-83) | **WhatsApp** (mailto fallback → wa.me upgrade) | Já 90%; #93 WhatsApp MCP integration future | S | MED |
| `src/pages/help.astro` (lines 60-66) | **WhatsApp** (contato GP) | Já implementado; gap = WhatsApp Business API direct vs deep-link | M | LOW |
| `src/components/sections/CpmaiSection.astro` + `cpmai.astro` | **Credly** (badge external) | OK existente; gap = Credly badge embed (vs link out) — minor UX | S | LOW |
| `src/pages/admin/sustainability.astro` (820 linhas) — costs/revenue/KPI tabs | **Google Sheets** (financial tracking external) | (a) chapter scoping (`organization_id`); (b) accounting account mapping; (c) bank account separation; (d) public transparency view; (e) NF-e/NFS-e link entry → invoice | XL | **HIGH** |
| `src/pages/blog/index.astro` (linhas 21-25) — `blog_posts` SSR | **Medium / WordPress** (chapter blog hosting) | Já internal; gap = chapter-scoped sub-blogs + RSS por chapter | M | MED |
| `src/pages/library.astro` (workspace knowledge cards) + ADR-0065 Drive | **Google Drive** (knowledge files) | OK existente; gap = chapter-scoped library + permission por chapter | M | LOW (já existing) |
| `src/pages/publications.astro` (PublicationsBoardIsland) | **ResearchGate / Academia.edu** (academic publishing) | Já internal w/ DOI optional; gap = DOI minting (CrossRef) | M | LOW |
| `src/pages/governance.astro` + member_document_signatures table | **DocuSign** (general signing) | Lightweight signing já 80% (governance chains); gap = ad-hoc doc signing fora de chains | M | MED |
| `src/pages/onboarding.astro` (deadline countdown, steps) | **Google Forms** (mandatory upstream PMI VEP only) | Internal form capture já existe (visitor_leads); gap = generic form builder | L | HIGH |
| `webinars.astro` + (`webinars.briefing_doc_url`, `promo_kit_url`) | **Google Drive / Notion** (briefings) | OK existente; gap = inline briefing editor | M | LOW |
| `src/pages/cpmai.astro` (CPMAI launch) | **Airmeet** (PMI Latam usa) | API integration (recordings/attendees/cert auto) | L | HIGH (CPMAI Latam considering) |

### Top 5 quick-wins (alto value, baixo effort)

1. **WhatsApp deep-link upgrade nas páginas de contato sem `site_config` check** — pattern já existe em ChaptersSection; replicar em help.astro, onboarding.astro fallback, etc. **Effort:** S. **Value:** Reduce mailto bounce (BR é WhatsApp-first).
2. **Internal video carousel from `events.youtube_url`** — substitui hardcoded playlist URLs em ResourcesSection.astro + TribesSection.astro com query dinâmica `events WHERE youtube_url IS NOT NULL ORDER BY date DESC LIMIT 5`. **Effort:** S. **Value:** Catálogo dinâmico (sem hardcode), elimina manual playlist update.
3. **Credly badge inline embed** em CpmaiSection (em vez de link out) — Credly suporta `<iframe>` embed. **Effort:** S. **Value:** Trust + retention on-page.
4. **Sub-blog scoping por chapter** em `/blog/?chapter=GO` — adicionar filtro query param + `chapter_code` column em blog_posts (se ainda não existe). **Effort:** S-M. **Value:** Multi-chapter narrative differentiation.
5. **Generic visitor form builder MVP** — extender `visitor_leads` schema com `form_kind` enum + JSON `extra_fields` jsonb; reuse capture_visitor_lead RPC. **Effort:** M. **Value:** Substitui Google Forms para leads/surveys/RSVP genérico.

### Top 5 strategic plays (alto value, alto effort, alto ROI multi-chapter)

1. **Sympla replacement = internal ticketing module** (event ticketing + payment direct + NF-e/NFS-e auto-emit + cert auto). Economia recorrente 5-10% por evento × N chapters. Substrato: webinars.sympla_event_url column atual indica desejo de migração; cost_entries.event_id FK existe; revenue_entries falta event_id FK (gap track 2). **Effort:** XL (3-4 sprints). **Value:** Cash flow direto-banco-chapter + audit trail + 5-10% margem recuperada.
2. **Sustentabilidade module → multi-chapter financial OS** (chapter scoping + accounting account mapping + bank separation + public transparency report per chapter). Substrato: 5 tabelas existem mas single-tenant. **Effort:** XL. **Value:** Prerequisite para Sympla replacement + diretoria-level accountability + LGPD-grade public transparency = vantagem reputacional vs chapters peers.
3. **Internal lightweight signing** (extend governance chains framework para ad-hoc docs sem aprovação multi-step). Substitui DocuSign para 80% casos chapter (declarações, termos curtos). **Effort:** L. **Value:** Recurring DocuSign cost saved + audit trail uniforme.
4. **Airmeet integration** (sync attendees + recordings + cert auto + simultaneous-translation playback). PMI Latam reference + CPMAI Latam EN/PT/ES alignment com D-7 trilingue. **Effort:** L. **Value:** Eliminates dual data entry (Airmeet attendee → cert manual); enables cross-region content.
5. **Calendar 2-way sync (provider-aware events)** — events.external_calendar_provider + sync_status columns já existem mas index `ix_events_sync_status_provider` tem 0 scans (não usado). Reativar com Apps Script bridge (#92/#116 BLOCKED PM action) ou Google Calendar API direct. **Effort:** L. **Value:** Eliminates duplo registro evento; chapter pode usar Calendar como source-of-truth com Núcleo como mirror.

---

## Track 2: DB Relationship + Index Opportunities

### FK constraints faltando

| Source table.col | Target table.col | Why missing matters | Severity |
|---|---|---|---|
| `cost_entries.organization_id` (NÃO EXISTE) | `organizations.id` | **BLOCKER** para multi-chapter financial. Sem essa coluna, sustentabilidade module é single-tenant. RPC chapter-scoped impossível. | CRITICAL |
| `revenue_entries.organization_id` (NÃO EXISTE) | `organizations.id` | Idem cost_entries; revenue tracking impossível por chapter. | CRITICAL |
| `revenue_entries.event_id` (NÃO EXISTE) | `events.id` | Sem rastreamento de receita por evento (Sympla → migração impossível sem isso). cost_entries TEM `event_id` mas revenue_entries não — assimetria que dói no relatório financeiro per evento. | HIGH |
| `revenue_entries.submission_id` (NÃO EXISTE) | `publication_submissions.id` | Sem rastreamento de receita por publication (e.g. patrocínio/venda ebook). cost_entries TEM essa FK; revenue não. | MED |
| `sustainability_kpi_targets.organization_id` (NÃO EXISTE) | `organizations.id` | KPI targets globais; impossível setar target diferente per chapter. | HIGH |
| `events.recurrence_group` (UUID col existente) | `recurring_event_groups.id` (presumo PK) | events.recurrence_group é UUID sem FK enforcement. Risk: orphan recurrence_groups apontando para grupo deletado. | LOW |
| `webinars.co_manager_ids` (text[]) | `members.id` | Array sem FK constraint; orphan member_ids podem persistir após offboarding. Mitigated by app-level checks but DB doesn't enforce. | LOW |
| `events.invited_member_ids` (text[]) | `members.id` | Mesmo padrão de webinars.co_manager_ids. PG arrays não suportam FK direto; alternativa = junction table (já existe `event_invited_members`!). Recomendação: migrar leitura para junction table e dropar coluna array (drift risk). | MED |
| `cost_entries.paid_by` (TEXT, não UUID) | `members.id` (deveria ser) | Usa text livre em vez de FK; nomes manuais entrarão (Vitor / vitor / V. Maia). Impede leaderboard de quem mais paga. | MED |

### Indexes opportunity

| Table | Column(s) | Query pattern (page) | Estimated benefit |
|---|---|---|---|
| `events` | **`(type, date DESC)` composite** | `HomepageHero.astro:224` `WHERE type='geral' AND date>=X ORDER BY date` | HIGH — hoje `idx_events_date` lê 1.158M tuples em 10K scans (média 100 tup/scan); com composite cairia para ~10 tup/scan (60 rows com type='geral'). 10x menos I/O em página mais visitada. |
| `events` | **`(type, date DESC) WHERE date >= NOW() - 14 days`** (partial) | Mesma query do hero, último 14d | MEDIUM — alternativa mais agressiva ao composite full. Index muito menor. |
| `cost_entries` | `event_id` | RPC `exec_portfolio_health` + sustentabilidade tab "Costs" filtros por evento | LOW — só FK existe sem index. Busca de custos por evento faz seq_scan (4 já registrados, baixo volume hoje mas crescerá). |
| `events` | `WHERE youtube_url IS NOT NULL` (partial sobre `(date DESC)`) | ResourcesSection.astro / TribesSection.astro (futuro replace de hardcoded URLs) | LOW (futuro) — só vale se quick-win #2 implementado. |
| `webinars` | `(status, scheduled_at DESC) WHERE status='confirmed'` (partial) | webinars.astro upcoming filter | LOW (volume baixo hoje); idx_webinars_status com 0 scans → dados ainda magros mas no scale faz sentido. |
| `member_document_signatures` | `(member_id, document_id) WHERE signed_at IS NOT NULL` | Query "minhas assinaturas" + governance check | MEDIUM (já tem FK mas sem composite). |

### Indexes a remover (over-indexed para volume atual)

| Index | Reason | Action |
|---|---|---|
| `events.idx_events_artia_stale` | 0 scans desde criação | KEEP (recente, vai pegar uso quando Artia sync rodar) |
| `events.idx_events_calendar_id` (UNIQUE WHERE NOT NULL) | 0 scans | KEEP (defesa de duplicação calendar_event_id) |
| `events.idx_events_minutes_fts` (GIN portuguese) | 0 scans | EVALUATE — se nunca usar full-text search em minutes, drop poupa write cost |
| `events.ix_events_sync_status_provider` | 0 scans | KEEP (designed para futuro cron Calendar sync; #92/#116) |
| `webinars.*` quase todos com 0 scans | volume = 6 webinars total | KEEP all (overhead negligible em low-volume) |
| `visitor_leads.idx_visitor_leads_chapter`, `idx_visitor_leads_email_norm`, `idx_visitor_leads_referrer` | 0 scans cada | EVALUATE — se rotina admin de promote_lead / dismiss_lead nunca usa esses filtros, são dead weight. Pelo menos `email_norm` é importante para dedupe (constraint check?). Confirmar antes drop. |

### RPC composite candidates

| Page / Component | Sequential RPCs called | Suggested composite RPC | Effort |
|---|---|---|---|
| `src/components/sections/HomepageHero.astro` (logged-in member view, lines 196-344) | 6 sequential round-trips: `get_homepage_stats` → `events SELECT type=geral` → `tribes SELECT meeting_link` → `tribe_meeting_slots SELECT` → `get_attendance_panel` → `get_dropout_risk_members` (GP only) | **`get_member_homepage_bundle(p_member_id)`** retornando JSON `{stats, next_general_event, my_tribe, attendance_summary, dropout_alert (if GP)}`. Reduz 6 round-trips para 1. | **L** — RPC orchestrator não-trivial mas alta visibilidade. Prerequisite: cleanup de member views. |
| `src/components/sections/TribesSection.astro` (lines 522-543) member tribe details | 3 sequential: `tribe_selections SELECT` → `tribe_meeting_slots SELECT` → `tribes SELECT` | **`get_my_tribe_summary()`** retornando bundle. | M |
| `src/pages/initiatives.astro` (lines 81-99) member view | 3 sequential: `list_initiatives` RPC → `persons SELECT id` → `engagements SELECT initiative_id WHERE active` | **`list_initiatives_with_my_membership()`** — server-side join dispensa client orchestration. | M |
| `src/components/sections/CpmaiSection.astro` (line 80) | 1 query (`public_members SELECT WHERE cpmai_certified...`) — OK como está | — | — |

---

## Track 3: Brazilian NF-e/Cupom Fiscal Research

**Critical 2026 context** (descoberto durante research): a partir de **1º Janeiro 2026** todas NFS-e (serviços) devem seguir **padrão único nacional** (Lei Complementar 214/2025); Simples Nacional obrigatório a partir de **Set/2026**. Isso muda fundamentalmente o approach: para NFS-e (caso predominante de chapters PMI, que vendem serviços de evento/treinamento, NÃO bens), basta integrar com **API REST do Ambiente Nacional NFS-e** — não precisa lib city-by-city como antes. Economia massiva de complexidade.

NF-e (modelo 55, bens) e NFC-e (modelo 65, consumo varejista) ainda dependem de SEFAZ por estado, então biblioteca ainda valiosa caso ticketing scale para mercado de produtos.

### Top 3 repos candidatos (Node.js para NF-e/NFC-e)

#### 1. NFeWizard-io — https://github.com/nfewizard-org/nfewizard-io

- **License:** **GPL-3.0** ⚠️ (copyleft — incompatível com modelo SaaS proprietário se inclui o código diretamente; OK se usado como dependency externa em Worker isolado)
- **Stars:** 202 · **Forks:** 33 · **Contributors:** múltiplos ativos
- **Latest version:** 0.3.1 (Jan 2025; versão 1.0.0 monorepo planejada)
- **Last commit:** ativo (commits recentes 2025-2026)
- **Maturity:** **BETA→STABLE** (uso em produção em vários setups; modular monorepo reduce bundle 77%)
- **Operations:** NF-e (55), NFC-e (65), NFS-e (beta), CT-e — autorização, queries, inutilização, cancelamento, carta de correção, DANFE
- **Node version:** ≥16
- **TypeScript-first:** 95.1% TS
- **Pros:**
  - Cobertura mais ampla (NF-e + NFC-e + NFS-e beta + CT-e em uma lib)
  - TS-first (alinhado stack Núcleo)
  - Modular packages → bundle leve quando só precisar 1 doc type
  - Comunidade ativa
- **Cons:**
  - **GPL-3.0** — strong copyleft; embedding direto em código fechado pode forçar AGPL. Como Núcleo é arch CC-BY-SA / MIT (frameworks repo), pode ser OK, mas exige análise legal explícita (legal-counsel sub-agent).
  - Requer JDK opcional para algumas funções de assinatura/schema (problema em Cloudflare Workers — sem JVM)
  - A1 cert only (chapter precisa adquirir certificado A1)
- **Integration path:** **Edge Function dedicada** (Deno permite chamadas SOAP via XML manual + crypto subtle); ou **Worker Node-compat** (cloudflare wrangler 2024+ suporta node-compat flag — XML signing requer subset Node crypto). Schema validation pode rodar serverless se desabilitar JDK part. Recomendação: **Edge Function dedicada `nfse_emit`/`nfe_emit`** chamando lib via npm import (Deno tem `npm:` specifier).

#### 2. node-sped-nfe — https://github.com/kalmonv/node-sped-nfe

- **License:** Tem LICENSE.md (verificar — provavelmente MIT ou Apache; confirmar antes adoção)
- **Stars:** 40 · **Forks:** 13 (menor que NFeWizard mas ativo)
- **Latest version:** 1.2.44 (npm `node-sped-nfe`, Out 2025 — RECENTE, ATIVO)
- **TypeScript:** 95.7% TS, 4.3% JS
- **Maturity:** **STABLE** — 118 commits, releases recorrentes
- **Operations:** NF-e (55), NFC-e (65), status SEFAZ, cancelamento, carta de correção, inutilização, manifestação destinatário (4 tipos), DistNFe
- **Pros:**
  - Versionamento ativo (Out 2025 release recente)
  - Cobertura completa NF-e/NFC-e
  - License provavelmente permissiva (vs GPL do NFeWizard)
  - Mais focado, menos overhead
- **Cons:**
  - Não cobre NFS-e nem CT-e (OK porque NFS-e nacional 2026 muda esse caminho)
  - Comunidade menor
  - Verificar Node version requirement
- **Integration path:** **Edge Function `nf_emit`** chamando via `npm:node-sped-nfe@1.2.44`. Mais leve que NFeWizard se só precisar NF-e/NFC-e.

#### 3. node-dfe — https://github.com/lealhugui/node-dfe

- **License:** **MIT** ✅
- **Stars:** 258 · **Forks:** 97 (maior comunidade que sped-nfe)
- **Latest version:** v0.0.25 (Mar 2022)
- **Status:** **ARCHIVED** desde Abr 2024 ❌ (read-only)
- **Maturity:** **MATURE BUT INACTIVE**
- **Operations:** NF-e (55), NFC-e (65) — emissão sync/async, cancelamento, CCe, inutilização
- **Pros:**
  - License MIT (mais permissiva)
  - Comunidade existente (forks alta)
  - Implementação testada
- **Cons:**
  - **ARQUIVADO** — não recebe security updates, schemas SEFAZ podem ter mudado desde 2022
  - Node 8+ (antigo)
  - Manutenção depende de fork
- **Integration path:** Não recomendado novo projeto. Útil somente como referência arquitetural.

### Recommendation

**Strategy faseada:**

**Fase 1 — NFS-e (predominante para chapters PMI vendendo serviços de evento/treinamento):**
- Use **API REST do Ambiente Nacional NFS-e** direto (não precisa lib).
- Integration via Edge Function `nfse_emit` chamando endpoint REST com payload JSON; SEFAZ retorna NFS-e XML + protocolo.
- Documentação: https://www.gov.br/receitafederal/pt-br (Receita Federal coordena padrão nacional 2026).
- **Vantagem:** padronizado nacional desde Jan/2026; sem complexidade city-by-city; sem certificado A1 obrigatório (ainda confirmar — mas Simples Nacional usa eCNPJ ou eCPF).

**Fase 2 — NFC-e (se ticketing scale para venda de produtos físicos, ex. livros impressos PMI):**
- Use **node-sped-nfe** (license permissiva + manutenção ativa Out/2025 + foco TypeScript).
- Edge Function `nfce_emit` separada.
- Fallback: NFeWizard-io (mais features mas GPL-3.0; usar com cautela).

**Fase 3 — NF-e modelo 55 (B2B, raríssimo para chapters):**
- Mesma lib que NFC-e (node-sped-nfe ou NFeWizard).
- Provavelmente nunca será necessário em scope chapter-PMI.

**Fallback se nenhuma lib JS encaixar:**
- **PHP** — `nfephp-org/sped-nfe` (lib mais madura do ecossistema brasileiro, 2.5K stars). Requer Edge Function PHP runtime (Vercel funciona; Cloudflare Workers NÃO suporta PHP — alternativa = serverless container Cloud Run).
- **Python** — várias opções (`pynfe`, `erpbrasil.edoc`); requer container.
- **Recomendação fallback:** evitar — duplica runtime. Preferir refactoring lib JS se gap específico (ex. um state SEFAZ não suportado).

### Integration architecture sketch

```
┌─────────────────────────────────────────────────────────────────┐
│ Chapter user (admin sustainability page)                         │
│ "Confirmar venda ticket evento → emit NFS-e"                     │
└────────────────────┬────────────────────────────────────────────┘
                     │ POST /functions/v1/emit-fiscal-doc
                     │ { type:'nfse', event_id, customer:{...}, amount }
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Edge Function: emit-fiscal-doc (Deno)                            │
│   ├─ Validar input (Zod schema)                                  │
│   ├─ Lookup chapter config (chapter_fiscal_config table — NEW):  │
│   │     - cnpj, ie, im, certificate_a1_url (Vault secret)        │
│   │     - city_code (IBGE), tax_regime (Simples / Lucro Real)    │
│   ├─ Lookup event + amount + customer                            │
│   ├─ Build NFS-e payload conforme padrão nacional 2026           │
│   ├─ Sign XML com cert A1 (Web Crypto API; subset RSA-SHA1)      │
│   ├─ POST https://nfse.gov.br/api/v1/dps (Receita Federal)       │
│   ├─ Receive { protocol, xml, pdf_url }                          │
│   ├─ INSERT INTO fiscal_documents (NEW table)                    │
│   ├─ INSERT INTO revenue_entries (event_id, amount, fiscal_id)   │
│   └─ Return { success, protocol, pdf_url } to frontend           │
└─────────────────────────────────────────────────────────────────┘
                                                ▼
                                    Receita Federal (NFS-e nacional)
                                                ▼
                              Customer email com PDF anexo (transactional)
```

**Tabela nova proposta `chapter_fiscal_config`** (substrato chapter-level):
```
id uuid PK
organization_id uuid FK organizations(id)  -- CHAPTER
cnpj text NOT NULL
ie text  -- Inscrição Estadual
im text  -- Inscrição Municipal
city_code text  -- IBGE 7 dígitos
tax_regime text CHECK ('simples' | 'lucro_real' | 'lucro_presumido')
cert_a1_vault_key text  -- key in Supabase Vault, NÃO o certificado em si
cert_expires_at timestamp
default_service_code text  -- código municipal serviço prestado
default_iss_pct numeric
created_at, updated_at
```

**Tabela nova proposta `fiscal_documents`** (audit trail + redownload):
```
id uuid PK
organization_id uuid FK
type text CHECK ('nfse' | 'nfce' | 'nfe')
fiscal_protocol text  -- NSU/recibo SEFAZ
xml_url text  -- R2 bucket
pdf_url text  -- R2 bucket
amount_brl numeric
customer_doc text  -- CPF/CNPJ
event_id uuid FK events  -- nullable, link ao evento se ticketing
revenue_entry_id uuid FK revenue_entries  -- 1:1 com receita
status text  -- 'authorized' | 'cancelled' | 'rejected'
emitted_at timestamp
cancelled_at timestamp
metadata jsonb  -- xml/json original SEFAZ response
```

---

## Sugestões pra Ω-E consolidation

Documentos sugeridos para consolidação na onda Ω-E (handed off para sub-agents D + E):

1. **`docs/strategy/EXTERNAL_TOOL_REPLACEMENT_ROADMAP.md`** — consolida Track 1 com fases (Quick wins → Strategic plays) + dependency graph + estimativas de effort.
2. **`docs/strategy/AIRMEET_INTEGRATION_OPPORTUNITY.md`** — spec técnico da integração (sync attendees + recordings + cert auto + multi-language). Use case CPMAI Latam.
3. **`docs/strategy/SYMPLA_REPLACEMENT_FEASIBILITY.md`** — análise econômica (5-10% fee saved × N events × N chapters) + fluxo end-to-end (ticket → payment direct → check-in → cert → fiscal doc) + integração com `webinars.sympla_event_url` migration path (transitional dual-write).
4. **`docs/strategy/DB_OPPORTUNITY_BACKLOG_P134.md`** — Track 2 consolidado com migrations sugeridas (cada FK / index / RPC composite vira issue concreta + ADR draft).
5. **`docs/strategy/NFE_INTEGRATION_RESEARCH_P134.md`** — Track 3 consolidado + arquitetura proposta + spec de `chapter_fiscal_config` + `fiscal_documents` tables + decisão NFS-e nacional API vs lib + risk register (cert A1 management, Vault integration, Web Crypto subset RSA-SHA1, audit trail LGPD).
6. **`docs/adr/ADR-0077-multi-tenant-financial-architecture.md`** (proposto) — formaliza decisão "cost_entries / revenue_entries / sustainability_kpi_targets receberão organization_id em V5 financial refactor". Encadeia naturalmente com strategic anchor PMIS/SaaS.
7. **`docs/adr/ADR-0078-internal-ticketing-module-sympla-replacement.md`** (proposto) — formaliza decisão "Núcleo emite tickets internamente, payment direct-to-chapter-bank, NFS-e auto-emit; Sympla sai gradualmente".
8. **`docs/adr/ADR-0079-fiscal-doc-emission-via-edge-function.md`** (proposto) — escolha técnica Edge Function vs Worker para NFS-e/NFC-e; license analysis (NFeWizard GPL-3.0 vs node-sped-nfe permissive); risk register cert management.

---

## Observações finais para PM

- **Maior surpresa Track 2:** descoberta de que `cost_entries` e `revenue_entries` não têm `organization_id`. Isto é hard-blocker para qualquer pilot multi-chapter financial. Migration deveria entrar antes de qualquer trabalho Sympla replacement.
- **Maior surpresa Track 3:** a NFS-e nacional padrão único em vigor desde Jan/2026 simplifica drasticamente o roadmap. Ao invés de precisar lib de mil cidades diferentes, basta REST API direct com Receita Federal. Isto desbloqueia internal ticketing module com effort menor do que estimado pré-research.
- **Quick win imediato sugerido:** index composite `(type, date DESC)` em events — implementação trivial (1 migration) com benefit observável imediato (homepage hero ~10x menos I/O).
- **Decisão pendente para PM:** Sympla replacement vai antes de Airmeet integration ou vice-versa? Sympla tem ROI direto-mensurável (fee economy); Airmeet tem ROI estratégico (CPMAI Latam alignment + diferenciação multi-language). Recomendação: começar por **Sustentabilidade multi-chapter refactor (V5 financial)** como prerequisite de ambos, depois Sympla (econômico) depois Airmeet (estratégico).
- **Council referrals sugeridos para Ω-E:**
  - **legal-counsel** sub-agent: validar GPL-3.0 do NFeWizard-io vs licensing model Núcleo
  - **security-engineer** sub-agent: cert A1 management via Vault + Web Crypto subset RSA-SHA1 viability em Cloudflare Workers
  - **data-architect** sub-agent: review chapter_fiscal_config + fiscal_documents schemas + V5 financial refactor scope
  - **vc-angel-lens** sub-agent: pricing model PMIS/SaaS (revenue model: per-chapter sub vs fee-on-ticket vs freemium)
