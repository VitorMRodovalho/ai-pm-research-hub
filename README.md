# 🌐 AI & PM Research Hub

**The AI & Project Management Study and Research Hub**
*A Joint Initiative of the PMI Brazilian Chapters*

[🇺🇸 English](#overview) · [🇧🇷 Português](#visão-geral) · [🇪🇸 Español](#descripción-general)

---

## Overview

The **AI & PM Research Hub** (originally *Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos*) is a multi-chapter research initiative under the PMI® Brazilian ecosystem, dedicated to advancing the intersection of Artificial Intelligence and Project Management.

Founded in 2024 as a pilot within PMI Goiás (PMI-GO), the initiative has grown into a structured alliance of five PMI chapters — **PMI-GO, PMI-CE, PMI-DF, PMI-MG, and PMI-RS** — with 44 active collaborators organized across 8 research streams and 4 strategic knowledge quadrants.

### Strategic Knowledge Quadrants

| # | Quadrant | Research Streams |
|---|----------|-----------------|
| Q1 | **The Augmented Practitioner** | AI Tools & Ecosystem for PM |
| Q2 | **AI Project Management** | Autonomous Agents & Hybrid Teams |
| Q3 | **Organizational Leadership** | TMO & PMO of the Future · Culture & Change · Talent & Upskilling · ROI & Portfolio Strategy |
| Q4 | **Future & Responsibility** | Governance & Trustworthy AI · Inclusion & Human-AI Collaboration |

### Project Governance

This project operates under a formal governance manual (R2, signed via DocuSign) with five hierarchical levels, a peer review committee (Comitê de Curadoria), and merit-based selection processes. All operations align with PMI® Global branding standards and the PMI Code of Ethics and Professional Conduct.

**Project Manager:** Vitor Maia Rodovalho

---

## Repository Structure

```
ai-pm-research-hub/
├── README.md                          # This file (trilingual)
├── LICENSE
├── CONTRIBUTING.md                    # How to contribute (trilingual)
├── CHANGELOG.md                       # Change request log (PMBOK 8 aligned)
│
├── docs/
│   ├── en/                            # 🇺🇸 English documentation
│   │   ├── project-charter.md         # Project charter & scope
│   │   ├── governance-overview.md     # Governance model summary
│   │   ├── strategic-analysis.md      # CoP/CoE analysis & SWOT
│   │   ├── roadmap.md                 # Internationalization roadmap
│   │   └── hosting-architecture.md    # Infrastructure decisions
│   │
│   ├── pt-br/                         # 🇧🇷 Portuguese documentation
│   │   ├── carta-do-projeto.md
│   │   ├── visao-governanca.md
│   │   ├── analise-estrategica.md
│   │   ├── roadmap.md
│   │   └── arquitetura-hospedagem.md
│   │
│   └── es-latam/                      # 🇪🇸 Spanish documentation
│       ├── carta-del-proyecto.md
│       ├── vision-gobernanza.md
│       ├── analisis-estrategico.md
│       ├── roadmap.md
│       └── arquitectura-hospedaje.md
│
├── change-requests/                   # Formal change request log
│   └── CR-001-manual-reform.md        # First CR: Manual governance reform
│
├── site/                              # Project website (presentation layer)
│   ├── package.json
│   ├── next.config.js                 # or astro.config.mjs
│   └── src/
│       ├── pages/
│       ├── components/
│       └── styles/
│
├── assets/                            # Shared assets
│   ├── brand/                         # PMI color standards, logos
│   └── templates/                     # Document templates
│
└── .github/
    ├── ISSUE_TEMPLATE/
    │   ├── change-request.md
    │   └── research-proposal.md
    └── workflows/
        └── deploy.yml
```

---

## Visão Geral

O **AI & PM Research Hub** (originalmente *Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos*) é uma iniciativa multi-capítulo de pesquisa sob o ecossistema PMI® brasileiro, dedicada a avançar a interseção entre Inteligência Artificial e Gerenciamento de Projetos.

Fundado em 2024 como piloto no PMI Goiás (PMI-GO), a iniciativa cresceu para uma aliança estruturada de cinco capítulos PMI — **PMI-GO, PMI-CE, PMI-DF, PMI-MG e PMI-RS** — com 44 colaboradores ativos organizados em 8 tribos de pesquisa e 4 quadrantes estratégicos de conhecimento.

### Quadrantes Estratégicos de Conhecimento

| # | Quadrante | Tribos de Pesquisa |
|---|-----------|-------------------|
| Q1 | **O Praticante Aumentado** | Radar Tecnológico do GP |
| Q2 | **Gestão de Projetos de IA** | Agentes Autônomos & Equipes Híbridas |
| Q3 | **Liderança Organizacional** | TMO & PMO do Futuro · Cultura & Change · Talentos & Upskilling · ROI & Portfólio |
| Q4 | **Futuro e Responsabilidade** | Governança & Trustworthy AI · Inclusão & Colaboração Humano-IA |

**Gerente de Projeto:** Vitor Maia Rodovalho

---

## Descripción General

El **AI & PM Research Hub** (originalmente *Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos*) es una iniciativa de investigación multi-capítulo bajo el ecosistema PMI® brasileño, dedicada a avanzar la intersección entre Inteligencia Artificial y Gestión de Proyectos.

Fundado en 2024 como piloto en PMI Goiás (PMI-GO), la iniciativa ha crecido hasta convertirse en una alianza estructurada de cinco capítulos PMI — **PMI-GO, PMI-CE, PMI-DF, PMI-MG y PMI-RS** — con 44 colaboradores activos organizados en 8 líneas de investigación y 4 cuadrantes estratégicos de conocimiento.

### Cuadrantes Estratégicos de Conocimiento

| # | Cuadrante | Líneas de Investigación |
|---|-----------|------------------------|
| Q1 | **El Practicante Aumentado** | Radar Tecnológico del GP |
| Q2 | **Gestión de Proyectos de IA** | Agentes Autónomos & Equipos Híbridos |
| Q3 | **Liderazgo Organizacional** | TMO & PMO del Futuro · Cultura & Cambio · Talentos & Upskilling · ROI & Portafolio |
| Q4 | **Futuro y Responsabilidad** | Gobernanza & IA Confiable · Inclusión & Colaboración Humano-IA |

**Director de Proyecto:** Vitor Maia Rodovalho

---

## Tech Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Site** | Astro + Tailwind CSS | Static site with i18n, PMI brand colors |
| **Hosting** | Cloudflare Pages (free) | Global CDN, custom domain, unlimited bandwidth |
| **Docs** | Markdown (this repo) | Version-controlled, trilingual |
| **CI/CD** | GitHub Actions | Auto-deploy on push to `main` |
| **Domain** | TBD | Custom domain via Cloudflare DNS |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on submitting change requests, research proposals, and documentation translations.

---

## License

Documentation is licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
Code is licensed under [MIT](LICENSE).

---

<sub>PMI®, PMBOK®, PMP® and PMI-CPMAI™ are registered marks of the Project Management Institute, Inc. This initiative is a collaborative project of independent PMI chapters and is not directly affiliated with or endorsed by PMI Global.</sub>
