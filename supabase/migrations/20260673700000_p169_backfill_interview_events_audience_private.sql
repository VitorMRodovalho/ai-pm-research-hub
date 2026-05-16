-- p169 — Backfill type='entrevista' events: audience_level='leadership' + try link selection_application_id
-- Bug discovered 2026-05-16: calendar import created entrevista events with audience_level='all'
-- which made /attendance render "0/49 presentes" (treating 49 active members as expected).
-- UI hotfix (commit hides type='entrevista' from /attendance). This migration backfills
-- the DB rows to be semantically correct in case any other consumer queries them later.
-- Rollback: UPDATE events SET audience_level='all', visibility='all' WHERE type='entrevista' AND audience_level='leadership';

-- Step 1: tighten audience_level + visibility for all interview events
UPDATE public.events
SET
  audience_level = 'leadership',
  visibility = 'leadership'
WHERE type = 'entrevista'
  AND audience_level = 'all';

-- Step 2: try to backfill selection_application_id via title parsing
-- Title pattern: "Entrevista Núcleo IA - Ciclo 2026-1 (Candidate Name) [- suffix]"
-- ILIKE applicant_name + '%' for partial matches (handles trailing spaces/middle names)
UPDATE public.events e
SET selection_application_id = (
  SELECT sa.id FROM public.selection_applications sa
  WHERE sa.applicant_name ILIKE trim(both ' ' from substring(e.title from '\(([^)]+)\)')) || '%'
  ORDER BY sa.created_at DESC
  LIMIT 1
)
WHERE e.type = 'entrevista'
  AND e.selection_application_id IS NULL
  AND e.title ~ '\([^)]+\)';
