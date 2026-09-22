-- ============================================================================
-- #2418 — o welcome de engajamento le o PAR (kind, role), nao so o kind
-- ============================================================================
--
-- POR QUE: `_enqueue_engagement_welcome` escolhia o texto com `CASE v_eng.kind`. A autoridade
-- mora no PAR (kind, role), que e a chave de `engagement_kind_permissions`. Resultado medido em
-- 22/09/2026: quem entra como `observer x participant` — o par que a #2416 fez conceder
-- `write_board` com escopo `initiative` — recebia "Voce tem acesso de LEITURA aos materiais e
-- reunioes da iniciativa". A mensagem subdescrevia a autoridade concedida.
--
-- E ISSO SAI POR E-MAIL, nao fica so na campainha: `delivery_mode='transactional_immediate'`, e no
-- historico **173 de 173** notificacoes `engagement_welcome` tiveram `email_sent_at` preenchido
-- (primeira 2026-04-28, ultima 2026-09-21, 31 nos ultimos 30 dias). E a primeira coisa que a pessoa
-- le sobre o que pode fazer ali.
--
-- Mesma familia do defeito de ler uma tabela de permissao por METADE da chave. A diferenca e que o
-- leitor errado aqui nao e uma consulta de diagnostico: e um texto que chega a pessoa real.
--
-- O QUE MUDA: exatamente um ramo, o de `observer`, que passa a ramificar por `role`.
--   role = 'participant' -> convidado a CONTRIBUIR no quadro daquela iniciativa, e so daquela,
--                           com a condicao de externo dita em voz alta (sem termo de voluntariado).
--   qualquer outro role  -> o texto de leitura de sempre, palavra por palavra.
-- Nenhum outro kind muda. Nenhuma autoridade muda: este arquivo so escolhe texto.
--
-- DELIMITADOR: `$function$`, de proposito. `tests/contracts/enqueue-engagement-welcome-url.test.mjs`
-- elege a migration mais recente que casa `CREATE OR REPLACE FUNCTION ... $function$ ... $function$`.
-- Com `$$` o `bodyPattern` dele nao casa, ele MANTEM o corpo do arquivo anterior e segue verde
-- afirmando sobre texto morto — ficaria vazio em vez de vermelho, que e pior.
--
-- Cross-ref: #2418, #2400, #2417, PR #2416, ADR-0131, BUG-212.A/#217 (a rota /initiative/).
-- ============================================================================

