-- Fix: board_lifecycle_events action CHECK constraint
-- The delete_board_item RPC inserts action='archived' but the constraint
-- only allowed 'item_archived'. Add 'archived' and 'deleted' values.

ALTER TABLE public.board_lifecycle_events
  DROP CONSTRAINT IF EXISTS board_lifecycle_events_action_check;

ALTER TABLE public.board_lifecycle_events
  ADD CONSTRAINT board_lifecycle_events_action_check
  CHECK (action IN (
    'board_archived','board_restored',
    'item_archived','item_restored',
    'archived','deleted',
    'created','status_change',
    'forecast_update','actual_completion',
    'mirror_created'
  ));
