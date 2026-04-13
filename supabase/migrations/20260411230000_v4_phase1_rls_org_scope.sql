-- ============================================================
-- Domain Model V4 — Fase 1 — Migration 3/N (RLS org scope)
-- ADR-0004: Organizations as First-Class — dual mode cutover
-- ============================================================
--
-- Escopo deste commit:
--   Ativar RLS filtering por organization_id = auth_org() em todas
--   as 40 tabelas de dominio que receberam a coluna nas Migrations
--   1, 2a e 2b.
--
-- Estrategia: RESTRICTIVE policy cross-cutting
--   Em vez de dropar+recriar as policies PERMISSIVE existentes
--   (muitas com USING (true) para acesso publico/anon legitimo),
--   adicionamos UMA policy RESTRICTIVE FOR ALL por tabela que eh
--   AND'd com todas as PERMISSIVE existentes.
--
--   Efeito pratico em single-org mode (auth_org() = UUID fixo Nucleo IA):
--     - SELECT: rows com org_id = Nucleo IA passam (todas, backfilled)
--     - INSERT: WITH CHECK forca org_id = Nucleo IA (DEFAULT ja cuida)
--     - UPDATE/DELETE: mesmo filtro
--
--   Efeito pratico em multi-org futuro:
--     - RESTRICTIVE enforca isolamento sem tocar PERMISSIVE layer
--     - auth_org() le JWT claim (Fase 1 cutover final — known gap)
--
-- Dual mode:
--   Policy permite organization_id IS NULL como rede de seguranca.
--   Qualquer row que escapou do backfill (improvavel, backfill foi 100%)
--   continua acessivel. Em cutover multi-org real, esse IS NULL
--   sera removido.
--
-- Por que RESTRICTIVE e nao dropar policies existentes:
--   Tables como courses, help_journeys, ia_pilots, portfolio_kpi_targets
--   tem USING (true) para exposicao publica legitima (anon marketing).
--   Dropar isso quebra landing pages e paginas publicas. RESTRICTIVE
--   eh o idioma correto do Postgres para security cross-cutting.
--
-- Pre-flight live check (2026-04-11, session 3 Fase 1):
--   Todas as 40 tabelas com rls_on=true (confirmado via pg_class).
--   Nenhum ENABLE RLS necessario nesta migration.
--
-- Rollback:
--   BEGIN;
--   DO $$
--   DECLARE t text; tables text[] := ARRAY[
--     'chapters','members','tribes','events','webinars',
--     'board_items','meeting_artifacts','tribe_deliverables',
--     'publication_submissions','public_publications','cycles',
--     'pilots','ia_pilots','project_boards','project_memberships',
--     'volunteer_applications','announcements','blog_posts',
--     'event_showcases','attendance','gamification_points',
--     'courses','partner_entities','change_requests',
--     'curation_review_log','board_lifecycle_events','board_sla_config',
--     'annual_kpi_targets','portfolio_kpi_targets',
--     'portfolio_kpi_quarterly_targets','selection_cycles',
--     'selection_applications','selection_committee',
--     'selection_evaluations','selection_interviews',
--     'selection_diversity_snapshots','member_activity_sessions',
--     'help_journeys','visitor_leads','comms_channel_config'
--   ];
--   BEGIN
--     FOREACH t IN ARRAY tables LOOP
--       EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
--         t || '_v4_org_scope', t);
--     END LOOP;
--   END $$;
--   COMMIT;
--
-- Autorizacao PM: Vitor em 2026-04-11 (sessao 3 de Fase 1).
-- Guardian pre-flight: GO com 2 riscos identificados (ambos mitigados
--   pela estrategia RESTRICTIVE — ver master doc).
-- Decisao JWT org_id claim: POSTERGADA (known gap, reconcilia multi-org).
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- STEP 1 — Aplicar RESTRICTIVE policy em todas as 40 tabelas
-- ------------------------------------------------------------
-- DO block iterativo para manter a migration uniforme e curta.
-- Idempotente: DROP IF EXISTS antes de CREATE garante re-runs safe.

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    -- Migration 1 (chapters)
    'chapters',
    -- Migration 2a (core critico)
    'members', 'tribes', 'events', 'webinars',
    -- Migration 2b (domain rest)
    'board_items', 'meeting_artifacts', 'tribe_deliverables',
    'publication_submissions', 'public_publications',
    'cycles', 'pilots', 'ia_pilots',
    'project_boards', 'project_memberships',
    'volunteer_applications',
    'announcements', 'blog_posts', 'event_showcases',
    'attendance', 'gamification_points',
    'courses', 'partner_entities', 'change_requests',
    'curation_review_log', 'board_lifecycle_events', 'board_sla_config',
    'annual_kpi_targets', 'portfolio_kpi_targets',
    'portfolio_kpi_quarterly_targets',
    'selection_cycles', 'selection_applications', 'selection_committee',
    'selection_evaluations', 'selection_interviews',
    'selection_diversity_snapshots',
    'member_activity_sessions', 'help_journeys', 'visitor_leads',
    'comms_channel_config'
  ];
  policy_name text;
