# Ω-A Sweep — Multi-Client / Whitelabel Gaps Report

**Sessão:** p134 Ω-A Trilingue Boot
**Sub-agent:** multi-client-mapper
**Escopo:** Páginas públicas (root + blog + docs + tribe + initiative + workspace + governance público + me + settings + publications + interview-booking + pmi-onboarding + volunteer-agreement + privacy + about + components consumidos)
**Excluído:** `admin/`, `api/`, `en/`, `es/`, `oauth/`, `.well-known/`
**Estado de origem:** Núcleo IA Hub é vertical PMIS/SaaS multi-tenant by design, mas implementação tem ZERO scoping explícito por organization no frontend. Pilot futuro PMI-CE (chapter_registry seeded ativo, `is_contracting=false`) seria bloqueado.

---

## Sumário

- **Páginas públicas auditadas:** 51 (`*.astro` e `*.ts` excluindo admin/api/en/es/oauth/.well-known)
- **Componentes auditados:** ~30 (sections, governance, help, islands, layouts, nav)
- **HIGH severity findings:** 14
- **MED severity findings:** 17
- **LOW severity findings:** 9
- **Total: 40 itens flagged**

### Stats brutos do grep
- `Núcleo IA` / `Nucleo IA` em texto/copy: **28 ocorrências** (excl. admin/i18n bundles)
- `PMI-GO` / `pmigo` / `Goiás`: **29 ocorrências**
- `nucleoia.vitormr.dev` hardcoded: **19 ocorrências**
- `organization_id` usado em queries frontend: **0 ocorrências** (críticol — RLS server-side é ÚNICA defesa)

### Estado da database (chapter scaffolding)
- ✅ `chapter_registry` table existe, 5 chapters seeded (GO, CE, DF, MG, RS) com `chapter_code`, `legal_name`, `state`, `country`, `logo_url`, `is_contracting_chapter`
- ✅ `organizations` table existe (1 row: `nucleo-ia` com `slug`, `website_url`, `logo_url`, `status`)
- ✅ `organization_id` column existe em ~40+ tabelas (V4 ADR-0004) com FKs
- ❌ NÃO existe tabela `chapter_brand_config`, `chapter_settings`, `tenant_config`, ou `organization_settings`
- ❌ `organizations.logo_url` e `website_url` são NULL pra "nucleo-ia"
- ⚠️ `site_config` é singleton key/value GLOBAL (não tenant-scoped) — guarda `whatsapp_gp`, `youtube_channel_url`, `kpi_targets_cycle_3`, `general_meeting_*`

---

## Tabela detalhada (HIGH severity primeiro)

