# p134 Ω-A Council Consolidated Review (Wave 1 — 11 perspectives)

**Date:** 2026-05-09
**Session:** p134 Ω-A
**Origin:** Council multi-perspective review (sediment `feedback_council_3_wave_methodology.md`) requested by PM after 5-agent sweep revealed 1884 lines of cross-cutting findings.

This document consolidates 11 council agent reviews. Each agent saw the same input (5 sub-agent reports + handoff_p134 + strategic anchors) but applied a distinct lens. Wave 3 (product-leader) synthesizes from this consolidation + 5 web research deep-dives.

---

## 1. UX Leader

**TL;DR:** 5 critical pages bloqueiam demo PMI international. Os 2 mais perigosos são structural (não volume): `governance/glossario.astro` `lang="pt-BR"` hardcoded L59 (browser quebra + screen readers) + `settings/notifications.astro` zero `t()`. Bloqueador whitelabel #1: `/onboarding` L29 mailto `nucleoia@pmigo.org.br` hardcoded — voluntário PMI-CE escreve pra chapter errada. Recomenda escopo cirúrgico Bloco 1 esta sessão (4-6h): glossario lang fix + settings/notifications full + onboarding mailto + teams + profile LGPD confirm prompt (risco LGPD real).

**Top journeys risk-ranked:**
1. `governance/glossario.astro` — lang attr fixo; screen readers declaram PT
2. `settings/notifications.astro` — zero i18n na pagina post-onboarding
3. `onboarding.astro` — mailto wrong-chapter + tip strings PT
4. `teams.astro` — Diretor Voluntariado entry-point quebrado
5. `profile.astro` LGPD confirm prompt PT em fluxo IRREVERSÍVEL

**MCP-no-surface gap (15 NEEDS_SCOPING)** — top friction:
1. Re-engajamento alumni / detecção inativos sem page diretor
2. Offboarding workflow sem page (3-hop journey)
3. Audit log read-only para Comitê Auditoria
4. Decision log cronológico para Conselho Consultivo
5. Deputy/VP view ausente

**ADR-NEW-B (CSS tokens override)**: impacto MAJOR identidade chapter, effort MEDIUM (selector `[data-chapter] { --color: }` inject middleware). Executar antes second chapter. NÃO migrar 60 tokens — apenas selector override.

**Brand strings 4-camada**: (1) operacionais mailto/email pré-pilot; (2) documentais PDF/JSON-LD credibilidade institucional; (3) UI page titles/og:site_name polish; (4) i18n bundle overlay XL final.

**Risk flags UX**: LGPD prompt PT pra membro internacional (consequência legal); mailto cross-chapter perda candidatos; demo glossario falha PMI int'l; CSS gambiarra antes ADR; pilot chapter percebe que está na instância do outro.

---

## 2. C-Level Advisor

**TL;DR:** Path A/B/C todos preservados. Estrutural blockers (`cost_entries` sem org_id + `supabase.ts` single-host) escalar como Ω-E gates pré-pilot, **NÃO mistura com Ω-A i18n** (atomicidade do diff). Ω-A direta unblocking para Natália + CPMAI. Para Detroit/LIM, whitepaper lidera com 33 READY substrate (Agent D) + framing honesto da MISSING como roadmap. **Red flag sustentabilidade**: zero segundo operadores documented = `CHAPTER_ONBOARDING_PLAYBOOK.md` mandatory antes Detroit.

**Path-by-path impact**:
- **Path A (PMI internal)**: APROXIMADO por 33 READY pages + trilingue + Sympla replacement. CLOSED por single-host blockers. Resolver Ω-E antes pitch meeting.
- **Path B (consulting)**: APROXIMADO. Sub-agent C/D/E artifacts são deliverables consulting prontos. NFS-e Receita 2026 = insight valioso pago. Trilingue gate antes demos internacionais.
- **Path C (Trentim founder/community)**: APROXIMADO. Trilingue = community-growth blocker. Sustainability gap = single operator documented. Open-source framing convida contribuição.

