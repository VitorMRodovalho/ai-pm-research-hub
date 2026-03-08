# AI & PM Research Hub — Project Plan

> **Date:** 2026-03-05
> **Status:** Kickoff Day — Site Live, Backend Operational
> **Next Session Priority:** Multi-page migration, Admin panel, KPI tracking

---

## PHASE 0: KICKOFF — ✅ COMPLETED (Today)

### Done
- [x] Ubuntu 24.04 LTS installed + dev environment configured
- [x] GitHub repository created with trilingual docs
- [x] Project Charter (PMBOK 8 aligned)
- [x] Hosting Architecture Decision Record (ADR-001)
- [x] CHANGELOG with 5 Change Requests
- [x] CONTRIBUTING.md with locked terminology glossary
- [x] Kickoff presentation as web page (v1 → v8)
- [x] Deploy to Cloudflare Pages (auto-deploy from GitHub)
- [x] Supabase project created (São Paulo region)
- [x] Database schema with members, tribe_selections, courses, course_progress
- [x] 45 active members + 12 inactive members seeded in DB
- [x] All PMI IDs populated (44/45, Maria Luiza pending)
- [x] Google OAuth working
- [x] LinkedIn OAuth configured (needs scope fix in LinkedIn Developer Portal)
- [x] Magic Link authentication working
- [x] Server-side auth matching (get_member_by_auth function)
- [x] Server-side tribe selection/deselection (select_tribe, deselect_tribe functions)
- [x] Role-based access (manager/leader/researcher/guest badges)
- [x] Tribe leader blocking (cannot self-select)
- [x] 45 member photos processed (400x400, center-cropped) and uploaded
- [x] Photo URLs linked in DB (45/45 active members)
- [x] Tribes grouped by quadrant with enriched descriptions from videos
- [x] Entregáveis as bullet lists with meeting schedules
- [x] LinkedIn links for all 8 tribe leaders
- [x] Leader photos displayed in tribe headers
- [x] Team gallery with circular photos + role dots
- [x] Strategic vision section (Benchmarking, Bimodal, CPMAI, Roadmap)
- [x] Countdown timer to selection deadline (Mon Mar 9, 12h BRT)
- [x] Realtime slot counters via Supabase
- [x] Certification trail section with 8 PMI courses (links to PMI.org)
- [x] Gamified ranking with progress bars and badges
- [x] Course progress data for 9 members seeded
- [x] Manual de Governança linked (Canva)
- [x] Consolidated strategic analysis document (v2) completed

### Pivoted from Original Plan
| Original Plan | What Happened | Why |
|--------------|---------------|-----|
| Static site (zero backend) | Supabase backend from day 1 | Gamification required auth + database |
| Cloudflare Access for auth | Supabase Auth | More flexible, supports OAuth providers |
| Cloudflare D1 for database | Supabase PostgreSQL | Better tooling, realtime, RLS |
| Astro site framework | Single HTML file | Speed of delivery — migrate to Astro in Phase 1 |
| PPTX presentation | Web-based presentation/site | Vitor's preference — more impactful, permanent |

---

## PHASE 1: PORTAL PÚBLICO — 🔄 IN PROGRESS

### Priority 1: Multi-Page Migration (Astro)
- [ ] Initialize Astro project in `site/` directory
- [ ] Migrate single HTML to Astro components
- [ ] Shared layout with nav, footer, Supabase client
- [ ] Route structure:
  ```
  /                    → Home (hero + summary)
  /kickoff/            → Cycle 3 kickoff (current one-page content)
  /tribes/             → Tribe selection + gamification
  /about/              → About + strategic analysis
  /members/            → Team gallery + member profiles
  /kpis/               → Dashboard with live indicators
  /governance/         → Manual, CRs, meetings
  /publications/       → Articles, frameworks, tribe outputs
  /media/              → YouTube playlist, webinars
  /trail/              → Certification trail + ranking
  /admin/              → Admin panel (manager/superadmin only)
  ```
