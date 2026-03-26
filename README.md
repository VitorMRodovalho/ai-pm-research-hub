# 🧠 AI & PM Research Hub

**Plataforma de pesquisa colaborativa do Núcleo de Estudos e Pesquisa em IA & Gestão de Projetos**

[![Live](https://img.shields.io/badge/Live-ai--pm--research--hub.pages.dev-blue)](https://ai-pm-research-hub.pages.dev)
[![Version](https://img.shields.io/badge/version-v1.0.0--beta-orange)]()
[![Tests](https://img.shields.io/badge/tests-779%2B%20unit%20%2B%208%20e2e-green)]()
[![License](https://img.shields.io/badge/license-MIT-lightgrey)]()

---

## O que é

Uma plataforma web trilíngue (PT-BR · EN-US · ES-LATAM) que conecta 5 capítulos do PMI no Brasil em torno de pesquisa aplicada sobre Inteligência Artificial na Gestão de Projetos.

**Números atuais (Ciclo 3 — 2026/1):**
- 52 membros ativos · 7 tribos de pesquisa · 4 quadrantes estratégicos
- 5 capítulos: PMI-GO, PMI-CE, PMI-DF, PMI-MG, PMI-RS
- 56 artefatos de pesquisa nos boards das tribos
- Custo operacional zero para as instituições

---

## Stack

| Camada | Tecnologia |
|--------|-----------|
| Framework | [Astro 5](https://astro.build/) (SSR on Cloudflare Pages) |
| UI Islands | [React 19](https://react.dev/) |
| Styling | [Tailwind CSS 4](https://tailwindcss.com/) |
| Database | [Supabase](https://supabase.com/) (PostgreSQL + Auth + Edge Functions + Storage) |
| Hosting | [Cloudflare Pages](https://pages.cloudflare.com/) |
| Auth | Google · LinkedIn · Microsoft Azure |
| Analytics | [PostHog](https://posthog.com/) |
| Error Tracking | [Sentry](https://sentry.io/) |
| Email | [Resend](https://resend.com/) |
| DnD | [@dnd-kit](https://dndkit.com/) |
| Rich Text | [TipTap](https://tiptap.dev/) |
| Charts | [Chart.js](https://www.chartjs.org/) |
| Tables | [@tanstack/react-table](https://tanstack.com/table) |
| Tests | Vitest (unit) + [Playwright](https://playwright.dev/) (e2e) |
| Cron | pg_cron (Supabase) |
| Badges | Credly API sync |

---

## Funcionalidades

### Para Pesquisadores
- Dashboard individual com XP, badges e ranking
- Sistema de presença com check-in e time window
- BoardEngine (Kanban/Table/Calendar/Timeline) para entregáveis da tribo
- Certificados digitais com verificação por código
- Notificações (6 tipos + digest)
- Blog trilíngue

### Para Líderes de Tribo
- Dashboard da tribo (5 abas: Visão Geral, Presença, Gamificação, Entregáveis, Configurações)
- Gestão de entregáveis via BoardEngine
- Atas de reunião (TipTap editor)

### Para Stakeholders (Sponsors / Pontos Focais)
- Dashboard por capítulo com métricas reais
- Comparativo entre capítulos
- Acesso PII-free (sem dados pessoais sensíveis)

### Para GP / Admin
- Painel administrativo completo
- Gestão de eventos e presença
- Governança: Change Requests, aprovação em lote, changelog versionado
- Emissão de certificados (individual e em lote)
- Gamificação com sync automático (Credly + pg_cron)
- Campanhas de email (Resend)
- Parcerias (CRUD + níveis de interação)
- Dashboards de KPIs e sustentabilidade

---

## Início Rápido

### Pré-requisitos

- Node.js 22+ (recomendado via [nvm](https://github.com/nvm-sh/nvm))
- Git
- Conta Supabase (para desenvolvimento local)
- Supabase CLI (`npm i -g supabase`)

### Setup

```bash
# 1. Clone
git clone git@github.com:VitorMRodovalho/ai-pm-research-hub.git
cd ai-pm-research-hub

# 2. Node version
nvm use  # usa a versão do .nvmrc (Node 22)

# 3. Dependências
npm install

# 4. Variáveis de ambiente
cp .env.example .env
# Preencher: SUPABASE_URL, SUPABASE_ANON_KEY, SENTRY_DSN, etc.

# 5. Dev server
npm run dev
# → http://localhost:4321

# 6. Build
npm run build

# 7. Testes
npm test              # unit tests (Vitest)
npx playwright test   # e2e tests
```

### Estrutura do projeto

```
ai-pm-research-hub/
├── src/
│   ├── components/       # React islands + Astro components
│   ├── i18n/             # pt-BR.ts · en-US.ts · es-LATAM.ts
│   ├── layouts/          # BaseLayout.astro
│   ├── lib/              # supabaseClient, permissions, utils
│   ├── pages/            # Astro pages (/, /en/, /es/)
│   └── styles/           # Tailwind + globals
├── supabase/
│   ├── functions/        # Edge Functions (16)
│   └── migrations/       # SQL migrations
├── tests/                # Unit + e2e
├── docs/                 # Documentação do projeto
│   ├── ARCHITECTURE.md
│   ├── CONTRIBUTING.md
│   ├── GOVERNANCE_CHANGELOG.md
│   ├── BOARD_ENGINE_SPEC.md
│   └── RUNBOOK.md
├── .nvmrc                # Node 22
├── astro.config.mjs
├── tailwind.config.ts
└── playwright.config.ts
```

---

## Documentação

| Documento | Descrição |
|-----------|-----------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Arquitetura do sistema, diagrama de camadas, padrões de segurança |
| [CONTRIBUTING.md](docs/CONTRIBUTING.md) | Guia para contribuidores |
| [GOVERNANCE_CHANGELOG.md](docs/GOVERNANCE_CHANGELOG.md) | Histórico de decisões estruturais (GC-001 → GC-131) |
| [BOARD_ENGINE_SPEC.md](docs/BOARD_ENGINE_SPEC.md) | Especificação do BoardEngine |
| [RUNBOOK.md](docs/RUNBOOK.md) | Operações: deploy, pg_cron, email, backups |

---

## Governança

Este é um **projeto**, não uma associação. Decisões estruturais são documentadas em `GOVERNANCE_CHANGELOG.md` com código (GC-XXX), data, contexto e justificativa. Não há atas, votações ou cargos eletivos.

**Modelo organizacional:**
- Seleção por mérito (processo seletivo aberto a cada ciclo)
- Custo zero para capítulos (infraestrutura mantida pelo GP)
- Código aberto (MIT)
- Changelog versionado como em desenvolvimento de software

---

## Autor

**Vitor Maia Rodovalho** — Gestor do Projeto (GP)
- PMI ID: 5975367
- Capítulo: PMI Goiás

Concebido em 2024 por Ivan Lourenço (Presidente PMI-GO) como projeto piloto. Formalizado em 2025 com PMI-CE. Ciclo 3 (2026) com 5 capítulos.

---

## Licença

MIT — veja [LICENSE](LICENSE) para detalhes.
