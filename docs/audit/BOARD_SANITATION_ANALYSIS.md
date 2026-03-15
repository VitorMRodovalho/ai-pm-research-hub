# Board Sanitation Analysis

**Generated**: 2026-03-15
**Purpose**: Audit all non-archived board items to classify cards as deliverables vs tasks, identify legacy contamination, and inform cleanup decisions.

---

## 1. Cards by Board, Cycle, and Source

| Board | Tribe | Cycle | Source | Count |
|---|---|---|---|---|
| T1: Radar Tecnológico - Quadro Geral | 1 | 3 | c3-artifact | 5 |
| T1: Radar Tecnológico - Quadro Geral | 1 | 3 | manual/other | 1 |
| T2: Agentes Autônomos - Quadro Geral | 2 | 3 | c3-artifact | 4 |
| T3: TMO & PMO do Futuro - Quadro Geral | 3 | 3 | c3-artifact | 5 |
| T3: TMO & PMO do Futuro - Quadro Geral | 3 | 3 | manual/other | 23 |
| T3: TMO & PMO do Futuro - Quadro Geral | 3 | 2 | miro-import | 24 |
| T4: Cultura & Change - Quadro Geral | 4 | 3 | c3-artifact | 11 |
| T4: Cultura & Change - Quadro Geral | 4 | 2 | miro-import | 52 |
| T5: Talentos & Upskilling - Quadro Geral | 5 | 3 | c3-artifact | 8 |
| T6: ROI & Portfólio - Quadro Geral | 6 | 3 | c3-artifact | 8 |
| T6: ROI & Portfólio - Quadro Geral | 6 | 2 | miro-import | 142 |
| T7: Governança & Trustworthy AI - Quadro Geral | 7 | 3 | c3-artifact | 9 |
| T8: Inclusão & Comunicação - Entregas | 8 | 3 | c3-artifact | 6 |
| Hub de Comunicação | — | 3 | manual/other | 46 |
| Publicações & Submissões PMI | — | 3 | manual/other | 31 |

**Totals**: 375 non-archived cards across 10 boards.

### Source Distribution

| Source | Count | % |
|---|---|---|
| c3-artifact (unified tags) | 56 | 14.9% |
| manual/other | 101 | 26.9% |
| miro-import (cycle 2 legacy) | 218 | 58.1% |

> **Key finding**: 58% of non-archived cards are cycle-2 legacy imports. These are tagged with the unified `ciclo_2` tag but remain visible in default board views. Board-level filtering by cycle or tag should be enabled to declutter.

---

## 2. Card Classification Summary

| Classification | Count | Description |
|---|---|---|
| DELIVERABLE | 56 | Cards with unified artifact tags (pesquisa, publicacao, framework, poc, etc.) |
| LIKELY-DELIVERABLE | 32 | Title mentions article, framework, report, toolkit, webinar, etc. |
| LIKELY-TASK | 20 | Title starts with action verb (criar, definir, buscar, levantar, etc.) |
| NEEDS-REVIEW | 173 | Cannot classify automatically — mixed content, references, notes |
| SHORT-NEEDS-REVIEW | 94 | Title under 30 chars — likely labels, names, or fragments |

### Per Board Breakdown

| Board | DELIVERABLE | LIKELY-DELIV | LIKELY-TASK | NEEDS-REVIEW | SHORT-REVIEW |
|---|---|---|---|---|---|
| T1: Radar Tecnológico | 5 | — | 1 | — | — |
| T2: Agentes Autônomos | 4 | — | — | — | — |
| T3: TMO & PMO do Futuro | 5 | 3 | 18 | 11 | 15 |
| T4: Cultura & Change | 11 | 6 | — | 26 | 20 |
| T5: Talentos & Upskilling | 8 | — | — | — | — |
| T6: ROI & Portfólio | 8 | 14 | 1 | 80 | 47 |
| T7: Governança & Trustworthy AI | 9 | — | — | — | — |
| T8: Inclusão & Comunicação | 6 | — | — | — | — |
| Hub de Comunicação | — | 7 | — | 30 | 9 |
| Publicações & Submissões PMI | — | 2 | — | 26 | 3 |

