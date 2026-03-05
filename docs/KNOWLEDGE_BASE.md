# AI & PM Research Hub — Knowledge Base

> **Last Updated:** 2026-03-05 (Kickoff Day)
> **Project Manager:** Vitor Maia Rodovalho
> **Repository:** https://github.com/VitorMRodovalho/ai-pm-research-hub
> **Live Site:** https://ai-pm-research-hub.pages.dev/

---

## 1. PROJECT IDENTITY

### Official Names (Locked Translations)
| Language | Name |
|----------|------|
| PT-BR | Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos |
| EN-US | The AI & PM Study and Research Hub |
| ES-LATAM | Centro de Estudios e Investigación en IA y Gestión de Proyectos |

### Subtitle
"A Joint Initiative of the PMI Brazilian Chapters (PMI-GO, PMI-CE, PMI-DF, PMI-MG, PMI-RS)"

### Origin
- Started as a **pilot project** conceived by Ivan Lourenço (PMI-GO President) in 2024/2
- Evolved through Cycle 1 (2025/1), Cycle 2 (2025/2)
- Current: **Cycle 3 (2026/1)** — the most structured and ambitious cycle
- 5 chapters, 8 tribe leaders, 44 active researchers, 12 inactive alumni

### Email
- nucleoia@pmigo.org.br (Google Workspace)

---

## 2. TECH STACK (PRODUCTION)

| Component | Technology | Details |
|-----------|-----------|---------|
| Frontend | Single HTML file (v8) | Will migrate to Astro multi-page |
| Hosting | Cloudflare Pages | Auto-deploy from GitHub `main` branch |
| Domain | ai-pm-research-hub.pages.dev | Custom domain TBD (e.g. aipmhub.org) |
| Auth | Supabase Auth | Google OAuth ✅, LinkedIn OIDC ✅ (scope issue), Magic Link ✅ |
| Database | Supabase PostgreSQL | São Paulo region, free tier |
| Storage | Supabase Storage | `member-photos` bucket (public) |
| Realtime | Supabase Realtime | `tribe_selections` table subscribed |
| CDN | Cloudflare (included) | Global edge |
| Repository | GitHub | VitorMRodovalho/ai-pm-research-hub |
| CI/CD | Cloudflare Pages auto-deploy | Triggers on every push to `main` |

### Supabase Credentials
- **Project URL:** https://ldrfrvwhxsmgaabwmaik.supabase.co
- **Anon Key:** eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkcmZydndoeHNtZ2FhYndtYWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI3MjU5NDQsImV4cCI6MjA4ODMwMTk0NH0.gzibKd7Jyck3Ya61vzrloX1YZt-0pNReTuefdi4mAmw
- **Region:** South America (São Paulo)
- **Project Name:** ai-pm-hub

### Cloudflare
- **Account ID:** 67d4c2262aebde75efb5fb6a1bb12cd2
- **Pages Project:** ai-pm-research-hub
- **Build output directory:** `site`

### Google OAuth
- Configured in Google Cloud Console
- Redirect URI: `https://ldrfrvwhxsmgaabwmaik.supabase.co/auth/v1/callback`

### LinkedIn OAuth (OIDC)
- App: "AI PM Research Hub" on LinkedIn Developer Portal
- Status: Enabled in Supabase but has `invalid_scope_error` — needs "Sign In with LinkedIn using OpenID Connect" product activated in LinkedIn Developer Portal → Products tab

---

## 3. DATABASE SCHEMA

### Tables

#### `members` (57 rows: 45 active + 12 inactive)
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | gen_random_uuid() |
| auth_id | UUID FK → auth.users | Linked on first login |
| name | TEXT | Title Case enforced |
| email | TEXT UNIQUE | Primary email |
| secondary_emails | TEXT[] | Additional emails for auth matching |
| chapter | TEXT | PMI-GO, PMI-CE, PMI-DF, PMI-MG, PMI-RS, Outro |
| role | TEXT | sponsor, manager, tribe_leader, researcher, facilitator, communicator, ambassador, observer, guest |
| is_active | BOOLEAN | Overall active status |
| current_cycle_active | BOOLEAN | Active in Cycle 3 |
| pmi_id | TEXT UNIQUE | PMI membership ID (mandatory for non-public access) |
| pmi_id_verified | BOOLEAN | Whether PMI ID has been verified |
| phone | TEXT UNIQUE | Phone number |
| linkedin_url | TEXT UNIQUE | LinkedIn profile URL |
| photo_url | TEXT | Supabase Storage URL |
| state | TEXT | State/Province |
| country | TEXT | Country |
| cycles | TEXT[] | e.g. ['pilot-2024','cycle1-2025','cycle2-2025','cycle3-2026'] |
| tribe_id | INTEGER | Pre-assigned for tribe leaders |
| is_superadmin | BOOLEAN | Only Vitor = true |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