- [ ] i18n setup: PT-BR (primary), EN-US, ES-LATAM
- [ ] PMI Global 2026 brand tokens in Tailwind config

### Priority 2: Admin Panel
- [ ] Member management (CRUD, activate/deactivate, change roles)
- [ ] Tribe assignment override
- [ ] Course progress manual update
- [ ] View/export member data (respecting encryption)
- [ ] Dashboard with KPI status
- [ ] Change Request management

### Priority 3: Artifact Tracking System
- [ ] `artifacts` table: id, tribe_id, title, type, status, created_by, approved_by, approved_at, replaced_by, linked_kpis
- [ ] Artifact types: article, webinar, podcast, template, framework, prototype, guide, ebook
- [ ] Status flow: draft → in_review → peer_reviewed → leader_approved → curadoria_approved → published
- [ ] GP approval required for substitutions
- [ ] Artifact ↔ KPI correlation tracking
- [ ] Version history (artifact_versions table)

### Priority 4: Attendance & Impact Hours Tracking
- [ ] `events` table: id, type (general/tribe/webinar), title, date, duration_minutes, tribe_id
- [ ] `attendance` table: member_id, event_id, present, joined_at, left_at
- [ ] Impact hours = duration × attendees (auto-calculated)
- [ ] Weekly cadence: leaders update Saturday by 17h
- [ ] Manager generates report Monday morning
- [ ] Live KPI dashboard showing hours accumulated vs target (1,800h)

### Priority 5: PMI ID Onboarding Flow
- [ ] On first login, if member has no PMI ID → popup modal to complete profile
- [ ] Fields: PMI ID (mandatory), phone (optional), LinkedIn (optional)
- [ ] Validate PMI ID uniqueness
- [ ] Until PMI ID provided → public access only
- [ ] Maria Luiza case: specific trigger on `malusilveirab@gmail.com`

---

## PHASE 2: AUTHENTICATION & ACCESS LAYERS — ✅ PARTIAL

### Done
- [x] Google OAuth
- [x] Member matching by auth_id → email → secondary_emails
- [x] Role badges in UI
- [x] Guest vs member distinction
- [x] Tribe leader selection blocking

### Pending
- [ ] Fix LinkedIn OAuth scope error (LinkedIn Developer Portal → Products → "Sign In with LinkedIn using OpenID Connect")
- [ ] Microsoft/Outlook OAuth (Azure AD → Supabase Azure provider)
- [ ] PMI ID verification popup for incomplete profiles
- [ ] Multi-email support: allow adding emails from profile settings
- [ ] Unique constraint enforcement UI (phone, LinkedIn, PMI ID — show user-friendly errors)
- [ ] Two-layer auth: Layer 1 = SSO login, Layer 2 = match against members DB + active cycle check

---

## PHASE 3: INTEGRATIONS — ⏳ FUTURE

### YouTube API
- [ ] Auto-embed tribe leader videos
- [ ] Playlist auto-sync for `/media/` page
- [ ] View count tracking

### Google Drive API
- [ ] Document index by tribe/quadrant
- [ ] Link to shared folders from tribe pages

### Transparency Portal (Sponsors)
- [ ] KPI dashboard pulling from `events`, `attendance`, `artifacts`, `course_progress`
- [ ] Chapter-level breakdown
- [ ] Export capabilities

### Meeting Transcripts
- [ ] Teams recording transcripts → AI processing → searchable knowledge base
- [ ] Tag by tribe, topic, action items

### WhatsApp Insights
- [ ] Export (manual) → offline processing → portal insights
- [ ] NO direct API integration (closed/paid)

---

## ARCHITECTURAL DECISIONS

### ADR-001: Cloudflare Pages + Astro
- **Status:** Approved, partially implemented (Cloudflare Pages done, Astro pending)
- **Rationale:** Free tier unlimited, auto-deploy, global CDN

### ADR-002: Supabase over Cloudflare D1
- **Status:** Implemented
- **Rationale:** Better auth ecosystem, realtime subscriptions, RLS, Storage, PostgreSQL functions

