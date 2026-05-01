# Claude Code — Project Rules

## Domain Model V4 (concluído 2026-04-13)
Refactor arquitetural completo: 6 ADRs (0004-0009), 30 migrations, 7 fases. Ver `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` para decisões e histórico. Decisões-chave:
- `can()` / `can_by_member()` é a source of truth para autoridade (ADR-0007)
- `initiatives` é o primitivo de domínio; `tribes` é bridge via dual-write (ADR-0005)
- `persons` + `engagements` modelam identidade; `members` é bridge (ADR-0006)
- Novos tipos de iniciativa = config no admin, não código (ADR-0009)

## Platform
- **URL:** https://nucleoia.vitormr.dev
- **Supabase:** ldrfrvwhxsmgaabwmaik (sa-east-1)
- **Version:** v3.2.1 (Structural Quality) | **236 MCP tools (157R+79W) + 4 prompts + 3 resources v2.53.0** | **31 Edge Functions** + **1 Cloudflare worker (pmi-vep-sync) LIVE @ wrangler 4.x** | **1443** unit (**1408** pass DB-aware) + 40 e2e tests | **68 ADRs + 8 amendments** (p87 hotfix 2026-05-01 ~16-17h BRT: 3 commits + 1 migration + 2 GitHub items + 0 dependabot vulns. `dbdd1c9` ADR-0066 Amendment 2026-05-01 (Phase 2 trigger + workflow gate gap surfacing + raise-the-bar mindset + Fabricio incident trace). `1fc1125` chore deps bump pmi-vep-sync wrangler 3→4 + vitest 2→3 (4 dependabot moderates closed: vite/undici×2/esbuild dev-time transitives — 0 prod runtime impact). `20260516370000` p87 hotfix migration: campaign_templates `pre_eval_pause` (3 langs) + Danilo status revert idempotente. Issue #117 spinoff (workflow gate enforcement: RPC precondition + Calendar token + audit log) + comment #116 (Calendar sync gap) com sweep findings. Operacional: emails Thayanne+Danilo Resend ack delivered (`5effc0ba` + `d4976563`, Danilo opened 16:10:02), Danilo `interview_pending → submitted`. Smoke 11/11 invariants = 0 violations. Routine `trig_01DYnnv5...` armed 2026-05-02T14:00Z verifica reschedule outcome. | p86 MEGA-marathon 2026-05-01: 10 commits autônomos + 6 deploys + 5 migrations + 2 issues fechadas + **Wave 5b chain 100% COMPLETE end-to-end**. `0b62229` Wave 5b-1b ai_analysis_runs separate table (RLS committee+manage_member SELECT, anon DENY) + backfill 6 apps run_index=1 + EF refactor pmi-ai-analyze (INSERT row up-front + UPDATE on completion/fail, derives triggered_by from enrichment_count) + EF redeploy. `b3846d6` Wave 5b-3 admin diff UI: nova aba "Análises IA" no modal admin/selection com runs timeline expansível (run_index DESC, badges triggered_by + status, snapshot expand: sumário/strengths/areas_to_probe/red_flags/fields_changed/tokens/duration) + topics-viewed audit count (informational). RPC `get_application_ai_analysis_runs` V4 committee/manage_member/view_internal_analytics. Migrations 20260516350000+360000. #115 CI closed (raiz: 8 commits unpushed); #113 Mayanna closed (audit revelou 7/7 items já implementados desde p77/p79). | p86 marathon 2026-05-01: 5 commits autônomos + 4 deploys + 4 migrations. `8d1de5d` Wave 5d core (RPC `request_interview_reschedule` V4 manage_member-or-committee-lead + admin UI amber block + email via campaign_send_one_off template `interview_reschedule_request` 3 langs + 14 contract tests + migrations 20260516320000+330000). `1ae7522` corrigi `.claude/rules/database.md` apply_migration MCP gap (NÃO escreve file local nem registra schema_migrations — manual repair mandatório). `d0f2acd` admin UX fixes (Data Aplicação column em pipeline list + filtros category/source no histórico de campanhas). `2b4c8cc` #5 architectural: Comunicação tab no perfil candidato (RPC `get_application_communications` lookup por external_email cobre PMI welcomes + reschedule + futuras sem backfill, migration 20260516340000). `343dc60` Wave 5b-2 portal frontend (Cards B + A): InterviewTopicsOptIn opt-in reveal + log_topic_view audit + EnrichmentCard 5 textareas com cap 2/cooldown 5min/cap-reached message + 28 i18n × 3 langs + onEnriched re-poll 8s. Wave 5b chain: 5b-0+5b-1+5b-2 ✅ ; 5b-1b/5b-3 deferred. Wave 5d ✅ E2E. Worker version `3ddd12ad-6516-48ad-a8dc-225cf9eeb9a1`. 8 sediment patterns (apply_migration MCP gap, campaign_send_one_off canonical, comms↔candidate via external_email, frontend changes need wrangler deploy separado, etc). Routine `trig_01DYnnv5...` armed 2026-05-02T14:00Z (Thayanne verify). | p84 EPIC 2026-04-30: 20 commits autônomos em 7 phases. Phase 1 chapter sweep 4 commits (admin/report+ReportPage data-driven, frontpage 3 sections + i18n + title 15, cycle-report HSL chart colors, certificate text neutralized 7 surfaces). Phase 2 Council UX/Product Wave 1+2+3 reorganização 6 commits (reorder 14 sections + drop dup stats, Hero "15 capítulos" pill, KPI goal-beat 8→15 superada, footer/ResourcesSection/chapters.cta neutralized, TribesSection a11y WCAG, CpmaiSection PT-BR announcement). Phase 3 PM-flagged content 1 commit. Phase 4 dynamic Dream Team + iniciativas + migration 20260430144154 (1 commit + 1 migration — `get_homepage_stats`/`get_public_platform_stats` extended com initiatives + active_leaders). Phase 5 SEO/RSS baseline 1 commit (sitemap.xml + /blog/feed.xml + /publications/feed.xml). Phase 6 MCP catalog + framework 3 commits (`scripts/generate-mcp-manifest.mjs` + `/docs/mcp` Astro page Path B curado + `docs/drafts/blog-mcp-framework-outline.md`). Phase 7 Wave 5b spec + council Tier 2 + 5b-0 legal blockers 4 commits (`docs/specs/p84-wave5-ai-augmented-self-improvement.md` + bug fix /blog anon read migration 20260430223830 + privacy.s4.googleAi 3 langs B1 + ADR-0067 N1 Art.20 safeguards + R3-C3 cláusula 9-A draft N2). 8 council agents convocados em 3 sets paralelos. Wave 5b-1+ destravada (schema migration + EF redeploy + frontend Card B antes A + admin diff). Memory updated: handoff_p85 + reference_key_people (Roberto Macedo correto, Macioni hallucination corrigida `d56b36d`). p83 chapter expansion foundation 2026-04-29: 3 commits autonomous data-driven `chapter_registry`. Sprint 1 backend: schema +country/display_order/logo_url cols + backfill 5 founding chapters + RPC `get_active_chapters()` SECDEF anon-grant LGPD-safe (cnpj não exposto). Sprint 2 frontend: novo `src/lib/chapters.ts` helper module-cached + 7 hot-spots refactored (3 React islands via useEffect+loadChapters; 3 Astro components SSR-fetch ou JSON injection; 1 admin page inline-script). Removed CHAPTER_FULL constant. Sprint 4 i18n: meta.description (3 langs) drops "5"; privacy.s1.chapters template `{list}` placeholder; footer.chapters semantic label + BaseLayout SSR-renders dynamic line; about.astro descriptions drop "5"; certificate footer text deferred Sprint 5. **15 chapters expansion now data-only** — quando Ivan mandar lista oficial: INSERTs em `chapter_registry` + adicionar 10 PNG logos = footer/privacy/team/admin atualizam automaticamente. p82 CBGPL launch 2026-04-29 18h: Ricardo Vargas QR + 15 chapters PMI Brasil união anunciada Ivan. Phase B portal completa: 6 UX fixes R1-R6 + interview opt-out all-or-nothing + Calendar booking `gh9WjefjcmisVLoh7` + Apps Script auto-add guests + profile self-service (LinkedIn/Credly/WhatsApp). Phase C parcial: EF `pmi-ai-analyze` gemini-2.5-flash + responseSchema PT-BR + retry 1s/4s/9s + anti-bias, dispatch via give_consent_via_token. N1 Resend daily throttle 100/day + 4/s burst + cron */30min. N2 AI retry cron 0 * * *. RPC `get_pmi_launch_health()` real-time observability. p82: 9 commits + 8 migrations 250000-310000 + 2 crons + 2 EFs (1 nova). DEFERRED V2: CV PDF extraction + LinkedIn post scraping. ADR-0066 PMI Journey v4 Phase 1 LIVE com Amendment 2026-04-29 pivot to /ingest pattern: 4 new tables + 22 RPCs (14 token-auth + 8 service helpers) + 2 views + 3 triggers. Worker pmi-vep-sync `dfaee1d6` + browser script. | p80 marathon: Phase B'' batches 15-20 (18 V3→V4 conversions across attendance/tribe/privacy/interview/showcase/admin/onboarding/selection-committee/eval-readers/dashboard tracks) — Phase B'' 131/246 (~53.3%) | p79: Mayanna feedback rounds 2+3 + #113 frontend 5/5 closed + Phase B'' batches 11-14 | p78: ADR-0065 Drive Phase 4 auto-discovery atas via cron + filename date heuristic + auto-promote + Pattern 43 4th reuse health RPC; ADR-0064 Drive Phase 3 LIVE com Path F OAuth refresh; 5 EFs Drive, 8 MCP tools Drive total | p77 ULTRA-EXTREME-marathon: Mayanna 6/7 items closed, ADR-0063 WhatsApp, drift v4 catched 3 LGPD broken | Phase B'' V3→V4: **131/246 (~53.3%)**)
- **AI Model:** Claude Opus 4.7 (`claude-opus-4-7`) — released 2026-04-16. xhigh effort level available. Updated tokenizer (1.0-1.35x token mapping). /ultrareview for code review.
- **Wiki:** GitHub org `nucleo-ia-gp` — repos `wiki` (private, Obsidian vault) + `frameworks` (public, CC-BY-SA/MIT). Synced to `wiki_pages` table via FTS. Scope: narrative knowledge only (ADR-0010) — operational data stays in SQL.
- **LGPD:** Art. 18 cycle complete (consent gate + export + delete + anonymize cron 5y)

## Build & Test
```bash
npx astro build          # MUST pass before commit
npm test                 # 1383 pass / 0 fail / 35 skip locally (with SUPABASE_SERVICE_ROLE_KEY: 1418 total)
npx wrangler deploy      # Deploy Worker
supabase functions deploy <name> --no-verify-jwt  # Deploy EF
```

## GC-097: Pre-Commit Validation (MANDATORY)

### If you touched SQL/RPC:
1. Check FK constraints: `SELECT constraint_name, pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = 'TABLE'::regclass AND contype = 'f';`
2. Verify `auth.uid()` vs `members.id` — events.created_by FK → auth.users(id), NOT members(id)
3. Test the RPC with real data via MCP execute_sql
4. Check for column name mismatches: members uses `name` (not `full_name`), `credly_url` (not `credly_username`), publication_submissions uses `submission_date` (not `submitted_at`)
5. Check array types: members.designations is `text[]` (not jsonb). Use `&&` not `?|`, use `array_length()` not `jsonb_array_length()`

### If you touched i18n:
1. Every new key MUST exist in ALL 3 dictionaries (pt-BR.ts, en-US.ts, es-LATAM.ts)
2. Grep for raw keys in components: any `t('key.name')` must have a corresponding entry
3. Check the key name matches exactly (e.g., `modal.advanced` vs `modal.advancedFields`)

### If you created/modified routes:
1. If a PT-BR page exists, /en/ and /es/ redirect pages must also exist
2. Check: `ls src/pages/en/X.astro src/pages/es/X.astro`

### If you modified an RPC signature:
1. Use DROP + CREATE (not CREATE OR REPLACE) when changing parameter types or count
2. Check for overloaded functions: `SELECT count(*) FROM pg_proc WHERE proname = 'X' AND pronamespace = 'public'::regnamespace`
3. After applying to DB, ALWAYS run: `NOTIFY pgrst, 'reload schema'`
4. Mark migration as applied: `supabase migration repair --status applied TIMESTAMP`

### ALWAYS:
1. Run `npx astro build` — must pass with 0 new errors
2. `npm test` — 0 failures
3. No hardcoded legacy URLs (grep for `platform.ai-pm-research-hub.workers.dev`)

## Key Architecture Decisions (do NOT re-litigate)
1. `checkOrigin: false` + manual CSRF in middleware (Astro's check blocks OAuth/MCP POSTs)
2. Custom domain `nucleoia.vitormr.dev` (`.workers.dev` has Bot Fight Mode blocking datacenter IPs)
3. `@modelcontextprotocol/sdk@1.29.0` + WebStandardStreamableHTTPServerTransport + Zod 4 schemas for MCP
4. Webinars table is source of truth (not events filtered by type)
5. Board items read-all for Tier 1+ members (curators need cross-board access)
6. LGPD: anon/ghost gets nothing from PII tables; public data via SECURITY DEFINER RPCs only
7. V4 Authority: `can()` is the canonical gate (ADR-0007). RLS uses `rls_can(action)` helpers. `operational_role` is a cache maintained by `sync_operational_role_cache` trigger.

## Detailed Rules
- Database: `.claude/rules/database.md`
- i18n: `.claude/rules/i18n.md`
- MCP: `.claude/rules/mcp.md`
- Deploy: `.claude/rules/deploy.md`

## Council (multi-agent review structure)
**Active since 2026-04-18.** 12 especialized sub-agents em `.claude/agents/` (product-leader, ux-leader, c-level-advisor, stakeholder-persona, senior-software-engineer, ai-engineer, data-architect, security-engineer, startup-advisor, vc-angel-lens, legal-counsel, accountability-advisor) operando em 3 tiers:

- **Tier 1 (always)**: `platform-guardian` + `code-reviewer` em início/fim de sessão e mudanças estruturais
- **Tier 2 (domain-triggered)**: invocar agent específico conforme domínio (ver `docs/council/README.md` tabela)
- **Tier 3 (strategic)**: `/council-review [topic]` em milestones — output em `docs/council/`

Todos são **consultivos** (não modificam código). PM/main loop decide ação. Decision log em `docs/council/decisions/`.