#### `tribe_selections` (gamification)
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| member_id | UUID FK → members | UNIQUE (one selection per member) |
| tribe_id | INTEGER | 1-8 |
| selected_at | TIMESTAMPTZ | |

#### `courses` (8 rows)
| Column | Type | Notes |
|--------|------|-------|
| id | SERIAL PK | |
| code | TEXT UNIQUE | GENAI_OVERVIEW, DATA_LANDSCAPE, etc. |
| name | TEXT | Full course name |
| category | TEXT | core, complementary, optional |
| is_free | BOOLEAN | |
| url | TEXT | PMI.org link |
| sort_order | INTEGER | |

#### `course_progress`
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| member_id | UUID FK → members | |
| course_id | INTEGER FK → courses | |
| status | TEXT | not_started, in_progress, completed |
| completed_at | TIMESTAMPTZ | |
| UNIQUE | (member_id, course_id) | |

#### `presentations` (empty, ready for use)
#### `change_requests` (empty, ready for use)

### Server Functions (SECURITY DEFINER)

#### `get_member_by_auth()` → JSON
Matches current auth user to member record. Searches by: auth_id → email → secondary_emails. Returns guest JSON if no match. Auto-links auth_id on first match by email.

#### `select_tribe(p_tribe_id INTEGER)` → JSON
Inserts or updates tribe selection for current member. Returns `{success: true/false}`.

#### `deselect_tribe()` → JSON
Deletes tribe selection for current member.

#### `title_case(input TEXT)` → TEXT
Standardizes names to Title Case.

#### `set_progress(p_email, p_code, p_status)` → VOID
Helper to seed course progress data.

### RLS Notes
- **CRITICAL:** The `members` table had infinite recursion in the "Managers can update" policy. Fixed with `FOR ALL USING (true)` — needs proper fix with non-recursive check.
- `tribe_selections`: public SELECT, auth INSERT/UPDATE via server functions
- Storage `member-photos`: public read, auth upload

---

## 4. ACCESS LEVELS (6 Layers)

| Level | Role | Access |
|-------|------|--------|
| Public | (no login) | See all content, cannot select tribes |
| Guest | Logged in but email NOT in members table | See all, cannot select tribes, gets "Solicite cadastro ao GP" message |
| Observer | PMI member without PMI ID verified | Public content only until PMI ID is provided |
| Researcher (L4) | Active Cycle 3 member with PMI ID | Full access, select tribes, track progress |
| Tribe Leader (L3) | Pre-assigned to tribe | Cannot self-select tribe, full content access |
| Manager (L2) | Vitor (is_superadmin=true) | Full access + future admin panel |
| Sponsor (L1) | Chapter presidents | Future: transparency portal |

### Auth Flow
1. User clicks "Entrar" → modal with Google / LinkedIn / Magic Link
2. On OAuth redirect, `get_member_by_auth()` runs server-side
3. If email matches `members.email` or `members.secondary_emails` → full access with role
4. If no match → guest access
5. If member has no PMI ID → future: popup to complete profile (Maria Luiza case)

### Vitor's Auth Setup
- Primary email in DB: `vitor.rodovalho@outlook.com`
- Google login email: `vitorodovalho@gmail.com` (in secondary_emails)
- auth_id: `58675a94-eb44-483b-ab7d-9f8892e4fc3c` (Google)
- Also has Outlook auth: `2ec67522-66b1-4294-ba2f-d8bf59725ba5`

---

## 5. MEMBER DATA

### Active Members (Cycle 3): 45
| Chapter | Count | Leaders |
|---------|-------|---------|
| PMI-CE | 12 | Ana Carla Cavalcante (T8), Débora Moura (T2) |
| PMI-DF | 6 | Fernando Maquiaveli (T4), Jefferson Pinto (T5) |
| PMI-GO | 15 | Fabricio Costa (T6) + Vitor (Manager) |
| PMI-MG | 10 | Hayala Curto (T1), Marcel Fleming (T3), Marcos Klemz (T7) |
| PMI-RS | 2 | (none) |

### Inactive Members: 12
Cristiano Oliveira, Diego Menezes, Herlon Sousa, Ivan Lourenço (founder/sponsor), Lucas Vasconcelos, Marcelo Ferreira, Marcio Miranda, Roberto Macêdo, Rodrigo Lima Dutra, Rogério Côrtes, Sarah Faria Alcantara Macedo, Werley Miranda.

### Photos
- 45/45 active members have photos in Supabase Storage
- Format: 400x400px JPEG, center-cropped square
- Bucket: `member-photos/avatars/{email_encoded}.jpg`
- Inactive members with photos: archived in `~/Downloads/fotos/`