### Board Health Assessment

**Clean boards** (only tagged deliverables, no legacy noise):
- T1, T2, T5, T7, T8 — pristine, only cycle-3 artifacts

**Contaminated boards** (legacy items polluting active views):
- **T6** (worst): 142 miro-import items (cycle 2) — personal notes, LinkedIn profiles, retrospective stickies, course links. Only 8 real cycle-3 deliverables.
- **T4**: 52 miro-import items (cycle 2) — bibliography, problem statements, individual boards. 11 cycle-3 deliverables.
- **T3**: 24 miro-import items (cycle 2) + 23 manual items — mix of cycle-2 research notes and cycle-3 tasks (action items from Trello). 5 cycle-3 deliverables.

**Global boards** (operational, not research-driven):
- **Hub de Comunicação**: 46 cards, mostly social media posts and planning items. No unified tags. Classification: operational tasks.
- **Publicações & Submissões PMI**: 31 cards. ~20 are "How to use" instruction cards baked into the board as column descriptions. 6 are real article submissions under review.

---

## 3. Detailed Card Inventory

### T1: Radar Tecnológico - Quadro Geral

| Classification | Title | Cycle | Status | Baseline |
|---|---|---|---|---|
| DELIVERABLE | Artigo Acadêmico — Radar Tecnológico e Padrões Agênticos | 3 | backlog | 2026-08-31 |
| DELIVERABLE | Artigo LinkedIn — Quick Win Radar Tecnológico | 3 | backlog | 2026-04-30 |
| DELIVERABLE | Implementação de 2 Padrões Agênticos em GP | 3 | backlog | 2026-06-30 |
| DELIVERABLE | Matriz de Artefatos Potencializáveis por IA | 3 | backlog | 2026-05-31 |
| DELIVERABLE | Pesquisa: Artefatos de GP Potencializáveis com IA | 3 | in_progress | 2026-03-31 |
| LIKELY-TASK | Finalizar Curso 01 da Trilha IA | 3 | in_progress | 2026-03-16 |

### T2: Agentes Autônomos - Quadro Geral

| Classification | Title | Cycle | Status | Baseline |
|---|---|---|---|---|
| DELIVERABLE | Artigo LinkedIn — Agentes Autônomos em GP | 3 | backlog | 2026-04-30 |
| DELIVERABLE | Plano Inicial + Framework EAA (Engenharia de Agentes Autônomos) | 3 | in_progress | 2026-03-31 |
| DELIVERABLE | Publicação Final — Framework EAA | 3 | backlog | 2026-06-30 |
| DELIVERABLE | Webinar Comunitário — Agentes Autônomos em Ação | 3 | backlog | 2026-05-31 |

### T3: TMO & PMO do Futuro - Quadro Geral

