# Architecture — AI & PM Research Hub

> Última atualização: 27 Março 2026 · v1.0.0-beta

---

## Visão Geral

```
┌─────────────────────────────────────────────────────────┐
│                   CLOUDFLARE WORKERS                      │
│                   (SSR + Static Assets)                   │
│                                                           │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │  Astro 6    │  │ React 19     │  │  Static Assets │  │
│  │  SSR Pages  │  │ Islands      │  │  (CSS/JS/img)  │  │
│  │  (routing,  │  │ (interactive │  │                │  │
│  │   i18n,     │  │  components) │  │                │  │
│  │   layouts)  │  │              │  │                │  │
│  └──────┬──────┘  └──────┬───────┘  └────────────────┘  │
│         │                │                                │
│         └────────┬───────┘                                │
│                  │ supabase-js client                     │
└──────────────────┼────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│                      SUPABASE                            │
│                                                           │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ Auth     │  │ PostgreSQL   │  │ Edge Functions    │  │
│  │ (Google, │  │ (300+ RPCs,  │  │ (17 functions,   │  │
│  │ LinkedIn,│  │  RLS, Views, │  │  Credly sync,    │  │
│  │ Azure)   │  │  pg_cron)    │  │  email, etc.)    │  │
│  └──────────┘  └──────────────┘  └───────────────────┘  │
│                                                           │
│  ┌──────────┐  ┌──────────────┐                          │
│  │ Storage  │  │ Realtime     │                          │
│  │ (avatars,│  │ (future)     │                          │
│  │  assets) │  │              │                          │
│  └──────────┘  └──────────────┘                          │
└─────────────────────────────────────────────────────────┘
                   │
        ┌──────────┼──────────┐
        ▼          ▼          ▼
   ┌─────────┐ ┌────────┐ ┌────────┐
   │ PostHog │ │ Sentry │ │ Resend │
   │Analytics│ │ Errors │ │ Email  │
   └─────────┘ └────────┘ └────────┘
```

---

## Camadas

### 1. Apresentação (Astro + React)

**Astro 6** opera em modo SSR via Cloudflare Workers adapter (`@astrojs/cloudflare` v13). Env access via `import { env } from 'cloudflare:workers'` (NOT `locals.runtime.env`). Páginas são `.astro` files que podem conter React islands para interatividade.

