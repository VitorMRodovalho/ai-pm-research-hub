-- #3147, segunda fatia: três ajustes da revisão de segurança ao ciclo de fim de vínculo, antes de a chave ser ligada.
--
-- 1. _drive_revocation_notify: o aviso deixa de ser calado por um aviso de outro episódio. Conta só outra concessão do
--    mesmo par (membro, iniciativa) com item ainda aberto (pending ou approved) e detectado a até 7 dias deste. No
--    "foi encerrado" (p_closing_now), só um aviso de "foi encerrado" já dado conta: o "termina em 7 dias" não cala o
--    aviso de que o acesso saiu hoje.
-- 2. enqueue_membership_drive_revocations, passo b2: cada item liberado (falho ou "manter" de quem voltou ao roster)
--    ganha uma linha no admin_audit_log com o estado de antes, porque o próprio item passa a dizer engagement_restored.
-- 3. enqueue_membership_drive_revocations, passo e: relê a visibilidade da iniciativa. O item avisado com 7 dias cuja
--    iniciativa ficou confidencial depois do aviso é aprovado neste ciclo, e o item grava a confidencialidade e o
--    prazo de fato. Quem sai assim antes do prazo avisado recebe o aviso de "foi encerrado" no mesmo ciclo (decisão
--    do GP de 23/11/2026), pelo mesmo helper, que deixa passar o "foi encerrado" depois de um "7 dias".
--
-- Fora isso, as duas funções ficam como na 20261123013234. A chave site_config.drive_membership_revoke_enabled não muda.

CREATE OR REPLACE FUNCTION public._drive_revocation_notify(p_revocation_id uuid, p_closing_now boolean)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c_episode constant interval := interval '7 days';
  v         record;
