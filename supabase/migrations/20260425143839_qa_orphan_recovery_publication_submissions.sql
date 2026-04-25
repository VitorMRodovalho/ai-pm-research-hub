-- Track Q-A Batch M — orphan recovery: publication submissions (3 fns)
--
-- Final batch — captures the last 3 orphan functions in publication
-- submission CRUD surface (update + add author + remove author). Bodies
-- preserved verbatim from `pg_get_functiondef` — no behavior change.
--
-- After this migration, orphan baseline is 0 (all 92 documented orphans
-- have at least one CREATE FUNCTION migration capture). The Q-C contract
-- test ALLOWLIST_BASELINE_SIZE will be decremented to 0 in this batch's
-- companion changes.
--
-- Notes:
-- - All 3 are SECURITY DEFINER. Authority gate is permissive (`is_active`
--   member only — no role/designation gate). Surface assumes calling
--   context is curated (admin UI). Phase B candidate: tighten to authoring
--   member or curator.

CREATE OR REPLACE FUNCTION public.add_publication_submission_author(p_submission_id uuid, p_member_id uuid, p_author_order integer DEFAULT 2, p_is_corresponding boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid;
  v_caller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.members WHERE auth_id = v_caller_id AND is_active = true) THEN
    RAISE EXCEPTION 'Not an active member';
  END IF;

  INSERT INTO public.publication_submission_authors (submission_id, member_id, author_order, is_corresponding)
  VALUES (p_submission_id, p_member_id, p_author_order, p_is_corresponding)
  ON CONFLICT (submission_id, member_id) DO UPDATE SET
    author_order = EXCLUDED.author_order,
    is_corresponding = EXCLUDED.is_corresponding
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.remove_publication_submission_author(p_submission_id uuid, p_member_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  DELETE FROM public.publication_submission_authors
  WHERE submission_id = p_submission_id AND member_id = p_member_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_publication_submission(p_id uuid, p_title text DEFAULT NULL::text, p_abstract text DEFAULT NULL::text, p_target_name text DEFAULT NULL::text, p_target_url text DEFAULT NULL::text, p_submission_date date DEFAULT NULL::date, p_review_deadline date DEFAULT NULL::date, p_acceptance_date date DEFAULT NULL::date, p_presentation_date date DEFAULT NULL::date, p_estimated_cost_brl numeric DEFAULT NULL::numeric, p_actual_cost_brl numeric DEFAULT NULL::numeric, p_cost_paid_by text DEFAULT NULL::text, p_reviewer_feedback text DEFAULT NULL::text, p_doi_or_url text DEFAULT NULL::text, p_board_item_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.members WHERE auth_id = v_caller_id AND is_active = true) THEN
    RAISE EXCEPTION 'Not an active member';
  END IF;

  UPDATE public.publication_submissions SET
    title = COALESCE(p_title, title),
    abstract = COALESCE(p_abstract, abstract),
    target_name = COALESCE(p_target_name, target_name),
    target_url = COALESCE(p_target_url, target_url),
    submission_date = COALESCE(p_submission_date, submission_date),
    review_deadline = COALESCE(p_review_deadline, review_deadline),
    acceptance_date = COALESCE(p_acceptance_date, acceptance_date),
    presentation_date = COALESCE(p_presentation_date, presentation_date),
    estimated_cost_brl = COALESCE(p_estimated_cost_brl, estimated_cost_brl),
    actual_cost_brl = COALESCE(p_actual_cost_brl, actual_cost_brl),
    cost_paid_by = COALESCE(p_cost_paid_by, cost_paid_by),
    reviewer_feedback = COALESCE(p_reviewer_feedback, reviewer_feedback),
    doi_or_url = COALESCE(p_doi_or_url, doi_or_url),
    board_item_id = COALESCE(p_board_item_id, board_item_id),
    updated_at = now()
  WHERE id = p_id;
END;
$function$;
