# Claude Code — Project Rules

## Grounding — numbers must come from a live tool result (MANDATORY)

**IMPORTANT — YOU MUST:** any DB count, %, metric, cohort size, denominator, version number, or test baseline
that enters a user-decision prompt, an `AskUserQuestion` option, a commit message, a PR body, a SPEC, or a memory
file MUST be produced by a tool call **in the current turn**. NEVER recite or "correct" a number from memory,
from `MEMORY.md`, from a handoff, or from a prior turn — **re-query the source of truth** (`execute_sql`
read-only / MCP RPC / `npm view` / `curl` / `npm test`). A simulation/estimate is NOT a measurement; label it as
such and never let it become a stated antes/depois.

- If you do not have a fresh tool result for a number, **say so and re-query** — do NOT emit a confident estimate.
- When **correcting** a wrong number, re-run the query; do not nudge the value from memory (that produces another
  fabrication — see the 2026-05-30 incident in `reference_process_fix_and_context_hygiene_2026_05_30`).
- Before an `AskUserQuestion` whose options contain a number, the query that produced it must already be in the
  transcript above the question.
- antes→depois: capture BOTH from live queries (BEFORE pre-apply, AFTER post-apply). Never derive "before" by
  reasoning backward from "after".
- Re-ground numbers at each PR boundary; do not carry them in working memory across a long multi-PR session.

## Asserção de guard amarra CONDIÇÃO ao RESULTADO — presença de string não é prova (MANDATÓRIO)

**IMPORTANT — YOU MUST:** ao escrever um guard que afirma sobre um corpo (SQL, TS, `.astro`), a
asserção tem de casar **a condição junto com o resultado que ela produz**, dentro do bloco que
decide. `includes('x')` ou `/x/` solto num corpo de centenas de linhas fica **verde com o
mecanismo removido**, porque a string sobrevive em algum lugar que não decide nada.

- Três incidentes em 17/09/2026, todos pegos pelo teste de mutação e **nenhum por leitura**:
  1. `#2335`: `/is_visitor/` solto passava com o campo **removido do UNION** — a string sobrevivia
     nos comentários.
  2. `#2286`: `ef.includes('other_notifications')` passava com o **bloco do e-mail removido** —
     casava o comentário que eu mesmo escrevi para explicar a seção.
  3. `#2341`: `/retired_at IS NOT NULL/` passava com a **classificação inteira neutralizada** —
     casava a contagem de `retired_jobs` no `RETURN`.
- **A forma que funciona:** recortar o bloco que decide e afirmar dentro dele, ligando os dois lados
  — `assert.match(bloco, /retired_at IS NOT NULL\s+THEN\s+'aposentado'/)`, não
  `assert.match(corpo, /retired_at/)`. Para TS, mascarar comentários antes de medir
  (`maskJsComments`); para SQL, `maskLineComments`.
- **Mutação é obrigatória, e a mutação tem de MUDAR O ARQUIVO de fato** (compare o md5 antes e
  depois; uma mutação que não aplicou lê como "guard aprovou"). Cada asserção precisa de uma
  mutação que a faça reprovar, e o controle sem mutação precisa passar no fim.
- **Mutar o ARQUIVO não exercita camada VIVA.** Quando o guard afirma sobre o banco, a prova é
  evidência direta + controle positivo — exercer a função com impersonação e mostrar o estado
  mudando nos dois sentidos, como em `#2341` (expectativa sem cron ⇒ `red`).

## Antes de propor uma DECISÃO sobre uma tabela, leia os guards dela (MANDATÓRIO)

**IMPORTANT — YOU MUST:** antes de montar opções para o dono sobre o que fazer com os DADOS de uma
tabela (apagar, corrigir, migrar, rotular), rode `grep -rl "<tabela>" tests/contracts/` e **leia o
que esses guards afirmam**. Uma opção recomendada por quem não leu o guard é recomendação sem
lastro.

