-- ============================================================
-- Domain Model V4 — Fase 1 — Migration 2a/N (core critical)
-- ADR-0004: Organizations as First-Class
-- ============================================================
--
-- Escopo deste commit:
--   Adicionar organization_id NOT NULL + FK + index nas 4 tabelas
--   de dominio mais criticas (nucleo do modelo):
--     - members   (71 rows)
--     - tribes    (8 rows)
--     - events    (267 rows)
--     - webinars  (6 rows)
--
-- Estrategia de backfill:
--   ADD COLUMN NOT NULL DEFAULT '<uuid Nucleo IA>' faz backfill
--   atomico de todas as linhas existentes com o UUID fixo.
--   O DEFAULT permanece (single-org mode) — remove-se no cutover
--   multi-org (pos-Fase 1).
--
-- Por que 2a separado de 2b:
--   Estas 4 tabelas sao o nucleo critico. Smoke obrigatorio
--   (build + tests 779/0 + MCP initialize) entre 2a e 2b.
--   Se 2a quebra algo, reverter e investigar antes de prosseguir
--   com as 35 tabelas de 2b.
--
-- Pre-flight executado via MCP (2026-04-11):
--   SELECT column_name FROM information_schema.columns
--     WHERE column_name='organization_id' AND table_schema='public';
--   → apenas 'chapters' (Migration 1). Core 2a: zero colunas.
--
-- Rollback:
--   ALTER TABLE public.members   DROP COLUMN IF EXISTS organization_id;
--   ALTER TABLE public.tribes    DROP COLUMN IF EXISTS organization_id;
--   ALTER TABLE public.events    DROP COLUMN IF EXISTS organization_id;
--   ALTER TABLE public.webinars  DROP COLUMN IF EXISTS organization_id;
--   (indices caem junto por CASCADE)
--
-- Autorizacao PM: Vitor em 2026-04-11 (sessao 2 de Fase 1).
-- Guardian audit: Opcao A (escopo expandido) aprovada pelo PM.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- members
-- ------------------------------------------------------------
ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS organization_id uuid NOT NULL
    DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'
    REFERENCES public.organizations(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_members_organization_id
  ON public.members(organization_id);

COMMENT ON COLUMN public.members.organization_id IS
  'ADR-0004: organizacao dona deste membro. Single-org mode ate cutover — sempre Nucleo IA.';

-- ------------------------------------------------------------
-- tribes
-- ------------------------------------------------------------
ALTER TABLE public.tribes
  ADD COLUMN IF NOT EXISTS organization_id uuid NOT NULL
    DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'
    REFERENCES public.organizations(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_tribes_organization_id
  ON public.tribes(organization_id);

COMMENT ON COLUMN public.tribes.organization_id IS
  'ADR-0004: organizacao dona desta tribo.';

-- ------------------------------------------------------------
-- events
-- ------------------------------------------------------------
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS organization_id uuid NOT NULL
    DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'
    REFERENCES public.organizations(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_events_organization_id
  ON public.events(organization_id);

COMMENT ON COLUMN public.events.organization_id IS
  'ADR-0004: organizacao dona deste evento.';

-- ------------------------------------------------------------
-- webinars
-- ------------------------------------------------------------
ALTER TABLE public.webinars
  ADD COLUMN IF NOT EXISTS organization_id uuid NOT NULL
    DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'
    REFERENCES public.organizations(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_webinars_organization_id
  ON public.webinars(organization_id);

COMMENT ON COLUMN public.webinars.organization_id IS
  'ADR-0004: organizacao dona deste webinar.';

-- ------------------------------------------------------------
-- PostgREST schema reload
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

COMMIT;