| # | File | Line | Issue | Dim | Sev | Fix complex | Backlog cand |
|---|------|------|-------|-----|-----|-------------|--------------|
| 1 | `src/lib/supabase.ts` | 21-23 | `FALLBACK_SUPABASE_URL`/`FALLBACK_SUPABASE_ANON_KEY` hardcoded ao projeto Núcleo (`ldrfrvwhxsmgaabwmaik`) | 5/8 | HIGH | M | yes |
| 2 | `src/middleware.ts` | 7 | `CANONICAL_HOST = "nucleoia.vitormr.dev"` hardcoded — single tenant. Multi-chapter requer dynamic detection ou subdomain match | 8 | HIGH | L | yes |
| 3 | `src/middleware.ts` | 8-12 | `LEGACY_HOSTS` array fixo — não acomoda hosts legados de outros chapters | 8 | HIGH | M | yes |
| 4 | `src/lib/sentry.ts` | 7 | `Sentry.init` com DSN único — todos os chapters reportariam ao mesmo project | 5/8 | HIGH | M | yes |
| 5 | `src/layouts/BaseLayout.astro` | 121-148 | PostHog single project (`PUBLIC_POSTHOG_KEY`) — events de todos os chapters misturados | 5/8 | HIGH | M | yes |
| 6 | `src/layouts/BaseLayout.astro` | 222-229 | `safePH('group', 'chapter', m.chapter || 'unknown')` — usa `m.chapter` (text) mas não há fallback se chapter ≠ Núcleo. Não usa `organization_id` | 1/8 | HIGH | S | yes |
| 7 | `src/layouts/BaseLayout.astro` | 48 | `og:site_name="Núcleo IA & GP"` hardcoded — todo SEO/social share é PMI-GO | 2 | HIGH | S | yes |
| 8 | `src/layouts/BaseLayout.astro` | 54 | `<link rel="icon" href="/favicon.svg">` hardcoded — não chapter-scoped | 7 | HIGH | S | yes |
| 9 | `src/pages/privacy.astro` | 38-40 | `dpo@pmigo.org.br`, `Ivan Lourenço Costa`, `Angeline Altair Silva Prado` hardcoded — privacy policy = único PMI-GO version | 6 | HIGH | M | yes |
| 10 | `src/pages/about.astro` | 27,30-36 | `og:url=https://nucleoia.vitormr.dev/about` + JSON-LD `ResearchOrganization` com `name`/`url` Núcleo hardcoded | 2/3/8 | HIGH | M | yes |
| 11 | `src/pages/.well-known/oauth-authorization-server.ts` | 7 | `BASE = "https://nucleoia.vitormr.dev"` — OAuth metadata aponta a 1 host | 3/5 | HIGH | M | yes |
| 12 | `src/pages/.well-known/oauth-protected-resource.ts` | 7 | Mesmo problema do #11 | 3/5 | HIGH | M | yes |
| 13 | `src/pages/mcp.ts` | 17 | `BASE = 'https://nucleoia.vitormr.dev'` no proxy MCP — todos os chapters compartilhariam o MCP server único | 5 | HIGH | L | yes |
| 14 | `src/components/sections/ChaptersSection.astro` | 18-20 | `ANNOUNCED_TOTAL = 15` hardcoded literal "15 capítulos PMI Brasil" — copy quebra se segundo chapter operar instância isolada | 2 | HIGH | S | no (cosmético se segundo chapter operar isoladamente) |
| 15 | `src/pages/initiatives.astro` | 82,93-97 | `list_initiatives` RPC + `engagements` query sem `organization_id` filter — depende 100% RLS server-side | 1 | HIGH | M | yes |
| 16 | `src/pages/workspace.astro` | 371-411,505,592,623,656,691,756 | 9 RPCs/queries sem chapter scope (boards, events, alerts, near_events, presence, onboarding, publications) — dependem 100% RLS | 1 | HIGH | L | yes |
| 17 | `src/pages/library.astro` | 279,388,420,424 | `from('tribes')` + `search_hub_resources` + `from('hub_resources')` sem org scope | 1 | MED | M | yes |
| 18 | `src/pages/teams.astro` | 115 | `from('cycle_tribe_dim')` sem org scope | 1 | MED | S | yes |
| 19 | `src/pages/gamification.astro` | 597,811 | `from('tribes')`, `from('gamification_points')` sem org scope | 1 | MED | M | yes |
| 20 | `src/pages/webinars.astro` | 19 | `list_webinars_v2` sem org scope | 1 | MED | S | yes |
| 21 | `src/pages/changelog.astro` | 152 | `get_changelog` global single source | 1 | MED | S | yes |
| 22 | `src/pages/blog/index.astro` | 21,91 | `from('blog_posts')` + `get_blog_likes_batch` sem org scope | 1 | MED | M | yes |
| 23 | `src/pages/publications.astro` | 190,288 | Bibtex + JSON-LD com `publisher: "Núcleo IA & GP — PMI Brazilian Chapters"` hardcoded | 2 | HIGH | M | yes |
| 24 | `src/pages/governance/glossario.astro` | 59,66,156 | "Núcleo IA & GP" + "sediado em PMI Goiás (PMI-GO)" hardcoded | 2 | HIGH | S | yes |
| 25 | `src/pages/volunteer-agreement.astro` | 53 | `<div>...PMI Goiás — Núcleo de Estudos...</div>` hardcoded no PDF | 2 | HIGH | M | yes |
| 26 | `src/pages/onboarding.astro` | 29 | `link: 'mailto:nucleoia@pmigo.org.br'` hardcoded — onboarding step 2 quebra para outros chapters | 4 | HIGH | S | yes |
| 27 | `src/pages/help.astro` | 300 | "Olá, preciso de ajuda com a plataforma do Núcleo IA." hardcoded copy | 2 | MED | S | yes |
| 28 | `src/pages/interview-booking/[token].astro` | 39-41,109,142 | Title + 2x mailto `nucleoia@pmigo.org.br` hardcoded | 2/4 | HIGH | S | yes |
| 29 | `src/pages/pmi-onboarding/[token].astro` | 40-42,66 | Title + mailto `nucleoia@pmigo.org.br` hardcoded | 2/4 | HIGH | S | yes |
| 30 | `src/pages/blog/[slug].astro` | 54,62-63 | Title `\| Núcleo IA & GP`, `og:url`, `og:image` hardcoded ao Núcleo | 2/3 | MED | S | yes |
| 31 | `src/pages/blog/feed.xml.ts` | 30,32,34 | RSS feed `title: 'Núcleo IA & GP — Blog'`, `site: 'https://nucleoia.vitormr.dev'` | 2/3 | MED | S | yes |
| 32 | `src/pages/publications/feed.xml.ts` | 30,32 | Mesmo padrão do #31 | 2/3 | MED | S | yes |
| 33 | `src/pages/meetings.astro` | 10-12,26 | `'Atas de Reunião — Núcleo IA & GP'` + `og:url=nucleoia.vitormr.dev` | 2/3 | MED | S | yes |
| 34 | `src/pages/webinars.astro` | 44,47 | Title `${...}— Núcleo IA & GP` + `og:url=nucleoia.vitormr.dev` | 2/3 | MED | S | yes |
| 35 | `src/pages/stakeholder.astro` | 26 | "Bem-vindo à plataforma do Núcleo IA & GP" fallback hardcoded (i18n key existe mas fallback é PT-BR Núcleo) | 2 | LOW | S | no |
| 36 | `src/pages/docs/mcp.astro` | 3,168 | "Núcleo IA & GP" comment + `nucleoia.vitormr.dev/mcp` link | 5/2 | MED | S | yes |
| 37 | `src/pages/governance/ip-agreement.astro` | 80 | Title PDF `'Termo... — Núcleo de IA & GP'` hardcoded | 2 | MED | S | yes |
| 38 | `src/pages/governance/my-pending.astro` | 58 | Label `president_go: 'Presid. PMI-GO'` (chapter-specific role labels) | 2 | MED | M | yes |
| 39 | `src/pages/404.astro` | 33 | `https://github.com/VitorMRodovalho/ai-pm-research-hub/issues` (repo único) | 3 | LOW | S | no |
| 40 | `src/pages/api/calendar-webhook.ts` | 184 | GitHub repo URL hardcoded em error response (api/ tecnicamente excluído mas é compartilhado) | 3 | LOW | S | no |
| 41 | `src/components/sections/ChaptersSection.astro` | 57,68 | `mailto:nucleoia@pmigo.org.br` hardcoded como CTA fallback (upgrade a WhatsApp via `site_config.whatsapp_gp` que TAMBÉM é singleton global) | 4 | HIGH | M | yes |
| 42 | `src/components/sections/ResourcesSection.astro` | 70,78 | GitHub repo URL + `mailto:nucleoia@pmigo.org.br` hardcoded | 3/4 | MED | S | yes |
| 43 | `src/components/sections/TeamSection.astro` | 120-122 | `chapterLogos` fallback `'PMI-GO': '/assets/logos/pmigo.png'` etc — PMI-Brasil fixed | 7 | MED | S | yes |
| 44 | `src/components/sections/TeamSection.astro` | 124 | `FALLBACK_CHAPTER_ORDER = ['PMI-GO','PMI-CE',...]` — order assumido | 7 | LOW | S | no |
| 45 | `src/components/help/HelpFloatingButton.tsx` | 271-273,454,457-458 | 3 i18n strings + GitHub URL + `mailto:nucleoia@pmigo.org.br` hardcoded em 3 línguas | 4/3/2 | HIGH | S | yes |
| 46 | `src/components/pmi-onboarding/PMIOnboardingPortal.tsx` | 175,182,189,1021 | "Por que o Núcleo IA & GP?" hardcoded em 3 línguas + mailto Núcleo | 2/4 | MED | S | yes |
| 47 | `src/components/onboarding/PreOnboardingChecklist.tsx` | 43 | i18n strings com "blog do Núcleo" / "Núcleo" hardcoded em hint_pt/en/es | 2 | LOW | S | no |
| 48 | `src/components/governance/ChainPDFDocument.tsx` | 377,390,519,548 | PDF: `creator="Núcleo IA & GP"`, `<Text>PMI Brasil–Goiás Chapter · nucleoia.vitormr.dev</Text>`, fmt platform footer, link `nucleoia.vitormr.dev/admin/...` | 2/3 | HIGH | M | yes |
| 49 | `src/components/governance/ChainAuditReportPDF.tsx` | 4,127,147-148,154,377 | PDF auditoria: "Conselho Fiscal PMI-GO", `subject="Auditoria Conselho Fiscal PMI-GO"`, `<Text>PMI Brasil–Goiás Chapter</Text>`, footer `Plataforma: nucleoia.vitormr.dev` | 2/3 | HIGH | M | yes |
| 50 | `src/components/governance/ChainAuditReportIsland.tsx` | 58,60 | "Conselho Fiscal PMI-GO" hardcoded no UI heading | 2 | MED | S | yes |
| 51 | `src/components/governance/ReviewChainIsland.tsx` | 35,47 | `president_go: 'Presid. PMI-GO'`, `'Assinar como presidência PMI-GO'` | 2 | MED | M | yes |
| 52 | `src/components/governance/DocumentVersionEditor.tsx` | 41 | `president_go: 'Presid. PMI-GO'` label | 2 | LOW | S | no |
| 53 | `src/components/islands/ImpactPageIsland.tsx` | 58,524 | "Iniciativa colaborativa entre capítulos do PMI® no Brasil" + `mailto:nucleoia@pmigo.org.br` | 2/4 | MED | S | yes |
| 54 | `src/components/meetings/MeetingsPage.tsx` | 356 | PDF footer "Núcleo de IA & GP — nucleoia.vitormr.dev" hardcoded | 2/3 | MED | S | yes |
| 55 | `src/components/attendance/RecurringModal.astro` | 23 | Default value `"Reunião Geral — Núcleo IA & GP \| Semana {n}"` em form | 2 | LOW | S | no |
| 56 | `src/components/sections/HomepageHero.astro` | 38 | `text-[#05BFE0]` hardcoded color literal — escapou o sistema de tokens | 7 | LOW | S | no |
| 57 | `src/components/nav/Nav.astro` | 137-140 | `bg-navy/97`, `border-orange`, `text-orange` — cores PMI fixadas. Tokens são `--color-navy` etc. mas valores `:root` são únicos | 7 | MED | M | yes |
| 58 | `src/styles/theme.css` | 18-100 | `:root { --color-navy: #003B5C; --color-orange: #FF610F; ... }` — tokens são GLOBAL, não chapter-scoped. `data-theme="dark"` toggle existe mas não há `data-chapter="..."` paralelo | 7 | HIGH | L | yes |
| 59 | `src/lib/chapters.ts` | 28-65 | `loadChapters()` lê `chapter_registry` mas NÃO há tipo `Chapter.brand_config` jsonb — gap upstream pra whitelabel | 2/7 | MED | M | yes |
| 60 | i18n bundles `src/i18n/{pt-BR,en-US,es-LATAM}.ts` | múltiplas | ~150+ keys com "Núcleo IA & GP" / "Goiás" / "PMI Brasil" hardcoded — bundle inteiro é PMI-GO targeted | 2 | HIGH | XL | yes |