**Demo windows criticality**:
- **Natália PMI Latam (próxima)**: Português safe; ES risk médio; CPMAI page priority; 3-5h work pré-touchpoint.
- **Detroit/LIM (Sep-Oct 2026)**: highest stakes. Multi-client gap = narrative risk. **LIM Lima 13-Aug** (session #747 accepted) é tighter constraint. Agent D directorate cross-ref table = LIM whitepaper appendix verbatim.
- **CPMAI Latam multi-país**: maior frequência; trilingue `/cpmai.astro` priority.

**ADR sequencing** (optionality preservation):
1. ADR-A URL routing — pre-condition todas demo windows — **Ω-A**
2. ADR-B brand schema — Ω-E
3. ADR-F multi-tenant financial — Ω-E (NÃO defer past Jul)
4. ADR-C contact emails — Ω-E após B
5. ADR-E i18n chapter-aware — post-Ω-B (XL)
6. ADR-D per-chapter MCP — post-Detroit (Oct-Dec)
7. ADR-G internal ticketing — H2 2026

**Recomendação Ω-A esta sessão**: Trilingue como planejado. Escalar 2 items para Ω-E (não mistura): `cost_entries`/`revenue_entries` org_id como CRITICAL gate "blocks PMI-CE pilot"; `middleware.ts` single-host como ADR-B prerequisite "do not onboard chapter 2 until CANONICAL_HOST is dynamic".

**Risk flags strategic**:
- Sustentabilidade: 0 segundo operadores documented (CHAPTER_ONBOARDING_PLAYBOOK.md before Detroit)
- Financial commingling LGPD Art. 46 risk
- GPL-3.0 NFeWizard-io flag legal-counsel
- Institutional narrative coherence (canonical framing antes Detroit pitch deck)

---

## 3. AI Engineer

**TL;DR:** Ω-A NÃO toca MCP multi-tenancy (orthogonal). Para ADR-D multi-tenant MCP: **Option 2 (1 EF, JWT org_id custom claim)** — NÃO N EFs separados. Single deploy, one Zod baseline, Claude.ai connector unchanged. R-1 HIGH: `mcp_usage_log` sem `organization_id` (cross-org indistinguishable today). R-2 HIGH: `nucleo-guide` prompt hardcoda "Núcleo IA" + chapter list literal.

**ADR-D Architecture options analysis**:
- **Option 1 (N EFs)**: complete blast-radius isolation MAS N deploy pipelines + 284-tool codebase duplicated + Claude.ai connector URL change per chapter (re-registration). **Reject for pilot**.
- **Option 2 (1 EF org-claim routing)** ✅: JWT carries `organization_id` claim (set at `/oauth/token`); EF reads from decoded JWT; same `tools/list` for all orgs but `nucleo-guide` filters via `chapter_feature_flags`; OAuth endpoints shared (chapter gets `pmigo.nucleoia.vitormr.dev` via Cloudflare CNAME, Worker reads Host header for branding). **Adopt for pilot**, scales 3-5 chapters.
- **Option 3 (subdomain-per-chapter OAuth origin)**: Option 2 + extra OAuth complexity. Defer post-5-chapter.

**Sequence ADR-D**:
1. Write ADR-D (capture decision, JWT claim, `chapter_feature_flags` table, blast-radius)
2. Add `organization_id` to `mcp_usage_log` (nullable default `'nucleo-go'`)
3. Modify `/oauth/token` Worker: embed `organization_id` JWT custom claim
4. Modify `getMember` EF helper: pass `p_org_id` from JWT to RPC
5. Add `chapter_feature_flags(chapter_id, feature_key, enabled)`
6. Update `nucleo-guide` prompt: filter by `chapter_feature_flags`
7. Pre-deploy checks unchanged (single EF)

**MCP server multi-tenant**:
- **Tools registration**: NO conditional registration at boot. **Runtime visibility via `nucleo-guide` prompt** (already does N `canV4` calls). Same 284 tools `tools/list` for all orgs; LLM coached via dynamic prompt content per org.
- **Tool naming**: NO prefix tools with org slug — Claude.ai connector contract stable.
- **`tools/list_changed`** infeasible em stateless transport — feature flag changes invisible until reconnect (acceptable for pilot).

**Knowledge multi-tenant**:
- Wiki: **Option B (keep `wiki_pages` global, chapter-private goes to `governance_docs`/`knowledge_assets`)** — lower-risk path for pilot.
- RAG: future-proof flag — chunks tagged `organization_id` at index time. Cross-org leakage = LGPD violation.
- `nucleo-guide` prompt hardcodes chapter list `GO, CE, DF, MG, RS` literal — soft multi-tenant gap; resolve via `chapter_registry` query at prompt-render time.

**Cost considerations Claude Opus 4.7 + xhigh**: keep Opus 4.7 default for `analyze_application` EF (billed Núcleo centrally). Routine MCP tool calls billed each chapter's Claude.ai seat. Server-side AI inference (`pmi-ai-triage` EF) = Anthropic API cost to Núcleo. Gate on `chapter_feature_flags` before enabling AI-heavy tools per chapter.

**Risk flags AI**: `mcp_usage_log` sem org_id (R1 HIGH); nucleo-guide hardcoded org strings (R2 HIGH); `canV4` infers org via RLS (R3 MED — verify RLS); `analyze_application` no per-chapter gate (R4 MED); tool descriptions org-Núcleo-biased (R5 MED); Zod pinned 4.3.6 drift risk (R6 LOW); stateless transport notification gap (R7 LOW).

---

## 4. Data Architect

**TL;DR:** BLOCK financial multi-tenant work até ADR-F; SAFE-WITH-CHANGES índice + FK quick wins; zero DB impact i18n/docs Ω-A.

**Priority order:**
1. **ADR-F V5 financial migration** — `organization_id` em 3 tables (`cost_entries`, `revenue_entries`, `sustainability_kpi_targets`). Hard-blocker pilot multi-chapter. Pre-req Sympla/fiscal/chapter P&L.
2. **`revenue_entries` FK parity** — add `event_id` + `submission_id` (cost_entries já tem). Per-event P&L impossível sem isso.
3. **`sustainability_kpi_targets` UNIQUE(cycle, kpi_name)** bloqueia segundo chapter immediately. Mudar para `UNIQUE(organization_id, cycle, kpi_name)` na mesma migration.
4. **events composite index `(type, date DESC)`** — `CREATE INDEX CONCURRENTLY`, ~10x I/O reduction hero homepage.
5. **`site_config` → `organization_settings`** — bloqueado pending ADR-NEW-A URL routing.
6. **`invited_member_ids` array deprecation** — ADR-0012 P1 violation; junction `event_invited_members` canonical sem sync trigger.

**ADR-F migration plan (2-phase)**:
- **Phase A**: nullable column add + backfill `nucleo-ia` UUID `2b4f58ab-7c45-4170-8718-b77ee69ff906` (fixed in `20260411200000`).
- **Verification step** (read-only via `execute_sql`): all NULL counts must = 0.
- **Phase B**: NOT NULL + UNIQUE constraint fix (drop old + add `(org_id, cycle, kpi_name)`) + indexes `idx_*_org`.

**RLS CRITICAL CO-CHANGE (RF-1 HIGH-SEVERITY discovery)**:
> Current RLS from `20260319100044`: `USING (true)` for SELECT on all authenticated. **Any authenticated user can `SELECT * FROM cost_entries` via PostgREST direct TODAY** — single-tenant data exposure issue, independent of multi-tenant.

Replacement policy:
```sql
DROP POLICY IF EXISTS "Authenticated can view costs" ON public.cost_entries;
CREATE POLICY "cost_entries_org_scoped" ON public.cost_entries
  FOR SELECT TO authenticated
  USING (organization_id = public.auth_org());
```

`auth_org()` (defined `20260411200000`) returns nucleo-ia UUID single-org mode; reads JWT claim multi-org. Identical behavior single-tenant.

**Mandatory write-path co-change**: `create_cost_entry` + `create_revenue_entry` SECURITY DEFINER bypass RLS. Both must DROP+CREATE (não OR REPLACE — GC-097) com `organization_id = public.auth_org()` no INSERT. Check overloads: `SELECT count(*) FROM pg_proc WHERE proname IN ('create_cost_entry','create_revenue_entry')`.

**`exec_portfolio_health` audit required**: reads cost_entries; verify SECURITY DEFINER body via pg_proc before Phase B.

**Chapter accounting + bank schemas (ADR-F refs Ω-B+)**: `chapter_accounting_accounts(id, organization_id, code, name, account_type, parent_id, is_active)` + `chapter_bank_accounts(id, organization_id, bank_name, account_type, account_number, agency, pix_key, pix_key_type, is_primary, vault_credential_key, is_active)`. Both `organization_id NOT NULL` from day one.

**FK + Index quick wins (Ω-A)**:
- events composite `(type, date DESC)` `CREATE INDEX CONCURRENTLY` — zero downtime, ~10x I/O reduction.
- `revenue_entries` FK parity — additive nullable, zero downtime, bundle Ω-A.
- `invited_member_ids` COMMENT deprecation Ω-A; DROP COLUMN Ω-C após governance RPC rewrite (`create_event_governance_alignment` writes array).

**RPC composite candidates (Ω-B)**:
- `get_member_homepage_bundle()` — 6 round-trips → 1 RPC; SECURITY INVOKER preferred (RLS preserves auth).
- `get_my_tribe_summary()` — 3 round-trips, M effort.
- `list_initiatives_with_my_membership()` — 3 round-trips; CAUTION re V4 authority gates (4-step audit `docs/reference/V4_AUTHORITY_MODEL.md`).

**`site_config` → `organization_settings`**: Option B (new table) — keep `site_config` truly global, new table chapter-scoped (`whatsapp_gp`, `youtube_channel_url`, `general_meeting_*`, `kpi_targets_cycle_3`). BLOCKED pending ADR-NEW-A.

**`organizations` table state**: 1 row (`nucleo-ia`), `logo_url`/`website_url` NULL. `chapter_registry` (5 rows) has NO FK to `organizations(id)`. **Missing for second-tenant**: `organization_id` FK bridge, `brand_config jsonb`, `contact_email`, `dpo_email`, `canonical_url`. Scope Ω-B.

**Pattern 43 RPCs impact analysis**: NO regression. `get_admin_dashboard` doesn't read cost/revenue. `get_invitation_health` doesn't. `get_lgpd_cron_health` doesn't. Safe from ADR-F.

**Invariants for ADR-F (ADR-0012 P2 mandate)**:
- INV-G1: cost_entries.org_id IS NULL count = 0 (high)
- INV-G2: revenue_entries.org_id IS NULL count = 0 (high)
- INV-G3: sustainability_kpi_targets.org_id IS NULL count = 0 (high)
- INV-G4 (cross-org prevention): `revenue_entries re JOIN events e WHERE re.event_id IS NOT NULL AND re.organization_id != e.organization_id count = 0` (high). FK can't enforce; needs runtime check + BEFORE INSERT/UPDATE trigger.

**Risk flags data**:
- **RF-1 CRITICAL**: financial table RLS wide open today (`USING true`) — independent multi-tenant. Fast-track fix possível: interim policy `USING (can_by_member(auth.uid()::text::uuid, 'manage_finance'))`. Consult security-engineer.
- RF-2: write-path SECURITY DEFINER no `org_id` on INSERT — silent corruption risk after backfill if multi-tenant cuts over.
- RF-3: UNIQUE(cycle, kpi_name) blocks second chapter immediately.
- RF-4: `invited_member_ids` dual-source sem sync trigger.
- RF-5: `cost_entries.paid_by` TEXT sentinel anti-pattern.
- RF-6: `check_schema_invariants()` zero coverage financial — must add INV-G1-G4 same migration.

---

## 5. Security Engineer

**TL;DR:** Single-org RLS é solid. **Critical risk Ω-A**: undefined security architecture for multi-tenant. 3 áreas requerem gate decisions antes pilot chapter 2: (1) `supabase.ts` fallback hard-bind ao Núcleo project ref, (2) zero `organization_id` em new p125 tables, (3) NF-e A1 cert storage com NO current answer. Anonymize bifurcated cron é o melhor LGPD retention chain do codebase. ADR-0076 anonymization ship-ready contingent Wave 4 Ivan sign-off.

**1. Multi-tenant isolation analysis**:
- Frontend ✅ adequate single-tenant: zero `organization_id` em queries frontend = correct server-side defense (RLS via `members.organization_id`).
- `CANONICAL_HOST` middleware:7 hardcoded — chapter 2 white-label triggers 301-loop. **Severity Medium current, Critical pre-pilot-2-deploy**.
- `supabase.ts:21-22` FALLBACK **HIGH severity multi-tenant**: comment "Anon keys are public by design" correct single-project. Risk materializes se chapter 2 deploys em separate Supabase project sem env vars = silent route to Núcleo-GO project = data sovereignty violation + cross-chapter PII leak. **Required ADR decision**: single Supabase project (org-scoped RLS) vs separate per chapter — foundational isolation decision for PMIS/SaaS, no current ADR.

**OAuth audience claim**: `/.well-known/oauth-authorization-server.ts:7` BASE hardcoded `nucleoia.vitormr.dev`. MCP clients validate `iss`. Chapter 2 separate Workers deployment com wrong issuer — same hardcoded-host architectural debt.

**2. RLS V4 + multi-tenant**:
- Pattern 43 cache risk inherits ADR-0012 (not new p134).
- `service_history_view_pii_select` grants `view_pii OR promote` — `promote` action mais broad que necessário (selection committee may not need full PII access). **LOW** — split to `view_selection_pii` Cycle 4.

**3. NF-e A1 cert handling — CRITICAL**:
> No migration, no code, no ADR. Threat model: (1) DB backup exfil → PFX read → tax fraud impersonation; (2) chapter B cert accessible chapter A admin → cross-chapter financial fraud; (3) cert expired no rotation.

Required:
- **Storage**: NOT public Supabase Storage bucket; NOT readable column; NOT app env vars. Acceptable: **Supabase Vault (`pgsodium`)** OR external KMS (AWS/Google KMS) OR Cloudflare Secrets Store.
- **Per-chapter isolation MANDATORY**: cert stored com `organization_id` namespace key. Service_role query MUST require explicit `organization_id` parameter.
- **Rotation** (A1 expira 1y): track `expiry_date`, alert D-60/D-30/D-7 (reuse PMI membership E3 cron pattern).
- **Access log**: every NF-e issuance writes `admin_audit_log` com `action='nfe_cert_accessed'`, `organization_id`, accessor.

**Recommendation**: ADR-0077 NF-e cert storage. Options: (A) Supabase Vault `pgsodium.create_key()` + `encrypt_to_id()` per chapter — fits stack, zero external deps; (B) Cloudflare Secrets Store — cert never touches DB; (C) AWS KMS. **Option A recommended for speed**.

**4. Legal/license risks**:
- **NFeWizard-io GPL-3.0 — HIGH, requires legal-counsel ADR**: questão "distribution under GPL § 4-6". FSF interpretation: network services NOT distribution (ASP loophole; AGPL fecha). NFeWizard-io é GPL-3.0 não AGPL. Tentative: server-side EF/Worker NOT distribution to users. Cloudflare Workers bundle deploy is unresolved case law. Alternative `node-sped-nfe` MIT eliminates risk. **Recommendation**: escalate legal-counsel; if urgent timeline use node-sped-nfe interim.

**5. LGPD chapter rollout**:
- ADR-0076 single controlador (PMI-GO). Multi-chapter creates "operador + multiple controladores" novo legal subject. Required: legal-counsel confirm operador role + DPA artifact. Wave 4 parallel Ivan DPO.
- `anonymize_rejected_applicants` operates globally sem `organization_id` scoping. SECURITY DEFINER bypasses RLS. Required pre-multi-chapter: add `p_organization_id` parameter; cron schedules per-organization.
- Art. 18 cycle: consent ✓; access (`list_pii_access_log_admin` not org-scoped); export gap selection_applications PII; delete/anonymize bifurcated cron comprehensive `data_anomaly_log` exception logging — notable improvement.

**6. Existing strengths (do NOT regress)**:
- `anonymize_pmi_cascade()` resolves person→members→selection via email join.
- `community_profile_private` defense-in-depth `import_vep_applications`.
- `profile_about_me` excluded AI triage prompt (R7 finding addressed).
- PKCE S256 enforced; allowlist redirect URIs.
- Rate limit proxy 100/min general + 10/min destructive.
- `anonymize_rejected_applicants` exception → `data_anomaly_log` (first LGPD function with proper failure audit).

**ADR sequencing**:
1. (block) Single-project vs multi-project Supabase decision
2. (block) ADR-0077 NF-e cert storage
3. (block) Legal-counsel DPA multi-chapter
4. (block) NFeWizard-io GPL clearance
5. (conditional) Promote CANONICAL_HOST/UPSTREAM/SUPABASE_URL env vars
6. (conditional) `p_organization_id` anonymize crons
7. (deferred) Signed-export RPC applicant PII Cycle 4

**Ship gate ADR-0076 + p125 migrations: CONDITIONAL OK**. Ivan signs base legal + retention before crons activate `p_dry_run=false`. NF-e Track 3 BLOCK. Multi-chapter PMIS BLOCK on supabase.ts decision. NFeWizard-io BLOCK GPL clearance. Single-chapter platform: OK ship.

**Risk flags security**: 10 flags ranked R1-R10; supabase.ts fallback (HIGH), CANONICAL_HOST (MED), NF-e cert undefined (CRITICAL), NFeWizard-io GPL (HIGH), anonymize crons not org-scoped (MED), DPA undefined (HIGH), pii_access_log not org-scoped (LOW), mailto hardcoded (LOW), service_history promote broad (LOW accepted), OAuth issuer hardcoded (MED).

---

## 6. Senior Software Engineer

**TL;DR:** 13-21h estimate credible mas bottom-heavy; 5 critical pages = mechanical replaces 1-2h cada; risk pages `profile.astro` 1833L + `attendance.astro` 2197L hold hidden tail. DB findings reveal 2 CRITICAL blockers multi-chapter financial work: `cost_entries`/`revenue_entries` zero `organization_id` (created `20260319100044_w139_sustainability_framework.sql` pre-V4). Composite index `events (type, date DESC)` highest-ROI lowest-risk migration available — ship em Ω-A. `get_member_homepage_bundle()` premature optimization — DO NOT.

**Critical pages complexity rating**:
- `governance/glossario.astro` MEDIUM (não COMPLEX): `lang="pt-BR"` única ocorrência repo-wide. BaseLayout already accepts `lang` prop dynamic. One-character fix `lang={lang}` + `fmtDate()` toLocaleDateString hardcode + ~14 chrome keys. **Effort 1.5h**.
- `settings/notifications.astro` SIMPLE: 199L total, zero `t()`, ~20 strings, no islands. **1-1.5h mechanical**.
- `profile.astro` HARD: 1833L, scattered inline fallbacks scripts ~1300-1740 (photo upload callbacks, signature handler, LGPD export/delete confirm chain). LGPD multiline confirm L1517-1522 → backtick-template key, test all 3 langs. **4-6h full pass**.
- `teams.astro` MEDIUM: ~8-10 keys, no islands. **1h**.
- `onboarding.astro` MEDIUM: ~20 keys. Parameterized `Fase ${pi+1} de ${phases.length}` — verify `t()` interpolation `{var}` support em `src/i18n/utils.ts` BEFORE writing key. **1.5-2h**.

**Risk hotspot**: `attendance.astro` 2197L (largest file in codebase, NOT in critical list). Sweep requires targeted grep all string literals em script blocks. **Defer next sprint**.

**Inline dict anti-pattern 5 files** (`about.astro`, `meetings.astro`, `pmi-onboarding/[token].astro`, `interview-booking/[token].astro`, `library.astro`): invisible existing parity test (counts pt-BR.ts only). Migration to global bundles must precede meaningful parity testing. Each file = one commit.

**DB findings priority**:
- **CRITICAL** confirmed: `cost_entries`+`revenue_entries` no `organization_id` (verified migration body). Pre-V4 debt. Migration: `ALTER TABLE … ADD COLUMN … DEFAULT backfill nucleo`. Pre-req ADR-0077 V5 financial. **NÃO bundle Ω-A i18n**.
- **HIGH**: `revenue_entries` falta `event_id`+`submission_id` (cost_entries tem ambos). Add nullable FKs same migration org_id.
- **MED**: `cost_entries.paid_by` text NOT NULL not uuid FK. Add `paid_by_member_id` nullable alongside, deprecate text. `SELECT DISTINCT paid_by` antes design.
- **MED**: `events.invited_member_ids uuid[]` vs junction `event_invited_members` drift. Both exist. `create_event` writes array (`database.gen.ts:4718`). Zero frontend reads array. `set_event_invited_members` RPC exists — confirm writes junction. If yes: drop array via DROP+CREATE-OR-REPLACE RPC sequence.
- **LOW**: `webinars.co_manager_ids text[]` no FK — app guard exists, low volume, acceptable debt.

**Index opportunities**:
- **HIGH ROI near-zero risk**: `events (type, date DESC)` composite. NO existing — `idx_events_date` non-composite, no `idx_events_type` exists. Agent E 10x I/O credible filter `type='geral'` ~60 rows. `CREATE INDEX CONCURRENTLY` no write locks. ~3 lines SQL. **Highest ROI per hour. Ship Ω-A**.
- **MED**: `member_document_signatures (member_id, document_id) WHERE signed_at IS NOT NULL` — useful governance scale, backlog.

**RPC composite**:
- **`get_member_homepage_bundle()` REJECT for Ω-A**: 6 RPCs latency smell, mas L-effort + coupling risk (one sub-query failure = total bundle failure) + non-trivial PL/pgSQL orchestration. **Premature optimization**, blast radius marginal benefit. Backlog post-Ω-A.
- `get_my_tribe_summary()` + `list_initiatives_with_my_membership()` — M each, post-Ω-A.

**Test impact i18n**:
- `tests/contracts/i18n-mobile-readiness.test.mjs:22-40` validates count ±5% across 4445-key dicts = ±222 keys tolerance. Adding 180 keys passes trivially — NÃO catches missing translations specific keys.
- Zero structural test verifying key-by-key name parity (every key in pt-BR.ts exists same name en-US.ts + es-LATAM.ts). Real gap. 5 inline-dict files completely invisible current tests.
- **Actions (não bloqueia Ω-A, schedule post-Ω-A)**: upgrade parity test to assert set equality of key names; migrate inline dicts.

**Contract test impact DB**: org_id additions touch `kpi-portfolio-health.test.mjs` + `schema-invariants.test.mjs`. Run `npm test` immediately after migration; failure = block.

**ADR sequencing tech**:
1. Events composite index — zero dep, ship immediately
2. i18n 180-key batch — parallelize independent
3. ADR-0077 V5 financial — own sprint
4. ADR-NEW-A URL routing — PM/architect decision
5. ADR-NEW-B brand schema — follows A
6. ADR-NEW-C contact emails — follows B
7. invited_member_ids drop — only after read-path audit junction sole consumer

**Suggested 5 commits sequence**:
1. `feat(i18n): settings/notifications + glossario chrome + teams sections` (Fase A)
2. `feat(i18n): onboarding 20 keys` (separate — interpolation pattern risk)
3. `feat(i18n): profile.astro full pass + toasts + LGPD confirm` (isolated highest blast radius)
4. `feat(i18n): migrate 5 inline-dict pages to global bundles`
5. `perf(db): CREATE INDEX CONCURRENTLY idx_events_type_date on events(type, date DESC)`

**Total ~14h** — low end 13-21h estimate with attendance deferred (correct call: 6h isolated sprint).

**Risk flags eng**: R1 i18n interpolation unverified before onboarding commit; R2 profile multiline LGPD confirm test all 3 langs browser; R3 inline dict atomic PR per file; R4 cost_entries.paid_by live data unknown shape (`SELECT DISTINCT` before design); R5 `events.invited_member_ids` drop requires RPC rewrite; R6 parity test too loose post-Ω-A upgrade.

**Veredict**: approve-with-notes. Ω-A executable scoped if `attendance.astro` deferred. DB migrations NÃO bundle this sweep — own ADR + sprint. Composite index é único DB change ship esta window.

---

## 7. VC/Angel Lens

**TL;DR:** Núcleo IA Hub é real-market problem chasing defensible wedge MAS **NÃO investável today**. Real substrate (multi-tenant scaffolding, governance chains, Sustentabilidade 5 tables) MAS commercialization variables todas open: zero paying chapters, zero CAC, no validated pricing, multi-tenant gap 40 HIGH/MED items 3-6 months work pre-second chapter safe. Investability gate: close ONE paying pilot chapter (PMI-GO/CE) at any price, measure retention, price-anchor from there.

**5 questions investidor faria**:
1. Quem escreveu cheque? PMI-GO uses free, Natalia "integrate not buy". 0 paying after 43 active members + 15 seeded chapters = core commercial risk.
2. Counter-argument Wild Apricot ~$50-150/mo (UNVALIDATED — WebFetch blocked)? "AI/MCP layer" precisa survive 10 seconds skepticism.
3. Sympla replacement = best near-term monetization. Build timeline + NFS-e legal sign-off?
4. Multi-client gap 40 severity items deep — quem builds, timeline, funded how?
5. Path A/C distribution paths não monetization. When does money enter model?

**Moat: FORMING — não exists yet**:
- AI/MCP differentiation: per-chapter MCP candidate moat IF accumulates chapter-specific structured data (governance, volunteer, financial) making switching costly. Today single-tenant; multi-tenant scoping não built. Moat forms when (a) chapter-own MCP endpoint, (b) chapter-specific data accumulates isolation, (c) switching = lose institutional memory.
- Defensibility 12-24mo: governance chains (genuinely hard replicate 6-9 months minimum); volunteer lifecycle V4 (4-6 months replicate); trilingue + LATAM positioning regional wedge; **network effects ABSENT today** (no cross-chapter knowledge transfer).
- 18-month moat-killer: PMI Global builds/acquires chapter-ops platform (budget + distribution). Asymmetric downside Natalia "integrate" = prelude PMI absorbing internal tool no equity event.

**TAM/SAM/SOM (UNVALIDATED — knowledge cutoff Aug 2025)**:
- Global PMI: ~300 chapters (verify pmi.org). Realistic paying TAM: 100-150 chapters >100 active + budget + pain. **TAM ~120 × R$1500/mo = R$2.16M ARR (~$432K USD) bootstrap-scale not venture**.
- Brazil SAM: 19 chapters PMI Brasil. Realistic 12mo: 3-5 paying. R$800-2000/chapter/mo. **SAM Brazil 19 × R$1200 = R$273.6K ARR (~$54.7K USD) bootstrap-scale**.
- LATAM beyond Brazil: +30-50 chapters (Colombia, Mexico, Argentina, Peru). **SAM LATAM 50 × R$1200 = R$720K ARR (~$144K USD) bootstrap-scale**.
- SOM 12mo: 3 paying × R$1000/mo = R$36K ARR year 1. Honest. NOT VC justification. **Bootstrap validation**.
- Upmarket scenario: PMI Global directly white-label = ~$50M+ annually estimated UNVALIDATED. Path A only scenario justifies VC. Requires PMI = buyer not distribution.

**Capital efficiency by ADR (R$100K allocation order)**:
1. ADR-F multi-tenant closes pilot blocker (L-XL 3-6mo, prerequisite all chapter revenue, capital sink before payoff)
2. ADR-H ticketing take-rate play (XL 4-6mo, best revenue potential 1-2% take-rate vs Sympla 5-10%, requires NFS-e legal first)
3. Everything else = product depth after revenue validates
**Do NOT build ADR-I through ADR-L before closing one paying pilot**.

**Monetization model**:
- Free (current Núcleo): pilot chapter, ≤50 active members, core governance + volunteer. Reference customer demo.
- Pro per chapter: R$800-1500/mo, unlimited members, governance chains, trilingue, MCP scoped, financial basic (no NF-e). Chapters 100-500 members.
- Enterprise: R$2500-5000/mo OR R$30-60K/year + onboarding fee, ticketing module + NF-e/NFS-e + custom domain + dedicated support. Chapters >500 members OR PMI federation contracts.
- **Take-rate ticketing**: Sympla 5-10% → internal 1-3% (or zero with flat monthly). PMI-GO flagship R$500×300 attendees=R$150K gross × 2% = R$3K/event. 8-12 events/year = R$24-36K addt ARR per chapter. 5 chapters = R$120-180K addt ARR. **Near 100% margin once built**.
- NF-e as service: viable post ticketing. Per-emission fee. Regulatory complexity (fiscal responsibility, cert mgmt). NÃO price into projections before legal review.

**Comparables UNVALIDATED warning** (WebFetch blocked, sediment `feedback_comparable_validation_before_citing.md`):
- Wild Apricot, Sympla, Bizzabo, Hopin, Airmeet — all UNVALIDATED, must verify before citing
- **Hopin sold to RingCentral 2023, UK liquidation Feb 2024 — DO NOT cite as functioning comparable**
- DocuSign PUBLICLY VERIFIED ~$2.8B ARR — safe directional cite

**Pitch readiness gates demo blockers**:
1. Multi-tenant gap (29 hardcoded "PMI-GO" + 14 HIGH Agent C) — kills "your chapter can have this" first 5 minutes
2. Trilingue incomplete (5 critical PT-only pages Agent A) — PMI Latam/PMI-WDC EN demo fails immediately
3. No pricing ready — absence pricing page = not commercially ready signal
4. Zero paying customer reference — institutional + chapter presidents both ask social proof

**Numbers needed 6mo to be pitchable**:
- 1 paying pilot chapter at any price (R$200/mo minimum contractual relationship)
- Churn = 0 (one chapter retained 6 months)
- Event ticket volume processed internally (1 event migrated Sympla→internal)
- Trilingue complete public pages (Ω-A + Ω-B done)
- Multi-tenant whitelabel MVP (ADR-F Phase 1)

**Path A/B/C capital path**:
- **A (PMI partnership)**: Natalia "integrate not buy" = opening; PMI moves slowly (2026→2028 likely); PMI may absorb not pay. **Distribution accelerator NOT monetization**. Don't expect PMI check.
- **B (consulting bootstrap)**: highest capital efficiency. R$5-20K per chapter onboard + monthly platform fee. Bootstrap to 3-5 paying then raise on demonstrated traction. **Correct first move**.
- **C (PE/VC)**: only after Path B validates 5+ chapters R$15-20K MRR. R$500K-1.5M raise hire 2 engineers + CS + ADR-H. NOT traditional VC (TAM too small 100x return). BR angel syndicate, impact/edtech angels, strategic (Trentim/LSB). Multiple at exit BR edtech/community SaaS 3-8x ARR. R$100K ARR (5 chapters) → exit R$300K-800K. Acquirer candidates: PMI Global internal, consulting firm, Sympla/Evently.

**Recomendação Ω-A capital-efficient**:
Ω-A → Ω-B sequence technically correct mas commercially back-loaded. Translation = blocking dependency institutional demos but generates zero revenue. **Recommended**:
1. Commercial action 2 weeks: propose PMI-GO paid pilot R$500/mo 90 days. Get written response. **De-risks paying assumption**.
2. Ω-A trilingue parallel.
3. ADR-F Phase 1 whitelabel MVP unblocks PMI-CE pilot.
4. Sympla replacement feasibility: NFS-e legal sign-off first, scope ADR-H. Take-rate revenue play.

Do NOT build ADR-I through ADR-L before steps 1-4 yield paying customer.

**Risk flags VC**:
1. Single-founder technical concentration (Vitor sole engineer, bus factor=1) — institutional checks blocker
2. PMI brand dependency — risk Natalia "integrate" prelude absorption
3. NFeWizard-io GPL-3 IP liability commercial SaaS
4. 40 HIGH/MED multi-tenant findings = real eng weeks data-leakage risk (DPO names cross-chapter = LGPD violation)
5. TAM bootstrap-scale not venture — Brazilian PMI chapter SaaS peaks ~R$250-300K ARR. Strong SMB/bootstrap, NOT VC unless Path A activates. **Pitch que não acknowledges esta distinction = detected immediately**.

---

## 8. Stakeholder Persona — GP Leader voice

**Pain-meter atual: 6/10**. Com Prio 1+2+3 entregues: 3/10 (adoção confortável). Sem: 8/10 (resistência institucional).

**Top 5 fricções incomodariam**:
1. **Branding PMI-GO visível para meus membros PMI-CE (BLOQUEADOR)**: og:site_name "Núcleo IA & GP — PMI Goiás", PDF Termo Voluntário, footer email transacional, link onboarding `mailto:nucleoia@pmigo.org.br`. Board pergunta "isso é produto PMI-GO ou nosso?" → resposta honesta hoje "PMI-GO".
2. **Página glossario quebrada qualquer língua não PT-BR**: `lang="pt-BR"` hardcoded + zero `t()`. Membro EUA/México navega /governance EN/ES → labels PT fixo. Vergonha institucional.
3. **Sympla sem substituto funcional hoje**: Diretor Eventos não tem onde migrar. RSVP público + QR + repasse banco direto MISSING. Cobra 5-10% perdendo dado participante terceiro.
4. **Financeiro chapter não existe per-chapter**: `cost_entries`/`revenue_entries` sem `organization_id` mistura PMI-GO. Diretor Financeiro NÃO pode usar.
5. **Handover anual diretoria não existe**: PMI chapters trocam diretoria todo ano. Sem playbook digital → caos cada mandato.

**Top 5 features brilhariam**:
1. Certificado verificável publicamente `/verify/[code]` — substitui PDF assinado manual.
2. Pipeline candidatura + interview-booking via token sem login — substitui Forms+WhatsApp manual.
3. Gamification + leaderboard + Credly link integration — argumento tangível retenção voluntários.
4. Termos com cadeia aprovação — substitui DocuSign este caso. Audit Comitê Ética compliance hoje impossível.
5. Dashboard executivo `/report` para board — A4 imprimível, KPIs verde/amarelo/vermelho, sem compilar planilha.

**Walking through dia operacional**:
- Início day: workspace KPIs OK mas falta banner "Você está no PMI-CE" claro
- Diretoria call: glossario em PT confunde membro espanhol convidado
- Evento prep: webinar fluxo OK mas "como inscreve?" → `webinars.sympla_event_url` sai sistema
- Membros: `/gamification` OK mas CPMAI Latam attendees Mexico vê PT
- Financial review: admin/sustainability mostra dados Núcleo Goiás não PMI-CE
- EOD: `/report` funciona; Vice-Presidente sem deputy view

**Onboarding pilot 90 days**:
- **Day 1 must-work**: chapter configurado nome+logo+email próprio (zero "nucleoia@pmigo"), login 3 diretores, /workspace dados PMI-CE, termo voluntário "PMI-CE" cabeçalho. Falha qualquer = diretores questionam.
- **Week 1 must-show**: pipeline candidatura 1 candidato real, attendance tribu sem mistura PMI-GO, certificado 1 membro verificável `/verify/[code]`, notificações chapter remetente.
- **Month 3 must-prove**: 1 evento inscrição plataforma (mesmo formulário externo se dado volta), receita/despesa evento separados Núcleo Goiás, board recebe `/report` real PMI-CE, retenção voluntários estável.

**Trade-offs perceived**:
- **Sympla migration**: alto valor (R$9-24K/ano economic) mas alto risco primeiro evento (perda confiança). Não migro até beta rodando evento baixo risco (study group gratuito) primeiro.
- **Airmeet integration**: médio-alto CPMAI Latam contexto mas mais ferramenta stack treinamento. Prioridade Sympla > Airmeet.
- **Brand rebranding**: altíssimo valor. **Não-negociável pré-pilot real**. Aceito esperar mas não assino sem.
- **MCP setup**: médio valor uso avançado. Onboard 1-2 diretores entusiastas tech primeiro; boca-a-boca.

**Recomendação Ω-A from gp-leader voice (90 days adoption order)**:
1. **Whitelabel básico** (chapter_brand_config) — pré-requisito absoluto
2. **Financial chapter scoping** (org_id em cost/revenue) — sem isso Diretor Financeiro não usa
3. **Trilingue 3 críticas** (glossario, settings/notifications, onboarding)
4. **Event registration MVP pre-Sympla** — formulário público + dados + email confirmação. Pode ser sem pagamento. Permite começar testar migração study groups gratuitos.
5. **Handover diretoria checklist** — pode ser pagina admin simples + checklist estático Day 1.

**Risk flags fariam desistir**:
1. Dados misturados PMI-GO/PMI-CE primeiro mês — Diretor Financeiro sai e nunca volta
2. Primeiro evento na plataforma dá errado — perda confiança equipe + participantes meses recuperar
3. Onboarding voluntário mostra "PMI Goiás" para voluntário PMI-CE — perco voluntário pré-primeiro evento
4. Nenhum diretor consegue usar sem ajuda time tech Núcleo — autonomia chapter comprometida
5. PMI Global questionar uso da marca — problema institucional. Quero clareza tratamento antes assinar.

---

## 9. Startup Advisor

**TL;DR GTM:** Go — mas sequence brutal. V5 financial multi-tenant refactor first (sem 1-4) → Sympla replacement Phase 1 registration-only second (sem 5-10) → Airmeet API integration third (sem 11-16). NÃO build all 3 simultaneously. Kill scenario = burn 90-day window Sympla full-stack antes validar chapters quer migrar.

**Sympla replacement deep analysis**:
- Sympla 10% serviço + 2-2.5% processing = ~12.5% total ticket. 4-6 paid events/year × R$150-400 = R$6K-25K annually per chapter walking out third-party.
- **MVP NÃO é "replace Sympla"**: é **internal event registration RSVP + waitlist + PMI member discount, ZERO payment ZERO NF-e**. Sympla parallel — chapters keep Sympla payment, Núcleo captures subscriber data. Dual-write transitional (`webinars.sympla_event_url` already signals).
- Phase 2 (direct payment + NFS-e) só after PMI-GO runs 1 event Phase 1 + flow validated. Test: CPMAI study group próximo paid cohort.

**NF-e SaaS BR alternatives**:
- NFS-e Receita Federal API direct — dropping fiscal compliance from XL to L
- node-sped-nfe MIT/LGPL — fallback NFC-e
- **NFeWizard-io GPL-3.0 — DO NOT TOUCH** (license contamination SaaS)
- Recommendation sequence: (1) NFS-e Receita direct primary, (2) node-sped-nfe fallback NFC-e, (3) NFeWizard-io defer legal-counsel

**ROI per chapter scale**:
- PMI-GO flagship 19º seminário ~200-500 participantes R$200-400 = Sympla fee R$5K-25K saved per event. 2 events/year = Phase 1 build payback within first year.
- 5 chapters × 3 paid events × R$8K avg = R$120K/year system-wide savings. **Pitch para chapter Financeiro Director**.
- Buyer = Financeiro Director. Pitch: "Você paga até 12% faturamento Sympla. Eliminamos. Chapter fica dinheiro + audit trail LGPD-grade."

**Recommendation timing**:
- **Sem 1-4**: V5 financial refactor (CRITICAL DB blocker confirmed Agent E)
- **Sem 5-8**: Sympla Phase 1 single chapter pilot PMI-GO test event
- **Week 8 GATE**: chapter actually used? N-registrations visible? Yes → proceed. No → understand why before Phase 2.
- **Sem 9-16**: Sympla Phase 2 payment direct + NFS-e SE gate 8 passes.

**Airmeet partnership posture**:
- Integrate NÃO compete. PMI Latam `pmilatam.airmeet.com` = distribution channel. Núcleo angle: Airmeet event happens; Núcleo journey continues (attendee record, certificate, recording token-gated, member ID validation, follow-up digest).
- Integration: one-directional sync — Airmeet attendees webhook/polling → Núcleo `webinars` table → certificate auto-emit + subscriber segment. **L effort**, no replacement.

**CPMAI Latam catalyst** (PT+ES simultaneous Sep-Oct 2026):
- Demo Núcleo: CPMAI attendees automatically receive (1) certificate via Núcleo, (2) recording access token-gated, (3) subscriber record follow-up, (4) PMI member discount validated registration → PMI Latam concrete operational benefit.
- **Concrete ask Natalia testing commitment**: "Você pode nos ceder acesso Airmeet API pra piloto integração antes CPMAI?" Zero-cost ask. Yes = design partner. "Check with team" = validator.

**PMI Latam relationship dynamics**:
- Natalia validator NÃO client. Don't over-invest. Secondary test: "Podemos incluir integração Airmeet caso uso whitepaper Detroit?" Yes = design partner. Approval needed = validator.

**Sustentabilidade as differentiator**:
- Single-tenant admin-only hoje. Cannot differentiate até V5 financial refactor lands.
- Pitch directorate: "Substitui Google Sheets que conselho não sabe ler por painel auditável onde qualquer membro vê agregado sem ver detalhes LGPD-protegidos. Transparência pública + accountability interna num sistema." Diferencial real = transparency é valor governança não só operacional.

**Pricing model chapter SaaS pilot**:
- **Free**: core platform (volunteers, governance, attendance, MCP). Reference customer.
- **Pro**: Sympla replacement + Sustentabilidade multi-chapter + NFS-e. **R$299-499/mo per chapter OR 3-5% fee on ticket revenue** (lower than Sympla 12.5%, aligned incentives, zero upfront). **Take-rate compelling: zero-cost se zero events**.
- **Enterprise (later)**: whitelabel domain + chapter-scoped MCP + custom email + API access.

**Reference narrative 1-page**:
> "PMI Goiás capítulo hospedou iniciativa. Eliminamos R$18K/ano taxas Sympla. Migramos governança documental Google Docs → cadeia assinatura auditável. 52 pesquisadores ativos, 8 tribos, 111 eventos registrados. Este é o sistema oferecido ao seu capítulo."

**Multi-chapter pilot GTM 30-day demonstrable benefits**:
1. Governance signing (DocuSign replacement) — substrate 80% built READY Agent D
2. Attendance + certificate auto-emission — substrate READY Agent D
3. Chapter dashboard KPIs `/stakeholder` — NEEDS_SCOPING shortest "wow" path

Benefits 4+ (Sympla, NFS-e, financial) = 90-day horizon.

**Onboarding playbook MISSING = blocker**: provisioning script new org_id, chapter admin role seed, whitelabel config, PMI VEP sync per chapter. **Logistics gap REAL pre-pilot blocker NÃO features**.

**Brand strategy chapters**:
- Acordo Cooperação tech pilot ANTES second chapter signs — `legal-counsel` flag.
- Natalia incident (Vargas "ação PMI") = brand bleed organic when product good. Mitigation = canonical language ready partners use NÃO brand policing. Boilerplate `feedback_pmi_brand_canonical` + distribute proactively.

**Path A/B/C reinforcement**:
- **Path A pitch line for Detroit/LIM**: "15 chapters, 1 platform, R$120K/year external tool fees eliminated, zero PMI Global budget required." PMI Global programs cannot replicate (top-down sale). Núcleo = chapter-peer software built by chapter for chapters.
- **Path B service offer**: Sympla replacement + Sustentabilidade multi-chapter = primary service wrapper. Fixed-price per chapter. Compatible Path A.
- **Path C MVP scope**: premature. Moat depends multi-tenant proof PMI scale first. Build once, count all paths.

**Recomendação Ω-A scope**: Trilingue público priority correct = international demo unblocking. Don't displace strategic findings above current sprint.

Concrete Ω-A output GTM value beyond i18n: Agent E `cost_entries`/`revenue_entries` sem org_id é CRITICAL pre-pilot blocker → flag immediately backlog labeled "blocks PMI-CE pilot" não generic.

**Risk flags**:
1. **Kill sequence inversion**: Sympla full-stack before V5 financial = single-tenant tables commingle data → LGPD violation + migration headache
2. **Airmeet over-investment**: 2 sprints integration if Natalia not committed = stranded
3. **Brand exposure pre inter-chapter agreement**: fee-on-ticket activates revenue chapters before legal framework. Angelina (advogada PMI-GO voluntária) review BEFORE first external chapter payment.
4. **Closes optionality A/B/C**: fee-on-ticket shifts Núcleo Path A voluntary → Path B commercial. Escalate `c-level-advisor` before pricing communicated. Today framed "operational cost recovery"; once contract signed, optionality narrows.
5. **NFeWizard-io GPL-3.0**: do not import without explicit `legal-counsel` sign-off. Use NFS-e API direct primary path.

---

## 10. Legal Counsel (PT-BR)

**1. NFS-e Nacional 2026 — obrigação chapters PMI**:
Chapters cobrando eventos = OBRIGADOS emissão NFS-e. **Simples Nacional obrigatório padrão único set/2026** (verificar portaria vigente deploy). API REST direta Ambiente Nacional (`nfse.gov.br`) — sem lib third-party. Substitui ISS municipal.

**2. GPL-3.0 NFeWizard-io copyleft analysis**:
GPL-3.0 ≠ AGPL-3.0. Edge Function Deno **server-side NÃO distribuindo código ao cliente final = tecnicamente compatível com GPL-3.0**. Risco surge SE código for published as package/SDK. **Documentar decisão em ADR-0079**. **Preferir node-sped-nfe** (LGPL-3.0/MIT dual = mais permissivo, todas opções futuras abertas).

**3. LGPD chapter rollout — data controller architecture**:
Cada chapter = controlador independente. Núcleo = operador. **DPA por chapter ANTES pilot PMI-CE = MANDATORY**. RPCs sem `p_organization_id` explicit = LGPD hard blocker. **DPO compartilhado (Ivan) é VIÁVEL durante fase piloto** SE formalizado em cláusula Acordo de Cooperação.

**4. ADR-0076 base legal Art. 7 IX replicabilidade**:
✅ Replicável todos chapters com 3 condições: (a) LIA simplificada por chapter, (b) privacy policy adaptada identifying chapter-controlador, (c) candidato ciente escopo multi-chapter ao se inscrever. **Retention 5y/12m/90d uniformes** (LGPD federal).

**5. PMI brand hierarchy risk**:
**Risco BAIXO** se Núcleo mantém branding próprio + chapters como "operadores da plataforma Núcleo IA Hub". **Risco MÉDIO** se nomeadas "PMI-CE Platform" (cria expectativa PMI Global oficial). **Mailto hardcoded HIGH must-fix pré-pilot**.

**6. Termo Voluntariado v2.7 §15.4 Roberto**:
NÃO bloqueia Ω-A/B/C técnicos. Bloqueia emissão Termos voluntários PMI-CE. Decisão Opção C (híbrida) bem fundamentada — CF art. 5 XXXVI + Lei 9.610/98 art. 49. **Angelina deve validar mecanismo "ciência prévia" como substituto consentimento expresso**.

**7. Política IP v2.7 Wave 1-5**:
NÃO bloqueia técnico Ω-A. **Bloqueia transferência IP cross-chapter + Trentim Path B firewall legalmente vinculante**. IP Policy v3 (Q3/2026) = veículo firewall definitivo.

---

## 11. Accountability Advisor

**TL;DR**: 5 classes institutional risk pre-multi-chapter. Trilingue Ω-A low risk → proceed. 7 ADRs require ratification sequencing. **Hard blockers TODAY** (NÃO backlog): cost/revenue sem `organization_id` + chapter brand strings hardcoded em governance PDFs.

**1. PMI institutional compliance**:
- Chapter Operations Standards trilingue gap: not reportable PMI Global standalone violation. Reportable as broader audit if Núcleo claims international scope formal submissions (LIM, Detroit). **Gate**: trilingue substantially complete before formal PMI submission.
- **Brand usage audit window**: 28 occurrences "Núcleo IA & GP"/"PMI-GO" + 19 hardcoded `nucleoia.vitormr.dev` + governance PDFs `PMI Brasil-Goiás Chapter` footers (`ChainPDFDocument.tsx:377,390,519,548`; `ChainAuditReportPDF.tsx:127,147-148,154,377`). Defensible single-chapter. **Risk escalates pilot launch**: PDFs from PMI-CE members carry "PMI-GO" footer = audit trigger PMI Latam + chapter board complaint.
- PMI Global notification triggers: financial module per-chapter + NF-e emission on behalf chapter = chapter financial operations requiring board oversight + legal agency.

**2. Governance chain analysis**:
- **ADR-NEW-D per-chapter MCP** affects LGPD Art. 7 IX base legal scope (ADR-0076 pending Wave 4). Don't finalize until ADR-0076 closes.
- **ADR-NEW-E per-chapter privacy policy** = LGPD compliance instrument not product decision. PMI-CE different DPO mandatory (currently Ivan + Angeline hardcoded). Requires `legal-counsel` co-sign.
- **ADR-NEW-G i18n bundles chapter-aware** = brand representations. ~150+ keys "Núcleo IA & GP"/"Goiás" — chapter sign-off mandatory before bundle overlay deployed.
- **Curador signatures pending pre any multi-chapter**: Roberto Macedo open comments (5 unresolved Política IP v2.7 + Termo Voluntário) MUST close. Expanding chapter with open curator objections = audit trail showing known issues unresolved at expansion time.

**3. Budget impact**:
- i18n 13-21h: PM bandwidth opportunity cost. **5 critical pages 3-5h delivers 80% demo-readiness**. Schedule remainder Ω-B.
- Sympla replacement XL highest-capex. Capital allocation question: if Vitor sole dev = PM bandwidth; if PMIS/SaaS chapter fees = amortized.
- NF-e infra: each chapter provides CNPJ + Cert A1 (eCNPJ/eCPF) + tax regime declaration. **DPA Núcleo↔chapter NOT exists**. Cert A1 = chapter legal signing credential — breach = chapter-level legal event.

**4. Audit readiness**:
- **CRITICAL**: cost/revenue commingled multi-chapter = audit isolated extraction impossible application-level only. PMI chapter bylaws require annual chapter-level reporting. **Hard blocker before financial module any second chapter**.
- pii_access_log missing org_id both accessor + target sides. LGPD Art. 37 (ROPA) requires per-chapter audit. Status: NEEDS_SCOPING.
- Decision log coverage: 7 ADRs Agent C + 3 ADR-0077-0079 NÃO em decision log. **Required**: create entries `docs/council/decisions/2026-05-09-*.md` "Proposed" status before any code touches.

**5. Risk management**:
- Sustentabilidade module no role-based separation. PMI-CE Diretor Financeiro role chapter-scoped + write entries + read-only other chapters + auditable does NOT exist. Don't expose without role design (ADR-0077).
- **NF-e fiscal responsibility chapter assumes**: chapter CNPJ = legal emitter. Errors = chapter responsibility. Required: (a) DPA Núcleo↔chapter, (b) UI fiscal terms chapter responsible, (c) chapter policy authorize NFS-e emission. **NONE EXIST**.
- **LGPD Art. 42 joint controller liability**: PMI-CE = controller, Núcleo = processor. Required: (a) DPA per chapter, (b) PMI-CE own DPO not Ivan, (c) PMI-CE privacy policy version, (d) chapter-isolated extraction Art. 18 (LGPD cron 5y currently global not per-chapter).

**Concrete worst-case PMI-CE Art. 18 deletion request**: Ivan (PMI-GO DPO) receives notification → not PMI-CE DPO → handling PMI-GO domain not PMI-CE → PMI-CE president legally exposed for Art. 18 failure unaware. **Chapter president exposure scenario must close before pilot**.

**6. Diretoria handover playbook MISSING = critical**:
PMI annual elections. Outgoing → incoming must: (1) receive admin transfer, (2) understand existing data + decisions + obligations (LGPD, governance, financial), (3) continue financial reporting uninterrupted. NO handover workflow. Closest = audit log MCP. Year-end financial reconciliation impossible audit log alone.

**Minimum viable handover audit trail**: decision log + governance chain PDF exports + sustainability CSV + member roster engagement history. **Pre-second-chapter formalization required** otherwise Núcleo = dependency chapter cannot hand over.

**Continuity audit Vitor solo developer risk**: if transitions roles, operational continuity 100% docs quality. DISASTER_RECOVERY.md + RUNBOOK.md exist; **governance continuity docs (admin transfer, chapter obligations) NOT exist standalone artifact non-technical chapter leadership**. **Recommendation**: `docs/CHAPTER_GOVERNANCE_CONTINUITY.md` before Ω-E.

**7. Voluntariado vs profissional Sustentabilidade**:
Lei 6.404/76 + CFC: signing financial statements requires Contador with CRC. Distinction:
- Volunteer Diretor Financeiro CAN: view/enter cost/revenue, generate internal reports
- ONLY licensed accountant CAN: sign annual DRE, audited financial statement, NFS-e fiscal responsibility declaration jurisdictions

Platform must NOT present substitute professional accounting. **UI fiscal emission carry**: "Esta plataforma é ferramenta apoio. Responsabilidade fiscal pela NFS-e/NFC-e emitida é inteiramente do capítulo como pessoa jurídica, devendo manter contabilidade formal junto a profissional contábil habilitado."

**ADR sequencing governance-safe (Gates)**:
- **Gate 0** (async, no Ω-A block): Roberto comments close + ADR-0076 Wave 4 Ivan DPO
- **Gate 1** (pre-second-chapter): ADR-NEW-C contact emails + ADR-0077 multi-tenant financial + decision log entries all ADRs
- **Gate 2** (pre-fiscal module): DPA template + legal-counsel review ADR-NEW-E + ADR-0079 + chapter fiscal responsibility terms
- **Gate 3** (pre-prod financial): ADR-NEW-B brand schema + ADR-NEW-D MCP (post-ADR-0076) + ADR-NEW-A URL routing + ADR-0078 ticketing
- **Gate 4** (post-pilot 6mo): ADR-NEW-G i18n chapter-aware + ADR-NEW-F frontend defense

**Recomendação Ω-A governance-safe**: proceed Ω-A trilingue + critical pages + README/INDEX corrections. Decision log entries ADR-NEW-A through G logged "Proposed" before any code touches relevant component. **Don't implement Ω-A**: whitelabel/branding (requires ADR-NEW-B), financial multi-chapter (requires org_id + ADR-0077), fiscal docs (requires DPA + legal-counsel + ADR-0079), per-chapter DPO routing (requires PMI-CE formal DPO).

**Risk flags governance summary** (10 risks with category/likelihood/impact/status):
- Governance PDFs wrong chapter attribution: HIGH/HIGH **Hard blocker pre-pilot**
- cost/revenue org_id: CERTAIN/HIGH **Hard blocker pre-financial-module**
- NF-e no DPA: HIGH/CRITICAL **Gate 2**
- LGPD Art. 18 wrong DPO: HIGH/HIGH **Gate 1**
- Diretoria handover no playbook: CERTAIN/MED-HIGH **Create before pilot**
- Roberto curator open at expansion: MED/MED **Gate 0**
- Volunteer Financeiro fiscal no disclaimer: HIGH/MED **Gate 2**
- ADR-NEW-A/G no decision log: CERTAIN/MED **Before any Ω-E implementation**
- i18n PT-only PMI international demos: HIGH/MED **Ω-A close**
- pii_access_log no org_id: HIGH/MED **Gate 1**

---

## Cross-cutting tensions to resolve (for Wave 3 Product Leader)

1. **NFeWizard-io GPL-3.0**: Security/VC (BLOCK) vs Legal (technically compatible server-side IF not packaged) vs NFS-e research (irrelevant — Java/JDK can't run on Workers anyway). **Resolution**: use node-sped-nfe by default + ADR-0079 documenting rationale + NFeWizard-io as authorized fallback IF future requires unique features.

2. **Per-chapter DPO**: Accountability (PMI-CE needs own DPO) vs Legal (DPO compartilhado VIÁVEL during pilot phase IF formalized in Acordo Cooperação). **Resolution**: pilot phase shared DPO formalized; production phase per-chapter DPO required.

3. **Ω-A scope this session**: UX (Bloco 1 ~5-7h critical 4 pages), Senior-eng (~14h with attendance deferred), VC/Angel (parallel commercial action 2 weeks), Startup-advisor (trilingue parallel sequence V5→Sympla→Airmeet). **Resolution**: trilingue critical 4-5 pages this session + flag commercial action + save findings as Ω-E queue.

4. **Sympla replace timing**: Startup-advisor (sem 5-10 Phase 1) vs Sympla research (HYBRID API ingestion R$0 build first) vs VC/Angel (don't build before paying pilot). **Resolution**: Phase 1 = Sympla API ingestion (R$0 build, like pmi-vep-sync), no internal ticketing yet. Replace decision triggered by paid pilot validation + agg fee >R$30K.

5. **Multi-tenant single-project vs separate**: Security flagged as foundational ADR decision. AI-eng (single EF + JWT claim) + Multi-tenant research (row-per-tenant <500 tenants). **Resolution**: ADR — single Supabase project + row-per-tenant + JWT org_id claim until ~50 chapters.

6. **NFS-e emission capacidade Núcleo**: Legal (chapter cobrando = obrigado), NFS-e research (NFS-e Nacional API + mTLS via Cloudflare Workers `mtls_certificates` binding), Accountability (DPA + chapter fiscal responsibility UI terms mandatory). **Resolution**: ADR-0079 (cert storage) + ADR-NEW-DPA + UI terms before any fiscal feature exposed.

---

## Strategic anchors confirmed across council

1. **Núcleo positioning vs Wild Apricot/AMS** (chapter-mgmt research + ux-leader): Núcleo = governance + AI layer ABOVE the AMS, NOT competitor. Resolves VC/Angel "Wild Apricot counter-argument".
2. **Best-of-breed > all-in-one institutional norm** (chapter-mgmt + Airmeet research): PMI WDC AI CoP uses Zoom; Toastmasters Zoom+Easy-Speak; CNCF KubeCon tiered; DevOpsDays Zoom+Streamyard+Discord. Hybrid is institutional pattern.
3. **Path A reframe** (c-level + vc-angel + startup-advisor): PMI partnership = distribution accelerator NOT monetization. "Don't expect PMI to write a check."
4. **Sustainability red flag** (c-level + accountability): zero second operators documented + Vitor solo dev = bus factor 1. CHAPTER_ONBOARDING_PLAYBOOK.md mandatory before Detroit.
5. **Bootstrap-scale TAM, not venture** (vc-angel): R$250-300K ARR Brazil PMI peak. Strong SMB. Path A activation only path to VC scale.

---

End of Council Wave 1 consolidated. Wave 3 Product Leader synthesizes from this + 5 web research deep-dives (`docs/research/p134_*.md`).
