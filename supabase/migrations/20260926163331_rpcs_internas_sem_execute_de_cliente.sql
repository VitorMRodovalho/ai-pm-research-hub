-- RPCs internas deixam de ser executaveis por clientes, e create_initiative ganha gate de autoridade.
--
-- Cada funcao abaixo teve o grafo de chamadores revisado (app, Edge Functions, outras funcoes, cron): as
-- cinco primeiras nao tem chamador cliente legitimo, entao perdem o EXECUTE de PUBLIC/anon/authenticated
-- e mantem service_role (funcao SECURITY DEFINER chamada por outra roda como a dona e segue passando).
-- create_initiative tem um unico chamador cliente, a tela admin/initiatives, restrita ao tier manager;
-- o gate espelha essa regra (manage_platform) para chamador REST. O resto do corpo e identico a captura
-- anterior (20260805000234).

-- _get_peer_review_eligibility: chamada so por dispatch_peer_review_invitations, que roda como dona.
REVOKE EXECUTE ON FUNCTION public._get_peer_review_eligibility(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._get_peer_review_eligibility(uuid) TO service_role;

-- anonymize_application_for_ai_training: chamada so pela Edge Function pmi-ai-analyze-research, com service_role.
REVOKE EXECUTE ON FUNCTION public.anonymize_application_for_ai_training(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymize_application_for_ai_training(uuid) TO service_role;

-- check_application_score_consistency: sem chamador no app, no banco ou no cron.
REVOKE EXECUTE ON FUNCTION public.check_application_score_consistency() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_application_score_consistency() TO service_role;

-- process_interview_reminders_1h: chamada so pelo cron interview-reminder-1h-q15min, como postgres.
REVOKE EXECUTE ON FUNCTION public.process_interview_reminders_1h() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_interview_reminders_1h() TO service_role;

-- v4_notify_expiring_affiliations: chamada so pelo cron v4-affiliation-expiry-notify, como postgres.
REVOKE EXECUTE ON FUNCTION public.v4_notify_expiring_affiliations(boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.v4_notify_expiring_affiliations(boolean) TO service_role;

-- create_initiative
CREATE OR REPLACE FUNCTION public.create_initiative(
  p_kind text,
  p_title text,
  p_description text DEFAULT NULL::text,
  p_metadata jsonb DEFAULT '{}'::jsonb,
  p_parent_initiative_id uuid DEFAULT NULL::uuid,
  p_visibility text DEFAULT 'standard'::text
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_kind_row record;
  v_count integer;
  v_new_id uuid;
  v_legacy_tribe_id int;
  v_board_scope text;
  v_domain_key text;
BEGIN
  -- Chamador REST (GUC de role authenticated/anon) precisa de manage_platform: e a regra que o unico
  -- consumidor cliente, a tela admin/initiatives (tier manager), ja aplica. service_role e conexao
  -- direta seguem passando.
  IF public._request_is_rest_caller() THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: create_initiative requires manage_platform' USING ERRCODE = '42501';
    END IF;
  END IF;
  SELECT * INTO v_kind_row FROM public.initiative_kinds WHERE slug = p_kind;
  IF v_kind_row IS NULL THEN
    RAISE EXCEPTION 'Unknown initiative kind: %', p_kind USING ERRCODE = 'P0004';
  END IF;

  -- #785 PR-4: validate the visibility enum (the column CHECK enforces it too, but a clean
  -- ERRCODE is friendlier to callers than a constraint-violation).
  IF p_visibility IS NULL OR p_visibility NOT IN ('standard', 'confidential') THEN
    RAISE EXCEPTION 'Invalid visibility "%": must be standard or confidential', p_visibility
      USING ERRCODE = 'P0007';
  END IF;

  -- #708: research_tribe é tribe-scoped — precisa do bridge legacy_tribe_id (via
  -- admin_upsert_legacy_tribe). create_initiative nunca seta legacy_tribe_id, então
  -- criar uma tribo por aqui produziria uma tribo SEM legacy_tribe_id, cujo board
  -- nem 'tribe' (trigger exige legacy_tribe_id) nem 'global' (scope errado p/ tribo)
  -- é válido. Fail-loud em vez de criar uma tribo meia-quebrada.
  IF p_kind = 'research_tribe' THEN
    RAISE EXCEPTION 'research_tribe deve ser criada via o bridge de tribo (admin_upsert_legacy_tribe), não create_initiative'
      USING ERRCODE = 'P0006';
  END IF;

  IF v_kind_row.max_concurrent_per_org IS NOT NULL THEN
    SELECT count(*) INTO v_count
    FROM public.initiatives
    WHERE kind = p_kind
      AND organization_id = public.auth_org()
      AND status IN ('draft', 'active');

    IF v_count >= v_kind_row.max_concurrent_per_org THEN
      RAISE EXCEPTION 'Maximum concurrent initiatives of kind "%" reached (limit: %)',
        p_kind, v_kind_row.max_concurrent_per_org USING ERRCODE = 'P0005';
    END IF;
  END IF;

  INSERT INTO public.initiatives (kind, title, description, metadata, parent_initiative_id, organization_id, visibility)
  VALUES (p_kind, p_title, p_description, p_metadata, p_parent_initiative_id, public.auth_org(), p_visibility)
  RETURNING id INTO v_new_id;

  IF v_kind_row.has_board THEN
    -- #708: derivar board_scope da tribe-scoping real (um dual-write trigger pode ter
    -- setado legacy_tribe_id para kinds de tribo). Antes ficava no default 'tribe' e o
    -- trigger de taxonomy rejeitava todo board de kind não-tribo.
    SELECT legacy_tribe_id INTO v_legacy_tribe_id FROM public.initiatives WHERE id = v_new_id;
    IF v_legacy_tribe_id IS NOT NULL THEN
      v_board_scope := 'tribe';
      v_domain_key  := nullif(p_metadata->>'domain_key', '');
    ELSE
      v_board_scope := 'global';
      v_domain_key  := coalesce(nullif(p_metadata->>'domain_key', ''), 'cross_functional');
    END IF;

    INSERT INTO public.project_boards (board_name, initiative_id, source, is_active, organization_id, board_scope, domain_key)
    VALUES (p_title, v_new_id, 'manual', true, public.auth_org(), v_board_scope, v_domain_key);
  END IF;

  RETURN v_new_id;
END;
$function$;
