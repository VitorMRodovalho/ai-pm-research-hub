# Wireframe Specifications — Product/UX Team

**Date:** 2026-03-09  
**Context:** Tribe kickoff starts week of 2026-03-10. These wireframes define the next UX improvements.

---

## 1. Guest Landing State

**Trigger:** User logs in (Google/LinkedIn) but is NOT in the members table.

**Current behavior:** Auth gates on every page with no explanation.

**Target UX:**
- Amber banner at top: "Sua conta foi autenticada, mas ainda nao esta cadastrada no Nucleo."
- Contact info: nucleoiagp@gmail.com
- CTA: "Fale com o gestor do projeto" (mailto link)
- Nav shows user name with amber "Conta nao cadastrada" badge
- Catalog (artifacts) and leaderboard (gamification) remain accessible
- Profile page shows friendly "not registered" card with steps to join

**Components affected:** Nav.astro, profile.astro, attendance.astro, gamification.astro, artifacts.astro  
**Status:** Implemented

---

## 2. Researcher Onboarding Flow

**Route:** /onboarding (implemented)

**8-step checklist:**
1. Aceite a posicao no volunteer.pmi.org
2. Confirme seu cadastro com o gestor (nucleoiagp@gmail.com)
3. Faca login com Google ou LinkedIn
4. Complete seu perfil (/profile)
5. Escolha sua tribo ate o deadline do DB (/#tribes)
6. Faca os 8 mini cursos PMI
7. Participe da reuniao semanal da tribo
8. Submeta artefatos de pesquisa (/artifacts)

**Status:** Implemented

---

## 3. Tribe Dashboard (Future — P2)

**Route:** /tribe/[id] (not yet implemented)

**Structure:**
- Header: Tribe name, leader, quadrant
- Tabs: Members | Deliverables | Resources
- Members: table with photo, name, role, status
- Deliverables: from tribe_deliverables table — title, assignee, status, due date
- Resources: from hub_resources filtered by tribe_id

**Data sources:** members, tribe_deliverables, hub_resources, tribe_meeting_slots  
**Status:** Schema ready. Route not yet implemented.

---

## 4. Deliverables Tracker (Future — P2)

**Integrated in:** Tribe Dashboard + Admin

**Features:**
- Progress bar per tribe (X/Y concluidas)
- Cards per deliverable with status (Planejado/Em andamento/Concluido)
- Tribe leader: create, edit, assign, link to artifact
- Status transitions: planned -> in_progress -> completed

**Status:** Schema ready (tribe_deliverables). UI not yet implemented.

---

## 5. Researcher Weekly View (Future — P2)

**Route:** Enhanced /profile or new /my-week

**Cards:**
- Proxima reuniao (tribe_meeting_slots)
- Trilha IA progress (course_progress)
- Entregas pendentes (tribe_deliverables)
- XP semanal (gamification_points)
- Avisos recentes (announcements)

**Status:** Data sources all available. Route not yet implemented.

---

## Implementation Priority

| Screen | Priority | Data Ready | Implemented |
|--------|----------|------------|-------------|
| Guest landing state | P0 | Yes | Yes |
| Onboarding flow | P0 | Yes | Yes |
| Tribe dashboard | P2 | Yes (schema) | No |
| Deliverables tracker | P2 | Yes (schema) | No |
| Researcher weekly view | P2 | Yes | No |