| Classification | Title | Cycle | Status | Baseline |
|---|---|---|---|---|
| DELIVERABLE | Arquitetura do Modelo TMO/PMO do Futuro | 3 | backlog | — |
| DELIVERABLE | Construção da PoC — TMO com IA | 3 | backlog | — |
| DELIVERABLE | Execução e Validação da PoC | 3 | backlog | — |
| DELIVERABLE | Ideação do Projeto Piloto TMO/PMO | 3 | backlog | — |
| DELIVERABLE | Relatório / Artigo Final TMO com IA | 3 | backlog | — |
| LIKELY-DELIVERABLE | 1) Posteriormente 2) Mayanna 3) Luciana - Referências Bibliográficas | 2 | backlog | — |
| LIKELY-DELIVERABLE | Artigos Ciclo 1 | 2 | backlog | — |
| LIKELY-DELIVERABLE | Fabricio 1. Introduction 2. Problem... | 2 | backlog | — |
| LIKELY-TASK | Buscar materiais acadêmicos e referências | 3 | todo | 2025-03-31 |
| LIKELY-TASK | Criar apresentação/resumo do estudo | 3 | done | 2025-05-20 |
| LIKELY-TASK | Criar documento no google drive para controle | 3 | todo | — |
| LIKELY-TASK | Criar o board no Trello e convidar os membros | 3 | todo | 2025-03-17 |
| LIKELY-TASK | Decidir os subtópicos | 3 | todo | — |
| LIKELY-TASK | Decidir quantidade de artigos | 3 | todo | 2025-03-30 |
| LIKELY-TASK | Definir a estrutura do artigo | 3 | in_progress | 2025-04-06 |
| LIKELY-TASK | Definir escopo do grupo | 3 | todo | — |
| LIKELY-TASK | Definir o objetivo geral da pesquisa | 3 | todo | 2025-04-03 |
| LIKELY-TASK | Distribuir as seções entre os membros do grupo | 3 | in_progress | 2025-04-06 |
| LIKELY-TASK | Elaborar quadro de coerencia | 3 | todo | 2025-04-14 |
| LIKELY-TASK | Identificar ferramentas de IA para priorização | 3 | todo | 2025-04-07 |
| LIKELY-TASK | Levantar as principais questões de pesquisa | 3 | todo | 2025-04-03 |
| LIKELY-TASK | Organizar as referências coletadas | 3 | todo | — |
| LIKELY-TASK | Preparar versão final do documento | 3 | done | 2025-05-13 |
| LIKELY-TASK | Redigir os primeiros rascunhos | 3 | in_progress | 2025-04-15 |
| LIKELY-TASK | Refinar e ajustar o conteudo | 3 | in_progress | 2025-04-22 |
| LIKELY-TASK | Submeter para revisão do Núcleo | 3 | review | 2025-05-05 |
| NEEDS-REVIEW | (11 items — cycle 2+3 mixed content, research notes, ATAs) | — | — | — |
| SHORT-NEEDS-REVIEW | (15 items — member names, labels, fragments from cycle 2) | — | — | — |

> **T3 Note**: 18 LIKELY-TASK items appear to be from a Trello import of cycle-2/early-cycle-3 task lists. Dates show 2025 — likely stale. Consider converting to checklist items under deliverables or archiving.

### T4: Cultura & Change - Quadro Geral

| Classification | Title | Cycle | Status | Baseline |
|---|---|---|---|---|
| DELIVERABLE | 11 cycle-3 artifacts with baselines (Mar–Nov 2026) | 3 | mixed | set |
| LIKELY-DELIVERABLE | 6 items — cycle-2 article drafts, outlines | 2 | backlog | — |
| NEEDS-REVIEW | 26 items — cycle-2 bibliography, problem statements, links | 2 | backlog | — |
| SHORT-NEEDS-REVIEW | 20 items — member names, labels, empty HTML | 2 | backlog | — |

> **T4 Note**: 52 cycle-2 miro-import items are tagged with `ciclo_2` unified tag. All are in `backlog` status. Recommendation: archive or filter by default.

### T5: Talentos & Upskilling - Quadro Geral

| Classification | Title | Cycle | Status | Baseline |
|---|---|---|---|---|
| DELIVERABLE | Artigo Acadêmico Aplicado — Competências de IA em GP | 3 | backlog | 2026-10-31 |
| DELIVERABLE | Checklist de Evidências — Gate A | 3 | backlog | 2026-07-31 |
| DELIVERABLE | Matriz de Competências × Proficiência × IA | 3 | backlog | 2026-04-30 |
| DELIVERABLE | Relatório Final — Toolkit Consolidado | 3 | backlog | 2026-12-31 |
| DELIVERABLE | Rubricas de Proficiência em IA para GP | 3 | backlog | 2026-06-30 |
| DELIVERABLE | Taxonomia de Competências em IA para GP | 3 | backlog | 2026-04-30 |
| DELIVERABLE | Toolkit v1.0 de Talentos & Upskilling — Gate B | 3 | backlog | 2026-08-31 |
| DELIVERABLE | Webinário de Discussão — Competências de IA | 3 | backlog | 2026-10-31 |

