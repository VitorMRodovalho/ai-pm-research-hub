-- ============================================================================
-- V4 Phase 2 — Migration 2/5: initiatives table + seed from tribes
-- ADR: ADR-0005 (Initiative como Primitivo do Domínio)
-- Depends on: 20260413200000_v4_phase2_initiative_kinds.sql
-- Rollback: DROP TABLE public.initiatives CASCADE;
-- ============================================================================

-- initiatives is the universal container for any durable work group.
-- Tribes, study groups, congresses, workshops — all are initiatives with different kinds.
-- The legacy_tribe_id column bridges the old integer PK to the new UUID PK
-- during the transition period (Fase 2-6). Dropped in Fase 7.

CREATE TABLE public.initiatives (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind                  text NOT NULL REFERENCES public.initiative_kinds(slug) ON DELETE RESTRICT,
  organization_id       uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
                        REFERENCES public.organizations(id) ON DELETE RESTRICT,
  title                 text NOT NULL,
  description           text,
  status                text NOT NULL DEFAULT 'active'
                        CHECK (status IN ('draft', 'active', 'concluded', 'archived')),
  parent_initiative_id  uuid REFERENCES public.initiatives(id) ON DELETE SET NULL,
  legacy_tribe_id       integer UNIQUE,
  metadata              jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.initiatives IS 'V4: Universal container for durable work groups — tribes, study groups, congresses, workshops (ADR-0005). legacy_tribe_id bridges to old tribes.id during transition.';

-- Indexes
CREATE INDEX idx_initiatives_kind ON public.initiatives(kind);
CREATE INDEX idx_initiatives_org ON public.initiatives(organization_id);
CREATE INDEX idx_initiatives_status ON public.initiatives(status);
CREATE INDEX idx_initiatives_parent ON public.initiatives(parent_initiative_id) WHERE parent_initiative_id IS NOT NULL;
CREATE INDEX idx_initiatives_legacy_tribe ON public.initiatives(legacy_tribe_id) WHERE legacy_tribe_id IS NOT NULL;

-- RLS
ALTER TABLE public.initiatives ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read all active initiatives in their org
CREATE POLICY "initiatives_select_authenticated"
  ON public.initiatives FOR SELECT TO authenticated
  USING (true);

-- Org-scoped RESTRICTIVE policy (Fase 1 pattern)
CREATE POLICY "initiatives_org_scope"
  ON public.initiatives AS RESTRICTIVE FOR ALL TO authenticated
  USING (organization_id = public.auth_org() OR organization_id IS NULL)
  WITH CHECK (organization_id = public.auth_org());

-- Seed: migrate 8 existing tribes → initiatives of kind 'research_tribe'
-- All tribe-specific columns go into metadata jsonb for kind-specific storage
INSERT INTO public.initiatives (kind, organization_id, title, description, status, legacy_tribe_id, metadata)
SELECT
  'research_tribe',
  t.organization_id,
  t.name,
  t.notes,
  CASE WHEN t.is_active THEN 'active' ELSE 'archived' END,
  t.id,
  jsonb_build_object(
    'quadrant', t.quadrant,
    'quadrant_name', t.quadrant_name,
    'workstream_type', t.workstream_type,
    'leader_member_id', t.leader_member_id,
    'video_url', t.video_url,
    'video_duration', t.video_duration,
    'legacy_board_url', t.legacy_board_url,
    'meeting_schedule', t.meeting_schedule,
    'meeting_day', t.meeting_day,
    'meeting_time_start', t.meeting_time_start,
    'meeting_time_end', t.meeting_time_end,
    'whatsapp_url', t.whatsapp_url,
    'drive_url', t.drive_url,
    'miro_url', t.miro_url,
    'meeting_link', t.meeting_link,
    'name_i18n', t.name_i18n,
    'quadrant_name_i18n', t.quadrant_name_i18n
  )
FROM public.tribes t
ORDER BY t.id;

-- PostgREST reload
NOTIFY pgrst, 'reload schema';
