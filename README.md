# 🌐 AI & PM Research Hub (Núcleo IA & GP)

**The AI & Project Management Study and Research Hub**
*A Joint Initiative of the PMI Brazilian Chapters*

[🇺🇸 English](#overview) · [🇧🇷 Português](#visão-geral) · [🇪🇸 Español](#descripción-general)

---

## 🇺🇸 Overview

The **AI & PM Research Hub** (originally *Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos*) is a multi-chapter research initiative under the PMI® Brazilian ecosystem, dedicated to advancing the intersection of Artificial Intelligence and Project Management.

Founded in 2024 as a pilot within PMI Goiás (PMI-GO), the initiative has grown into a structured alliance of five PMI chapters — **PMI-GO, PMI-CE, PMI-DF, PMI-MG, and PMI-RS** — with 44 active collaborators organized across 8 research streams and 4 strategic knowledge quadrants. Today, the platform operates as a rich, relational "Knowledge Hub" for cross-pollinating intellectual property among researchers.

### Strategic Knowledge Quadrants

| # | Quadrant | Research Streams |
|---|----------|-----------------|
| Q1 | **The Augmented Practitioner** | AI Tools & Ecosystem for PM |
| Q2 | **AI Project Management** | Autonomous Agents & Hybrid Teams |
| Q3 | **Organizational Leadership** | TMO & PMO of the Future · Culture & Change · Talent & Upskilling · ROI & Portfolio Strategy |
| Q4 | **Future & Responsibility** | Governance & Trustworthy AI · Inclusion & Human-AI Collaboration |

### Project Governance

This project operates under a formal governance manual (R2, signed via DocuSign) with hierarchical levels, a peer review committee (Comitê de Curadoria), and merit-based selection processes. All operations align with PMI® Global branding standards and the PMI Code of Ethics and Professional Conduct.

**Project Manager:** Vitor Maia Rodovalho
**Deputy PM:** Fabrício Costa

---

## 🌍 Governança Financeira, Sustentabilidade e Tech Stack

O Núcleo IA & GP adota uma política de **"Custo Zero e Alto Valor" (Zero-Cost, High-Value Architecture)**. Sendo uma iniciativa voluntária ligada à comunidade PMI, a nossa arquitetura foi intencionalmente desenhada para não depender de licenças de software pagas, garantindo que o projeto possa existir indefinidamente e ser replicado por outros capítulos sem entraves orçamentários.

### O Nosso Stack "Custo Zero" (Free Tiers)
* **Frontend & Hospedagem:** Astro + Cloudflare Pages (Gratuito, CDN global, limite de banda livre).
* **Banco de Dados & Autenticação:** Supabase / PostgreSQL (Plano gratuito acomoda até 500MB de dados estruturados e 500.000 requisições *serverless*, suficiente para dezenas de milhares de registros históricos).
* **Automações Agnostic:** Priorizamos o uso de Webhooks internos (Edge Functions) e plataformas de plano gratuito robusto (ex: Make.com / n8n) para integrações, ao invés de soluções Enterprise caras.
* **Inteligência Artificial Nativa:** As funcionalidades de IA da plataforma (Assistente de Copy, Análise de Credly) consomem APIs com *Free Tiers* generosos (como Google Gemini / Groq), mantendo o processamento fora da fatura do projeto.

### Política de Adoção de Novas Ferramentas (Tech for Good)
Antes de incorporar ferramentas de terceiros ao nosso fluxo (Kanban, CRMs, etc.), deve-se avaliar:
1. A funcionalidade pode ser construída no nosso próprio painel administrativo (`/admin`) usando o nosso banco de dados relacional? (Prioridade Alta).
2. Se a ferramenta externa for indispensável, o provedor oferece *Grants* (doações de licença) para associações sem fins lucrativos (Non-Profits)? O Núcleo utilizará o CNPJ dos Capítulos PMI parceiros para requerer isenção total.
3. A ferramenta aceita parcerias de permuta em troca de visibilidade ("Powered By") no rodapé da nossa plataforma?

Qualquer dado externo deve ser orquestrado por eventos para o nosso Hub. O Hub é, e sempre será, a única Fonte da Verdade (Source of Truth) para gamificação e métricas do projeto.

---

## 🇧🇷 Visão Geral

O **AI & PM Research Hub** é uma iniciativa multi-capítulo de pesquisa sob o ecossistema PMI® brasileiro, dedicada a avançar a interseção entre Inteligência Artificial e Gerenciamento de Projetos. Fundado em 2024 como piloto no PMI Goiás (PMI-GO), a iniciativa cresceu para uma aliança estruturada de cinco capítulos PMI com 44 colaboradores ativos organizados em 8 tribos de pesquisa e 4 quadrantes estratégicos de conhecimento.

---

## 🇪🇸 Descripción General

El **AI & PM Research Hub** es una iniciativa de investigación multi-capítulo bajo el ecosistema PMI® brasileño, dedicada a avanzar la intersección entre Inteligencia Artificial y Gestión de Proyectos. Fundado en 2024 como piloto en PMI Goiás (PMI-GO), la iniciativa ha crecido hasta convertirse en una alianza estructurada de cinco capítulos PMI con 44 colaboradores activos organizados en 8 líneas de investigación y 4 cuadrantes estratégicos de conocimiento.

---

## Repository Structure

```text
ai-pm-research-hub/
├── README.md                          # This file (trilingual + tech stack)
├── LICENSE
├── CONTRIBUTING.md                    # How to contribute (trilingual)
├── backlog-wave-planning-updated.md   # Current release planning and epics
│
├── docs/
│   ├── en/                            # 🇺🇸 English documentation
│   ├── pt-br/                         # 🇧🇷 Portuguese documentation
│   └── es-latam/                      # 🇪🇸 Spanish documentation
│
├── site/                              # Project website (presentation layer)
│   ├── package.json
│   ├── astro.config.mjs               # Astro framework config
│   └── src/
│       ├── pages/
│       ├── components/
│       └── styles/
│
├── assets/                            # Shared assets (brand, templates)
└── .github/                           # CI/CD Workflows (Dependabot, Deploy)


---

## Contributing & License
See CONTRIBUTING.md for guidelines on submitting change requests, research proposals, and documentation translations.

Documentation is licensed under CC BY-SA 4.0. Code is licensed under MIT.

<sub>PMI®, PMBOK®, PMP® and PMI-CPMAI™ are registered marks of the Project Management Institute, Inc. This initiative is a collaborative project of independent PMI chapters and is not directly affiliated with or endorsed by PMI Global.</sub>