### PMI IDs
- 44/45 verified (Maria Luiza = pending, `malusilveirab@gmail.com`)
- Rule: Without PMI ID, member gets public-only access

---

## 6. ORGANIZATIONAL STRUCTURE

### 4 Knowledge Quadrants

**Q1 — O Praticante Aumentado** (Ferramentas, Produtividade, Engenharia de Agentes)
- Tribe 1: Radar Tecnológico do GP — Hayala Curto

**Q2 — Gestão de Projetos de IA** (Metodologia GenAI/ML, Equipes Híbridas)
- Tribe 2: Agentes Autônomos & Equipes Híbridas — Débora Moura

**Q3 — Liderança Organizacional** (Estratégia, Pessoas, Cultura, Portfólio)
- Tribe 3: TMO & PMO do Futuro — Marcel Fleming
- Tribe 4: Cultura & Change — Fernando Maquiaveli
- Tribe 5: Talentos & Upskilling — Jefferson Pinto
- Tribe 6: ROI & Portfólio — Fabricio Costa

**Q4 — Futuro e Responsabilidade** (Ética, Governança, Sociedade)
- Tribe 7: Governança & Trustworthy AI — Marcos Klemz
- Tribe 8: Inclusão & Colaboração — Ana Carla Cavalcante

### Tribe Selection Rules
- Min 3, Max 6 researchers per tribe
- Deadline: Saturday March 8, 2026, 12:00 BRT (15:00 UTC)
- Tribe leaders are pre-assigned, cannot self-select
- Members can select/deselect/switch until deadline

### Governance Hierarchy
- Level 1: 5 Chapter Sponsors
- Level 2: Project Manager (Vitor)
- Level 3: 8 Tribe Leaders
- Level 4: Researchers/Facilitators/Communicators
- Level 5: Ambassadors (future CoP layer)
- Support: Comitê de Curadoria (Peer Review Committee)

---

## 7. KPIs 2026

| KPI | Annual Target | Per Tribe |
|-----|--------------|-----------|
| Participating Chapters | 8 | — |
| Gov/Academic Partners | 3 | — |
| Impact Hours | ≥ 1,800h | ~225h |
| Published Articles | ≥ 10 | 1-2 |
| Webinars/Talks | ≥ 6 | ~1 |
| AI Pilot Projects | ≥ 3 | 1 per 3 tribes |
| Study Hours | ≥ 90h | ~11h |
| GPs with AI mini cert | ≥ 70% | — |
| CPMAI Members | ≥ 2 | — |

### Certification Trail (8 courses)
Core (4): GenAI Overview, Data Landscape, Prompt Engineering, Practical GenAI
Complementary (4): CDBA Intro, CPMAI Intro, AI Infrastructure, AI Agile

Current progress: 9 members tracked, top performers Fabricio Costa (100%) and Italo Nogueira (100%).

---

## 8. SITE SECTIONS (v8 — Current)

| Section | Nav ID | Content |
|---------|--------|---------|
| Hero | #hero | Title, date, chapters, countdown timer |
| Agenda | #agenda | 6 blocks × 15min each |
| Quadrants | #quadrants | 4 strategy cards |
| Tribes | #tribes | 8 tribes grouped by quadrant, leader photos, LinkedIn, entregáveis bullets, meeting times, select/deselect gamification |
| KPIs | #kpis | 6 metric cards |
| Breakout | #breakout | Ice-breaker question |
| Rules | #rules | 4 rule cards + value journey timeline |
| Trail | #trail | 8 PMI courses with links + gamified ranking with progress bars |
| Team | #team | 45 member photos circular gallery |
| Vision | #vision | 4 strategy cards (Benchmarking, Bimodal, CPMAI, Roadmap) |
| Resources | #resources | 6 resource cards with links |

### Key Links in Site
- Playlist YouTube: https://youtube.com/playlist?list=PLQJVKrw1fcrx3fD2ug1hnps6TklcMT1dc
- Manual de Governança: https://www.canva.com/design/DAG1Nc3jhC4/gWGhQCJyv7axeCbKozD1gg/view
- GitHub: https://github.com/VitorMRodovalho/ai-pm-research-hub
- PMI AI Courses: https://www.pmi.org/learning/ai-in-project-management
- volunteer.pmi.org
- nucleoia@pmigo.org.br

---

## 9. STRATEGIC ANALYSIS (from Consolidated Analysis v2)

### SWOT Summary
- **Strengths:** Multi-chapter collaboration (unique in PMI ecosystem), merit-based selection, structured governance, bilingual capability
- **Weaknesses:** Volunteer fatigue risk, no dedicated budget, single PM dependency
- **Opportunities:** PMI-CPMAI certification wave, no AI Ambassadors program yet (first-mover), international chapters seeking collaboration (Ireland, Germany, Sweden)
- **Threats:** PMI Global launches competing program, content obsolescence, brand compliance violations

