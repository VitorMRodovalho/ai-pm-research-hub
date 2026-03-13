# KPI Agreement — GP-Sponsor (12/Oct/2025)

## Parties
- **GP (Gerente de Projeto):** Vitor Maia Rodovalho
- **Sponsor (Presidente PMI-GO):** Ivan Lourenço

## Date
12 de outubro de 2025

## Scope
Annual goals for 2026. Continuous monitoring via `/#kpis`.

---

## 9 KPIs Agreed

| # | Metric Key | Label (pt) | Target | Unit | Formula / Data Source |
|---|-----------|-----------|--------|------|----------------------|
| 1 | `chapters_participating` | Capítulos PMI | 8 | count | `COUNT(DISTINCT chapter) FROM members WHERE current_cycle_active` |
| 2 | `partner_entities` | Entidades Parceiras | 3 | count | `COUNT(*) FROM partner_entities WHERE entity_type IN ('academia','governo','empresa') AND status='active'` |
| 3 | `certification_trail` | Trilha Mini Cert. IA | 70% | percent | `AVG(completed_courses / total_courses) * 100` for eligible members |
| 4 | `cpmai_certified` | Certificados CPMAI | 2 | count | `COUNT(*) FROM members WHERE cpmai_certified = true AND current_cycle_active` |
| 5 | `articles_published` | Artigos Publicados | 10 | count | `COUNT(*) FROM board_items WHERE curation_status='approved'` (cycle-filtered) |
| 6 | `webinars_completed` | Webinares/Talks | 6 | count | `COUNT(*) FROM events WHERE type='webinar'` (cycle-filtered) |
| 7 | `ia_pilots` | Pilotos IA | 3 | count | From `site_config` key `ia_pilots_count` (default: 1 = Hub) |
| 8 | `meeting_hours` | Horas de Encontros | 90h | hours | `SUM(duration_actual) / 60` for events in cycle (raw hours, not per-attendee) |
| 9 | `impact_hours` | Horas de Impacto | 1800h | hours | `SUM(duration_minutes / 60)` per attendee present (duration x attendees) |

## Color Thresholds (UI)
- Green: >= 70% of target
- Yellow: >= 40% of target
- Red: < 40% of target

## Notes
- Targets are annual (2026). Monitoring is continuous via the `/#kpis` section on the home page.
- Partner entities of type `pmi_chapter` are tracked separately and do NOT count toward the partner_entities KPI target (chapters are already KPI #1).
- Certification trail uses aggregated course progress from the `courses` + `course_progress` tables, not binary `cpmai_certified`.
- CPMAI certification (KPI #4) is a separate binary count — how many members hold the full CPMAI credential.
- Meeting hours (KPI #8) counts raw event duration. Impact hours (KPI #9) multiplies by attendees present.