BEGIN
  SELECT x.id, x.member_id, x.initiative_id, x.due_at, x.detected_at, i.title, m.member_status
    INTO v
    FROM public.drive_membership_revocations x
    JOIN public.initiatives i ON i.id = x.initiative_id
    LEFT JOIN public.members m ON m.id = x.member_id
   WHERE x.id = p_revocation_id;
  IF v.id IS NULL OR v.member_id IS NULL THEN RETURN false; END IF;
  -- já avisado por outra concessão do mesmo par NO MESMO EPISÓDIO: item ainda aberto e detectado perto deste. Um item
  -- fechado (revogado, cancelado, falho) é de um episódio que já acabou e não cala o aviso novo. No "foi encerrado",
  -- só um aviso de "foi encerrado" já dado conta (o prazo igual à hora do aviso): quem recebeu "termina em 7 dias"
  -- e perde o acesso hoje fica sabendo.
  IF EXISTS (SELECT 1 FROM public.drive_membership_revocations o
              WHERE o.id <> v.id AND o.member_id = v.member_id AND o.initiative_id = v.initiative_id
                AND o.notified_at IS NOT NULL
                AND o.status IN ('pending','approved')
                AND o.detected_at BETWEEN v.detected_at - c_episode AND v.detected_at + c_episode
                AND (NOT p_closing_now OR o.due_at <= o.notified_at)) THEN
    RETURN false;
  END IF;
  PERFORM public.create_notification(
    p_recipient_id => v.member_id,
    p_type         => 'drive_access_revocation_scheduled'::text,
    p_title        => CASE WHEN p_closing_now
                        THEN 'Seu acesso à pasta de ' || v.title || ' no Drive foi encerrado'
                        ELSE 'Seu acesso à pasta de ' || v.title || ' no Drive termina em 7 dias' END,
    p_body         => CASE
                        WHEN p_closing_now AND v.member_status IN ('active','alumni')
                          THEN 'Seu vínculo com ' || v.title || ' terminou, e o acesso à pasta dela no Drive sai hoje. Se for engano, fale com a gestão do Núcleo.'
                        WHEN p_closing_now
                          THEN 'A gestão do Núcleo encerrou seu acesso à pasta de ' || v.title || ' no Drive. Se for engano, fale com a gestão do Núcleo.'
                        ELSE 'Seu vínculo com ' || v.title || ' terminou, então o acesso à pasta dela no Drive será removido em '
                             || to_char(v.due_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY')
                             || '. Se você continua na iniciativa, fale com a liderança dela ou com a gestão do Núcleo antes dessa data.' END,
    p_link         => NULL::text,
    p_source_type  => 'drive_membership_revocations'::text,
    p_source_id    => v.id);
  RETURN true;
END;
$function$;
REVOKE ALL ON FUNCTION public._drive_revocation_notify(uuid, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._drive_revocation_notify(uuid, boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_membership_drive_revocations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c_notice      constant interval := interval '7 days';
  v_cfg         jsonb;
  v_on          boolean;
  v_backfilled  int := 0;
  v_cancelled   int := 0;
  v_queued      int := 0;
  v_released    int := 0;
  v_notified    int := 0;
  v_sent        int := 0;
  v_approved    int := 0;
  v_ids         uuid[];
  v_early       uuid[];
  v_closed_early int := 0;
  v_id          uuid;
  r             record;
BEGIN
  -- pg_cron chama por SQL, sem JWT: aceita o cron e o service_role, recusa usuário REST (ADR-0028 p89).
  IF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'service-role or cron only';
  END IF;

  SELECT value INTO v_cfg FROM public.site_config WHERE key = 'drive_membership_revoke_enabled';
  -- chave ausente = desligada
  v_on := coalesce(v_cfg, 'false'::jsonb) IS NOT DISTINCT FROM 'true'::jsonb;

  -- a. a trilha de desligamento já revogou a mesma permissão depois do último envio desta concessão
  WITH done AS (
    UPDATE public.drive_membership_grants g
       SET status = 'revoked', revoked_at = a.revoked_at, revoked_by = a.approved_by,
           revoked_via = 'offboarding_audit', updated_at = now()
      FROM public.drive_offboarding_audit a
     WHERE g.status = 'granted'
       AND a.drive_file_id = g.drive_folder_id AND a.permission_id = g.permission_id
       AND a.status IN ('revoked','already_absent') AND a.revoked_at IS NOT NULL
       AND a.revoked_at > coalesce(g.last_dispatched_at, g.granted_at)
    RETURNING g.id
  )
  SELECT count(*) INTO v_backfilled FROM done;

  -- b. o item aberto que deixou de valer
  WITH c AS (
    UPDATE public.drive_membership_revocations q
       SET status = 'cancelled', cancelled_at = now(), updated_at = now(),
           cancel_reason = CASE
             WHEN g.status IS DISTINCT FROM 'granted' THEN 'grant_closed'
             WHEN EXISTS (SELECT 1 FROM public.drive_offboarding_audit a
                          WHERE a.drive_file_id = g.drive_folder_id AND a.permission_id = g.permission_id
                            AND a.status IN ('pending_revoke','approved')) THEN 'offboarding_lane'
             WHEN coalesce(public.can_by_member(q.member_id, 'manage_platform'), false) THEN 'manage_platform_exception'
             ELSE 'engagement_restored' END
      FROM public.drive_membership_grants g
     WHERE g.id = q.grant_id AND q.status IN ('pending','approved')
       AND ( g.status IS DISTINCT FROM 'granted'
          OR ( q.reason = 'engagement_ended'
               AND ( public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id)
                  OR coalesce(public.can_by_member(q.member_id, 'manage_platform'), false)
                  OR EXISTS (SELECT 1 FROM public.drive_offboarding_audit a
                             WHERE a.drive_file_id = g.drive_folder_id AND a.permission_id = g.permission_id
                               AND a.status IN ('pending_revoke','approved')) ) ) )
    RETURNING q.id
  )
  SELECT count(*) INTO v_cancelled FROM c;

  -- b2. o bloqueio que deixou de importar. Uma falha ou um "manter" da gestão impede a concessão de voltar à fila
  -- (passo c). Quando a pessoa volta ao roster, o bloqueio já não protege nada: o item fecha como engagement_restored,
  -- e se o vínculo terminar de novo a concessão entra limpa. Cada item liberado ganha uma linha no admin_audit_log com o
  -- estado de antes (lido de o, a mesma linha antes do UPDATE), porque o próprio item passa a dizer engagement_restored.
  WITH rel AS (
    UPDATE public.drive_membership_revocations q
       SET status = 'cancelled', cancel_reason = 'engagement_restored',
           cancelled_at = coalesce(q.cancelled_at, now()), updated_at = now()
      FROM public.drive_membership_grants g, public.drive_membership_revocations o
     WHERE g.id = q.grant_id AND o.id = q.id
       AND ( (q.status = 'failed' AND q.reason = 'engagement_ended') OR q.cancel_reason = 'management_kept' )
       AND public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id)
    RETURNING q.id, q.grant_id, o.status AS status_before, o.cancel_reason AS cancel_reason_before
  ), rel_audit AS (
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    SELECT NULL, 'drive_membership_revocation_released', 'drive_membership_revocations', rel.id,
           jsonb_build_object('status_before', rel.status_before, 'cancel_reason_before', rel.cancel_reason_before,
                              'status_after', 'cancelled', 'cancel_reason_after', 'engagement_restored'),
           jsonb_build_object('grant_id', rel.grant_id, 'via', 'enqueue_membership_drive_revocations')
      FROM rel
    RETURNING 1
  )
  SELECT count(*) INTO v_released FROM rel;

  -- c. entra na fila a concessão cuja pessoa saiu do roster da iniciativa
  WITH ins AS (
    INSERT INTO public.drive_membership_revocations (grant_id, initiative_id, member_id, reason, is_confidential)
    SELECT g.id, g.initiative_id, g.grantee_member_id, 'engagement_ended', (i.visibility = 'confidential')
      FROM public.drive_membership_grants g
      JOIN public.initiatives i ON i.id = g.initiative_id
     WHERE g.status = 'granted' AND g.permission_id IS NOT NULL
       AND g.grantee_person_id IS NOT NULL AND g.grantee_member_id IS NOT NULL
       AND NOT public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id)
       -- exceção nomeada (GP, 22/11/2026): quem tem manage_platform vê a iniciativa confidencial pela ADR-0105
       AND NOT public.can_by_member(g.grantee_member_id, 'manage_platform')
       -- já tem item aberto, falhou (vai à tela, e repetir só reavisaria) ou a gestão decidiu manter
       AND NOT EXISTS (SELECT 1 FROM public.drive_membership_revocations x
                       WHERE x.grant_id = g.id
                         AND (x.status IN ('pending','approved','failed') OR x.cancel_reason = 'management_kept'))
       -- a trilha de desligamento já tem a mesma permissão aberta
       AND NOT EXISTS (SELECT 1 FROM public.drive_offboarding_audit a
                       WHERE a.drive_file_id = g.drive_folder_id AND a.permission_id = g.permission_id
                         AND a.status IN ('pending_revoke','approved'))
    ON CONFLICT DO NOTHING
    RETURNING id
  )
  SELECT count(*) INTO v_queued FROM ins;

  IF v_on THEN
    -- d. o aviso e o prazo. Item segurado não é avisado até soltar. A confidencialidade é a de agora, não a da entrada.
    -- A pausa (inactive) fica fora: é reversível sem portão (ADR-0107 Emenda 1, item 2), e a gestão decide na tela.
    FOR r IN
      SELECT x.id, (i.visibility = 'confidential') AS conf_now
        FROM public.drive_membership_revocations x
        JOIN public.initiatives i ON i.id = x.initiative_id
        JOIN public.members m ON m.id = x.member_id
       WHERE x.status = 'pending' AND x.reason = 'engagement_ended'
         AND x.notified_at IS NULL AND x.held_at IS NULL
         AND m.member_status IN ('active','alumni')
       ORDER BY x.detected_at, x.id
       FOR UPDATE OF x
    LOOP
      UPDATE public.drive_membership_revocations
         SET notified_at = now(),
             due_at = CASE WHEN r.conf_now THEN now() ELSE now() + c_notice END,
             is_confidential = r.conf_now,
             updated_at = now()
       WHERE id = r.id;
      IF public._drive_revocation_notify(r.id, r.conf_now) THEN
        v_sent := v_sent + 1;
      END IF;
      v_notified := v_notified + 1;
    END LOOP;

    -- e. vencido, avisado e não segurado, de quem é active ou alumni: aprova, conferindo a condição de novo no UPDATE.
    -- A visibilidade é relida aqui: o item avisado com 7 dias cuja iniciativa ficou confidencial depois do aviso sai
    -- neste ciclo, como sairia se já fosse confidencial na entrada (decisão do GP de 22/11/2026). O prazo de antes vem de
    -- o, a mesma linha antes do UPDATE: quem sai antes do prazo avisado recebe o "foi encerrado" (GP, 23/11/2026).
    WITH ap AS (
      UPDATE public.drive_membership_revocations x
         SET status = 'approved', approval_mode = 'auto', approved_at = now(), updated_at = now(),
             is_confidential = (i.visibility = 'confidential'),
             due_at = LEAST(x.due_at, now())
        FROM public.drive_membership_grants g, public.members m, public.initiatives i, public.drive_membership_revocations o
       WHERE g.id = x.grant_id AND m.id = g.grantee_member_id AND i.id = x.initiative_id AND o.id = x.id
         AND x.status = 'pending' AND x.reason = 'engagement_ended'
         AND x.held_at IS NULL AND x.notified_at IS NOT NULL
         AND (x.due_at <= now() OR i.visibility = 'confidential')
         AND g.status = 'granted'
         AND m.member_status IN ('active','alumni')
         AND NOT public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id)
         AND NOT public.can_by_member(g.grantee_member_id, 'manage_platform')
      RETURNING x.id, (o.due_at > now()) AS closing_early
    )
    SELECT array_agg(id ORDER BY id), array_agg(id ORDER BY id) FILTER (WHERE closing_early) INTO v_ids, v_early FROM ap;
    v_approved := coalesce(cardinality(v_ids), 0);

    -- o aviso de "foi encerrado" de quem saiu antes do prazo avisado. A hora do aviso vai para notified_at ANTES de
    -- avisar, item a item: o segundo item do mesmo par vê o primeiro como "foi encerrado" e não avisa de novo.
    FOREACH v_id IN ARRAY coalesce(v_early, ARRAY[]::uuid[]) LOOP
      UPDATE public.drive_membership_revocations SET notified_at = now(), updated_at = now() WHERE id = v_id;
      IF public._drive_revocation_notify(v_id, true) THEN
        v_sent := v_sent + 1;
      END IF;
      v_closed_early := v_closed_early + 1;
    END LOOP;
  END IF;

  IF v_backfilled + v_cancelled + v_released + v_queued + v_notified + v_approved > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'drive_membership_revocation_cycle', 'drive_membership_revocations', NULL, '{}'::jsonb,
            jsonb_build_object('enabled', v_on, 'ledger_aligned', v_backfilled, 'cancelled', v_cancelled,
                               'released', v_released, 'queued', v_queued, 'notified', v_notified,
                               'notices_sent', v_sent, 'auto_approved', v_approved,
                               'closed_early', v_closed_early,
                               'approved_ids', to_jsonb(coalesce(v_ids, ARRAY[]::uuid[]))));
  END IF;

  RETURN jsonb_build_object('enabled', v_on, 'ledger_aligned', v_backfilled, 'cancelled', v_cancelled,
                            'released', v_released, 'queued', v_queued, 'notified', v_notified,
                            'notices_sent', v_sent, 'auto_approved', v_approved,
                            'closed_early', v_closed_early);
END;
$function$;
REVOKE ALL ON FUNCTION public.enqueue_membership_drive_revocations() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_membership_drive_revocations() TO service_role;

NOTIFY pgrst, 'reload schema';
