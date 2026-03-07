# 🌐 AI & PM Research Hub

**The AI & Project Management Study and Research Hub**  
*A Joint Initiative of the PMI Brazilian Chapters*

[🇺🇸 English](#overview) · [🇧🇷 Português](#visão-geral) · [🇪🇸 Español](#descripción-general)

---

## Overview

The **AI & PM Research Hub** (originally *Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos*) is a multi chapter research initiative under the PMI® Brazilian ecosystem, dedicated to advancing the intersection of Artificial Intelligence and Project Management.

Founded in 2024 as a pilot within PMI Goiás (PMI GO), the initiative has grown into a structured alliance of five PMI chapters — **PMI GO, PMI CE, PMI DF, PMI MG, and PMI RS** — with active collaborators organized across 8 research streams and 4 strategic knowledge quadrants.

### Strategic Knowledge Quadrants

| # | Quadrant | Research Streams |
|---|----------|------------------|
| Q1 | **The Augmented Practitioner** | AI Tools & Ecosystem for PM |
| Q2 | **AI Project Management** | Autonomous Agents & Hybrid Teams |
| Q3 | **Organizational Leadership** | TMO & PMO of the Future · Culture & Change · Talent & Upskilling · ROI & Portfolio Strategy |
| Q4 | **Future & Responsibility** | Governance & Trustworthy AI · Inclusion & Human AI Collaboration |

### Project Governance

This project operates under a formal governance model with hierarchical access levels, a peer review committee (*Comitê de Curadoria*), and merit based selection processes. Operations align with PMI® branding standards, LGPD aware data handling, and the PMI Code of Ethics and Professional Conduct.

**Project Manager:** Vitor Maia Rodovalho

---

## Current Platform Scope

The platform currently serves as the operational hub for the initiative, supporting:

- member onboarding and profile management
- tribe selection and cycle participation
- attendance tracking and impact hour visibility
- gamification, certificates, and leaderboard experiences
- artifact submission and review flow
- admin visibility for governance and operational coordination
- multilingual public experience in Portuguese, English, and Spanish

This repository is therefore both a **product** and a **knowledge infrastructure asset** for the Núcleo.

---

## March 2026 Operational Status

The repository received a short stabilization cycle in early March 2026 focused on production resilience and documentation hygiene.

### Recent production hotfixes

- Cloudflare Pages SPA fallback redirect support added.
- Legacy route aliases restored for `/teams`, `/rank`, and `/ranks`.
- `TribesSection.astro` patched to guard against missing `deliverables` data during SSR rendering.
- Credly verification scoring expanded to a tier based model, with backend improvements already delivered.

### Known open gaps

- The new tier based Credly scoring is **not yet fully reflected** in all rank and gamification UI surfaces.
- Mobile paste behavior for the Credly URL field still requires dedicated validation on iOS Safari and Chrome.
- Some route and navigation behavior should still be covered by repeatable smoke tests after deploy.

---

## Product Direction

The medium term direction of the Hub is to evolve from a public facing research platform into a **relational knowledge workspace** across tribes.

This does **not** mean cloning external software. The strategy is to build **entity based relational views** on top of the Supabase data model already being structured for members, events, artifacts, cycles, and future knowledge assets.

Planned direction includes:

- cross tribe knowledge visibility
- workspace style views for in progress artifacts, studies, and events
- stronger relational traceability between courses, studies, and final outputs
- long term preservation of institutional memory across cycles

The Hub should become the living graph of the initiative, not a cemetery of links lost in WhatsApp threads and whiteboards.

---

## Architecture Principles

### 1. Zero Cost, High Value Architecture

The Núcleo adopts a **Zero Cost, High Value** philosophy. As a volunteer initiative tied to the PMI community, the architecture is intentionally designed to avoid dependency on expensive enterprise tooling whenever an open, free tier, or native solution is enough.

### 2. Hub as Source of Truth

The Hub is the single source of truth for:

- member state
- cycle participation
- gamification logic
- operational metrics
- artifacts and research outputs

External tools may integrate with the Hub, but they do not replace it.

### 3. Cycle Aware Data Model

The `members` table should be treated as the **current snapshot** of the person. Historical roles, promotions, tribe participation, and cycle specific states must live in `member_cycle_history` and related fact tables.

### 4. Legacy Deprecation Discipline

Legacy columns and compatibility layers may exist temporarily to avoid breaking production, but they must be explicitly documented and removed after migration windows close.

---

## Technical Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| Frontend | Astro + Tailwind CSS | Fast multilingual interface with low operational cost |
| Hosting | Cloudflare Pages | Free CDN delivery and static plus server hybrid deployment |
| Database | Supabase PostgreSQL | Relational data model, auth, storage, RLS |
| Server Logic | Supabase Edge Functions | Lightweight backend logic and integrations |
| Docs | Markdown in repo | Version controlled operational and governance docs |
| Analytics | PostHog via iframe strategy | Internal product analytics with low frontend friction |
| External Media Metrics | Looker Studio + Sheets + automation | External funnel and communications dashboard |

---

## Product Analytics and Governance Notes

### Internal analytics

The recommended pattern for product analytics is to use **PostHog shared dashboards embedded via iframe** in restricted admin routes instead of building charts directly into Astro.

Guidelines:

- use `member_id` or at most `operational_role`, not email or full name, in analytics identity payloads
- mask all input fields in session replay
- enforce role based visibility for analytics
- maintain a right to be forgotten operational procedure across both Supabase and analytics tooling

### External communications analytics

For YouTube, LinkedIn, and Instagram performance, the preferred pattern is:

- YouTube via native Looker Studio connector
- LinkedIn and Instagram via weekly Make.com or n8n automation into Google Sheets
- Looker Studio iframe embedded in an internal admin communications route

This avoids brittle direct social API integrations inside Astro or Supabase.

---

## Immediate Engineering Priorities

1. Complete UI integration for tier based Credly scoring in rank and gamification flows.
2. Validate and fix the mobile Credly URL paste experience in `Profile.astro`.
3. Continue frontend migration away from legacy role fields toward `operational_role` and `designations`.
4. Add smoke checks for direct navigation and legacy aliases.
5. Keep documentation in sync with every production hotfix and architectural decision.

---

## Repository Documentation Map

- `README.md` → project entry point, product context, stack, and current status
- `backlog-wave-planning-updated.md` → wave planning, completed work, debt, and next priorities
- `docs/GOVERNANCE_CHANGELOG.md` → governance and product engineering decisions
- `docs/MIGRATION.md` → technical transition notes and compatibility guidance
- `docs/RELEASE_LOG.md` → operational release and hotfix history

---

## Recommended Local Workflow

```bash
npm install
npm run build
npm run dev -- --host 0.0.0.0 --port 4321
```

---

## Visão Geral

O **AI & PM Research Hub** (originalmente *Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos*) é uma iniciativa multi capítulo de pesquisa sob o ecossistema PMI® brasileiro, dedicada a avançar a interseção entre Inteligência Artificial e Gerenciamento de Projetos.

Fundado em 2024 como piloto no PMI Goiás (PMI GO), o projeto evoluiu para uma aliança estruturada entre cinco capítulos PMI — **PMI GO, PMI CE, PMI DF, PMI MG e PMI RS** — com colaboradores ativos organizados em 8 frentes de pesquisa e 4 quadrantes estratégicos de conhecimento.

### Quadrantes Estratégicos de Conhecimento

| # | Quadrante | Tribos de Pesquisa |
|---|-----------|--------------------|
| Q1 | **O Praticante Aumentado** | AI Tools & Ecosystem for PM |
| Q2 | **Gestão de Projetos de IA** | Autonomous Agents & Hybrid Teams |
| Q3 | **Liderança Organizacional** | TMO & PMO do Futuro · Cultura & Change · Talentos & Upskilling · ROI & Portfólio |
| Q4 | **Futuro e Responsabilidade** | Governança & Trustworthy AI · Inclusão & Colaboração Humano IA |

**Gerente de Projeto:** Vitor Maia Rodovalho

---

## Descripción General

El **AI & PM Research Hub** (originalmente *Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos*) es una iniciativa de investigación multi capítulo dentro del ecosistema PMI® brasileño, dedicada a avanzar la intersección entre Inteligencia Artificial y Gestión de Proyectos.

Fundado en 2024 como piloto en PMI Goiás (PMI GO), el proyecto evolucionó hacia una alianza estructurada entre cinco capítulos PMI — **PMI GO, PMI CE, PMI DF, PMI MG y PMI RS** — con colaboradores activos organizados en 8 líneas de investigación y 4 cuadrantes estratégicos de conocimiento.

### Cuadrantes Estratégicos de Conocimiento

| # | Cuadrante | Líneas de Investigación |
|---|-----------|-------------------------|
| Q1 | **El Practicante Aumentado** | AI Tools & Ecosystem for PM |
| Q2 | **Gestión de Proyectos de IA** | Autonomous Agents & Hybrid Teams |
| Q3 | **Liderazgo Organizacional** | TMO & PMO del Futuro · Cultura & Change · Talento & Upskilling · ROI & Portafolio |
| Q4 | **Futuro y Responsabilidad** | Gobernanza & Trustworthy AI · Inclusión & Colaboración Humano IA |

**Director del Proyecto:** Vitor Maia Rodovalho

---

## License

Documentation is licensed under CC BY SA 4.0.  
Code is licensed under MIT.

<sub>PMI®, PMBOK®, PMP® and PMI CPMAI™ are registered marks of the Project Management Institute, Inc. This initiative is a collaborative project of independent PMI chapters and is not directly affiliated with or endorsed by PMI Global.</sub>
