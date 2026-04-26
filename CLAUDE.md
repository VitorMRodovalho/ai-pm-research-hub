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
- **Version:** v3.2.1 (Structural Quality) | 143 MCP tools (96R+47W) | 24 Edge Functions | **1397** unit (**1374** with DB env) + 40 e2e tests (0 fails — p58 Track Q-D batches 3a.3a+3a.3b+3a.4 initiative/board+knowledge/wiki readers (7 dead + 22 member-tier + 1 verified-public) Q-D 73/109=67% + p57 Q-D batch 3a.1 council-validated reshape + p55 Track Q-D SECDEF security hardening sweep started + p54 Phase B' batch 4 migrated 4 V3-gated/no-gate fns to V4 incl drift signals #7 #8 + p53 Phase B' batches 1-3 migrated 9 V3-gated fns to V4 manage_platform + p52 Track Q Phase A+B captured 159 orphans/drifted fn bodies via 13 recovery + 4 drift correction migrations)
- **AI Model:** Claude Opus 4.7 (`claude-opus-4-7`) — released 2026-04-16. xhigh effort level available. Updated tokenizer (1.0-1.35x token mapping). /ultrareview for code review.
- **Wiki:** GitHub org `nucleo-ia-gp` — repos `wiki` (private, Obsidian vault) + `frameworks` (public, CC-BY-SA/MIT). Synced to `wiki_pages` table via FTS. Scope: narrative knowledge only (ADR-0010) — operational data stays in SQL.
- **LGPD:** Art. 18 cycle complete (consent gate + export + delete + anonymize cron 5y)

## Build & Test
```bash
npx astro build          # MUST pass before commit
npm test                 # 1372 pass / 0 fail / 25 skip locally (p50 Q-C added 1 offline + 2 DB-aware contracts; with SUPABASE_SERVICE_ROLE_KEY: 1374 pass / 23 skip)
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
