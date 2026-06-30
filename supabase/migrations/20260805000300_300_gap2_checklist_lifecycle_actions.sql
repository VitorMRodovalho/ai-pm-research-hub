-- =====================================================================
-- #300 Gap 2 — unbreak update_checklist_item / delete_checklist_item
-- =====================================================================
-- Both RPCs write board_lifecycle_events rows with:
--   update_checklist_item  -> action = 'activity_updated'
--   delete_checklist_item  -> action = 'activity_deleted'
-- but board_lifecycle_events_action_check (last set by p197,
-- 20260715000000) omits BOTH values. Result: EVERY call to either
-- MCP-exposed RPC throws board_lifecycle_events_action_check violation —
-- a live, 100%-reproducible broken-RPC / data-integrity bug
-- (discovered p225, 2026-05-23; grounded live this session 2026-06-29).
--
-- Fix: extend the CHECK to include the two values, consistent with the
-- existing activity_* family (activity_added/completed/reopened/assigned).
-- Widening an IN-list CHECK never fails on existing data. Drop+recreate
-- per constraint-change discipline.
-- =====================================================================

ALTER TABLE public.board_lifecycle_events
  DROP CONSTRAINT IF EXISTS board_lifecycle_events_action_check;

ALTER TABLE public.board_lifecycle_events
  ADD CONSTRAINT board_lifecycle_events_action_check
  CHECK (action = ANY (ARRAY[
    'board_archived', 'board_restored', 'item_archived', 'item_restored',
    'archived', 'deleted', 'created', 'status_change', 'forecast_update',
    'actual_completion', 'mirror_created', 'assigned', 'member_assigned',
    'member_unassigned', 'submitted_for_curation', 'reviewer_assigned',
    'curation_review', 'curation_approved', 'moved_out', 'moved_in',
    'baseline_set', 'baseline_locked', 'baseline_changed', 'forecast_changed',
    'title_changed', 'portfolio_flag_changed', 'activity_added',
    'activity_completed', 'activity_reopened', 'activity_assigned',
    -- #300 Gap 2: written by update_checklist_item / delete_checklist_item
    'activity_updated', 'activity_deleted',
    'comment_added', 'comment_edited', 'comment_deleted',
    -- p197 fix B1: distinct from 'curation_review' (curator scoring)
    'peer_review_completed',
    'leader_review_completed'
  ]));