### Benchmarking
- **PMI Ireland:** AI Innovation Hub — smaller, less structured
- **PMI Germany:** CoP AI — community-focused, less research output
- **PMI Sweden:** Global Chapter Report (27 chapters, 129 nations) — broader but less deep on AI
- **Núcleo:** Most robust and structured AI+PM initiative in the PMI global ecosystem

### Bimodal Model (CR-002)
- **Axis A (CoE):** Levels 1-4, closed Center of Excellence with peer review
- **Axis B (CoP):** Level 5, open Community of Practice (AI Ambassadors) accessible to any PMI member

### Roadmap
- **Phase 1 (2026):** Consolidate Cycle 3, international visibility
- **Phase 2 (2026-2027):** Cross-border expansion, co-authorship
- **Phase 3 (2027):** Launch AI Ambassadors
- **Phase 4 (2027-2028):** PMI Global endorsement

---

## 10. GOVERNANCE TERMINOLOGY

### Critical Rules
- **Never** use associative language (membros/votos → colaboradores/designação por consenso)
- **Always** refer to the initiative as an "internal chapter project" not an "association"
- The manual is a living document, undergoing revision in Cycle 3
- All materials must comply with PMI Global branding standards
- LLM transparency clause required in all publications

### Locked Terminology Glossary
| EN-US | PT-BR | ES-LATAM |
|-------|-------|----------|
| Research Stream | Tribo (de Pesquisa) | Línea de Investigación |
| Knowledge Quadrant | Quadrante | Cuadrante |
| Center of Excellence | Centro de Excelência | Centro de Excelencia |
| Community of Practice | Comunidade de Prática | Comunidad de Práctica |
| Peer Review Committee | Comitê de Curadoria | Comité de Curaduría |
| Tribe Leader | Líder de Tribo | Líder de Tribu |
| Change Request | Solicitação de Mudança | Solicitud de Cambio |
| Trustworthy AI | IA Confiável | IA Confiable |

---

## 11. CHANGE REQUESTS (from CHANGELOG.md)

| CR | Title | Status | Priority |
|----|-------|--------|----------|
| CR-001 | Governance Manual Reform — Terminology & CoP/CoE Alignment | PROPOSED | HIGH |
| CR-002 | Bimodal Operating Model — Axis A (CoE) + Axis B (CoP) | PROPOSED | HIGH |
| CR-003 | International Connection Pipeline | PROPOSED | MEDIUM |
| CR-004 | PMI-CPMAI Integration Strategy | PROPOSED | MEDIUM |
| CR-005 | Project Website & Digital Presence | IN PROGRESS | HIGH |

---

## 12. FILES IN REPOSITORY

```
ai-pm-research-hub/
├── README.md (trilingual EN/PT/ES)
├── CHANGELOG.md (5 CRs)
├── CONTRIBUTING.md (trilingual with glossary)
├── site/
│   └── index.html (v8 — production)
├── docs/
│   ├── en/
│   │   ├── project-charter.md
│   │   ├── hosting-architecture.md
│   │   └── setup-guide.md
│   ├── pt-br/ (.gitkeep)
│   └── es-latam/ (.gitkeep)
├── change-requests/ (.gitkeep)
├── assets/brand/ (.gitkeep)
├── assets/templates/ (.gitkeep)
├── process_photos.py (photo processing script)
└── .github/ISSUE_TEMPLATE/change-request.md
```

### Git History (key commits)
```
8f14e96 chore: initial project structure
4737625 feat: add Cycle 3 kickoff presentation as web page
671c0ce feat: Supabase auth + real-time tribe selection gamification
e82eb5f feat: all 8 leader LinkedIn URLs
18685e1 fix: complete rebuild v4 - clean JS, all auth + tribe selection
e8f23a3 fix: match by auth_id first, then email, then secondary_emails
e72cfac feat: server-side tribe selection + deselect function
(latest) feat: v8 - certification trail with gamified ranking
```

---

## 13. VITOR'S ENVIRONMENT

- **Machine:** MSI Stealth GS66-12UGS
- **OS:** Ubuntu 24.04.4 LTS (installed fresh this session)
- **Node.js:** v24.14.0 (via nvm)
- **Git:** configured with SSH ED25519 key
- **Username:** VitorMRodovalho
- **Email:** vitor.rodovalho@outlook.com / vitorodovalho@gmail.com
- **Phone:** +1 267-874-8329
- **LinkedIn:** https://www.linkedin.com/in/vitor-rodovalho-pmp/
- **PMI ID:** 5975367
