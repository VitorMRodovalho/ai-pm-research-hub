-- ============================================================================
-- V4 Phase 2 — Migration 3/5: Add initiative_id to domain tables + backfill
-- ADR: ADR-0005 (Initiative como Primitivo do Domínio)
-- Depends on: 20260413210000_v4_phase2_initiatives_table.sql
-- Rollback: For each table: ALTER TABLE public.<table> DROP COLUMN initiative_id;
-- ============================================================================

-- Strategy: Add initiative_id uuid column to all tables that currently have
-- tribe_id FK to tribes. Backfill from the initiatives.legacy_tribe_id bridge.
-- tribe_id columns remain intact — dual-write triggers (next migration) will
-- keep both columns in sync during the transition period.

-- Helper: reusable backfill pattern
-- For each table: ADD COLUMN → BACKFILL → INDEX

-- ── 1. events ──────────────────────────────────────────────────────────────
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.events e
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = e.tribe_id
  AND e.tribe_id IS NOT NULL
  AND e.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_events_initiative
  ON public.events(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── 2. meeting_artifacts ───────────────────────────────────────────────────
ALTER TABLE public.meeting_artifacts
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.meeting_artifacts ma
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = ma.tribe_id
  AND ma.tribe_id IS NOT NULL
  AND ma.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_meeting_artifacts_initiative
  ON public.meeting_artifacts(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── 3. tribe_deliverables ──────────────────────────────────────────────────
ALTER TABLE public.tribe_deliverables
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.tribe_deliverables td
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = td.tribe_id
  AND td.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_tribe_deliverables_initiative
  ON public.tribe_deliverables(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── 4. project_boards ──────────────────────────────────────────────────────
ALTER TABLE public.project_boards
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.project_boards pb
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = pb.tribe_id
  AND pb.tribe_id IS NOT NULL
  AND pb.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_project_boards_initiative
  ON public.project_boards(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── 5. webinars ────────────────────────────────────────────────────────────
ALTER TABLE public.webinars
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.webinars w
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = w.tribe_id
  AND w.tribe_id IS NOT NULL
  AND w.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_webinars_initiative
  ON public.webinars(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── 6. announcements ───────────────────────────────────────────────────────
ALTER TABLE public.announcements
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.announcements a
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = a.tribe_id
  AND a.tribe_id IS NOT NULL
  AND a.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_announcements_initiative
  ON public.announcements(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── 7. publication_submissions ─────────────────────────────────────────────
ALTER TABLE public.publication_submissions
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.publication_submissions ps
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = ps.tribe_id
  AND ps.tribe_id IS NOT NULL
  AND ps.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_publication_submissions_initiative
  ON public.publication_submissions(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── 8. pilots ──────────────────────────────────────────────────────────────
ALTER TABLE public.pilots
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.pilots p
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = p.tribe_id
  AND p.tribe_id IS NOT NULL
  AND p.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_pilots_initiative
  ON public.pilots(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── 9. hub_resources ───────────────────────────────────────────────────────
ALTER TABLE public.hub_resources
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.hub_resources hr
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = hr.tribe_id
  AND hr.tribe_id IS NOT NULL
  AND hr.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_hub_resources_initiative
  ON public.hub_resources(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── 10. broadcast_log ──────────────────────────────────────────────────────
ALTER TABLE public.broadcast_log
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.broadcast_log bl
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = bl.tribe_id
  AND bl.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_broadcast_log_initiative
  ON public.broadcast_log(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── 11. members (current tribe assignment) ─────────────────────────────────
ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.members m
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = m.tribe_id
  AND m.tribe_id IS NOT NULL
  AND m.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_members_initiative
  ON public.members(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── 12. public_publications ────────────────────────────────────────────────
ALTER TABLE public.public_publications
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.public_publications pp
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = pp.tribe_id
  AND pp.tribe_id IS NOT NULL
  AND pp.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_public_publications_initiative
  ON public.public_publications(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── 13. ia_pilots ──────────────────────────────────────────────────────────
ALTER TABLE public.ia_pilots
  ADD COLUMN IF NOT EXISTS initiative_id uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

UPDATE public.ia_pilots ip
SET initiative_id = i.id
FROM public.initiatives i
WHERE i.legacy_tribe_id = ip.tribe_id
  AND ip.tribe_id IS NOT NULL
  AND ip.initiative_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_ia_pilots_initiative
  ON public.ia_pilots(initiative_id) WHERE initiative_id IS NOT NULL;

-- ── PostgREST reload ───────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
