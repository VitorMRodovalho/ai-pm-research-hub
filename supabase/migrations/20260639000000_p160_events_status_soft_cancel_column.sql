-- p160 (2026-05-14): events.status column for soft-cancel semantics
--
-- PM requirement: tribe leaders cancel recurring meetings (weekly obligation
-- broken when life happens). Today's drop_event_instance hard-deletes the row,
-- losing audit trail. Soft-cancel preserves the row + attendance history so the
-- weekly cadence "hole" is visible without penalizing members.
--
-- Business rule (enforced in get_tribe_attendance_grid by next migration):
--  • status='scheduled' (default) → grid renders normally
--  • status='cancelled' AND no scheduled tribe event in same ISO week →
--    event appears in grid with 'na' (traço) cells. No penalty to rate%.
--  • status='cancelled' AND another scheduled tribe event exists in same
--    ISO week (replan) → cancelled event hidden from grid; replan handles it.
--  • status='completed' (reserved, not used yet — future hook for "event
--    finished" lifecycle distinct from "still scheduled")

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled', 'cancelled', 'completed')),
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_by uuid REFERENCES public.members(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cancellation_reason text;

CREATE INDEX IF NOT EXISTS idx_events_status_date ON public.events(status, date) WHERE status <> 'scheduled';
CREATE INDEX IF NOT EXISTS idx_events_status_initiative ON public.events(initiative_id, status, date) WHERE status = 'cancelled';

COMMENT ON COLUMN public.events.status IS 'Event lifecycle (p160). scheduled=default, cancelled=soft-cancelled (preserved for audit), completed=terminal-finished (reserved).';
COMMENT ON COLUMN public.events.cancelled_at IS 'Set when cancel_event_occurrence runs. NULL otherwise.';
COMMENT ON COLUMN public.events.cancelled_by IS 'members.id of GP/tribe-leader who soft-cancelled. NULL otherwise.';
COMMENT ON COLUMN public.events.cancellation_reason IS 'Optional free-text reason for cancellation. NULL otherwise.';

NOTIFY pgrst, 'reload schema';
