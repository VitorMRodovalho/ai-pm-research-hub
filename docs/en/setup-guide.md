# 🚀 GitHub Repository Setup Guide

## Repository Name Recommendation

### Suggested Name: `ai-pm-research-hub`

| Option | Name | Pros | Cons |
|--------|------|------|------|
| ✅ **Recommended** | `ai-pm-research-hub` | Clean, descriptive, kebab-case, SEO-friendly | — |
| Alternative 1 | `ai-pm-hub` | Shorter | Less descriptive |
| Alternative 2 | `pmi-ai-pm-research-hub` | Includes PMI | May conflict with PMI trademark in repo name |
| Alternative 3 | `nucleo-ia-gp` | Portuguese original | Not international |

**Rationale for `ai-pm-research-hub`:**
- Follows GitHub kebab-case convention
- Maps to the English name "The AI & PM Study and Research Hub"
- Avoids PMI® trademark in the repo URL (compliance with Policy Manual)
- Internationally recognizable
- Good SEO for the intersection of AI + Project Management

### GitHub Organization (Optional)

If you want to create a GitHub Organization instead of using your personal account:

| Option | Name | Notes |
|--------|------|-------|
| ✅ Recommended | `ai-pm-hub` | Clean org name, then repo is `ai-pm-hub/ai-pm-research-hub` |
| Alternative | `pmi-brazil-ai-pm` | More specific, but longer |

**Note:** Do NOT use "PMI" as the primary identifier in the GitHub org name to avoid trademark issues. "ai-pm-hub" is descriptive without implying official PMI endorsement.

---

## Quick Setup (Step by Step)

### Step 1: Create Repository on GitHub

1. Go to https://github.com/new
2. Repository name: `ai-pm-research-hub`
3. Description: "The AI & PM Study and Research Hub — A Joint Initiative of the PMI Brazilian Chapters"
4. Public repository
5. Add README: No (we provide our own)
6. License: MIT
7. Create repository

### Step 2: Initialize with Project Files

```bash
git clone https://github.com/YOUR_USERNAME/ai-pm-research-hub.git
cd ai-pm-research-hub

# Copy the project structure we prepared
# (from the delivered project-setup.zip or directory)

git add .
git commit -m "chore: initial project structure with trilingual docs, charter, and CR log"
git push origin main
```

### Step 3: Set Up Cloudflare Pages

1. Create free account at https://dash.cloudflare.com
2. Go to **Workers & Pages** → **Create** → **Pages**
3. Connect to GitHub → Select `ai-pm-research-hub`
4. Build settings:
   - Build command: `cd site && npm install && npm run build`
   - Build output: `site/dist`
5. Deploy

### Step 4: Custom Domain (when ready)

1. Register domain (e.g., `aipmhub.org`) via any registrar
2. In Cloudflare Pages → Custom domains → Add domain
3. Update DNS nameservers to Cloudflare (free DNS)
4. SSL is automatic

---

## Files Delivered in This Package

```
project-setup/
├── README.md                              # Trilingual readme (EN/PT/ES)
├── CONTRIBUTING.md                        # How to contribute (trilingual)
├── CHANGELOG.md                           # Change Request Log (5 CRs from strategic analysis)
│
├── docs/
│   └── en/
│       ├── project-charter.md             # PMBOK 8 aligned charter
│       └── hosting-architecture.md        # ADR: Cloudflare + Astro decision
│
└── .github/
    └── ISSUE_TEMPLATE/
        └── change-request.md              # CR template for GitHub Issues
```

### What Comes Next (in order of priority)

1. **You create the repo** → Push these files
2. **We build the Astro site** → PMI Global 2026 colors, trilingual, kickoff page
3. **You share the Manual** → I analyze and feed into CR-001
4. **We build the kickoff presentation** → Hosted on the site for tomorrow's meeting
5. **We set up Cloudflare Pages** → Deploy live
6. **We translate docs** → PT-BR and ES-LATAM versions of charter and governance

---

## Terminology Glossary (Locked Terms)

These translations have been established across project history and must be maintained consistently:

| English (EN-US) | Português (PT-BR) | Español (ES-LATAM) |
|-----------------|-------------------|-------------------|
| AI & PM Research Hub | Núcleo de Estudos e Pesquisa em IA e GP | Centro de Estudios e Investigación en IA y GP |
| Research Stream | Tribo (de Pesquisa) | Línea de Investigación |
| Knowledge Quadrant | Quadrante (de Conhecimento) | Cuadrante (de Conocimiento) |
| The Augmented Practitioner | O Praticante Aumentado | El Practicante Aumentado |
| AI Project Management | Gestão de Projetos de IA | Gestión de Proyectos de IA |
| Organizational Leadership | Liderança Organizacional | Liderazgo Organizacional |
| Future & Responsibility | Futuro e Responsabilidade | Futuro y Responsabilidad |
| Governance Manual | Manual de Governança e Operações | Manual de Gobernanza y Operaciones |
| Center of Excellence (CoE) | Centro de Excelência | Centro de Excelencia |
| Community of Practice (CoP) | Comunidade de Prática | Comunidad de Práctica |
| Peer Review Committee | Comitê de Curadoria | Comité de Curaduría |
| Tribe Leader | Líder de Tribo | Líder de Tribu |
| Collaborator / Researcher | Pesquisador(a) / Colaborador(a) | Investigador(a) / Colaborador(a) |
| Ambassador | Embaixador(a) | Embajador(a) |
| Change Request | Solicitação de Mudança | Solicitud de Cambio |
| Project Manager | Gerente de Projeto | Director de Proyecto |
| Chapter Sponsor | Patrocinador de Capítulo | Patrocinador de Capítulo |
| Merit-based Selection | Seleção por Mérito | Selección por Mérito |
| Trustworthy AI | IA Confiável | IA Confiable |
| Hybrid Teams | Equipes Híbridas | Equipos Híbridos |
| Upskilling | Upskilling | Upskilling |
