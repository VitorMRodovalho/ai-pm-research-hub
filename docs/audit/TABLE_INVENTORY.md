# W139 — Table & View Inventory

**Data:** 2026-03-14
**Método:** Cross-reference `information_schema.tables` + `pg_stat_user_tables` vs frontend `.from()` calls

---

## Resumo

| Métrica | Valor |
|---------|-------|
| Tabelas no schema public | 74 |
| Views no schema public | 9 |
| Materialized views | 1 (`cycle_tribe_dim`) |
| Tabelas referenciadas pelo frontend | 38 |
| Tabelas NÃO referenciadas diretamente | 36 (maioria acessada via RPCs) |

---

## Tabelas Referenciadas pelo Frontend que NÃO Existem

| Referência | Tipo Real | Arquivo | Impacto |
|-----------|-----------|---------|---------|
| `active_members` | **NÃO EXISTE** | `workspace.astro:309`, `AttendanceForm.tsx:95` | ⚠️ Silently fails — count returns null, member list empty |
| `publication_submission_events` | **NÃO EXISTE** | `PublicationsBoardIsland.tsx:200` | ⚠️ Silently fails — event data not loaded |
| `cycle_tribe_dim` | Materialized view | `teams.astro:115` | ✅ OK — funciona |
| `documents` | Storage bucket | `artifacts.astro:707`, `admin/index.astro:2508` | ✅ OK — `sb.storage.from()` |

### Ações Necessárias

1. **`active_members`**: Criar view simples:
   ```sql
   CREATE VIEW active_members AS
   SELECT id, name, email, tribe_id, operational_role, designations, chapter, photo_url
   FROM members WHERE is_active = true AND current_cycle_active = true;
   ```

2. **`publication_submission_events`**: Criar tabela ou remover referência. O RPC `upsert_publication_submission_event` existe no DB mas a tabela alvo não.

---

## Inventário Completo de Tabelas

### Tabelas Core (uso frequente)

| Tabela | Rows | Frontend? | RPCs? | Status |
|--------|------|-----------|-------|--------|
| members | 68 | ✅ | ✅ | ✅ Ativo |
| tribes | 8 | ✅ | ✅ | ✅ Ativo |
| tribe_selections | 35 | ✅ | ✅ | ✅ Ativo |
| events | 161 | ✅ | ✅ | ✅ Ativo |
| attendance | 759 | ✅ | ✅ | ✅ Ativo |
| board_items | 364 | ✅ | ✅ | ✅ Ativo |
| board_item_assignments | 21 | — | ✅ | ✅ Ativo (via RPCs) |
| project_boards | 13 | — | ✅ | ✅ Ativo (via RPCs) |
| cycles | 4 | ✅ | ✅ | ✅ Ativo |
| site_config | 14 | ✅ | ✅ | ✅ Ativo |
| notifications | 12 | — | ✅ | ✅ Ativo (via RPCs) |
| gamification_points | 265 | ✅ | ✅ | ✅ Ativo |

### Tabelas de Conteúdo

| Tabela | Rows | Frontend? | RPCs? | Status |
|--------|------|-----------|-------|--------|
| hub_resources | 330 | ✅ | ✅ | ✅ Ativo |
| blog_posts | 1 | ✅ | — | ✅ Ativo |
| artifacts | 29 | ✅ | ✅ | ✅ Ativo |
| public_publications | 7 | — | ✅ | ✅ Ativo |
| meeting_artifacts | 0 | — | ✅ | ✅ Ativo (via RPC) |
| courses | 8 | ✅ | — | ✅ Ativo |
| course_progress | 103 | ✅ | — | ✅ Ativo |
| certificates | 0 | ✅ | — | ⚠️ Vazio |
| ia_pilots | 1 | ✅ | — | ✅ Ativo |
| help_journeys | 7 | — | ✅ | ✅ Ativo |
| home_schedule | 1 | ✅ | — | ✅ Ativo |

### Tabelas de Comunicação/Campanhas

| Tabela | Rows | Frontend? | RPCs? | Status |
|--------|------|-----------|-------|--------|
| campaign_templates | 5 | ✅ | ✅ | ✅ Ativo |
| campaign_sends | 0 | ✅ | ✅ | ✅ Ativo |
| campaign_recipients | 0 | — | ✅ | ✅ Ativo (via RPC) |
| broadcast_log | 21 | ✅ | ✅ | ✅ Ativo |
| comms_channel_config | 3 | — | ✅ | ✅ Ativo |
| comms_metrics_daily | 5 | ✅ | ✅ | ✅ Ativo |
| comms_metrics_ingestion_log | 5 | — | ✅ | ✅ Ativo |
| communication_templates | 3 | — | ✅ | ✅ Ativo |
| announcements | 1 | ✅ | — | ✅ Ativo |

### Tabelas de Processo Seletivo

