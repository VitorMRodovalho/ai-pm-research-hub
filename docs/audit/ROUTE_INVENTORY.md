# W139 — Route Inventory

**Data:** 2026-03-14
**Total de Rotas:** 63 arquivos .astro → 42 rotas únicas (excl. redirects e variantes i18n)

---

## Legenda de Status

- ✅ = Página carrega, features funcionam, dados são reais
- ⚠️ = Página carrega mas funcionalidade parcial (facade, placeholder, dados incompletos)
- ❌ = Página com erros, referências quebradas, ou completamente não-funcional
- 🔀 = Redirect (301/302 ou meta-refresh)

---

## Páginas Públicas (sem autenticação)

| # | Rota | Arquivo | Auth | Role Gate | Nav? | Status |
|---|------|---------|------|-----------|------|--------|
| 1 | `/` | `src/pages/index.astro` | Não | Nenhum | ✅ Home | ✅ |
| 2 | `/about` | `src/pages/about.astro` | Não | Nenhum | Via /help | ✅ |
| 3 | `/blog` | `src/pages/blog/index.astro` | Não | Nenhum | ✅ Nav primary | ✅ |
| 4 | `/blog/[slug]` | `src/pages/blog/[slug].astro` | Não | Nenhum | Via /blog | ✅ |
| 5 | `/help` | `src/pages/help.astro` | Não | Nenhum | ✅ Nav + "?" button | ✅ |
| 6 | `/library` | `src/pages/library.astro` | Não | Nenhum | ✅ Nav primary | ✅ |
| 7 | `/privacy` | `src/pages/privacy.astro` | Não | Nenhum | Via footer | ✅ |
| 8 | `/projects` | `src/pages/projects.astro` | Não | Nenhum | ✅ Nav | ⚠️ Btn sem handler |
| 9 | `/gamification` | `src/pages/gamification.astro` | Não | Nenhum | ✅ Nav primary | ✅ |
| 10 | `/artifacts` | `src/pages/artifacts.astro` | Não* | Nenhum | ✅ Nav | ✅ |
| 11 | `/404` | `src/pages/404.astro` | Não | Nenhum | Sistema | ✅ |

*Artifacts: público para visualizar, auth para upload

---

## Páginas Autenticadas (membros)

| # | Rota | Arquivo | Auth | Role Gate | Nav? | Status |
|---|------|---------|------|-----------|------|--------|
| 12 | `/workspace` | `src/pages/workspace.astro` | Sim | Qualquer membro | ✅ Nav primary | ⚠️ `active_members` view inexistente |
| 13 | `/profile` | `src/pages/profile.astro` | Sim | Qualquer membro | ✅ Drawer | ✅ |
| 14 | `/attendance` | `src/pages/attendance.astro` | Sim | Qualquer membro | ✅ Drawer | ✅ |
| 15 | `/notifications` | `src/pages/notifications.astro` | Sim | Qualquer membro | ✅ Nav | ✅ |
| 16 | `/onboarding` | `src/pages/onboarding.astro` | Sim | Qualquer membro | ✅ Nav | ✅ |
| 17 | `/tribe/[id]` | `src/pages/tribe/[id].astro` | Sim | Qualquer membro | ✅ Nav dynamic | ✅ |
| 18 | `/presentations` | `src/pages/presentations.astro` | Sim | Qualquer membro | ✅ Nav | ✅ |
| 19 | `/publications` | `src/pages/publications.astro` | Sim | Leader+ | ✅ Nav | ⚠️ `publication_submission_events` table inexistente |
| 20 | `/webinars` | `src/pages/webinars.astro` | Sim | Leader+ | ✅ Nav | ✅ |
| 21 | `/teams` | `src/pages/teams.astro` | Sim | Qualquer membro | Via workspace/publications | ✅ |
| 22 | `/report` | `src/pages/report.astro` | Sim | Admin+ | ✅ Drawer admin | ✅ |

---

## Páginas Admin

