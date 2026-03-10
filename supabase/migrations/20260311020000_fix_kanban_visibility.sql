-- Fix Kanban visibility: two bugs preventing items from appearing
--
-- Bug 1: list_curation_board was never granted to authenticated role,
--         so the frontend silently fell back to list_pending_curation.
-- Bug 2: The 21 ingested presentations got curation_status='published'
--         (column default) instead of 'pending_review', making them
--         invisible to the fallback RPC's filter.

GRANT EXECUTE ON FUNCTION public.list_curation_board(text) TO authenticated;

UPDATE artifacts
SET curation_status = 'pending_review'
WHERE type = 'presentation'
  AND status = 'review'
  AND curation_status = 'published'
  AND submitted_at >= '2026-03-10';
