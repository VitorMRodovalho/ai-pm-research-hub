-- Jornadas fatia D: aposenta a pré-jornada gamificada (decisão do GP em 20/11/2026; a #873 deixa de ser "reviver depois").
-- A pré-jornada morreu quando a FK onboarding_progress.step_key -> onboarding_steps (#2245) passou a impedir as chaves
-- dela. Medido em 21/11: 0 de 905 linhas com metadata.phase ou metadata.xp, 0 linhas fora do catálogo e 0 linhas de
-- gamification_points ligadas a ela. Nenhum dado é apagado, e o XP do ledger não muda.
--   1. check_pre_onboarding_auto_steps fica só com o ramo de perfil (o retorno mantém a mesma forma);
--   2. get_candidate_onboarding_progress perde o agregado pre_onboarding, os campos xp e phase e a ordenação morta;
--   3. get_pre_onboarding_leaderboard sai: 0 chamadores no pg_proc; no repositório, só o componente e a ferramenta do
--      MCP que saem na mesma PR;
--   4. seed_pre_onboarding_steps sai: 0 chamadores no pg_proc (get_application_onboarding_pct só a cita em comentário)
--      e 0 no repositório; o INSERT dela falharia na FK.
-- Cada corpo é a captura cujo md5 bate com o vivo em 21/11.

CREATE OR REPLACE FUNCTION public.check_pre_onboarding_auto_steps(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_completed int := 0;
  v_member record;
  v_profile_complete boolean;
  v_caller_id uuid;
  v_cron_context boolean;
BEGIN
  -- p179 LGPD hardening: defense-in-depth caller auth gate.
  -- Structural protection: REVOKE'd from authenticated. This gate catches
  -- regressions if GRANT changes + ensures internal callers (PERFORM) cannot
  -- bypass when invoked outside the canonical pipeline contexts.
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

  IF NOT v_cron_context THEN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: caller is not a registered member';
    END IF;

    IF v_caller_id <> p_member_id
       AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: cannot probe another member''s onboarding';
    END IF;
  END IF;

  SELECT id INTO v_member FROM members WHERE id = p_member_id;

  IF v_member.id IS NULL THEN
    RETURN json_build_object('error', 'Member not found');
  END IF;

  -- Jornadas fatia D: os ramos create_account, setup_credly, explore_platform e read_blog saíram. Eram chaves fora do
  -- catálogo, que a FK de onboarding_progress.step_key impede de existir, então nunca fechavam nada.
  -- Step: complete_profile. Jornadas fatia C: a regra única (_member_profile_ready, os 7 campos que a assinatura
  -- do Termo exige), só em etapa aberta e só onde a etapa vale para o papel da jornada (#3152).
  v_profile_complete := public._member_profile_ready(p_member_id);

  UPDATE onboarding_progress op
  SET status = 'completed', completed_at = now(), updated_at = now(),
      metadata = COALESCE(op.metadata, '{}'::jsonb) || jsonb_build_object('completed_via', 'perfil_pronto_para_o_termo')
  WHERE op.member_id = p_member_id AND op.step_key = 'complete_profile' AND op.status IN ('pending', 'overdue')
    AND v_profile_complete
    AND EXISTS (SELECT 1 FROM onboarding_steps s
                WHERE s.id = 'complete_profile'
                  AND public.onboarding_step_applies(s.applies_to_role, public._onboarding_journey_role(p_member_id)));
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'complete_profile' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  RETURN json_build_object(
    'auto_completed', v_completed,
    'member_id', p_member_id,
    'profile_complete', v_profile_complete
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_candidate_onboarding_progress(p_member_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_mid uuid;
  v_caller uuid;
  v_member_role text;
  v_result json;
BEGIN
  SELECT id INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  v_mid := COALESCE(p_member_id, v_caller);

  IF v_mid <> v_caller
     AND NOT public.can_by_member(v_caller, 'write', NULL, NULL)
     AND NOT public.can_by_member(v_caller, 'manage_member', NULL, NULL) THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  -- #3156: o recorte de etapa usa o papel da jornada (#3152), não o cache de autoridade.
  v_member_role := public._onboarding_journey_role(v_mid);

  -- First run auto-detection
  PERFORM check_pre_onboarding_auto_steps(v_mid);

  -- Jornadas fatia D: saíram o agregado pre_onboarding e os campos xp e phase de cada etapa. Nenhuma linha de
  -- onboarding_progress carrega metadata.xp ou metadata.phase, então eles devolviam sempre 0 e 'onboarding'.
  SELECT json_build_object(
    'member_id', v_mid,
    'steps', coalesce((
      SELECT json_agg(json_build_object(
        'step_key', op.step_key,
        'status', op.status,
        'completed_at', op.completed_at,
        'sla_deadline', op.sla_deadline
      ) ORDER BY
        CASE op.step_key
          WHEN 'complete_profile' THEN 2
          WHEN 'code_of_conduct' THEN 7
          WHEN 'volunteer_term' THEN 8
          WHEN 'vep_acceptance' THEN 9
          WHEN 'first_meeting' THEN 10
          WHEN 'meet_tribe' THEN 11
          WHEN 'start_trail' THEN 12
          ELSE 99
        END
      )
      FROM onboarding_progress op
      WHERE op.member_id = v_mid
    ), '[]'::json),
    'onboarding', json_build_object(
      'total', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid
        AND step_key IN (SELECT id FROM onboarding_steps s WHERE public.onboarding_step_applies(s.applies_to_role, v_member_role))),
      'completed', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid
        AND step_key IN (SELECT id FROM onboarding_steps s WHERE public.onboarding_step_applies(s.applies_to_role, v_member_role))
        AND status IN ('completed', 'skipped'))
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

DROP FUNCTION public.get_pre_onboarding_leaderboard();

DROP FUNCTION public.seed_pre_onboarding_steps(uuid, uuid);

NOTIFY pgrst, 'reload schema';
