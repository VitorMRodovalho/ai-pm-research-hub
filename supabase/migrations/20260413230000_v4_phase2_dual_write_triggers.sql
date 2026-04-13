-- ============================================================================
-- V4 Phase 2 — Migration 4/5: Dual-write triggers (tribe_id ↔ initiative_id)
-- ADR: ADR-0005 (Initiative como Primitivo do Domínio)
-- Depends on: 20260413220000_v4_phase2_initiative_id_retrofit.sql
-- Rollback: DROP FUNCTION public.sync_initiative_from_tribe CASCADE;
--           DROP FUNCTION public.sync_tribe_from_initiative CASCADE;
-- ============================================================================

-- Two shared trigger functions handle bidirectional sync:
-- 1. sync_initiative_from_tribe: when tribe_id is set, auto-populate initiative_id
-- 2. sync_tribe_from_initiative: when initiative_id is set, auto-populate tribe_id
-- Both are BEFORE INSERT OR UPDATE triggers, so the resolved value is stored atomically.

CREATE OR REPLACE FUNCTION public.sync_initiative_from_tribe()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- Only resolve if tribe_id is provided and initiative_id is not
  IF NEW.tribe_id IS NOT NULL AND NEW.initiative_id IS NULL THEN
    SELECT id INTO NEW.initiative_id
    FROM public.initiatives
    WHERE legacy_tribe_id = NEW.tribe_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_tribe_from_initiative()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- Only resolve if initiative_id is provided and tribe_id is not
  IF NEW.initiative_id IS NOT NULL AND NEW.tribe_id IS NULL THEN
    SELECT legacy_tribe_id INTO NEW.tribe_id
    FROM public.initiatives
    WHERE id = NEW.initiative_id;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.sync_initiative_from_tribe() IS 'V4 dual-write: auto-populate initiative_id from tribe_id via legacy bridge';
COMMENT ON FUNCTION public.sync_tribe_from_initiative() IS 'V4 dual-write: auto-populate tribe_id from initiative_id via legacy bridge';

-- Apply triggers to all 13 retrofitted tables.
-- Order: sync_initiative fires first (a), sync_tribe fires second (b).

-- events
CREATE TRIGGER trg_a_sync_initiative_events
  BEFORE INSERT OR UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_events
  BEFORE INSERT OR UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- meeting_artifacts
CREATE TRIGGER trg_a_sync_initiative_meeting_artifacts
  BEFORE INSERT OR UPDATE ON public.meeting_artifacts
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_meeting_artifacts
  BEFORE INSERT OR UPDATE ON public.meeting_artifacts
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- tribe_deliverables
CREATE TRIGGER trg_a_sync_initiative_tribe_deliverables
  BEFORE INSERT OR UPDATE ON public.tribe_deliverables
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_tribe_deliverables
  BEFORE INSERT OR UPDATE ON public.tribe_deliverables
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- project_boards
CREATE TRIGGER trg_a_sync_initiative_project_boards
  BEFORE INSERT OR UPDATE ON public.project_boards
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_project_boards
  BEFORE INSERT OR UPDATE ON public.project_boards
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- webinars
CREATE TRIGGER trg_a_sync_initiative_webinars
  BEFORE INSERT OR UPDATE ON public.webinars
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_webinars
  BEFORE INSERT OR UPDATE ON public.webinars
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- announcements
CREATE TRIGGER trg_a_sync_initiative_announcements
  BEFORE INSERT OR UPDATE ON public.announcements
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_announcements
  BEFORE INSERT OR UPDATE ON public.announcements
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- publication_submissions
CREATE TRIGGER trg_a_sync_initiative_publication_submissions
  BEFORE INSERT OR UPDATE ON public.publication_submissions
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_publication_submissions
  BEFORE INSERT OR UPDATE ON public.publication_submissions
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- pilots
CREATE TRIGGER trg_a_sync_initiative_pilots
  BEFORE INSERT OR UPDATE ON public.pilots
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_pilots
  BEFORE INSERT OR UPDATE ON public.pilots
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- hub_resources
CREATE TRIGGER trg_a_sync_initiative_hub_resources
  BEFORE INSERT OR UPDATE ON public.hub_resources
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_hub_resources
  BEFORE INSERT OR UPDATE ON public.hub_resources
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- broadcast_log
CREATE TRIGGER trg_a_sync_initiative_broadcast_log
  BEFORE INSERT OR UPDATE ON public.broadcast_log
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_broadcast_log
  BEFORE INSERT OR UPDATE ON public.broadcast_log
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- members
CREATE TRIGGER trg_a_sync_initiative_members
  BEFORE INSERT OR UPDATE ON public.members
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_members
  BEFORE INSERT OR UPDATE ON public.members
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- public_publications
CREATE TRIGGER trg_a_sync_initiative_public_publications
  BEFORE INSERT OR UPDATE ON public.public_publications
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_public_publications
  BEFORE INSERT OR UPDATE ON public.public_publications
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- ia_pilots
CREATE TRIGGER trg_a_sync_initiative_ia_pilots
  BEFORE INSERT OR UPDATE ON public.ia_pilots
  FOR EACH ROW EXECUTE FUNCTION public.sync_initiative_from_tribe();
CREATE TRIGGER trg_b_sync_tribe_ia_pilots
  BEFORE INSERT OR UPDATE ON public.ia_pilots
  FOR EACH ROW EXECUTE FUNCTION public.sync_tribe_from_initiative();

-- PostgREST reload
NOTIFY pgrst, 'reload schema';
