-- p169 — Trigger to auto-set audience_level='leadership' for interview/1on1 events
-- Bug discovered 2026-05-16: calendar import + manual type edits create entrevista/1on1
-- events that inherit DB default audience_level='all', causing /attendance to render
-- "0/49 presentes" (49 active members as expected attendees for a 1:1 interview).
-- Trigger guards against future regressions regardless of insertion path:
--   - import-calendar-legacy EF
--   - calendar_event_importer.ts script
--   - manual admin UI edits
--   - any CSV/spreadsheet bulk import
-- Rollback: DROP TRIGGER trg_interview_audience_private ON events; DROP FUNCTION enforce_interview_audience_private();

CREATE OR REPLACE FUNCTION public.enforce_interview_audience_private()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  -- Only when type indicates a private 1:1/interview event
  IF NEW.type IN ('entrevista', 'interview', '1on1', 'parceria') THEN
    -- Force audience_level/visibility to 'leadership' (no broad attendance expectation)
    IF NEW.audience_level IS NULL OR NEW.audience_level = 'all' THEN
      NEW.audience_level := 'leadership';
    END IF;
    IF NEW.visibility IS NULL OR NEW.visibility = 'all' THEN
      NEW.visibility := 'leadership';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_interview_audience_private ON public.events;
CREATE TRIGGER trg_interview_audience_private
  BEFORE INSERT OR UPDATE OF type, audience_level, visibility ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_interview_audience_private();

COMMENT ON FUNCTION public.enforce_interview_audience_private() IS
  'p169 — auto-set audience_level=leadership for entrevista/1on1/parceria events. Prevents /attendance UI from rendering "0/49 presentes" false negatives. Bug fix 2026-05-16.';
