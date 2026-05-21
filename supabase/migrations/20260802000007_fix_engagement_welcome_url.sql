-- BUG-212.A fix: _enqueue_engagement_welcome generated link `/iniciativas/<id>`
-- which 404s because the real route is `/initiative/[id]` (English singular).
-- ALL engagement-welcome emails since ADR-0060 G7 deployment have landed on 404.
--
-- Change: v_link := '/iniciativas/' → '/initiative/'
-- Other behaviour preserved byte-for-byte from current live body
-- (captured via pg_get_functiondef 2026-05-21 p211).
--
-- Cross-ref: Issue #217 BUG-212.A; ADR-0060 G7; P162 log #106 RESOLVED-212.A;
-- pre-fix bodies in 20260514310000 (original create) + 20260686000000 (p178
-- drift capture) — historical, never re-applied.

CREATE OR REPLACE FUNCTION public._enqueue_engagement_welcome(p_engagement_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
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
      v_subject := 'Voce esta listado como observer em ' || COALESCE(v_initiative_title, 'iniciativa');
      v_body := 'Sua participacao como observador foi registrada. ' ||
                'Voce tem acesso de leitura aos materiais e reunioes da iniciativa.';
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