---

## Findings agrupados por dimensão

### 1. organization_id usage gaps (HIGH urgency)

**Estado:** ZERO ocorrências de `organization_id` ou filtros de chapter no frontend público.

A defesa contra cross-tenant leak depende 100% de RLS policies server-side via `org_scope()` helper. Se RLS está bem configurada (V4 ADR-0004), não há leak. Mas:

- Frontend não envia `p_organization_id` em RPCs como `list_initiatives`, `list_active_boards`, `get_changelog`, `search_hub_resources`, `list_webinars_v2`
- Queries diretas em `from('tribes')`, `from('engagements')`, `from('blog_posts')`, `from('cycle_tribe_dim')`, `from('hub_resources')`, `from('gamification_points')` não usam `.eq('organization_id', ...)`
- Em multi-tenant onde RLS faz dispatch via JWT claims, isso é OK em runtime
- Mas: em scenario "PMI-CE pilot dentro do mesmo Supabase", precisa-se de chave/contexto explícito por chapter
- Em scenario "PMI-CE em Supabase isolado", precisa-se de tenant resolution antes de criar client

**Findings (#15-22):** todas as 9 queries em `workspace.astro` + `library.astro` + `teams.astro` + `gamification.astro` + `webinars.astro` + `changelog.astro` + `blog/*.astro` + `initiatives.astro`.

**Sugestão:** ADR sobre policy + frontend convention "se chapter context é resolved no middleware, RPCs DEVEM passar `p_organization_id` explícito (defense-in-depth)" + auditoria pré-deploy via grep.

### 2. Hardcoded brand strings (HIGH/MED urgency)

**Estado:** "Núcleo IA & GP" / "Núcleo de IA" / "Núcleo IA" aparece em **28 lugares** no codebase público (excluindo i18n bundles que têm ~150+ keys adicionais).

Locais críticos:
- `og:site_name` (BaseLayout.astro:48) — todos os SEO/share
- Bibtex publisher + JSON-LD `ResearchOrganization` (publications.astro:190,288; about.astro:30-36)
- Glossário canônico (`governance/glossario.astro:59,66,156`) — "sediado em PMI Goiás (PMI-GO)"
- Volunteer agreement header em PDF (`volunteer-agreement.astro:53`)
- Page titles `meetings.astro:10-12`, `webinars.astro:44`, `blog/[slug].astro:54`
- Help/PDF footer / governance PDFs (5 lugares)
- Nav i18n key `nav.brand` é `'Núcleo IA & GP — Ciclo 03'` em pt + es; `'AI & PM Research Hub — Cycle 03'` em en

**Findings (#7,9,10,14,23-29,30-37,46-47,53-55):** ~20 entries.

**Sugestão:** ADR "Brand strings movidos para `chapter.brand_config.display_name` resolved no middleware + contextual lookup. Fallback: `chapter.legal_name`."

### 3. Hardcoded URLs (HIGH urgency)

**Estado:** `nucleoia.vitormr.dev` aparece em **19 lugares**, incluindo SEO meta tags, OAuth metadata, MCP proxy base, RSS feeds, PDF docs.

- OAuth discovery: `.well-known/oauth-authorization-server.ts:7`, `.well-known/oauth-protected-resource.ts:7`
- MCP proxy base: `pages/mcp.ts:17`
- SEO `og:url`: `about.astro:27`, `meetings.astro:26`, `webinars.astro:47`, `blog/index.astro:39`, `blog/[slug].astro:62-63`
- RSS feeds: `blog/feed.xml.ts:30,34`, `publications/feed.xml.ts:32`
- Governance PDFs: `ChainPDFDocument.tsx:377,390,519,548` + `ChainAuditReportPDF.tsx:147-148,154,377`
- Catalog MCP: `docs/mcp.astro:168`
- `MeetingsPage.tsx:356`
- GitHub repo URL: `BaseLayout.astro:266`, `404.astro:33`, `ResourcesSection.astro:70`, `HelpFloatingButton.tsx:454`, `api/calendar-webhook.ts:184`

**Findings (#10-13,30-34,36,42,48-49,54):** ~15 entries.

**Sugestão:** ADR "Use `Astro.url.origin` ou `request.headers.host` para URLs auto-referentes; chapter brand URL em `chapter.canonical_url`."

### 4. Email "from" hardcoded (HIGH urgency)

**Estado:** `nucleoia@pmigo.org.br` é o único email de contato em **9 lugares** (público); `dpo@pmigo.org.br` em privacy.

- Onboarding step 2 (`onboarding.astro:29`)
- Privacy DPO (`privacy.astro:38`)
- Interview booking errors (`interview-booking/[token].astro:109,142`)
- PMI onboarding (`pmi-onboarding/[token].astro:66`)
- Help button + i18n strings (`help/HelpFloatingButton.tsx:271-273,457-458`)
- Resources section (`sections/ResourcesSection.astro:78`)
- Chapters CTA (`sections/ChaptersSection.astro:57,68`) — com upgrade a WhatsApp via `site_config.whatsapp_gp` que também é singleton
- Impact page (`islands/ImpactPageIsland.tsx:524`)
- PMI onboarding portal (`pmi-onboarding/PMIOnboardingPortal.tsx:1021`)

**Findings (#9,26,28-29,41-42,45-46,53):** 9 entries diretos.

**Sugestão:** ADR "`chapter.contact_email` + `chapter.dpo_email` columns. Fallback: legacy `pmigo.org.br`."

### 5. MCP endpoint hardcoded (HIGH urgency)

**Estado:** `nucleo-mcp` Edge Function é singleton; OAuth metadata + proxy aponta a único host.

- `BASE = "https://nucleoia.vitormr.dev"` em `oauth-authorization-server.ts:7`, `oauth-protected-resource.ts:7`, `mcp.ts:17`
- MCP catalog: `docs/mcp.astro:168` referencia `nucleoia.vitormr.dev/mcp`
- Sentry/PostHog single project (`lib/sentry.ts:7`, `BaseLayout.astro:121-148`)
- Supabase fallback URL/anonkey: `lib/supabase.ts:21-23` aponta a project Núcleo

**Findings (#1,4-5,11-13,36):** 7 entries.

**Sugestão:** ADR-NEW "Per-tenant MCP endpoint" — opções:
- (a) shared MCP server com tenant resolution via JWT claims (low complexity)
- (b) separate EF deployment per chapter (higher isolation, higher ops)
- (c) hybrid: shared core + chapter-scoped tools

### 6. Privacy policy hardcoded (HIGH urgency)

**Estado:** `privacy.astro` tem **~80 i18n keys** específicas para PMI-GO LGPD compliance + DPO Ivan/Angeline + retention table de 12 rows + bases legais Art. 7 IX.

Cada chapter precisaria sua própria versão (CNPJ, DPO, jurisdição) + copy adaptada.

- Chaptes list é dynamic (`loadChapters` + `t('privacy.s1.chapters', lang).replace('{list}', ...)`) — bom
- Mas: contact `dpo@pmigo.org.br` (line 38) hardcoded
- DPO names hardcoded (lines 39-40)
- Retention rows + legal bases: bundle único PMI-GO

**Findings (#9):** 1 entry mas com escopo XL.

**Sugestão:** ADR-NEW "Per-chapter privacy policy" — chapter.privacy_policy_url ou versionamento `governance_documents` per chapter (substrato existente).

### 7. Settings/branding/theming gaps (HIGH urgency)

**Estado:** Tokens CSS `:root` em `theme.css` definem cores PMI-Brasil hardcoded (navy `#003B5C`, orange `#FF610F`, teal `#05BFE0`, etc.). Sistema tem `data-theme="dark"` toggle mas NÃO `data-chapter="..."`.

- Logo: `<link rel="icon" href="/favicon.svg">` (BaseLayout.astro:54)
- Logos chapter: `TeamSection.astro:120-122` hardcoded mapping de PMI-GO/CE/DF/MG/RS PNG paths
- Footer color: `bg-[#200F3B]` hardcoded (BaseLayout.astro:261)
- Theme tokens: `theme.css:18-100` — todos os 60+ vars são `:root` global, sem `[data-chapter]` overrides
- `chapter_registry.logo_url` existe (column nullable text) mas NÃO há equivalente `brand_config jsonb`
- `organizations.logo_url` existe mas NULL — desuso

**Findings (#8,43-44,56-58,59):** 6 entries + governing #59 (chapter type definition gap).

**Sugestão:** ADR-NEW "Chapter brand config schema":
- Adicionar `chapter_registry.brand_config jsonb` com `{ primary_color, secondary_color, accent_color, font_heading, logo_dark_url, favicon_url, contact_email, dpo_email, canonical_url, mcp_url, sentry_dsn, posthog_key, ... }`
- Layout middleware lê chapter context → injeta `<style>` override de tokens em `<head>`
- Logo/favicon resolved per-tenant

### 8. URL routing single-tenant assumptions (HIGH urgency)

**Estado:** Routing atual assume `nucleoia.vitormr.dev` é THE host. Pré-V4 multi-tenant decisões (ADR-0004 organization_id) escalaram DB mas não routing.

- Middleware `CANONICAL_HOST = "nucleoia.vitormr.dev"` (middleware.ts:7) força único canonical
- Legacy redirect array (lines 8-12) lista apenas hosts Núcleo
- `og:url` em todas as pages assume `nucleoia.vitormr.dev`
- Idioma routing (`/en/`, `/es/`) cohabita root path; chapter routing (futuro `/org/[slug]/...` ou `pmi-ce.nucleoia.dev`) não existe
- OAuth callback URLs referenciam `nucleoia.vitormr.dev`

**Findings (#2-3):** 2 entries críticos + impacto cascading em todo `og:url` (~10 lugares).

**Sugestão:** ADR-NEW "Multi-tenant URL routing":
- **Opção A**: subdomain (`pmi-ce.nucleoia.app`, `nucleo-ia.nucleoia.app`) — Cloudflare wildcard cert
- **Opção B**: path prefix (`/org/[slug]/...`) — invasivo em routing, conflict com `/en/`/`/es/`
- **Opção C**: separate deploys com mesmo repo (one Worker per chapter) — ops cost
- Decision PM-aware

---

## ADR draft headers sugeridos (HIGH severity recurrent)

1. **ADR-NEW-A: Multi-tenant URL routing strategy**
   *Decisão:* subdomain vs `/org/[slug]/` vs separate deploys. Trade-offs em SEO, certs, Cloudflare zone, OAuth.
   *Endereça:* findings #2,3,10-13,30-34
   *Complexidade:* L

2. **ADR-NEW-B: Chapter brand config schema (`chapter_registry.brand_config jsonb`)**
   *Decisão:* shape de jsonb + middleware layout injection + override de CSS tokens via `[data-chapter]` selector.
   *Endereça:* findings #7,8,14,43,56-59
   *Complexidade:* M

3. **ADR-NEW-C: Per-chapter contact emails (`chapter.contact_email`, `chapter.dpo_email`)**
   *Decisão:* nullable cols com fallback a `nucleoia@pmigo.org.br` durante transition.
   *Endereça:* findings #9,26,28-29,41-42,45-46,53
   *Complexidade:* S

4. **ADR-NEW-D: Per-chapter MCP server endpoint**
   *Decisão:* (a) shared+JWT-scoped vs (b) separate EFs vs (c) hybrid. OAuth metadata + proxy + Sentry/PostHog implications.
   *Endereça:* findings #1,4,5,11-13,36
   *Complexidade:* L

5. **ADR-NEW-E: Per-chapter privacy policy versioning**
   *Decisão:* Privacy.astro consome `governance_documents` per chapter ou `chapter.privacy_policy_url` redirect-out.
   *Endereça:* finding #9 (extended)
   *Complexidade:* M

6. **ADR-NEW-F: Frontend defense-in-depth — RPCs DEVEM passar `p_organization_id` explícito quando chapter context resolved**
   *Decisão:* convenção + lint rule + grep pre-commit. RLS continua sendo defesa primária; explicit param reduz attack surface.
   *Endereça:* findings #6,15-22
   *Complexidade:* M

7. **ADR-NEW-G: i18n bundles chapter-aware**
   *Decisão:* `pt-BR.ts` → `pt-BR.core.ts` + `pt-BR.chapter.{slug}.ts` overlay. Atual ~150+ keys com brand hardcoded.
   *Endereça:* finding #60
   *Complexidade:* XL — possivelmente split em fases (W1: extract brand keys; W2: chapter overlay layer; W3: per-chapter packaging)

---

## Sugestões pra Ω-E consolidation

Para consolidação no sub-agent E (synthesis):

1. **`CHAPTER_WHITELABEL_READINESS_AUDIT.md`** — documento canônico estado atual + gap matrix:
   - Coluna 1: dimension (1-8 listadas)
   - Coluna 2: % readiness (currently 0% pra dimensions 1-8)
   - Coluna 3: blocker hardcodings count
   - Coluna 4: ADR draft mapping
   - Coluna 5: estimated effort (S/M/L/XL)

2. **`MULTI_TENANT_GAP_BACKLOG.md`** — issues backlog candidates já com complexity scoring:
   - HIGH (#1-#16,#23-#29,#41,#45,#48-#49): Sprint candidates pre-pilot
   - MED (#17-#22,#30-#34,#37-#38,#43,#46,#50-#51,#53-#54,#57): backlog 6-meses
   - LOW (#35,#39-#40,#44,#47,#52,#55,#56): grooming

3. **`ADR_drafts/`** — 7 ADR headers (A-G acima) com structure ADR-NEW-* + decision pending.

4. **Critical observation pra PM**: a estratégia "PMI-GO + PMI-CE pilot" exposta em `project_chapter_pmis_saas_vision_p133.md` é **bloqueada hard** pelos findings #1-#16 (especialmente #1 Supabase fallback, #2 middleware host, #11-#13 OAuth/MCP, #58 theme tokens, #60 i18n). Sem mínimo ADR-A (URL routing) + ADR-B (brand config) + ADR-D (MCP), o pilot não é executável. ADR-G (i18n chapter-aware) é o mais XL — pode ser último.

5. **Quick wins** (S complexity, immediate sprint candidates):
   - #6 PostHog group via `organization_id` em vez de `m.chapter`
   - #7 `og:site_name` via i18n key (já existe `meta.title`)
   - #14 `ANNOUNCED_TOTAL` via `chapter_registry` count
   - #18 `from('cycle_tribe_dim')` adiciona `.eq('organization_id', orgCtx)`
   - #38,#51-#52 `president_go` label resolved via chapter.code
   - #56 hex `#05BFE0` → `text-[var(--color-teal)]`

6. **Anti-pattern observado**: `site_config` como singleton key/value (table tem `key TEXT PK, value JSONB`) viola princípio multi-tenant. Migrar pra `organization_settings (org_id, key, value)` ou `chapter_config` é precondition para chapter operations independentes (general_meeting_link, whatsapp_gp, kpi_targets, etc.).

7. **Cross-track impact**: 
   - Trilingue (D-7) é **upstream** de chapter-aware i18n (ADR-G). PMI-CE em ES/EN/PT força bundle split.
   - LGPD Art. 18 (privacy.astro) é **upstream** de ADR-E.
   - V4 `can_by_member()` (ADR-0007) é compatível com chapter context se `organization_id` chega na sessão.

---

## Fim do report

**Total findings:** 60 (14 HIGH + 17 MED + 9 LOW + ~20 cross-cutting i18n bundle entries).
**ADRs propostos:** 7 (A-G).
**Quick wins (S, < 2h cada):** 6 itens listed acima.
**Critical blockers para PMI-CE pilot:** dimensions 1, 2, 5, 7, 8 (5 das 8 dimensions).
