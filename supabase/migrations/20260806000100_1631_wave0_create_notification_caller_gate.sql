-- =====================================================================================
-- #1631 (Wave 0) -- gate de chamador em `create_notification`
--
-- MEDIDO em 2026-08-06, antes desta migration:
--   - 3 sobrecargas de public.create_notification, todas SECURITY DEFINER, todas com
--     EXECUTE para `authenticated`, NENHUMA com gate de autoridade do chamador. O unico
--     guard existente (`IF p_recipient_id = p_actor_id THEN RETURN NULL`) impede
--     auto-notificacao; nao e controle de acesso. Quem chamasse escolhia destinatario,
--     titulo, corpo, `link` e o ator aparente.
--   - 40 funcoes internas chamam create_notification. TODAS sao SECURITY DEFINER e
--     pertencem a `postgres`: numa chamada SECDEF->SECDEF o EXECUTE e verificado como o
--     DONO, entao revogar o grant de `authenticated` NAO as alcanca (medido no #1551).
--   - Chamadores DIRETOS como `authenticated` -- os unicos que a revogacao quebraria --
--     sao DOIS, ambos gateados apenas na aplicacao:
--       (1) VolunteerAgreementPanel.notifyPending()  -> tipo `system` (11 linhas, 9 em 90d)
--       (2) MCP send_notification_to_tribe / comms_post:notify_tribe -> `tribe_broadcast`
--           (100 linhas, 0 em 90d)
--     Esta migration da a cada um a sua RPC gateada, e SO ENTAO fecha a porta generica.
--
-- POR QUE fechar no GRANT e nao com um gate no corpo: `auth.uid()` continua sendo o
-- usuario final DENTRO de uma SECURITY DEFINER. Um gate de autoridade no corpo alcancaria
-- os 40 chamadores internos e derrubaria fluxo legitimo de membro comum (candidato em
-- onboarding, avaliador lancando nota, trigger de atribuicao de card). O GRANT separa
-- exatamente o que precisa ser separado: chamada DIRETA da borda vs. chamada ANINHADA,
-- que ja passou pelo gate do seu proprio chamador.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- (1) Substituto do chamador direto do painel do Termo de Voluntariado.
--
-- O painel varria a lista no CLIENTE e disparava uma RPC por membro. Alem de N
-- round-trips, era o cliente quem decidia o destinatario. Aqui o escopo e recalculado
-- no servidor, com o MESMO gate de `get_volunteer_agreement_status` -- quem enxerga o
-- painel pode cutucar, e mais ninguem. Divergir dele seria a tela autorizando uma coisa
-- e o servidor outra.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_pending_volunteer_agreements(p_lang text DEFAULT 'pt-BR')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_is_vol_director boolean;
  v_title text;
  v_body text;
  v_targets int := 0;
  v_m record;
BEGIN
  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  v_is_manage_member := public.can_by_member(v_caller_id, 'manage_member');
  v_is_chapter_board := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_caller_person_id
      AND ae.kind = 'chapter_board'
      AND ae.status = 'active'
  );
  v_is_vol_director := EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.id = v_caller_id AND 'voluntariado_director' = ANY(m.designations)
  );

  IF NOT v_is_manage_member AND NOT v_is_chapter_board AND NOT v_is_vol_director THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  v_title := CASE p_lang
    WHEN 'en-US'    THEN 'Volunteer Agreement Pending'
    WHEN 'es-LATAM' THEN 'Acuerdo de Voluntariado Pendiente'
    ELSE                 'Termo de Voluntariado Pendente'
  END;
  v_body := CASE p_lang
    WHEN 'en-US'    THEN 'Please sign your volunteer agreement to stay compliant.'
    WHEN 'es-LATAM' THEN 'Por favor firma tu acuerdo de voluntariado.'
    ELSE                 'Por favor assine seu termo de voluntariado para manter a conformidade.'
  END;

  -- Mesma populacao da aba do painel (voluntario ativo, dentro do escopo do chamador),
  -- filtrada pelos que ainda nao tem o termo do ano vigente emitido.
  FOR v_m IN
    SELECT m.id
    FROM public.members m
    WHERE m.is_active
      AND EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id = m.person_id AND ae.kind = 'volunteer' AND ae.status = 'active'
      )
      AND (v_is_manage_member OR v_is_vol_director OR m.chapter = v_caller_chapter)
      AND NOT EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = m.id
          AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
      )
  LOOP
    -- Notacao NOMEADA de proposito: sao 3 sobrecargas e a ambiguidade ja derrubou uma RPC
    -- antes. So esta sobrecarga tem p_title + p_body + p_link juntos.
    PERFORM public.create_notification(
      p_recipient_id => v_m.id,
      p_type         => 'system',
      p_title        => v_title,
      p_body         => v_body,
      p_link         => '/volunteer-agreement'
    );
    v_targets := v_targets + 1;
  END LOOP;

  -- `targets` conta chamadas EMITIDAS, nao entregas: create_notification respeita
  -- notification_preferences e pode suprimir em silencio, e a sobrecarga que devolve void
  -- nao reporta isso. Nomear de `sent` seria tratar ausencia de medicao como medicao.
  RETURN jsonb_build_object('ok', true, 'targets', v_targets);
