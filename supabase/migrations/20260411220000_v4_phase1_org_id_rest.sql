-- ============================================================
-- Domain Model V4 — Fase 1 — Migration 2b/N (expanded scope)
-- ADR-0004: Organizations as First-Class
-- ============================================================
--
-- Escopo deste commit (35 tabelas de dominio mecanicas):
--
--   Operacionais / conteudo:
--     board_items, meeting_artifacts, tribe_deliverables,
--     publication_submissions, public_publications, cycles,
--     pilots, ia_pilots, project_boards, project_memberships,
--     volunteer_applications, announcements, blog_posts,
--     event_showcases, attendance, gamification_points,
--     courses, partner_entities, change_requests,
--     curation_review_log
--
--   Board governance:
--     board_lifecycle_events, board_sla_config
--
--   KPIs:
--     annual_kpi_targets, portfolio_kpi_targets,
--     portfolio_kpi_quarterly_targets
--
--   Seleção (6 tabelas):
--     selection_cycles, selection_applications, selection_committee,
--     selection_evaluations, selection_interviews,
--     selection_diversity_snapshots
--
--   Engajamento / analytics:
--     member_activity_sessions, help_journeys, visitor_leads
--
--   Config operacional de comms (NAO infra global):
--     comms_channel_config
--
-- Escopo EXPANDIDO vs plano original (guardian audit 2026-04-11):
--   PM aprovou Opcao A: cobrir TODAS tabelas de dominio de uma vez
--   para evitar dividas da Fase 1 e Migration 3 corretiva.
--   Plano original listava 19 tabelas; guardian descobriu mais 16
--   via inventario de ALTER TABLE em migrations.
--
-- Excluidas (infra tecnica / escopo global, permanecem sem org_id):
--   site_config, releases, admin_audit_log, data_anomaly_log,
--   notifications, notification_preferences, mcp_usage_log,
--   email_webhook_events, campaign_*, legacy_*, trello_import_log
--
-- Pre-flight via MCP (2026-04-11):
--   Nenhuma das 35 tabelas tem organization_id. Clean slate.
--
-- Estrategia: mesma de 2a.
--   ADD COLUMN NOT NULL DEFAULT '<uuid Nucleo IA>' + FK + index.
--   DEFAULT permanece ate cutover multi-org.
--
-- Rollback:
--   Para cada tabela:
--     ALTER TABLE public.<t> DROP COLUMN IF EXISTS organization_id;
--
-- Autorizacao PM: Vitor em 2026-04-11 (Opcao A do guardian).
-- ============================================================

BEGIN;

-- DO block mecanico: aplica o mesmo padrao em todas as 35 tabelas.
-- Evita 105 linhas repetitivas e reduz superficie de erro de copy-paste.
DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    -- Operacionais / conteudo
    'board_items','meeting_artifacts','tribe_deliverables',
    'publication_submissions','public_publications','cycles',
    'pilots','ia_pilots','project_boards','project_memberships',
    'volunteer_applications','announcements','blog_posts',
    'event_showcases','attendance','gamification_points',
    'courses','partner_entities','change_requests',
    'curation_review_log',
    -- Board governance
    'board_lifecycle_events','board_sla_config',
    -- KPIs
    'annual_kpi_targets','portfolio_kpi_targets',
    'portfolio_kpi_quarterly_targets',
    -- Selecao
    'selection_cycles','selection_applications','selection_committee',
    'selection_evaluations','selection_interviews',
    'selection_diversity_snapshots',
    -- Engajamento / analytics
    'member_activity_sessions','help_journeys','visitor_leads',
    -- Config operacional
    'comms_channel_config'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format(
      'ALTER TABLE public.%I
         ADD COLUMN IF NOT EXISTS organization_id uuid NOT NULL
         DEFAULT %L
         REFERENCES public.organizations(id) ON DELETE RESTRICT',
      t, '2b4f58ab-7c45-4170-8718-b77ee69ff906'
    );
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I ON public.%I(organization_id)',
      'idx_' || t || '_organization_id', t
    );
    EXECUTE format(
      'COMMENT ON COLUMN public.%I.organization_id IS %L',
      t, 'ADR-0004: organizacao dona. Single-org mode ate cutover.'
    );
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
