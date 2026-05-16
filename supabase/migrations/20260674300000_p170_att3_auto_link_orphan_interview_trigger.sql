-- p170 ATT-3 — Auto-link orphan interview events via title parsing trigger
--
-- Context: ATT-1 (trigger sync interview → events) cobre o futuro. ATT-2 (admin UI link manual)
-- cobre histórico identificado. ATT-3 = defense in depth — qualquer evento type='entrevista'
-- inserted/updated com selection_application_id IS NULL e título no formato "...(Nome)..."
-- tenta auto-link via pg_trgm similarity threshold > 0.7.
--
-- Cobre paths legacy:
--   • Manual admin INSERT/UPDATE via /admin/events ou SQL console
--   • CSV imports que não usam schedule_interview()
--   • Calendar import EF retroativos (passa pelo trigger ao recriar)
--
-- Safeguards:
--   • Threshold 0.7 (alto — evita false positive em nomes ambíguos)
--   • Audit log em admin_audit_log com action='auto_link_interview_event_title_parse'
--   • Skip se MÚLTIPLOS matches com similar score (evita ambiguidade Paulo X vs Paulo Y)
--   • Skip se selection_application_id já preenchido
--   • Skip se title não tem parênteses
--
-- Rollback:
--   DROP TRIGGER IF EXISTS trg_auto_link_interview_event ON public.events;
--   DROP FUNCTION IF EXISTS public.auto_link_interview_event();

CREATE OR REPLACE FUNCTION public.auto_link_interview_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_parsed_name text;
  v_top_app_id uuid;
  v_top_score numeric;
  v_runner_up_score numeric;
  v_top_app_name text;
BEGIN
  -- Skip if not an interview, already linked, or title has no parenthetical
  IF NEW.type <> 'entrevista' THEN RETURN NEW; END IF;
  IF NEW.selection_application_id IS NOT NULL THEN RETURN NEW; END IF;
  IF NEW.title IS NULL OR NEW.title !~ '\([^)]+\)' THEN RETURN NEW; END IF;

  v_parsed_name := trim(both ' ' from substring(NEW.title from '\(([^)]+)\)'));
  IF v_parsed_name IS NULL OR length(v_parsed_name) < 3 THEN RETURN NEW; END IF;

  -- Find top match + runner up via pg_trgm similarity
  SELECT app_id, score, runner_up
    INTO v_top_app_id, v_top_score, v_runner_up_score
  FROM (
    SELECT sa.id AS app_id,
           similarity(LOWER(sa.applicant_name), LOWER(v_parsed_name)) AS score,
           LAG(similarity(LOWER(sa.applicant_name), LOWER(v_parsed_name)), 1) OVER (
             ORDER BY similarity(LOWER(sa.applicant_name), LOWER(v_parsed_name)) DESC
           ) AS runner_up
    FROM selection_applications sa
    WHERE similarity(LOWER(sa.applicant_name), LOWER(v_parsed_name)) > 0.5
    ORDER BY score DESC
    LIMIT 2
  ) ranked
  WHERE ranked.runner_up IS NULL  -- top row (LAG returned NULL because nothing before it)
  LIMIT 1;

  -- Conservative: only auto-link if top match > 0.7 AND clearly best (gap >= 0.15 vs runner up)
  IF v_top_app_id IS NULL OR v_top_score < 0.7 THEN
    RETURN NEW;
  END IF;

  -- Re-query the runner up to compute gap
  SELECT MAX(similarity(LOWER(sa.applicant_name), LOWER(v_parsed_name)))
    INTO v_runner_up_score
  FROM selection_applications sa
  WHERE sa.id <> v_top_app_id
    AND similarity(LOWER(sa.applicant_name), LOWER(v_parsed_name)) > 0.5;

  IF v_runner_up_score IS NOT NULL AND (v_top_score - v_runner_up_score) < 0.15 THEN
    -- Too ambiguous (e.g., "Paulo X" vs "Paulo Y") — skip auto-link, leave for manual ATT-2
    RETURN NEW;
  END IF;

  -- Get application name for audit log
  SELECT applicant_name INTO v_top_app_name FROM selection_applications WHERE id = v_top_app_id;

  -- Auto-link
  NEW.selection_application_id := v_top_app_id;

  -- Audit (DEFERRED — INSERT into admin_audit_log fires AFTER trigger completes)
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL,  -- system, not actor
    'auto_link_interview_event_title_parse',
    'event',
    NEW.id,
    jsonb_build_object(
      'before', jsonb_build_object('selection_application_id', NULL),
      'after',  jsonb_build_object('selection_application_id', v_top_app_id)
    ),
    jsonb_build_object(
      'parsed_name', v_parsed_name,
      'applicant_name', v_top_app_name,
      'similarity_score', v_top_score,
      'runner_up_score', COALESCE(v_runner_up_score, 0),
      'event_title', NEW.title,
      'method', 'auto_link_p170_att3'
    )
  );

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.auto_link_interview_event() IS
  'p170 ATT-3 — auto-link entrevista events via pg_trgm similarity on parsed (Nome) prefix. Threshold 0.7 + gap 0.15 vs runner-up. Audit em admin_audit_log com method=auto_link_p170_att3.';

DROP TRIGGER IF EXISTS trg_auto_link_interview_event ON public.events;
CREATE TRIGGER trg_auto_link_interview_event
  BEFORE INSERT OR UPDATE OF title, type, selection_application_id ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_link_interview_event();

COMMENT ON TRIGGER trg_auto_link_interview_event ON public.events IS
  'p170 ATT-3 — defense in depth para legacy paths que criem events entrevista sem selection_application_id. Threshold conservador (0.7 + gap 0.15) evita false positive.';

NOTIFY pgrst, 'reload schema';
