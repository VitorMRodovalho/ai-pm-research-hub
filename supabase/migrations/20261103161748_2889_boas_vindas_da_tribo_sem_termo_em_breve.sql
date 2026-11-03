-- Onboarding, onda 0, PR-3 (#2889 parte 2; Refs #1952): as boas-vindas da tribo deixam de prometer um Termo que a
-- pessoa ja assinou.
--
-- POR QUE: o ramo volunteer de _enqueue_engagement_welcome dizia "Em breve voce recebera o Termo de Voluntariado para
-- assinatura" a todo vinculo volunteer novo. Esse ramo tambem dispara quando o lider aprova um pedido de tribo, e pedir
-- tribo exige o Termo assinado. O link ia para /initiative/<id>, e nao para a pagina da tribo, e o texto saia sem acento.
--
-- O QUE MUDA, so no ramo volunteer:
--   - com o Termo assinado (algum vinculo ativo da pessoa com agreement_certificate_id) e numa research_tribe:
--     "Voce agora faz parte da tribo X", com link /tribe/<legacy_tribe_id>, onde estao o horario e os proximos passos;
--   - com o Termo assinado, fora de tribo: o mesmo texto de antes, sem a frase do Termo;
--   - sem o Termo: o texto de antes, com acento.
-- Os outros kinds ficam como estao, palavra por palavra. O INSERT passa a ler o modo de entrega do catalogo
-- (_delivery_mode_for('engagement_welcome'), catalogado na PR-2 com o mesmo transactional_immediate). Nenhuma
-- autoridade muda: este arquivo so escolhe texto e link.
--
-- O corpo parte da captura mais nova (20260922180458), com so estas mudancas; o md5 do corpo vivo e conferido contra
-- ela antes do apply. CREATE OR REPLACE mantem a ACL. Delimitador $function$, de proposito: o guard
-- enqueue-engagement-welcome-url elege a migration mais recente que casa CREATE OR REPLACE ... $function$.
--
-- ROLLBACK: reaplicar o corpo de 20260922180458.

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
  v_legacy_tribe_id integer;
  v_has_term boolean;
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
  SELECT i.title, i.kind, i.legacy_tribe_id INTO v_initiative_title, v_initiative_kind, v_legacy_tribe_id
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
      -- Onda 0 PR-3 (#2889): este ramo tambem dispara quando o lider aprova um pedido de tribo, e pedir tribo exige o
      -- Termo assinado; a mensagem prometia "em breve" um Termo que a pessoa ja assinou. O Termo assinado fica em
      -- engagements.agreement_certificate_id, gravado nos vinculos volunteer ativos no momento da assinatura; o vinculo
      -- da tribo nasce sem ele, entao o que vale e qualquer vinculo ativo da pessoa com o certificado.
      v_has_term := EXISTS (
        SELECT 1 FROM public.engagements eo
        WHERE eo.person_id = v_eng.person_id
          AND eo.status = 'active'
          AND eo.agreement_certificate_id IS NOT NULL
      );
      IF v_has_term AND v_initiative_kind = 'research_tribe' THEN
        v_subject := 'Bem-vindo(a) à tribo ' || COALESCE(v_initiative_title, 'de pesquisa');
        v_body := 'Você agora faz parte da tribo ' || COALESCE(v_initiative_title, 'de pesquisa') || '. ' ||
                  'Na página da tribo estão o horário das reuniões, os próximos eventos e quem participa.';
        v_link := COALESCE('/tribe/' || v_legacy_tribe_id::text, v_link);
      ELSIF v_has_term THEN
        v_subject := 'Bem-vindo(a) ao ' || COALESCE(v_initiative_title, 'Núcleo IA Hub');
        v_body := 'Sua participação como voluntário(a) foi registrada. ' ||
                  'Acesse a iniciativa para ver agenda e próximos passos.';
      ELSE
        v_subject := 'Bem-vindo(a) ao ' || COALESCE(v_initiative_title, 'Núcleo IA Hub');
        v_body := 'Sua participação como voluntário(a) foi registrada. ' ||
                  'Em breve você receberá o Termo de Voluntariado para assinatura. ' ||
                  'Acesse a iniciativa para ver agenda e próximos passos.';
      END IF;
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
    public._delivery_mode_for('engagement_welcome')
  );
END;
$function$;