**MCP Server:** OAuth 2.1-authenticated MCP server at `nucleoia.vitormr.dev/mcp` with 3 surfaces — `/mcp` (342 raw registry) · `/semantic` (52 intent-level, SPEC-280 / #1383) · `/actions` (88 overflow for the 256/connector cap, #1377). See `docs/MCP_SETUP_GUIDE.md`. _(This file's per-subsystem counts below are mid-refresh under #1183.)_

**CSP Middleware:** Content Security Policy headers applied via Astro middleware (`src/middleware.ts`), not via `_headers` file.

**Padrão de i18n:**
```
src/pages/blog.astro        → /blog          (PT-BR, default)
src/pages/en/blog.astro     → /en/blog       (EN-US)
src/pages/es/blog.astro     → /es/blog       (ES-LATAM)
```

Toda página nova DEVE existir nas 3 rotas. Chaves de tradução em `src/i18n/{locale}.ts`.

**React Islands** são componentes interativos montados via `client:load` ou `client:visible`. Usados para: dashboards, BoardEngine, formulários, charts.

**Regra crítica:** Scripts inline Astro (`<script>` e `define:vars`) usam JavaScript puro — NÃO TypeScript. Eles geram IIFEs que bypassa o compilador TS.

### 2. Autenticação

Supabase Auth com 3 providers: Google, LinkedIn (OIDC), Microsoft Azure.

**Fluxo:**
1. Usuário clica "Login" → `CustomEvent('open-auth')` dispatched no `document`
2. Auth modal (apenas em `BaseLayout.astro`) abre
3. Supabase `signInWithOAuth()` redireciona para provider
4. Callback → session criada → `members.auth_id` vinculado automaticamente

**Regra crítica:** `auth.uid()` ≠ `members.id`. São UUIDs diferentes conectados via `members.auth_id`. Todo RPC que escreve FK para `members(id)` deve fazer lookup:

```sql
SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
```

### 3. Banco de Dados (PostgreSQL via Supabase)

**~50 tabelas** incluindo: `members`, `tribes`, `events`, `attendance`, `board_items`, `certificates`, `gamification_points`, `notifications`, `partner_entities`, `governance_documents`, `change_requests`, etc.

**300+ SECURITY DEFINER functions.** A maioria das operações passa por RPCs (`.rpc()`) em vez de queries diretas (`.from()`), por duas razões:

1. **RLS recursion prevention:** Queries diretas contra `members` dentro de policies que referenciam `members` causam recursão infinita.
2. **Tabelas deny-all:** 12 tabelas têm policy `rpc_only_deny_all` — queries diretas sempre retornam vazio.

**Padrão de criação de RPC:**
```sql
DROP FUNCTION IF EXISTS my_function(param_types);
CREATE FUNCTION my_function(...)
RETURNS ... LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$ ... $$;

NOTIFY pgrst, 'reload schema';
```

**pg_cron (4 jobs ativos):**

| Job | Schedule | Função |
|-----|----------|--------|
| sync-credly-all | Every 5 days 03:00 UTC | Sync badges do Credly |
| sync-attendance-points | Every 5 days 03:15 UTC | Recalcula XP de presença |
| detect-detractors-weekly | Mondays 14:00 UTC | Detecta membros ausentes 21+ dias |
| attendance-reminders-daily | Daily 14:00 UTC | Notifica eventos do dia |

Jobs cron usam funções `_cron` separadas (sem `auth.uid()` check) com `REVOKE` para `authenticated/anon`.

### 4. Edge Functions

46 Edge Functions (Deno runtime no Supabase; amostra representativa abaixo, refresh completo em #1183):

| Categoria | Functions | Notas |
|-----------|-----------|-------|
| Credly sync | sync-credly-all, verify-credly, sync-attendance-points | 3 com `--no-verify-jwt` |
| Email/Campaign | send-campaign, send-global-onboarding, send-allocation-notify | Via Resend API |
| MCP | nucleo-mcp | OAuth 2.1, 3 surfaces (342 / 52 / 88) |
| Utility | detect-detractors, attendance-reminders, etc. | 1 com `--no-verify-jwt` |
| Legacy | 2 não-deployed | Mantidas por referência |

### 5. Observabilidade

- **PostHog:** Analytics de produto, eventos customizados, feature flags
- **Sentry:** Error tracking, source maps, alertas
- **Audit log unificado:** 4 fontes (governance, attendance, board_lifecycle_events, notifications)

---

## Modelo de Permissões

### Hierarquia Operacional

```
Tier 1: manager, deputy_manager (+ is_superadmin flag)
Tier 2: tribe_leader, curator, communicator
Tier 3: sponsor, chapter_liaison (read-only executivo)
Tier 4: researcher (membro padrão)
Tier 5: observer (acesso limitado)
```

### Designações (laterais, aditivas)

| Designação | RPCs | Descrição |
|-----------|------|-----------|
| curator | 22 | Pipeline de qualidade completo |
| comms_team | 7 | Comunicação e campanhas |
| ambassador | 5 | Representação externa |
| deputy | via flag | Substituto do GP |

### `is_superadmin`

Flag ortogonal que bypassa todas as restrições de role. Apenas o GP e o Deputy possuem.

---

## Gamificação

Membros acumulam XP por:
- Presença em reuniões (auto-sync via pg_cron)
- Certificações PMI (sync via Credly)
- CPMAI certification
- Trilhas de conhecimento

**Categorias XP:** `trail` (20), `cert_pmi_senior` (50), `cert_cpmai` (45), `cert_pmi_mid` (40), `cert_pmi_practitioner` (35), `cert_pmi_entry` (30), `knowledge_ai_pm` (20), `specialization` (25), `course` (15), `badge` (10).

**Regra crítica:** 3 objetos DB devem ser atualizados simultaneamente: view `gamification_leaderboard`, function `get_member_cycle_xp()`, function `sync_attendance_points()`.

---

## BoardEngine

Motor genérico de boards (Kanban/Table/Calendar/Timeline/GroupedList) servindo:
- Boards individuais por tribo (entregáveis de pesquisa)
- Board do CPMAI
- Curadoria (view cross-board)

**Stack:** `@dnd-kit` para drag-and-drop, React 19, CardDetail com ~56K linhas.

**Schema:** `project_boards`, `board_items`, `board_item_assignments`, `board_lifecycle_events` — zero tabelas novas necessárias.

---

## Decisões de Arquitetura

| Decisão | Justificativa |
|---------|---------------|
| Astro SSR (não SPA) | SEO, i18n por rota, menor JS bundle |
| React islands (não full React) | Interatividade só onde necessário |
| SECURITY DEFINER everywhere | Previne RLS recursion, centraliza lógica |
| pg_cron (não Edge Function cron) | Mais simples, sem infraestrutura extra, acesso direto ao DB |
| Chart.js (não Recharts) | Funciona em Astro inline scripts sem React |
| Zero-cost architecture | Constraint do projeto: free tier everywhere |
| Trilingual from day 1 | Expansão internacional planejada desde C3 |

---

## Constraints

- **Zero-cost:** Supabase free tier, Cloudflare Workers free, PostHog free, Sentry free
- **LGPD:** Views `members_public_safe` para dados públicos, `excuse_reason` nunca exposto abaixo de GP/Deputy
- **Governance terminology:** Sem linguagem associativa (ata, votos, membros → substituídos por equivalentes de projeto)
- **CoP terminology:** "Tribos" (PT-BR) / "Research Streams" (EN) — nunca "CoP" em texto user-facing

---

## Ver também

- [CONTRIBUTING.md](CONTRIBUTING.md) — Como contribuir
- [RUNBOOK.md](RUNBOOK.md) — Operações e manutenção
- [GOVERNANCE_CHANGELOG.md](GOVERNANCE_CHANGELOG.md) — Histórico de decisões
- [BOARD_ENGINE_SPEC.md](BOARD_ENGINE_SPEC.md) — Especificação do BoardEngine