| Tabela | Rows | Frontend? | RPCs? | Status |
|--------|------|-----------|-------|--------|
| selection_cycles | 1 | — | ✅ | ✅ Ativo |
| selection_applications | 62 | — | ✅ | ✅ Ativo |
| selection_committee | 2 | — | ✅ | ✅ Ativo |
| selection_evaluations | 159 | — | ✅ | ✅ Ativo |
| selection_interviews | 0 | — | ✅ | ✅ Ativo |
| selection_diversity_snapshots | 0 | — | ✅ | ⚠️ Vazio |
| volunteer_applications | 146 | — | ✅ | ✅ Ativo |

### Tabelas de Governança/Pipeline

| Tabela | Rows | Frontend? | RPCs? | Status |
|--------|------|-----------|-------|--------|
| member_cycle_history | 124 | ✅ | — | ✅ Ativo |
| onboarding_progress | 0 | ✅ | ✅ | ⚠️ Vazio |
| partner_entities | 17 | — | ✅ | ✅ Ativo |
| notification_preferences | 0 | ✅ | ✅ | ⚠️ Vazio |
| portfolio_kpi_targets | 9 | — | ✅ | ✅ Ativo |
| portfolio_kpi_quarterly_targets | 36 | — | ✅ | ✅ Ativo |
| data_anomaly_log | 0 | — | ✅ | ✅ Ativo |
| taxonomy_tags | 20 | — | ✅ | ✅ Ativo |
| tribe_deliverables | 4 | — | ✅ | ✅ Ativo |
| tribe_meeting_slots | 11 | ✅ | — | ✅ Ativo |

### Tabelas de Ingestão/Governança Avançada (backend-only)

| Tabela | Rows | Status |
|--------|------|--------|
| ingestion_source_controls | 7 | ✅ Backend-only |
| ingestion_source_sla | 7 | ✅ Backend-only |
| ingestion_remediation_escalation_matrix | 3 | ✅ Backend-only |
| knowledge_assets | 1 | ✅ Backend-only |
| knowledge_chunks | 1 | ✅ Backend-only |
| knowledge_ingestion_runs | 10 | ✅ Backend-only |
| knowledge_insights | 2 | ✅ Backend-only |
| knowledge_insights_ingestion_log | 1 | ✅ Backend-only |
| data_quality_audit_snapshots | 0 | ✅ Backend-only |
| data_retention_policy | 6 | ✅ Backend-only |
| release_readiness_policies | 1 | ✅ Backend-only |

### Tabelas Legadas/Auxiliares

| Tabela | Rows | Status |
|--------|------|--------|
| legacy_tribes | 6 | ✅ Histórico — mapeamento Ciclo 1-2 |
| trello_import_log | 5 | ✅ Histórico — log de importação |
| admin_links | 1 | ✅ Usado via RPC `list_admin_links` |
| board_lifecycle_events | 2 | ✅ Usado via triggers |
| board_sla_config | 0 | ⚠️ Vazio — configurado mas não usado |
| board_source_tribe_map | 5 | ✅ Usado via triggers |
| board_taxonomy_alerts | 0 | ⚠️ Vazio — sem alertas ativos |
| change_requests | 1 | ✅ Governance |
| curation_review_log | 0 | ⚠️ Vazio — curation não iniciada |
| project_memberships | 7 | ✅ Ativo |
| tribe_continuity_overrides | 2 | ✅ Usado via RPCs |
| tribe_lineage | 2 | ✅ Usado via RPCs |
| visitor_leads | 0 | ⚠️ Vazio — lead capture não ativo |

---

## Views

| View | Status |
|------|--------|
| `gamification_leaderboard` | ✅ Referenciada por frontend |
| `impact_hours_summary` | ✅ Referenciada por frontend |
| `impact_hours_total` | ✅ Referenciada por frontend |
| `member_attendance_summary` | ✅ Referenciada por frontend |
| `public_members` | ✅ Referenciada por frontend |
| `recurring_event_groups` | ✅ Usada por RPCs |
| `vw_exec_cert_timeline` | ✅ Usada por RPCs |
| `vw_exec_funnel` | ✅ Usada por RPCs |
| `vw_exec_skills_radar` | ✅ Usada por RPCs |
| `cycle_tribe_dim` (materialized) | ✅ Referenciada por frontend |

---

## Colunas `role` / `roles` Existentes

| Tabela | Coluna | Legítima? |
|--------|--------|-----------|
| `board_item_assignments.role` | ✅ Sim (author, reviewer, contributor) |
| `member_attendance_summary.role` | ✅ Sim (computed via `compute_legacy_role()`) |
| `project_memberships.role` | ✅ Sim (member role in project team) |
| `selection_committee.role` | ✅ Sim (lead, member, observer) |

Nenhuma referência à coluna dropada `members.role`.
