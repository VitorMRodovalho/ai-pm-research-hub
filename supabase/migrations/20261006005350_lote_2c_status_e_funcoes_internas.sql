-- Lote 2c (#2565, decisões do GP no lote 2b em 05/10/2026).
--
-- 1. Troca de status de submissão segue a regra de quem gerencia a submissão.
--    update_publication_submission_status só conferia o login. Passa a exigir a regra das outras
--    escritas em submissão (_can_manage_publication_submission): autor principal, quem a criou, a
--    gestão e a liderança de Publicações & Submissões. Vale para quem chama pela API
--    (_request_is_rest_caller(), #684). Chamadas internas seguem iguais. Base: a definição viva.
-- 2. Funções que só servem a quem tem login perdem o EXECUTE de PUBLIC e anon. authenticated e
--    service_role têm EXECUTE explícito em todas e seguem iguais. Nenhuma aparece em policy ou view,
--    e as chamadas internas partem de funções SECURITY DEFINER. get_cpmai_leaderboard fica de fora:
--    a W6b (#1383) a manteve com anon de propósito, como feed público.

CREATE OR REPLACE FUNCTION public.update_publication_submission_status(p_submission_id uuid, p_new_status submission_status, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller_id uuid; v_member_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  -- Quem gerencia a submissão: autor principal, quem a criou, a gestão e a liderança de P&S.
  IF public._request_is_rest_caller() AND NOT public._can_manage_publication_submission(p_submission_id) THEN
    RAISE EXCEPTION 'Not authorized to manage this submission';
  END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;
  UPDATE public.publication_submissions SET status = p_new_status WHERE id = p_submission_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Submission not found'; END IF;
END; $function$;

REVOKE EXECUTE ON FUNCTION public._artia_safe_monthly_metrics(integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.add_publication_submission_author(uuid, uuid, integer, boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_card_detail(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_card_full_history(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_gamification_leaderboard(integer, integer, text, text, text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_meeting_detail(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_my_attendance_history(integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_my_cards() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_my_tasks(text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_portfolio_planned_vs_actual(integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_tribe_events_timeline(integer, integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_event_mandatory_for_member(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_active_boards() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_meeting_action_items(uuid, text, uuid, text, boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_meetings_with_notes(integer, text, text, boolean, integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.remove_publication_submission_author(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.submit_cpmai_mock_score(uuid, integer, integer, integer, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_cpmai_progress(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_publication_submission(uuid, text, text, text, text, date, date, date, date, numeric, numeric, text, text, text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_publication_submission_status(uuid, public.submission_status, text) FROM PUBLIC, anon;
