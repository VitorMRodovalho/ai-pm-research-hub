# SQL Architecture Needs Board

Status date: 2026-03-08

## Purpose
Force explicit backend/SQL decisions for every sprint feature so we never ship only frontend surfaces without architecture alignment.

## Legend
- `DB-backed`: already supported by tables/functions/policies in production
- `Frontend/Embed`: mostly UI + external embed/env, no dedicated DB model yet
- `Needs SQL`: requires schema/RLS/RPC/migration work before being considered architecture-complete

## Board

| Feature | Current State | Backend Reality | Needs SQL? | Required SQL/Architecture Work | Owner Sprint |
|---|---|---|---|---|---|
| `S-AN1` Announcements | Completed | `announcements` table + ACL policies + global banner read path | No | Keep policy audits in ACL checklist | Continuous |
| `S-ADM2` Leadership Snapshot | Completed | Reads `members`, `course_progress`, `gamification_points` | No (v1) | Optional materialized view for performance if dataset grows | Backlog |
| `S-REP1` VRMS Export | Completed | Uses existing `events`, `attendance`, `members` | No (v1) | Optional reporting view for audit reproducibility | Backlog |
| `S-RM4` Admin ACL | Completed | `has_min_tier` + `current_member_tier_rank` + policies in prod | No | Extend parity to any new privileged table | Continuous |
| `S10` Credly Auto Sync | Completed | Edge functions + cron + DB hardening index | No | Track function versioning and secret rotation cadence | Ops |
| `S-COM6` Media Dashboard | Partial v3 | Route `/admin/comms`, iframe, KPI endpoint via env, and RPC fallback | **Yes** | `COMMS_METRICS_V1` SQL pack created (`comms_metrics_daily` + RLS + `comms_metrics_latest()`); pending production apply and ingestion source rollout | Active |
| `S-PA2` Executive ROI Dashboards | In Progress (v1 SQL foundation ready) | Curated views/RPCs implemented (`vw_exec_*`, `exec_*`) with admin+ gate | **Yes** | Apply migration in production, run audit, and rewire `/admin` executive panel to RPC-backed models | Active |
| `S-DR1` Disaster Recovery | Planned | Docs only | **Yes** | Add backup/restore verification SQL scripts + runbook sign-off checklist | Next |
| `S-KNW6` AI Knowledge Ingestion MVP | Partial (v1 foundation deployed) | Migration applied + function deployed + smoke validated in production | **Yes** | Add source connector automation + embeddings refresh and operational monitoring | Wave 5 |
| `S-KNW7` Internal RAG Assistant | In Progress (v1 text retrieval ready) | UI `/ai-assistant` + RPC `knowledge_search_text` migration pack prepared | **Yes** | Apply `knowledge-assistant-v1` in production, run audit, and evolve to hybrid ranking (`tsvector + vector`) once embedding refresh is operational | Wave 5 |
| `S-KNW8` Friction Insight Mining | In Progress (v1 SQL + sync function) | `knowledge_insights` fact table + scoring/taxonomy RPCs in production + `sync-knowledge-insights` function and cron workflow | **Yes** | Complete function production deploy + secret wiring + smoke/audit evidence for sustained operation | Wave 5 |
| `S-OPS2` AI Cost Guardrails | Planned | No quota model yet | **Yes** | Add usage/budget tables (`ai_usage_daily`, `ai_budget_limits`) + alerting query views for no-cost threshold control | Wave 6 |

## Immediate SQL Backlog (priority)
1. `COMMS_METRICS_V1` migration pack
   - table: `public.comms_metrics_daily`
   - fields: `metric_date`, `channel`, `audience`, `reach`, `engagement_rate`, `leads`, `source`, `payload`
   - unique key: `(metric_date, channel, source)`
   - RLS: admin+ read
2. `comms_metrics_latest()` RPC/view
   - returns normalized KPI payload consumed by `/admin/comms`
3. `EXEC_ROI_V1` analytic views
   - `vw_exec_funnel`
   - `vw_exec_cert_timeline`
   - `vw_exec_skills_radar`
4. `KNOWLEDGE_INGEST_V1` (YouTube-first MVP)
   - source table for raw transcript metadata
   - normalized chunk table + vector-ready columns
   - ingestion run ledger and retry-safe constraints

## Sprint Gate (mandatory)
A feature cannot be marked `Completed` unless this board says either:
- `Needs SQL = No`, or
- SQL work is delivered with migration + audit + rollback artifacts.