### T6: ROI & Portfólio - Quadro Geral

| Classification | Title | Cycle | Status | Baseline |
|---|---|---|---|---|
| DELIVERABLE | 8 cycle-3 artifacts with baselines (Apr–Nov 2026) | 3 | backlog | set |
| LIKELY-DELIVERABLE | 14 items — cycle-2 article references, research links | 2 | backlog | — |
| LIKELY-TASK | 1 item — "Criar agentes de IA" | 2 | backlog | — |
| NEEDS-REVIEW | 80 items — retrospective stickies, personal reflections, LinkedIn profiles, course links, WhatsApp notes | 2 | backlog | — |
| SHORT-NEEDS-REVIEW | 47 items — member names, tool names, one-word labels | 2 | backlog | — |

> **T6 Note**: Most contaminated board. 142 of 150 items are cycle-2 miro-import stickies from retrospectives, icebreakers, and brainstorming sessions. These are NOT research artifacts. All tagged with `ciclo_2`. Strong recommendation: archive all 142 or hide via default cycle filter.

### T7: Governança & Trustworthy AI - Quadro Geral

| Classification | Title | Cycle | Status | Baseline |
|---|---|---|---|---|
| DELIVERABLE | Checklist de Critérios de Aceite para GenAI/RAG | 3 | backlog | 2026-09-30 |
| DELIVERABLE | Estruturação dos Pilares Risco/Compliance para IA | 3 | backlog | 2026-04-30 |
| DELIVERABLE | Framework de Governança de IA para Organizações | 3 | backlog | 2026-06-30 |
| DELIVERABLE | Guia de Métricas de Valor para Projetos de IA | 3 | backlog | 2026-09-30 |
| DELIVERABLE | Matriz de Qualidade de Dados para IA | 3 | backlog | 2026-06-30 |
| DELIVERABLE | Piloto de Governança + Workshop de Validação — Gate A | 3 | backlog | 2026-07-31 |
| DELIVERABLE | Relatório Final — Toolkit de Governança Consolidado | 3 | backlog | 2026-12-31 |
| DELIVERABLE | Toolkit v1.0 de Governança de IA — Gate B | 3 | backlog | 2026-09-30 |
| DELIVERABLE | Treinamento da Comunidade + Coleta de Feedbacks | 3 | backlog | 2026-11-30 |

### T8: Inclusão & Comunicação - Entregas

| Classification | Title | Cycle | Status | Baseline |
|---|---|---|---|---|
| DELIVERABLE | Artigo de Revisão Crítica — Cérebro Neuroatípico e IA | 3 | backlog | 2026-05-31 |
| DELIVERABLE | Estudo de Campo — Neuro-Advantage em Ambientes de Projeto | 3 | backlog | 2027-03-31 |
| DELIVERABLE | Modelo de Alinhamento Cognitivo — Neurodiversidade × IA | 3 | backlog | 2026-11-30 |
| DELIVERABLE | Neuro-Advantage Framework 1.0 — Entrega Final Multi-Ciclo | 3 | backlog | 2027-07-31 |
| DELIVERABLE | Palestra/Webinar — Neurodiversidade e IA em Projetos | 3 | backlog | 2026-11-30 |
| DELIVERABLE | Protocolo Metodológico — Neuro-Advantage Framework | 3 | backlog | 2026-08-31 |

### Hub de Comunicação

| Classification | Count | Notes |
|---|---|---|
| LIKELY-DELIVERABLE | 7 | Social media posts ([POST X] series) |
| NEEDS-REVIEW | 30 | Post planning, event promotion, community management |
| SHORT-NEEDS-REVIEW | 9 | Planning items, tools, references |

### Publicações & Submissões PMI

| Classification | Count | Notes |
|---|---|---|
| LIKELY-DELIVERABLE | 2 | Real article submissions under review |
| NEEDS-REVIEW | 26 | ~20 are "How to use" / "Purpose:" instruction cards (column descriptions), 6 are real submissions |
| SHORT-NEEDS-REVIEW | 3 | Placeholder articles |

