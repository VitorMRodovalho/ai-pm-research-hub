# Comms Team Friction Analysis & Portal Migration Plan
**Source: WhatsApp chats + Trello exports + Canva search | 2026-03-14**

---

## Executive Summary

The communications team (Mayanna, Letícia, Andressa) operates across **7 disconnected tools** creating significant friction. The portal's Communication Engine (W131) can absorb 80% of their workflow, eliminating tool-switching and data loss.

---

## Current Tool Landscape

| Tool | What they use it for | Messages/mentions |
|------|---------------------|-------------------|
| WhatsApp | Coordination, approvals, link sharing, briefs | 4,745 messages (9 months) |
| Canva | All visual design (carousels, posts, banners) | 49 mentions, 25+ unique designs, 31 links shared |
| Trello | Task kanban (2 boards: Ciclo 3 + Mídias Sociais) | 22 mentions |
| Google Drive | File storage, shared docs, photos | 37 mentions |
| Instagram | Publishing posts/carousels | 23 mentions |
| LinkedIn | Publishing posts/articles | 77 mentions |
| Sympla | Event pages (webinar) | 15 mentions |

---

## Friction Points Identified

### F1: Link Hunting (191 signals)
**Pattern:** "é tão difícil achar as mensagens, eu tava até agora procurando esse link" (Andressa, 7/23)
**Evidence:** Links get buried in WhatsApp. Vitor lost all history when switching phones. Team repeatedly asks "where is X?"
**Portal fix:** All links live in board_items, global_links table, or campaign_templates. Searchable, persistent.

### F2: Access Chaos (24 signals)
**Pattern:** "pedi acesso" / "sem acesso ao Canva" / "fiz a solicitação"
**Evidence:** Lidia had to request Drive access. Leticia was without Canva access. Roberto had to request doc access.
**Portal fix:** Single auth (Google OAuth). Role-based access. No per-tool permissions.

### F3: Approval Bottleneck (31 signals)
**Pattern:** "segue para validação" → silence → "tudo ok? Podemos postar?" → more silence
**Evidence:** Mayanna creates content during lunch break, asks for validation, waits hours. Template reviews stall workflow.
**Portal fix:** Campaign template system with built-in preview + GP approval workflow. Status visible to all.

### F4: Context Fragmentation
**Pattern:** Brief is in WhatsApp audio, data is in Drive, design is in Canva, status is in Trello, publishing is on IG/LinkedIn.
**Evidence:** Andressa: "fiquei um bom tempo tentando entender o que, de fato, era pra fazer" (3/2/26)
**Portal fix:** BoardEngine card has description, attachments, assignee, status, due date — all in one place.

### F5: Template/Format Confusion (59 signals)
**Pattern:** "Post feed IG: 1080×1080 ou 1350×1080 / Stories: 1080×1920 / Banner Sympla: 1600×838"
**Evidence:** Format specs shared in WhatsApp, lost in scroll. Team has to re-discover specs each time.
**Portal fix:** Campaign templates with pre-set dimensions and format guides embedded in the template card.

### F6: Duplicate/Scattered Design Assets
**Pattern:** 25+ Canva designs, many variants of same content (Pesquisadores Blocos I-IV)
**Evidence:** Multiple Canva links for overlapping content. No single registry of all published assets.
**Portal fix:** Blog posts table + campaign_templates + board_items create a unified content registry.

### F7: Publishing Timing Pressure
**Pattern:** "mas já queria postar logo hoje pra não perder o timing" (Mayanna, 3/5/26)
**Evidence:** Content created hastily to catch timing windows. No editorial calendar visibility.
**Portal fix:** Campaign scheduling with planned send dates. Blog posts with publish dates.

---

## Team Dynamics (from message volume)

| Member | Messages | Role pattern |
|--------|----------|-------------|
| Mayanna | 655 (highest) | Content creator + coordinator. Does 70% of content creation. Creates during lunch breaks. |
| Letícia | 630 | Publisher (has IG/LinkedIn access). Less available recently ("turistando"). |
| Andressa | 301 | Designer (Canva). Creates templates and visual assets. Starting Masters program (reduced availability). |
| Vitor | 628 | GP review + strategic direction. Provides specs, references, approval. |
| Fabricio | 89 | Occasional input, strategic comments. |

