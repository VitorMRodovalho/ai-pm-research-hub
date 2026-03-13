-- ═══════════════════════════════════════════════════════════════
-- W106 Sprint E — Fix duration_actual defaults
-- Backfill NULL duration_actual with duration_minutes for past events
-- Add trigger to auto-set duration_actual = duration_minutes on insert
-- ═══════════════════════════════════════════════════════════════

-- 1. Backfill: set duration_actual = duration_minutes where NULL
UPDATE public.events
SET duration_actual = duration_minutes
WHERE duration_actual IS NULL;

-- 2. Set column default
ALTER TABLE public.events
  ALTER COLUMN duration_actual SET DEFAULT 60;

-- 3. Trigger: auto-copy duration_minutes to duration_actual on insert if not specified
CREATE OR REPLACE FUNCTION public.events_default_duration_actual()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.duration_actual IS NULL THEN
    NEW.duration_actual := NEW.duration_minutes;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_events_default_duration_actual ON public.events;
CREATE TRIGGER trg_events_default_duration_actual
  BEFORE INSERT ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION public.events_default_duration_actual();
