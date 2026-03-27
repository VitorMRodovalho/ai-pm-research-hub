# WhatsApp Cross-Group Analysis — 15 Groups, 18,338 Messages
**Date: 2026-03-15 | Sources: 15 WhatsApp group exports | For: Claude Code commit**

---

## Overview

| Category | Groups | Messages | Key insight |
|----------|--------|----------|-------------|
| OPERATIONAL | 3 | 9,492 | GERAL is the mega-group (6,373 msgs, 57 people). Comms team already analyzed in prior doc. |
| TRIBE | 4 active + 3 archived | 8,447 | T06 richest (2,505 msgs). T01 just starting (14 msgs). Archived T04/T05 have valuable C2 research. |
| GOVERNANCE | 4 | 1,369 | Líderes is the most active (1,208 msgs). Patrocinadores barely used (64 msgs). |
| ARCHIVE | 5 | 3,039 | T04 Riscos and T05 Revisão have rich C2 content. Documentação group produced the Manual de Governança. |

---

## Data Enriched in Production

### Tribes table updates:
| Tribe | Field | Value added | Source |
|-------|-------|-------------|--------|
| T01 | meeting_link | `meet.google.com/zxs-txmk-tiz` | WhatsApp T01 |
| T02 | meeting_link | `meet.google.com/uut-qqet-vnx` | WhatsApp T02 |
| T02 | miro_url | `miro.com/app/board/uXjVJHtOxSE=/` | WhatsApp T02 |
| T06 | meeting_link | `meet.google.com/kcv-gohj-scr` | WhatsApp T06 |
| T06 | meeting_day/time | Terça, 20:00-21:30 | WhatsApp T06 |
| T07 | meeting_link | `meet.google.com/mww-rhss-xkg` | WhatsApp T07 |
| T07 | meeting_day/time | Terça, 20:00-21:30 | WhatsApp T07 |
| T08 | meeting_day/time | Terça e Quinta, 20:30-22:00 | Notion extraction |

### Hub resources added (8 new):
- 5 Lovable prototypes (T06 research outputs): Bússola, EVA Hub, Priorização, Portfolio Compass, Outcome Priority
- 3 Claude artifacts (T02 agent research): Agente Cíntia, Fluxograma, Agent Design

---

## Friction Patterns Across All Groups