**Key insight:** Mayanna is the engine. She creates content, inserts researcher info, writes copy, and publishes when others are unavailable. Any friction reduction benefits her most.

---

## Trello Board Analysis

### Board 1: "Comunicação Ciclo 3" (current)
**11 lists, 17 active cards. Pipeline:**
ESTRATÉGICO → IDEAÇÃO → BACKLOG → PLANEJADOS → DESIGN → REDAÇÃO → REVISÃO → VALIDAÇÃO GP → PUBLICAÇÃO → CONCLUÍDO → MONITORAMENTO

**Active items:**
- 4 "Divulgação pesquisadores" cards (Blocos I-IV) in various stages
- 3 published items (Líderes, Big Bang Institucional, Bloco I)
- 8 strategic/reference cards (planning, briefing, tools, GPT assistant, Drive, meetings, researcher list)

### Board 2: "Mídias Sociais" (Ciclo 2, archive)
**10 lists, 40 cards (17 completed). POST numbering 1-17.**
**Completed content types:** PM Talks, tribe presentations, selection criteria, governance manual, testimonials, webinar series, knowledge pills, researcher onboarding.

---

## Canva Design Inventory (13+ found)

| Design | Type | Status |
|--------|------|--------|
| Pesquisadores Ciclo 3 Bloco I (2 variants) | Carousel 4-8 pages | Published |
| Pesquisadores Ciclo 3 Bloco II | Carousel 4 pages | Published |
| Pesquisadores Ciclo 3 Bloco III | Carousel 4 pages | In design |
| Pesquisadores Ciclo 3 Bloco IV | Carousel 4 pages | In design |
| Apresentação de Lideranças Ciclo 3 | Carousel 9 pages | Published |
| IA na Priorização Tribo 3 | Presentation 12 pages | Draft |
| Webinar Sympla covers | Banner + Feed + Stories | Used |
| Celebração Encerramento Ciclo 2 | Carousel 15 pages | Published |
| Various knowledge pills | Mixed formats | Published |

---

## Migration Plan: Trello → BoardEngine

### Phase 1: Import Trello data (immediate)
The Comms board in BoardEngine already exists (from W131 migration). Import the 17 active cards from Ciclo 3 board.

### Phase 2: Template consolidation
Create campaign_templates for recurring content types:
- Researcher spotlight carousel (reusable per cycle)
- Knowledge pill (article summary)
- Event announcement (webinar/meetup)
- Tribe presentation
- Institutional update

### Phase 3: Canva link registry
Add Canva design URLs as attachments to board_items, creating a searchable asset library.

### Phase 4: Editorial calendar
Use board_items with due_dates to create a visible publication schedule in /workspace.

---

## Recommended Portal Features (next waves)

| Feature | Friction solved | Effort |
|---------|----------------|--------|
| Canva link field in board_items | F1, F6 | Low |
| Campaign approval workflow (status: draft→review→approved→published) | F3 | Medium |
| Format guide embedded in campaign templates | F5 | Low |
| Social media calendar view in /workspace | F7 | Medium |
| Content brief template (replaces WhatsApp audio briefs) | F4 | Low |

---

## Key Quotes Supporting Migration

> "é tão difícil achar as mensagens" — Andressa (7/23/25)
> "Troquei de celular e perdi a documentação" — Vitor (7/14/25)  
> "onde está sendo salvo o material de comunicação deste ano? não achei na pasta do nucleo" — Vitor (3/5/26)  
> "no trello" — Mayanna (3/5/26)
> "sem friccao de dado sendo gerado fora, e publicacoes descentralizadas" — Vitor (3/7/26, when showing portal)
> "vale um post sobre isso (nosso sistema próprio), muitoooo bom!" — Mayanna (3/7/26)