BEGIN
  FOREACH t IN ARRAY tables LOOP
    policy_name := t || '_v4_org_scope';

    -- Drop idempotente
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.%I',
      policy_name, t
    );

    -- RESTRICTIVE FOR ALL: AND'd com qualquer PERMISSIVE existente.
    -- USING: enforca leitura/update/delete apenas do proprio org.
    -- WITH CHECK: enforca insert/update apenas do proprio org.
    -- "IS NULL" = dual mode (rede de seguranca para cutover).
    EXECUTE format(
      'CREATE POLICY %I ON public.%I '
      'AS RESTRICTIVE '
      'FOR ALL '
      'USING (organization_id = public.auth_org() OR organization_id IS NULL) '
      'WITH CHECK (organization_id = public.auth_org() OR organization_id IS NULL)',
      policy_name, t
    );

    RAISE NOTICE 'v4 org scope policy applied: %', t;
  END LOOP;
END $$;

-- ------------------------------------------------------------
-- STEP 2 — Sanity check: contar policies criadas
-- ------------------------------------------------------------
-- Deve retornar exatamente 40. Se nao, algo escapou.

DO $$
DECLARE
  policy_count int;
BEGIN
  SELECT count(*) INTO policy_count
  FROM pg_policy
  WHERE polname LIKE '%_v4_org_scope'
    AND polrelid::regclass::text LIKE 'public.%';

  IF policy_count <> 40 THEN
    RAISE EXCEPTION
      'v4 org scope: expected 40 policies, got %. Aborting migration.',
      policy_count;
  END IF;

  RAISE NOTICE 'v4 org scope: 40 RESTRICTIVE policies active';
END $$;

-- ------------------------------------------------------------
-- STEP 3 — Reload PostgREST schema cache
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- Post-deploy smoke checklist (executar manualmente):
--
-- 1. SELECT count(*) FROM pg_policy
--      WHERE polname LIKE '%_v4_org_scope'; -- deve retornar 40
--
-- 2. Transacao de isolamento (proof of work):
--    BEGIN;
--    INSERT INTO organizations (id, name, slug, is_active)
--      VALUES ('00000000-0000-0000-0000-000000000099',
--              'Test Org B', 'test-org-b', true);
--    INSERT INTO tribes (id, name, organization_id, status)
--      VALUES (gen_random_uuid(), '__v4_test_other_org__',
--              '00000000-0000-0000-0000-000000000099', 'active');
--    SET LOCAL ROLE authenticated;
--    SELECT count(*) FROM tribes WHERE name = '__v4_test_other_org__';
--    -- Deve retornar 0 (RESTRICTIVE bloqueia)
--    ROLLBACK;
--
-- 3. npm test — deve passar 779 (ou +8 com fixtures novos)
-- 4. npx astro build — 0 erros
-- 5. curl MCP initialize — HTTP 200
-- 6. Smoke de features estaveis (ver master doc)
-- ============================================================