CREATE OR REPLACE FUNCTION public._enqueue_engagement_welcome(p_engagement_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_eng record;
  v_member_id uuid;
  v_initiative_title text;
  v_initiative_kind text;
  v_subject text;
  v_body text;
  v_link text;
BEGIN
  SELECT e.*, p.id AS person_id_resolved
  INTO v_eng
  FROM public.engagements e
  LEFT JOIN public.persons p ON p.id = e.person_id
  WHERE e.id = p_engagement_id;

  IF NOT FOUND THEN RETURN; END IF;

  -- Resolve member_id from person_id (guard: skip se nao ha member linked)
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.person_id = v_eng.person_id
  LIMIT 1;

  IF v_member_id IS NULL THEN RETURN; END IF;

  -- Resolve initiative metadata
  SELECT i.title, i.kind INTO v_initiative_title, v_initiative_kind
  FROM public.initiatives i WHERE i.id = v_eng.initiative_id;

  v_link := '/initiative/' || COALESCE(v_eng.initiative_id::text, '');

  -- Per-kind subject + body. Legal: NUNCA bundle com cessao de direitos.
  CASE v_eng.kind
    WHEN 'speaker' THEN
      v_subject := 'Bem-vindo(a) como speaker em ' || COALESCE(v_initiative_title, 'iniciativa');
      v_body := 'Sua participacao como speaker foi registrada. ' ||
                'Antes da preparacao do material, voce recebera o Termo de Speaker ' ||
                'em etapa dedicada para leitura e assinatura. Duvidas sobre direitos ' ||
                'autorais? Contate a coordenacao do Nucleo IA Hub.';
    WHEN 'volunteer' THEN
      v_subject := 'Bem-vindo(a) ao ' || COALESCE(v_initiative_title, 'Nucleo IA Hub');
      v_body := 'Sua participacao como voluntario(a) foi registrada. ' ||
                'Em breve voce recebera o Termo de Voluntariado para assinatura. ' ||
                'Acesse a iniciativa para ver agenda e proximos passos.';
    WHEN 'study_group_owner' THEN
      v_subject := 'Voce e owner de ' || COALESCE(v_initiative_title, 'study group');
      v_body := 'Voce foi confirmado(a) como owner deste grupo de estudo. ' ||
                'Voce pode convocar participantes, agendar reunioes e emitir certificados ' ||
                'ao final. Use o painel da iniciativa para gerenciar.';
    WHEN 'study_group_participant' THEN
      v_subject := 'Bem-vindo(a) ao grupo ' || COALESCE(v_initiative_title, 'de estudo');
      v_body := 'Sua participacao no grupo de estudo foi registrada. ' ||
                'Acesse o cronograma e materiais na pagina da iniciativa.';
    WHEN 'observer' THEN
      -- #2418: o kind sozinho nao diz o que a pessoa pode fazer. `observer` e o jeito da
      -- plataforma dizer "vinculo externo, nao-voluntario" (ADR-0131), e quanta autoridade vem
      -- junto depende do ROLE. Descrever os dois casos com o mesmo texto e o defeito.
      IF v_eng.role = 'participant' THEN
        v_subject := 'Voce foi convidado(a) a contribuir em ' || COALESCE(v_initiative_title, 'uma iniciativa');
        v_body := 'Sua participacao como convidado(a) externo(a) foi registrada. ' ||
                  'Voce pode contribuir no quadro desta iniciativa, criando e movendo cartoes ' ||
                  'e comentando — e apenas nesta, nao nas demais da plataforma. ' ||
                  'Voce nao e voluntario(a) do Nucleo e nao ha Termo de Voluntariado a assinar.';
      ELSE
        v_subject := 'Voce esta listado como observer em ' || COALESCE(v_initiative_title, 'iniciativa');
        v_body := 'Sua participacao como observador foi registrada. ' ||
                  'Voce tem acesso de leitura aos materiais e reunioes da iniciativa.';
      END IF;
    WHEN 'committee_coordinator', 'committee_member' THEN
      v_subject := 'Bem-vindo(a) ao comite ' || COALESCE(v_initiative_title, '');
      v_body := 'Sua participacao no comite foi registrada. ' ||
                'Acesse o painel para ver responsabilidades e agenda.';
    WHEN 'workgroup_coordinator', 'workgroup_member' THEN
      v_subject := 'Bem-vindo(a) ao workgroup ' || COALESCE(v_initiative_title, '');
      v_body := 'Sua participacao no workgroup foi registrada. ' ||
                'Acesse o painel para ver tarefas e proximos passos.';
    ELSE
      -- Default: skip welcome para kinds nao-mapeados (guard clause)
      RETURN;
  END CASE;

  -- Enqueue notification (delivery_mode='transactional_immediate' = welcome eh time-sensitive)
  INSERT INTO public.notifications (
    recipient_id, type, title, body, link, source_type, source_id, delivery_mode
  ) VALUES (
    v_member_id,
    'engagement_welcome',
    v_subject,
    v_body,
    v_link,
    'engagement',
    p_engagement_id,
    'transactional_immediate'
  );
END;
$function$;

-- Pos-condicao na propria transacao. `CREATE OR REPLACE` que omite um atributo o reseta em
-- silencio, entao a assercao e sobre a ASSINATURA e os atributos, nao so sobre o corpo. E o
-- EXECUTE para anon/authenticated e checado porque funcao nova nasce com ele.
DO $$
DECLARE
  v_secdef boolean;
  v_config text[];
  v_n_assinaturas integer;
  v_grants_largos integer;
  v_ramifica boolean;
BEGIN
  SELECT count(*) INTO v_n_assinaturas
    FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = '_enqueue_engagement_welcome';
  IF v_n_assinaturas <> 1 THEN
    RAISE EXCEPTION '#2418: _enqueue_engagement_welcome ficou com % assinaturas, esperado 1', v_n_assinaturas;
  END IF;

  SELECT prosecdef, proconfig,
         prosrc ~ 'v_eng\.role\s*=\s*''participant'''
    INTO v_secdef, v_config, v_ramifica
    FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = '_enqueue_engagement_welcome';

  IF NOT v_secdef THEN
    RAISE EXCEPTION '#2418: a funcao perdeu SECURITY DEFINER no replace';
  END IF;
  IF v_config IS NULL OR NOT ('search_path=public, pg_temp' = ANY(v_config)) THEN
    RAISE EXCEPTION '#2418: search_path nao voltou como "public, pg_temp": %', v_config;
  END IF;
  IF NOT v_ramifica THEN
    RAISE EXCEPTION '#2418: o corpo vivo nao ramifica por role — o welcome continua lendo metade da chave';
  END IF;

  SELECT count(*) INTO v_grants_largos
    FROM information_schema.routine_privileges
   WHERE routine_schema = 'public' AND routine_name = '_enqueue_engagement_welcome'
     AND grantee IN ('anon', 'authenticated', 'PUBLIC');
  IF v_grants_largos > 0 THEN
    RAISE EXCEPTION '#2418: o replace deixou EXECUTE para anon/authenticated/PUBLIC (% grants)', v_grants_largos;
  END IF;
END $$;
