-- p124 phase 2 — schema for trilingual titles on events + tribe_deliverables.
-- Pattern follows tribes.name_i18n / initiatives.metadata.name_i18n: jsonb {pt,en,es}.
-- For events: only `title_i18n` (agenda_text/minutes_text are long-form content, stay PT).
-- For tribe_deliverables: title_i18n + description_i18n (descriptions are short, worth translating).
--
-- Backfill strategy: trigger auto-populates `*_i18n.pt` from canonical column on
-- INSERT/UPDATE so the columns are never NULL, and downstream RPCs/frontend
-- can always read i18n[code] with fallback. EN/ES filled incrementally via
-- per-row backfill (phase 3) or admin UI later.
--
-- Rollback:
--   DROP TRIGGER trg_events_title_i18n_sync ON public.events;
--   DROP FUNCTION public._events_title_i18n_sync;
--   ALTER TABLE public.events DROP COLUMN title_i18n;
--   DROP TRIGGER trg_deliverables_i18n_sync ON public.tribe_deliverables;
--   DROP FUNCTION public._deliverables_i18n_sync;
--   ALTER TABLE public.tribe_deliverables DROP COLUMN title_i18n, DROP COLUMN description_i18n;

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS title_i18n jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.tribe_deliverables
  ADD COLUMN IF NOT EXISTS title_i18n jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS description_i18n jsonb NOT NULL DEFAULT '{}'::jsonb;

-- Trigger for events: keep title_i18n.pt in sync with canonical title
CREATE OR REPLACE FUNCTION public._events_title_i18n_sync()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.title IS NOT NULL THEN
    NEW.title_i18n := jsonb_set(COALESCE(NEW.title_i18n, '{}'::jsonb), '{pt}', to_jsonb(NEW.title));
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_events_title_i18n_sync ON public.events;
CREATE TRIGGER trg_events_title_i18n_sync
  BEFORE INSERT OR UPDATE OF title ON public.events
  FOR EACH ROW EXECUTE FUNCTION public._events_title_i18n_sync();

-- Trigger for tribe_deliverables: keep title_i18n.pt + description_i18n.pt in sync
CREATE OR REPLACE FUNCTION public._deliverables_i18n_sync()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.title IS NOT NULL THEN
    NEW.title_i18n := jsonb_set(COALESCE(NEW.title_i18n, '{}'::jsonb), '{pt}', to_jsonb(NEW.title));
  END IF;
  IF NEW.description IS NOT NULL THEN
    NEW.description_i18n := jsonb_set(COALESCE(NEW.description_i18n, '{}'::jsonb), '{pt}', to_jsonb(NEW.description));
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_deliverables_i18n_sync ON public.tribe_deliverables;
CREATE TRIGGER trg_deliverables_i18n_sync
  BEFORE INSERT OR UPDATE OF title, description ON public.tribe_deliverables
  FOR EACH ROW EXECUTE FUNCTION public._deliverables_i18n_sync();

-- One-time backfill: populate *_i18n.pt for all existing rows
UPDATE public.events
SET title_i18n = jsonb_build_object('pt', title)
WHERE title IS NOT NULL AND NOT (title_i18n ? 'pt');

UPDATE public.tribe_deliverables
SET title_i18n = jsonb_build_object('pt', title)
WHERE title IS NOT NULL AND NOT (title_i18n ? 'pt');

UPDATE public.tribe_deliverables
SET description_i18n = jsonb_build_object('pt', description)
WHERE description IS NOT NULL AND NOT (description_i18n ? 'pt');

NOTIFY pgrst, 'reload schema';
