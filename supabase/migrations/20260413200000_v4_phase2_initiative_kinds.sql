-- ============================================================================
-- V4 Phase 2 — Migration 1/5: initiative_kinds config table
-- ADR: ADR-0005 (Initiative como Primitivo do Domínio)
-- Rollback: DROP TABLE public.initiative_kinds CASCADE;
-- ============================================================================

-- initiative_kinds defines the valid types of initiatives.
-- Each kind carries config for what features are available (board, attendance, etc).
-- New kinds can be added via UI in Fase 6 (ADR-0009).

CREATE TABLE public.initiative_kinds (
  slug              text PRIMARY KEY,
  display_name      text NOT NULL,
  description       text,
  icon              text,
  default_duration_days integer,
  max_concurrent_per_org integer,
  has_board         boolean NOT NULL DEFAULT false,
  has_meeting_notes boolean NOT NULL DEFAULT false,
  has_deliverables  boolean NOT NULL DEFAULT false,
  has_attendance    boolean NOT NULL DEFAULT false,
  has_certificate   boolean NOT NULL DEFAULT false,
  custom_fields_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
  lifecycle_states  text[] NOT NULL DEFAULT '{draft,active,concluded,archived}'::text[],
  organization_id   uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
                    REFERENCES public.organizations(id) ON DELETE RESTRICT,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.initiative_kinds IS 'V4: Config-driven initiative types (ADR-0005/ADR-0009). Each kind defines what features an initiative of that type supports.';

-- RLS
ALTER TABLE public.initiative_kinds ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read all kinds in their org
CREATE POLICY "initiative_kinds_select_authenticated"
  ON public.initiative_kinds FOR SELECT TO authenticated
  USING (true);

-- Org-scoped RESTRICTIVE policy (same pattern as Fase 1 Migration 3)
CREATE POLICY "initiative_kinds_org_scope"
  ON public.initiative_kinds AS RESTRICTIVE FOR ALL TO authenticated
  USING (organization_id = public.auth_org() OR organization_id IS NULL)
  WITH CHECK (organization_id = public.auth_org());

-- Seed: 4 initial kinds matching current and near-future use cases
INSERT INTO public.initiative_kinds (slug, display_name, description, icon, default_duration_days, max_concurrent_per_org, has_board, has_meeting_notes, has_deliverables, has_attendance, has_certificate) VALUES
  ('research_tribe', 'Tribo de Pesquisa', 'Grupo permanente de pesquisa em tema específico de IA & GP. Cadência semanal, board kanban, entregas por ciclo.', 'microscope', NULL, 10, true, true, true, true, true),
  ('study_group', 'Grupo de Estudos', 'Grupo temporário com foco em certificação ou tema específico. Duração limitada, entregas definidas.', 'book-open', 120, 5, true, true, true, true, true),
  ('congress', 'Congresso / Evento', 'Evento presencial ou híbrido com comitê organizador, trilhas e submissões.', 'calendar-days', 180, 3, true, true, true, false, false),
  ('workshop', 'Workshop', 'Sessão prática de curta duração, geralmente vinculada a uma tribo ou congresso.', 'wrench', 1, 20, false, true, false, true, false);

-- PostgREST reload
NOTIFY pgrst, 'reload schema';