| Signal | Total occurrences | Worst groups |
|--------|-------------------|-------------|
| Access/lost (links, data, permissions) | 156 | GERAL (54), T06 (24), T07 (21), T04-C2 (18) |
| Availability (can't attend, delays) | 50 | GERAL (11), T06 (10), T04-C2 (10), T05-C2 (7) |
| Confusion (don't understand, doubts) | 11 | GERAL (4), Líderes (4), Boas Práticas (2) |

**Cross-cutting friction:** Links buried in WhatsApp scroll is the #1 problem. Every group has it. The portal solves this by making links persistent and searchable.

---

## Group-by-Group Analysis

### GERAL (6,373 msgs, 57 people, 830 links)
The mega-group. Everything gets shared here — events, announcements, articles, congratulations. 
- 54 access/lost signals (highest of all groups)
- 137 actionable links found (Drive, Meet, Sympla, Instagram, Forms)
- This is the group that benefits MOST from the portal: announcements system, event calendar, and /about page replace 80% of what gets posted here
- **Backlog opportunity:** Create a "digest" feature that auto-posts portal activity to WhatsApp (weekly summary)

### Foro Líderes (1,208 msgs, 16 people)
Strategic coordination group for tribe leaders.
- 29 actionable links (presentations, meeting docs, article reviews)
- Key decisions made here: article submission timelines, tribe reorganization, celebration planning
- **Backlog opportunity:** Leadership dashboard in /workspace with tribe-leader-specific views

### T06 ROI & Portfólio (2,505 msgs, 12 people)
Most productive research tribe.
- **7 Lovable prototypes** created — most of any tribe
- 11 Google Docs (articles, research, planning)
- Multiple Miro boards
- Meeting schedule: Terças 20h
- **Data enriched:** meeting_link, meeting_day, meeting_time_start, 5 Lovable apps saved to hub_resources

### T02 Agentes Autônomos (942 msgs, 13 people)
Active tribe with strong EAA Framework research.
- Débora Moura leads with 397 msgs (42%)
- 3 Claude artifacts (agent prototypes)
- Own Miro board (separate from Ciclo 2 shared board)
- **Data enriched:** meeting_link, miro_url, 3 Claude artifacts saved to hub_resources
- Schedule: Segunda e Quarta 18:30-19:30 (from existing DB data)

### T07 Governança & Trustworthy AI (937 msgs, 15 people)
Ivan Lourenço very active here (340 msgs, 36%) — unusual for a sponsor, shows deep engagement.
- 3 Google Docs (ethical frameworks, AI governance)
- Meeting schedule: Terças 20h
- **Data enriched:** meeting_link, meeting_day, meeting_time_start

### T01 Radar Tecnológico (14 msgs, 6 people)
Just started! First meeting was 9/mar/2026.
- Hayala Curto organizing, first meeting recorded
- Members: Hayala, João Santos (RS), Ricardo Santos, Rodolfo Santana (MG), Leandro Mota (DF)
- **Data enriched:** meeting_link

### Onboarding (369 msgs, 45 people)
Key onboarding artifacts:
- Google Form for new member registration
- Drive folder with onboarding materials
- 45 people joined this group (pipeline funnel data)
- **Backlog opportunity:** Replace this group with portal onboarding flow (W124 + W130 already built)

### Patrocinadores (64 msgs, 6 people)
Sponsors group — minimal activity. Vitor drives 89% of messages.
- **Insight:** Sponsors are not engaged via WhatsApp. The portal's executive report (W105) may be more effective.

### Comitê de Boas Práticas (46 msgs, 5 people)
Minimal activity. Roberto Macêdo + Maurício Machado.
- One shared spreadsheet for improvement tracking
- **Backlog opportunity:** Could be absorbed into the admin panel change request system

### Comitê de Curadoria (51 msgs, 5 people)
Fabricio initiated curation criteria discussion. Sarah provided review methodology.
- Sarah's method: focus on PMI submission requirements, bilingual review, acronym consistency, intro must have thesis statement
- **Key artifact:** Curation criteria and review process documented in WhatsApp → should be codified as curation_review_log template in portal
- **Backlog opportunity:** W90 (curation audit trail) already exists — connect Sarah's methodology to the rubric

### ARCHIVE: T04 Riscos C2 (1,304 msgs, 10 people)
Herlon led (414 msgs). Rich experiment data:
- ClickUp Brain evaluation for risk management
- ML predictive models for project failure
- Own Drive folder with experiment documentation
- Multiple Google Docs with article drafts

### ARCHIVE: T05 Revisão C2 (841 msgs, 10 people)
Roberto Macêdo led (256 msgs). Systematic review:
- Structured review methodology
- Multiple article drafts for social impact theme
- Spreadsheet-based progress tracking

### ARCHIVE: T00 Relatório Geral C2 (114 msgs, 5 people)
GP-level report coordination. Drive folder with consolidated cycle reports.

### ARCHIVE: Documentação do Nucleo (54 msgs, 4 people)
Produced the Manual de Governança R1 and R2. Roberto, Fabricio, and Sarah as authors.

---

## Backlog / Change Request Opportunities Identified

| ID | Opportunity | Source | Priority |
|----|------------|--------|----------|
| CR-01 | WhatsApp → Portal digest bot (weekly activity summary) | GERAL friction | Low |
| CR-02 | Leadership dashboard in /workspace | Líderes group pattern | Medium |
| CR-03 | Codify Sarah's curation methodology into curation_review_log | Curadoria group | Medium |
| CR-04 | Replace Onboarding WhatsApp with portal flow | Onboarding group (45 people) | High |
| CR-05 | Executive sponsor dashboard (replace Patrocinadores group) | Patrocinadores low engagement | Low |
| CR-06 | Archive/reference C2 tribe research in Knowledge Hub | T04, T05 archive groups | Medium |
| CR-07 | Boas Práticas → admin panel change_requests | Boas Práticas group | Low |

---

## Governance Entry

```
GC-026: Cross-group WhatsApp analysis — 15 groups (18,338 messages) analyzed. 4 tribe meeting_links populated. 3 meeting schedules set (T06, T07, T08). T02 miro_url added. 8 hub_resources created (5 Lovable prototypes, 3 Claude artifacts). 156 access/friction signals cataloged. 7 backlog/change-request opportunities identified.
```