---

## 4. Recommendations

### Immediate Actions (P0)

1. **Archive T6 cycle-2 items** — 142 retrospective stickies provide zero research value. They're tagged `ciclo_2` but still clutter the board. Archive all `miro_import` items on T6.

2. **Archive T4 cycle-2 items** — 52 items are bibliography, problem statements, and member boards from cycle 2. Already tagged `ciclo_2`. Archive.

3. **Clean Publicações board** — Archive or tag the ~20 "How to use" / "Purpose:" instruction cards. They're board usage guides, not articles.

### Short-term Actions (P1)

4. **T3 task→checklist conversion** — 18 LIKELY-TASK items on T3 appear to be Trello-imported action items (dates in 2025). Convert completed ones to checklists under their parent deliverable. Archive stale todos.

5. **Default cycle filter** — Add a board-level default filter to show only current cycle (cycle=3) items. Legacy items remain accessible but hidden by default.

6. **Hub de Comunicação tagging** — Apply unified tags to the 46 comms items. Most are social media posts that could use a `social_media` or `comunicacao` tag.

### Future Sprint (P2)

7. **T3 baseline dates** — 5 T3 deliverables have NULL baseline_date. Marcel Fleming needs to set delivery targets.

8. **Publicações pipeline audit** — 6 real article submissions are in `review` status. Verify curation workflow is active for these.

---

## 5. Methodology

**Classification rules applied**:
- `DELIVERABLE`: Has unified artifact tag (pesquisa, publicacao, framework, poc, webinar, ferramenta, workshop_artifact, artigo_academico, artigo_linkedin, entrega_final)
- `LIKELY-TASK`: Title starts with action verb (criar, definir, buscar, levantar, decidir, elaborar, organizar, identificar, redigir, refinar, revisar, submeter, preparar, distribuir, finalizar)
- `LIKELY-DELIVERABLE`: Title contains deliverable noun (artigo, framework, relatório, report, toolkit, matriz, playbook, webinar, infográfico, plataforma, publicação)
- `SHORT-NEEDS-REVIEW`: Title under 30 characters — likely labels or fragments
- `NEEDS-REVIEW`: Does not match any heuristic

**Data source**: Supabase `board_items` joined with `project_boards` and `board_item_tag_assignments` + `tags`. Excludes `status = 'archived'`.

---

## 6. Sanitation Applied — Verification (2026-03-15)

Migration `20260315120000_board_sanitation.sql` deployed to production. Results verified:

| Board | Before | After (visible) | Archived | Status |
|---|---|---|---|---|
| T1: Radar Tecnológico | 6 | 6 | 0 | Clean |
| T2: Agentes Autônomos | 4 | 4 | 0 | Clean |
| T3: TMO & PMO do Futuro | 52 | 5 | 47 | Sanitized |
| T4: Cultura & Change | 63 | 11 | 52 | Sanitized |
| T5: Talentos & Upskilling | 8 | 8 | 0 | Clean |
| T6: ROI & Portfólio | 150 | 8 | 142 | Sanitized |
| T7: Governança & Trustworthy AI | 9 | 9 | 0 | Clean |
| T8: Inclusão & Comunicação | 6 | 6 | 0 | Clean |
| Hub de Comunicação | 46 | 46 | 0 | Tagged (20 ciclo-2) |
| Publicações & Submissões PMI | 31 | 8 | 23 | Sanitized |
| **Total** | **375** | **111** | **264** | |

### Actions taken
- 56 artifacts tagged `entregavel_lider` (red system tag)
- T3: 21 task cards converted to checklist items inside 4 parent deliverables
- T3: 47 items archived (18 converted tasks + 2 standalone tasks + 3 cycle-2 deliverables + 24 miro-import)
- T4: 52 cycle-2 miro-import items archived
- T6: 142 cycle-2 miro-import items archived
- Publicações: 23 instruction/placeholder cards archived
- Comms: 20 cycle-2 posts tagged with `ciclo-2` in text tags array