END;
$function$;

-- -------------------------------------------------------------------------------------
-- (2) Substituto do chamador direto do MCP (broadcast de tribo).
--
-- O EF resolvia a lista de destinatarios no cliente e emitia uma RPC por membro, com
-- `if (!e) sent++` -- uma falha vinha como "0 destinatarios", nao como erro. Aqui o
-- escopo e o gate vivem no servidor e a falha propaga.
-- -------------------------------------------------------------------------------------
-- Nome igual ao da tool MCP que a consome, de proposito. NAO chamar de
-- `send_tribe_broadcast`: ja existe a Edge Function `send-tribe-broadcast`, que manda
-- E-MAIL via Resend. Dois mecanismos diferentes com o mesmo nome e o tipo de ambiguidade
-- que faz a proxima sessao consertar o lado errado.
DROP FUNCTION IF EXISTS public.send_tribe_broadcast(text, text, text);

CREATE OR REPLACE FUNCTION public.send_notification_to_tribe(
  p_title text,
  p_body  text,
  p_link  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_tribe uuid;
  v_is_superadmin boolean;
  v_title text;
  v_body text;
  v_recipients int := 0;
  v_m record;
BEGIN
  SELECT m.id, m.tribe_id, COALESCE(m.is_superadmin, false)
    INTO v_caller_id, v_caller_tribe, v_is_superadmin
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'write') THEN
    RETURN jsonb_build_object('error', 'Unauthorized', 'required', 'write');
  END IF;

  IF v_caller_tribe IS NULL AND NOT v_is_superadmin THEN
    RETURN jsonb_build_object('error', 'no_tribe');
  END IF;

  v_title := left(btrim(COALESCE(p_title, '')), 200);
  v_body  := left(btrim(COALESCE(p_body,  '')), 4000);
  IF v_title = '' OR v_body = '' THEN
    RETURN jsonb_build_object('error', 'title_and_body_required');
  END IF;

  -- O link vira DESTINO de navegacao no cliente (`window.location.href = link`), onde um
  -- esquema `javascript:` EXECUTA. O gate de esquema fica na FONTE para alcancar tambem
  -- quem le a notificacao por outra superficie. `//host` parece caminho e troca a origem.
  IF p_link IS NOT NULL AND NOT (
       (p_link LIKE '/%' AND p_link NOT LIKE '//%')
       OR p_link ~* '^https?://'
     ) THEN
    RETURN jsonb_build_object('error', 'invalid_link');
  END IF;

  FOR v_m IN
    SELECT m.id
    FROM public.members m
    WHERE m.is_active
      AND m.current_cycle_active
      AND m.id <> v_caller_id
      AND (v_is_superadmin OR m.tribe_id = v_caller_tribe)
  LOOP
    PERFORM public.create_notification(
      p_recipient_id => v_m.id,
      p_type         => 'tribe_broadcast',
      p_title        => v_title,
      p_body         => v_body,
      p_link         => p_link
    );
    v_recipients := v_recipients + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'recipients', v_recipients,
    'scope', CASE WHEN v_is_superadmin THEN 'all_active' ELSE 'tribe' END
  );
END;
$function$;

-- -------------------------------------------------------------------------------------
-- (3) Negacao por padrao nas duas RPCs novas, depois o grant especifico.
-- `FROM PUBLIC` sozinho NAO fecha nada: o default do Postgres e EXECUTE para PUBLIC, mas
-- o Supabase ainda concede a anon/authenticated por default privileges.
-- -------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.notify_pending_volunteer_agreements(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_pending_volunteer_agreements(text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.send_notification_to_tribe(text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.send_notification_to_tribe(text, text, text) TO authenticated, service_role;

-- -------------------------------------------------------------------------------------
-- (4) E so agora a porta generica fecha -- as TRES sobrecargas.
-- Corrigir uma e deixar duas seria o padrao da gemea morta: o atacante usa a que sobrou.
-- -------------------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.create_notification(uuid, text, text, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.create_notification(uuid, text, text, uuid, text, uuid)       FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.create_notification(uuid, text, text, uuid, text, uuid, text) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.create_notification(uuid, text, text, text, text, text, uuid) IS
  'Interna (#1631). EXECUTE fechado para anon/authenticated: quem chama escolhe destinatario, titulo, corpo e link. A chamada tem de vir de uma funcao que ja gateou o proprio chamador (SECDEF->SECDEF resolve EXECUTE como o DONO), de pg_cron, ou de service_role. Chamador direto de borda usa notify_pending_volunteer_agreements ou send_notification_to_tribe.';

COMMENT ON FUNCTION public.create_notification(uuid, text, text, uuid, text, uuid) IS
  'Interna (#1631). EXECUTE fechado para anon/authenticated -- ver a sobrecarga de 7 argumentos.';

COMMENT ON FUNCTION public.create_notification(uuid, text, text, uuid, text, uuid, text) IS
  'Interna (#1631). EXECUTE fechado para anon/authenticated -- ver a sobrecarga com p_title/p_body/p_link.';
