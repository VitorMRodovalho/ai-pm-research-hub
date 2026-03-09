# Núcleo IA & GP — v4 Backlog & Wave Planning
## Status: Março 2026 (Atualizado com SecOps, Analytics e Fundação DB/UI)

---

## ✅ COMPLETED (Sprints 2-7 + Wave 2 Partial)

| Sprint | Deliverable | Status |
|--------|------------|--------|
| S2 | Index migration: 10 sections + 6 data files | ✅ Production |
| S3 | Attendance page: KPIs, events, roster, modals | ✅ Production |
| S4 | Artifact tracking (draft→published) + Enhanced profile | ✅ Production |
| S5 | i18n infrastructure + index PT/EN/ES (partial) | ✅ Production |
| S6 | Gamification: leaderboard, points, certificates | ✅ Production |
| S7 | Admin Dashboard: Tribe Management + Member CRUD | ✅ Production |
| — | Credly Edge Function (fuzzy match, 3 categories) | ✅ Production |
| — | LinkedIn OIDC login button | ✅ Production |
| — | 56 member photos in Supabase Storage | ✅ Production |

---

## 🌊 WAVE 3: Profile, Gamification & UX Excellence
**Foco:** Retenção de voluntários, UX impecável e inteligência de uso.

| ID | Feature | Priority | Description |
|----|---------|----------|-------------|
| S-RM2 | Completeness Bar & Timeline | High | Adaptative completion bar (Role-based) + "Minha Jornada" cycle history timeline. |
| S-RM3 | Gamification v2 (Levels) | High | Lifetime XP points, Levels (Explorador → Lenda), Automated achievements (Early Adopter). |
| S-PA1 | Product Analytics | High | Setup do PostHog (rastreamento autenticado via Supabase ID) para medir funis e retenção no Astro. |
| S8b | i18n Internal Pages | Medium | Apply i18n keys to `/admin`, `/attendance`, and modals. |
| S11 | UI Polish & Empty States | Medium | 404 page, loading spinners, and actionable Empty States nas tabelas. |

---

## 🌊 WAVE 4: Admin Tiers, Integrations & Comms
**Foco:** Reduzir atrito do Gerente de Projeto (GP) e melhorar comunicação.

| ID | Feature | Priority | Description |
|----|---------|----------|-------------|
| S-RM4 | Admin Tiers (ACL) | High | Implement access control (Superadmin, Admin, Leader, Observer) across routes and Supabase RLS. |
| S-REP1| Exportação VRMS (PMI) | High | Relatório CSV mastigado no `/admin` com as "Horas de Impacto" para o GP lançar no sistema global do PMI. |
| S10 | Credly Auto-Sync | Medium | Edge Function / Cron Job to auto-sync badges weekly. |
| S-AN1 | Announcements System | Medium | Tabela no banco para exibir banners/notificações globais no topo do site (ex: "Prazo encerra amanhã!"). |
| S-DR1 | Disaster Recovery Doc | Low | POP (Procedimento Operacional Padrão) de Restauração de Backup via Supabase (PITR). |

---

## 🌊 WAVE 5: Scale, Multi-tenant & Global Impact
**Foco:** Preparar o projeto para ser clonado/adotado por outros Capítulos.

| ID | Feature | Priority | Description |
|----|---------|----------|-------------|
| S-RM5 | Multi-tenant Config | Medium | Superadmin panel (`/admin/config`) to set `group_term`, `current_cycle`, and manage Webhooks. |
| S23 | Chapter Integrations | Medium | Event-driven architecture (Webhooks) para enviar dados aos portfólios locais (Artia/Jira) de forma agnóstica. |
| S24 | API for Chapters | Low | Read-only API endpoints for chapters to query their members' impact hours. |
| S-SC1 | Multilingual Screenshots| Low | Portar script Puppeteer para automatizar prints da documentação em PT/EN/ES a cada release. |

---

## 🛠️ TECHNICAL DEBT & DEVOPS INFRASTRUCTURE

| Issue | Impact | Mitigation Plan |
|-------|--------|-----------------|
| **README History Lost** | High | Restaurar história (Piloto 2024), 4 Quadrantes e stack atual baseando-se no antigo `README (archive).md`. |
| **No Security Scanning** | High | Ativar nativamente o GitHub Dependabot e CodeQL (Substitui scripts manuais de segurança). |
| **Semantic Versioning** | Medium | Criar workflow de Release Automática (GitHub Actions `release.yml`) para gerar tags (ex: v3.0.0). |
| **Hardcoded strings** | Medium | Apply i18n-first guidelines: chaves no banco, traduções no frontend. |
| **Architectural guidelines**| High | Enforce role-model-v3: Soft-delete-always (LGPD), cycle-aware-data e event-driven integrations. |

---

## 📋 RECOMMENDED EXECUTION ORDER (PLANO DE AÇÃO DETALHADO)

### 🔴 SESSÃO 1: Fundação de Dados & Interface Base (Imediato)
*Objetivo: Preparar o banco de dados e as interfaces do Admin para a nova estrutura de papéis antes de lançar a Gamificação.*

**Passo 1.1: Backend (Supabase SQL)**
* [ ] Rodar `ALTER TABLE members` para adicionar `operational_role` (text) e `designations` (text array).
* [ ] Criar tabela `member_cycle_history` (com `ON DELETE SET NULL` no member_id).
* [ ] Criar tabela `member_chapter_affiliations` (com colunas de consentimento LGPD).
* [ ] Criar a PostgreSQL Function `anonymize_member(uuid)` para soft delete (LGPD).
* [ ] Rodar o *Backfill* (UPDATE manual provisório) para colocar os líderes atuais como `operational_role = 'tribe_leader'`.

**Passo 1.2: Frontend (Astro / TypeScript)**
* [ ] Atualizar as interfaces TS (`types.d.ts` ou tipos do Supabase) para refletir os novos campos.
* [ ] Modificar o Modal de Edição de Membros no `/admin`:
    * Substituir o campo antigo "Role" por um Dropdown para `operational_role`.
    * Adicionar grupo de Checkboxes para `designations` (Embaixador, Patrocinador, Fundador).
    * Adicionar visualização read-only do Nível de Acesso (Superadmin, Admin, etc).
* [ ] Atualizar as queries no Astro para buscarem os novos campos ao invés do antigo array `roles`.

### 🟡 SESSÃO 2: Engajamento & UX (Próxima semana)
*Objetivo: Entregar valor para o usuário final com um perfil rico e gamificação contínua.*

**Passo 2.1: Frontend & Integrações**
* [ ] Criar o componente de **Completeness Bar** (Barra de Progresso do Perfil) adaptativa.
* [ ] Renderizar a **Timeline de Histórico de Ciclos** na aba do Perfil.
* [ ] Implementar a Lógica de XP e Níveis (Gamificação v2) mostrando Impacto *Lifetime* vs *Ciclo Atual*.
* [ ] Instalar o Script do **PostHog** no `BaseLayout.astro` e atrelar a sessão do Supabase ao rastreamento.

### 🟢 SESSÃO 3: Escala & DevOps (Semanas seguintes)
* [ ] Refatorar rotas com **Admin Tiers** (Bloquear rotas via Middleware Astro + RLS Supabase baseado na função `get_access_tier()`).
* [ ] Restauração do `README.md` e configuração do **GitHub Advanced Security / SemVer**.
* [ ] Criação do relatório exportável (CSV) para o VRMS do PMI.
