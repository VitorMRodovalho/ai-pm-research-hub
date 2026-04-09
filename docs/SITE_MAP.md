# Site Map & Access Tiers / Mapa do Site & Niveis de Acesso / Mapa del Sitio & Niveles de Acceso

> **Canonical URL:** [nucleoia.vitormr.dev](https://nucleoia.vitormr.dev)
> **Trilingual:** PT-BR (default) + EN-US (`/en/`) + ES-LATAM (`/es/`)
> **Source of truth:** [`src/lib/navigation.config.ts`](../src/lib/navigation.config.ts)

---

## Access Tiers / Niveis de Acesso / Niveles de Acceso

The platform uses a hierarchical tier model. Each page has a minimum tier — users at or above that tier can see it.

A plataforma usa um modelo hierarquico de niveis. Cada pagina tem um nivel minimo — usuarios no nivel ou acima podem ve-la.

La plataforma utiliza un modelo jerarquico de niveles. Cada pagina tiene un nivel minimo — los usuarios en ese nivel o superior pueden verla.

| Tier | # | PT-BR | EN-US | ES-LATAM | Who / Quem / Quien |
|------|---|-------|-------|----------|---------------------|
| `visitor` | 0 | Visitante | Visitor | Visitante | Anyone, no login / Qualquer pessoa sem login |
| `member` | 1 | Membro | Member | Miembro | Authenticated researcher / Pesquisador autenticado |
| `observer` | 2 | Observador | Observer | Observador | Chapter board, sponsors / Conselho do capitulo |
| `leader` | 3 | Lider | Leader | Lider | Tribe leaders / Lideres de tribo |
| `admin` | 4 | Administrador | Admin | Administrador | GP, Deputy GP, Curators / GP, Vice-GP, Curadores |
| `superadmin` | 5 | Super Admin | Super Admin | Super Admin | Platform owner / Proprietario da plataforma |

**Additional access via designations:** `sponsor`, `chapter_liaison`, `chapter_board`, `curator`, `co_gp`, `comms_leader`, `comms_member`, `ambassador`, `founder`.

---

## Public Pages (visitor) / Paginas Publicas / Paginas Publicas

No login required. Full SEO, social sharing, and public impact data.

| Route | Page | Description (PT-BR) | Description (EN) |
|-------|------|---------------------|-------------------|
| `/` | Homepage | Numeros de impacto, quadrantes, tribos, trilha, time | Impact numbers, quadrants, tribes, trail, team |
| `/about` | Sobre | Missao, visao, valores | Mission, vision, values |
| `/blog` | Blog | Artigos publicados pela equipe | Team-published articles |
| `/blog/[slug]` | Post | Artigo individual | Individual post |
| `/library` | Biblioteca | 330+ recursos categorizados | 330+ categorized resources |
| `/gamification` | Gamificacao | Leaderboard, XP, niveis | Leaderboard, XP, levels |
| `/governance` | Governanca | Manual de Governanca R2 (33 secoes, somente leitura) | Governance Manual R2 (33 sections, read-only) |
| `/webinars` | Webinars | Calendario publico de webinars | Public webinar calendar |
| `/projects` | Pilotos IA | Projetos piloto com IA | AI pilot projects |
| `/artifacts` | Artefatos | Frameworks e templates | Frameworks and templates |
| `/privacy` | Privacidade | Politica LGPD | LGPD privacy policy |
| `/help` | Ajuda | FAQ e guias | FAQ and guides |
| `/verify/[code]` | Verificacao | Verificacao publica de certificado | Public certificate verification |
| `/changelog` | Novidades | Historico de versoes | Version history |

---

## Member Pages (authenticated) / Paginas do Membro / Paginas del Miembro

Login required. Personal data, tribe interaction, and collaboration tools.

| Route | Min Tier | Page | Description |
|-------|----------|------|-------------|
| `/workspace` | member | Workspace | Personal dashboard: KPIs, tasks, attendance, tribe |
| `/profile` | member | Perfil | XP, badges, streak, completude, Credly |
| `/onboarding` | member | Onboarding | Checklist de integracao (8 steps) |
| `/tribe/[id]` | member | Tribo | Dashboard da tribo: membros, eventos, entregas |
| `/boards` | member | Quadros | Lista de boards kanban por tribo |
| `/boards/[id]` | member | Board | Board individual (kanban, table, calendar) |
| `/attendance` | member | Presenca | Eventos, check-in, ranking, quadro de presenca |
| `/notifications` | member | Notificacoes | Central de notificacoes |
| `/certificates` | member | Certificados | Certificados emitidos + termo de voluntariado |
| `/volunteer-agreement` | member | Termo de Voluntariado | Assinatura do termo de voluntariado |
| `/presentations` | member | Apresentacoes | Decks e materiais de apresentacao |
| `/cpmai` | member | Trilha CPMAI | Trilha de certificacao PMI-CPMAI |
| `/publications/submissions` | leader+ | Publicacoes | Pipeline de submissao de artigos |
| `/stakeholder` | observer+ | Stakeholder | Dashboard executivo para sponsors |

---

## Admin Pages / Paginas Administrativas / Paginas Administrativas

Requires `admin` tier or specific designations. Full governance and management tools.

| Route | Min Tier | Designations | Page |
|-------|----------|-------------|------|
| `/admin` | observer | — | Dashboard: KPIs, widgets, health |
| `/admin/members` | admin | — | Gerenciamento de membros |
| `/admin/members/[id]` | admin | — | Detalhe do membro |
| `/admin/tribes` | admin | — | Catalogo de tribos |
| `/admin/tribe/[id]` | leader | sponsor, chapter_liaison | Dashboard admin da tribo |
| `/admin/selection` | admin | — | Pipeline de selecao |
| `/admin/certificates` | admin | chapter_board | Certificados + termos de voluntariado |
| `/admin/analytics` | admin | sponsor, chapter_board | Analytics de produto |
| `/admin/chapter` | admin | chapter_board | Dashboard do capitulo |
| `/admin/chapter-report` | observer | sponsor, chapter_liaison | Relatorio por capitulo |
| `/admin/portfolio` | admin | sponsor, curator, chapter_board | Portfolio Gantt + heatmap |
| `/admin/cycle-report` | admin | sponsor, chapter_liaison | Metricas do ciclo |
| `/admin/governance-v2` | admin | curator, co_gp | Administracao de CRs |
| `/admin/curatorship` | observer | — | Board de curadoria |
| `/admin/sustainability` | admin | sponsor, curator | Sustentabilidade financeira |
| `/admin/knowledge` | admin | — | Gestao de conhecimento |
| `/admin/blog` | admin | comms_team | Editor de blog (TipTap) |
| `/admin/comms` | admin | comms_leader | Dashboard de comunicacao |
| `/admin/comms-ops` | admin | comms_leader | Board de operacoes |
| `/admin/campaigns` | admin | comms_team | Campanhas de email (Resend) |
| `/admin/webinars` | admin | — | CRUD de webinars |
| `/admin/publications` | admin | — | Admin de publicacoes |
| `/admin/partnerships` | admin | sponsor, chapter_liaison | Pipeline de parcerias |
| `/admin/pilots` | admin | — | Projetos piloto IA |
| `/admin/tags` | admin | — | Gerenciamento de tags |
| `/admin/data-health` | admin | — | Verificacoes de qualidade de dados |
| `/admin/audit-log` | admin | — | Trilha de auditoria |
| `/admin/adoption` | admin | — | Metricas de adocao |
| `/admin/settings` | superadmin | — | Configuracoes da plataforma |

---

## System Architecture / Arquitetura do Sistema / Arquitectura del Sistema

```
 Users (Browser)          AI Assistants (6 hosts)
       |                          |
       v                          v
+-------------------------------+-----------------------------+
|          Cloudflare Workers (Edge SSR)                      |
|  +------------------+  +---------------+  +-------------+  |
|  | Astro 6 SSR      |  | /mcp Proxy    |  | OAuth 2.1   |  |
|  | React 19 Islands |  | Auto-refresh  |  | DCR + PKCE  |  |
|  | Tailwind 4       |  | KV sessions   |  | Consent     |  |
|  +------------------+  +---------------+  +-------------+  |
+-------------------------------+-----------------------------+
                |                |
                v                v
+-------------------------------+-----------------------------+
|          Supabase (sa-east-1)                               |
|  +------------------+  +---------------+  +-------------+  |
|  | PostgreSQL       |  | Auth          |  | Edge Fns    |  |
|  | 200+ RPC/SECDEF  |  | Google        |  | 21 deployed |  |
|  | RLS per row      |  | LinkedIn      |  | sync-artia  |  |
|  | pg_cron (4 jobs) |  | Microsoft     |  | sync-credly |  |
|  +------------------+  +---------------+  +-------------+  |
+-------------------------------+-----------------------------+
                |                |
                v                v
+-------------------------------+-----------------------------+
|          External Integrations                              |
|  +----------+  +----------+  +--------+  +-------------+  |
|  | PostHog  |  | Sentry   |  | Artia  |  | Resend      |  |
|  | Analytics|  | Errors   |  | PMO    |  | Email       |  |
|  +----------+  +----------+  +--------+  +-------------+  |
+-------------------------------------------------------------+
```

### Integration Map / Mapa de Integracoes

| System | Protocol | Purpose (PT-BR) | Purpose (EN) |
|--------|----------|-----------------|--------------|
| **Supabase** | REST + Realtime | Banco de dados, auth, edge functions | Database, auth, edge functions |
| **Cloudflare Workers** | HTTP | SSR, OAuth proxy, MCP proxy | SSR, OAuth proxy, MCP proxy |
| **Cloudflare KV** | KV | Sessoes OAuth, refresh tokens (30d TTL) | OAuth sessions, refresh tokens |
| **PostHog** | HTTP | Product analytics, session replay | Product analytics, session replay |
| **Sentry** | HTTP | Monitoramento de erros em tempo real | Real-time error monitoring |
| **Artia** | REST API | Sincronizacao de portfolio PMI-GO | PMI-GO portfolio sync |
| **Resend** | REST API | Email campaigns e notificacoes | Email campaigns and notifications |
| **Credly** | REST API | Sincronizacao de badges e certificacoes | Badge and certification sync |
| **MCP (56 tools)** | Streamable HTTP | 47 leitura + 9 escrita, OAuth 2.1 | 47 read + 9 write, OAuth 2.1 |

### Verified MCP Hosts / Hosts MCP Verificados

| Host | Status |
|------|--------|
| Claude.ai | Verified (56 tools) |
| Claude Code | Verified |
| ChatGPT | Verified (beta) |
| Perplexity | Verified |
| Cursor / VS Code | Verified |
| Manus AI | Verified (JSON import) |

---

## LGPD Compliance / Conformidade LGPD

| Rule | Implementation |
|------|---------------|
| No PII for anonymous | RLS blocks all PII tables for `anon` role |
| Public data via SECURITY DEFINER | `get_public_platform_stats()`, `get_public_leaderboard()` — no email, phone, PMI ID |
| Ghost users (auth without member) | Get nothing from PII tables |
| Audit trail | All admin actions logged to `admin_audit_log` |
| Data retention | Configurable via `data_retention_policy` table |
| Right to deletion | Member deactivation preserves aggregate stats, removes PII |

---

*Generated from `navigation.config.ts` on 2026-04-08. For live access, visit [nucleoia.vitormr.dev](https://nucleoia.vitormr.dev).*