| # | Rota | Arquivo | Auth | Role Gate | Nav? | Status |
|---|------|---------|------|-----------|------|--------|
| 23 | `/admin` | `src/pages/admin/index.astro` | Sim | Observer+ | ✅ Nav primary | ✅ |
| 24 | `/admin/analytics` | `src/pages/admin/analytics.astro` | Sim | Admin + designations | ✅ Drawer | ✅ |
| 25 | `/admin/blog` | `src/pages/admin/blog.astro` | Sim | Admin + comms_team | ✅ AdminNav | ✅ |
| 26 | `/admin/board/[id]` | `src/pages/admin/board/[id].astro` | Sim | Admin | ❌ Sem link interno | ⚠️ Órfão |
| 27 | `/admin/campaigns` | `src/pages/admin/campaigns.astro` | Sim | Admin + comms_team | ✅ AdminNav | ✅ |
| 28 | `/admin/chapter-report` | `src/pages/admin/chapter-report.astro` | Sim | Observer + designations | ✅ AdminNav | ✅ |
| 29 | `/admin/comms` | `src/pages/admin/comms.astro` | Sim | Admin + comms_leader/member | ✅ AdminNav | ✅* |
| 30 | `/admin/comms-ops` | `src/pages/admin/comms-ops.astro` | Sim | Admin + comms designations | ✅ Nav | ✅ |
| 31 | `/admin/curatorship` | `src/pages/admin/curatorship.astro` | Sim | Observer+ | ✅ AdminNav | ✅ |
| 32 | `/admin/cycle-report` | `src/pages/admin/cycle-report.astro` | Sim | Admin + designations | ✅ AdminNav | ✅ |
| 33 | `/admin/governance-v2` | `src/pages/admin/governance-v2.astro` | Sim | Admin + curator/co_gp | ✅ Nav | ✅ |
| 34 | `/admin/member/[id]` | `src/pages/admin/member/[id].astro` | Sim | Admin | ❌ Sem link interno | ⚠️ Órfão |
| 35 | `/admin/partnerships` | `src/pages/admin/partnerships.astro` | Sim | Admin + designations | ✅ Nav | ✅ |
| 36 | `/admin/portfolio` | `src/pages/admin/portfolio.astro` | Sim | Admin + designations | ✅ Nav | ✅ |
| 37 | `/admin/selection` | `src/pages/admin/selection.astro` | Sim | Admin | ✅ Drawer | ✅ |
| 38 | `/admin/settings` | `src/pages/admin/settings.astro` | Sim | Superadmin | ✅ Drawer | ✅ |
| 39 | `/admin/sustainability` | `src/pages/admin/sustainability.astro` | Sim | Admin + designations | ✅ Nav | ⚠️ UI mockup sem backend |
| 40 | `/admin/tribes` | `src/pages/admin/tribes.astro` | Sim | Admin | ✅ AdminNav | ✅ |
| 41 | `/admin/tribe/[id]` | `src/pages/admin/tribe/[id].astro` | Sim | Leader+ | ✅ AdminNav dynamic | ✅ |
| 42 | `/admin/webinars` | `src/pages/admin/webinars.astro` | Sim | Admin | Via /admin/comms link | ✅ |

*comms: RPCs e dados existem; tokens de API social estão null (sem sync automático), dados seed presentes

---

## Redirects

| Rota | Destino | Tipo |
|------|---------|------|
| `/rank` | `/gamification` | 302 |
| `/ranks` | `/gamification` | 302 |
| `/admin/help` | `/help` | 301 |

---

## Variantes i18n (meta-refresh redirects)

| Rota | Destino |
|------|---------|
| `/en` | `/?lang=en` |
| `/en/workspace` | `/workspace?lang=en` |
| `/en/library` | `/library?lang=en` |
| `/en/profile` | `/profile?lang=en` |
| `/en/artifacts` | `/artifacts?lang=en` |
| `/en/gamification` | `/gamification?lang=en` |
| `/en/attendance` | `/attendance?lang=en` |
| `/en/onboarding` | `/onboarding?lang=en` |
| `/en/tribe/[id]` | `/tribe/[id]?lang=en` |
| `/es/*` | Mesmo padrão (9 variantes) |

---

## Conectividade de Navegação

### Páginas Sem Entrada Direta pela Navegação Principal

| Rota | Acessível Via | Órfão? |
|------|--------------|--------|
| `/about` | Link em `/help` | Não |
| `/admin/board/[id]` | **NENHUM LINK ENCONTRADO** | ⚠️ SIM |
| `/admin/member/[id]` | **NENHUM LINK ENCONTRADO** | ⚠️ SIM |
| `/admin/webinars` | Link em `/admin/comms` ("Voltar para Webinars") | Não |
| `/privacy` | Link no footer do BaseLayout | Não |
| `/teams` | Link em `/workspace` e `/publications` | Não |

### Dead Links (links no nav apontando para rotas inexistentes)

**NENHUM.** Todas as 30 rotas no `navigation.config.ts` e no `AdminNav.astro` apontam para arquivos .astro existentes.

---

## Classificação de Facades

| Rota | Tipo | Impacto | Esforço de Fix |
|------|------|---------|---------------|
| `/admin/sustainability` | Página completa — cards hardcoded, zero RPCs, zero tabelas | BAIXO (stakeholders only) | Médio (criar RPC + tabela de pilares) |
| `/projects` | Botão "Register Pilot" (`btn-register-pilot`) sem handler | BAIXO (admin-only button) | Pequeno (add onclick handler) |
| `/workspace` | Query `active_members` retorna null silenciosamente | MÉDIO (tribe member count always 0) | Pequeno (criar view) |
| `/publications` | Query `publication_submission_events` falha silenciosamente | BAIXO (extra metadata not loaded) | Pequeno (criar tabela ou remover query) |