- Incidente que originou a regra (2026-09-15, #2292): levei ao dono três opções sobre 224 linhas
  de XP com "apagar" marcada como recomendada. `gamification_points` é um **ledger append-only**
  desde a onda 3 da #1087, e o comentário do próprio guard diz que o carve-out de `DELETE` é Art.
  18 da LGPD, *"never for a business revoke"*. A opção alinhada com a norma era outra, e estava na
  mesma tela sem que eu soubesse por quê.
- Isto é a irmã da regra que já existia para **escrita** (`grep` antes de escrever no banco
  compartilhado, porque derruba PR alheia). Mesmo comando, outra pergunta: lá "quem quebra se eu
  escrever", aqui **"quem já decidiu como se escreve"**.
- Se a tabela for um ledger, a forma de desfazer é **linha compensatória**, nunca remoção — e
  então todo leitor que contava LINHA precisa passar a ler SALDO. Na #2292 foram quatro.

## Domain Model V4 (concluído 2026-04-13)
Refactor arquitetural completo: 6 ADRs (0004-0009), 30 migrations, 7 fases. Ver `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` para decisões e histórico. Decisões-chave:
- `can()` / `can_by_member()` é a source of truth para autoridade (ADR-0007)
- `initiatives` é o primitivo de domínio; `tribes` é bridge via dual-write (ADR-0005)
- `persons` + `engagements` modelam identidade; `members` é bridge (ADR-0006)
- Novos tipos de iniciativa = config no admin, não código (ADR-0009)

## Platform
- **URL:** https://nucleoia.vitormr.dev
- **Supabase:** `ldrfrvwhxsmgaabwmaik` (sa-east-1)
- **Stack:** Astro v6 (Cloudflare Workers) · Supabase Postgres + Edge Functions (Deno) · Cloudflare worker `pmi-vep-sync` (wrangler 4.x)
- **MCP server:** `nucleo-mcp` em `supabase/functions/nucleo-mcp/` — OAuth 2.1 + custom domain `nucleoia.vitormr.dev/mcp` (ver `.claude/rules/mcp.md`)
- **AI Model:** Claude Opus 4.8 (`claude-opus-4-8`) — released 2026-05-28. xhigh effort level. `/ultrareview` for code review.
- **Wiki:** GitHub org `nucleo-ia-gp` — repos `wiki` (private, Obsidian vault) + `frameworks` (public, CC-BY-SA / MIT). Synced to `wiki_pages` table via FTS. Scope: narrative knowledge only (ADR-0010) — operational data stays in SQL.
- **LGPD:** Art. 18 cycle complete (consent gate + export + delete + anonymize cron 5y).
- **Current state (counts, last commits, session handoffs):** NOT pinned in CLAUDE.md (per Anthropic guidance — frequently-changing data bloats context). Use `/audit` skill, MCP tools `get_admin_dashboard` / `get_invitation_health`, or read `memory/handoff_p*.md` + `git log` when needed.

## Build & Test
```bash
scripts/setup-lane.sh ../.wt-<lane> [branch]   # RODE ISTO AO ABRIR QUALQUER LANE, antes de qualquer coisa
npm ci                   # lane worktrees start WITHOUT node_modules; the gate below cannot run until this does
./node_modules/.bin/astro build   # MUST pass before commit. Not `npx` (pulls a stray version), never piped
npm test                 # unit + e2e; DB-aware tests require SUPABASE_SERVICE_ROLE_KEY env
npm run test:verdict     # PREFIRA ISTO local: `npm test` sao DOIS blocos com DOIS sumarios, e
                         # quem le o primeiro le metade da suite. O veredito consolida e tem um
                         # terceiro estado: bloco que morreu SEM reportar nao conta como aprovado.
npx wrangler deploy      # Deploy main Worker
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
1. Run `./node_modules/.bin/astro build` — must pass with 0 new errors. Verify by the **unpiped exit code**
   (`cmd > log 2>&1; echo $?`, or `${PIPESTATUS[0]}`) and read the **head** of the log, which is where the tool
   names the error. `| tail` returns tail's exit code, and that turned a broken build into a reported "exit 0"
   twice on 2026-08-29. The pre-commit hook is a secret/PII scan, not a build gate: nothing enforces this but you.
2. `npm test` — 0 failures
3. No hardcoded legacy URLs (grep for `platform.ai-pm-research-hub.workers.dev`)

## Key Architecture Decisions (do NOT re-litigate)
1. `checkOrigin: false` + manual CSRF in middleware (Astro's check blocks OAuth/MCP POSTs)
2. Custom domain `nucleoia.vitormr.dev` (`.workers.dev` has Bot Fight Mode blocking datacenter IPs)
3. `@modelcontextprotocol/sdk@1.30.0` + WebStandardStreamableHTTPServerTransport + Zod 4 schemas for MCP
4. Webinars table is source of truth (not events filtered by type)
5. Board items read-all for Tier 1+ members (curators need cross-board access). **Carve-out (ADR-0105, #785):** confidential initiatives (`initiatives.visibility='confidential'`) are EXCLUDED from this read-all — their board/events/artifacts/docs are visible only to engaged members + GP (`manage_platform`). Gate = `rls_can_see_initiative()`; curation excludes confidential by default. Any new SECDEF read RPC over initiative-linked tables MUST apply the gate (see `docs/reference/V4_AUTHORITY_MODEL.md`).
6. LGPD: anon/ghost gets nothing from PII tables; public data via SECURITY DEFINER RPCs only
7. V4 Authority: `can()` is the canonical gate (ADR-0007). RLS uses `rls_can(action)` helpers. `operational_role` is a cache maintained by `sync_operational_role_cache` trigger.
8. **No SSR auth gate by design (ADR-0106, #856).** There is intentionally NO route auth-gate in middleware. The boundary is RLS + SECURITY DEFINER RPCs + client-side `canFor()` (anon gets an empty admin shell, no data). `src/middleware.ts` is the ONLY middleware (does redirect + CSRF + #855 security headers); NEVER recreate `src/middleware/index.ts` (Astro loads one module; it would silently shadow the live one — the #855/#856 root cause). Guarded by `tests/contracts/856-auth-gate-retired-shadow-guard.test.mjs`.

## Detailed Rules (loaded on demand)
- Database: `.claude/rules/database.md`
- i18n: `.claude/rules/i18n.md`
- MCP: `.claude/rules/mcp.md`
- Deploy: `.claude/rules/deploy.md`
- **Bypass protocol (--admin / direct push)**: `.claude/rules/bypass-protocol.md` (post-p209 governance — Option C Híbrido + weekly cron audit at `.github/workflows/bypass-audit-weekly.yml`)
- V4 refactor invariants (historical, archived): `docs/refactor/refactor-in-progress-RULES-ARCHIVED.md`

## Council (multi-agent review structure)
**Active since 2026-04-18.** 12 specialized sub-agents em `.claude/agents/` (product-leader, ux-leader, c-level-advisor, stakeholder-persona, senior-software-engineer, ai-engineer, data-architect, security-engineer, startup-advisor, vc-angel-lens, legal-counsel, accountability-advisor) operando em 3 tiers:

- **Tier 1 (always)**: `platform-guardian` + `code-reviewer` em início/fim de sessão e mudanças estruturais
- **Tier 2 (domain-triggered)**: invocar agent específico conforme domínio (ver `docs/council/README.md` tabela)
- **Tier 3 (strategic)**: `/council-review [topic]` em milestones — output em `docs/council/`

Todos são **consultivos** (não modificam código). PM/main loop decide ação. Decision log em `docs/council/decisions/`.

### Routing discipline (MANDATORY — context-hygiene 2026-06-11)
- **1 agente por subação.** Escolha o agente cujo domínio casa com a tarefa; não convoque mais de um "por garantia".
- **NUNCA convocar o conselho inteiro por default.** Convocação múltipla (>1 agente) ou `/council-review` exige **justificativa explícita** (milestone, decisão estratégica de alto impacto, ou conflito de domínio real) — declare-a antes de invocar.
- Tier 1 (`platform-guardian`/`code-reviewer`) e o agente de domínio (Tier 2) cobrem ~95% dos casos. Tier 3 é exceção, não rotina.
- Agentes são lazy-loaded (custo ~0 em contexto fixo); o custo é **por spawn** — cada invocação extra é um context window inteiro. Trate convocação como gasto, não como hábito.

## Portfolio PMO (knowledge loop)

- This repo lives under Vitor's portfolio PMO at `~/projects` (the parent
  `CLAUDE.md` there governs PMO mode; machine-global skills at
  `~/.claude/skills/`, SSOT = `AI-PMO-Framework/skills/`).
- It carries a standing `[LL]` lessons-learned-intake issue; at the end of
  meaningful work sessions, log reusable lessons there (what worked, what
  should change in the framework/skills/kits) so the PMO can harvest them
  (`pmo-sync.sh harvest`).