### ADR-003: Server Functions over Client-Side Queries
- **Status:** Implemented
- **Rationale:** RLS infinite recursion issues, SECURITY DEFINER bypasses safely
- **Pattern:** All write operations and sensitive reads go through `SECURITY DEFINER` functions

### ADR-004: Single HTML → Astro Migration
- **Status:** Planned for next session
- **Rationale:** One-page is too complex to maintain; need component reuse, i18n, and route-based code splitting

---

## BUSINESS RULES

### Member Management
1. Email, phone, and LinkedIn are unique keys — cannot be shared between members
2. A member can have multiple emails (primary + secondary_emails array)
3. PMI ID is mandatory for non-public access; without it → public layer only
4. Names are stored in Title Case (enforced by `title_case()` function)
5. Future registrations should auto-apply Title Case

### Tribe Selection
1. Min 3, Max 6 researchers per tribe
2. Tribe leaders are pre-assigned (tribe_id set in members table)
3. Tribe leaders cannot self-select via gamification UI
4. Members can change selection until deadline (Monday 12h BRT)
5. After deadline, selections are locked

### Artifacts
1. Each artifact must correlate with at least one annual KPI
2. GP approval required for artifact substitution
3. All changes tracked with timestamps and responsible party
4. 7-step curation flow: Ideas → Research → Draft → Initial Review → Peer Review → Leader → Curadoria → Published

### Access Control
1. Not in DB → Guest (public content only)
2. In DB but no PMI ID → Observer (public only until PMI ID provided)
3. In DB + PMI ID + current_cycle_active → Full access per role
4. Superadmin (Vitor) → all access + admin panel
5. Sensitive data (phone, PMI ID) encrypted at rest (pgcrypto available, not fully implemented yet)

---

## IMMEDIATE NEXT ACTIONS (Next Chat)

### Critical (before next meeting)
1. [ ] Verify v8 deployed correctly — check trail section live
2. [ ] Fix LinkedIn OAuth scope
3. [ ] Test tribe selection with another member (ask a tribe leader to try)

### High Priority
4. [ ] Migrate to Astro multi-page
5. [ ] Create admin panel (member management + KPI dashboard)
6. [ ] Artifact tracking system (tables + UI)
7. [ ] Attendance tracking system (tables + UI)
8. [ ] PMI ID onboarding popup

### Medium Priority
9. [ ] Microsoft/Outlook OAuth
10. [ ] i18n (EN-US, ES-LATAM)
11. [ ] Custom domain (aipmhub.org or similar)
12. [ ] Email notifications via Cloudflare Email Routing

### Nice to Have
13. [ ] YouTube API integration
14. [ ] Google Drive document index
15. [ ] WhatsApp export processing pipeline
16. [ ] Migrate Trello → GitHub Projects

---

## REFERENCE DOCUMENTS

| Document | Location | Status |
|----------|----------|--------|
| Strategic Analysis v2 | Uploaded to Claude project | ✅ Complete |
| Governance Manual | https://www.canva.com/design/DAG1Nc3jhC4/gWGhQCJyv7axeCbKozD1gg/view | Living document, Cycle 3 revision pending |
| Leadership Kickoff (Feb 17) | /mnt/user-data/uploads/2026-02-17_-_Nucleo_IA_GP_-_Ciclo3_Kickoff_Lideranca.pptx | Reference for tribe details |
| PMI Template | /mnt/user-data/uploads/Template_de_Apresentação_-_PMI_Goiás_-_PALESTRANTE_VitorMaia.pptx | Color palette reference |
| Infographics | 5 PNG files uploaded | Mandala, Metas, Aliança, Jornada, Equipes Híbridas |
| LinkedIn Kickoff Post | Shared in chat | Contains all 8 video links + descriptions |
| Member Spreadsheet | Shared in chat (TSV) | 44 active + contact details |
| Course Progress | Shared in chat | 32 members tracked, completion rates |
