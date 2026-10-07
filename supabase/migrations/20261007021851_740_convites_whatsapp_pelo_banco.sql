-- #740: convites dos grupos de WhatsApp do Nucleo (onboarding e geral) servidos pelo banco.
-- WHAT: cria get_community_group_link(p_group), SECURITY DEFINER, que devolve o convite do grupo pedido
--       a partir de site_config, chave 'whatsapp_group_onboarding' ou 'whatsapp_group_general'.
-- WHY:  o convite do pre-onboarding ficava fixo no front e deixou de valer; o do grupo geral nao era
--       entregue por nenhuma tela. Convite de grupo nao entra no repositorio publico nem no bundle:
--       quem entra num grupo ve o telefone dos participantes. Mesmo padrao do get_tribe_group_link.
-- GATE: grupo de onboarding: membro ativo com login. Grupo geral: membro ativo com o termo assinado
--       (fora do pre-onboarding), a regra do grupo da tribo, ou admin da plataforma.
-- DATA: os convites NAO entram nesta migration; sao gravados em site_config fora do repositorio. A policy
--       de leitura de site_config so abre a membros as chaves que lista, e estas chaves nao estao nela.
-- ROLLBACK: DROP FUNCTION public.get_community_group_link(text);
CREATE FUNCTION public.get_community_group_link(p_group text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid           uuid := auth.uid();
  v_member_id     uuid;
  v_is_active     boolean;
  v_member_status text;
  v_person_id     uuid;
  v_link          text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_authenticated');
  END IF;

  IF p_group IS NULL OR p_group NOT IN ('onboarding', 'general') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid_group');
  END IF;

  SELECT id, is_active, member_status
    INTO v_member_id, v_is_active, v_member_status
    FROM public.members
   WHERE auth_id = v_uid
   LIMIT 1;

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_authenticated');
  END IF;

  IF v_is_active IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'reason', 'inactive');
  END IF;

  -- The general group follows the tribe-group rule: only after the volunteer term is signed.
  -- Fails closed without a person row, because member_is_pre_onboarding(NULL, ...) is false.
  IF p_group = 'general' AND NOT public.can_by_member(v_member_id, 'manage_platform') THEN
    SELECT id INTO v_person_id FROM public.persons WHERE legacy_member_id = v_member_id;
    IF v_person_id IS NULL OR public.member_is_pre_onboarding(v_person_id, v_member_status) THEN
      RETURN jsonb_build_object('success', false, 'reason', 'pre_onboarding');
    END IF;
  END IF;

  SELECT value #>> '{}' INTO v_link
    FROM public.site_config
   WHERE key = 'whatsapp_group_' || p_group;

  -- Only a WhatsApp group invite is ever served; anything else reads as no link.
  IF v_link IS NULL OR v_link !~ '^https://chat\.whatsapp\.com/[A-Za-z0-9]{10,}(\?[A-Za-z0-9_=&-]*)?$' THEN
    RETURN jsonb_build_object('success', false, 'reason', 'no_link');
  END IF;

  RETURN jsonb_build_object('success', true, 'whatsapp_url', v_link);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_community_group_link(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_community_group_link(text) TO authenticated, service_role;

COMMENT ON FUNCTION public.get_community_group_link(text) IS
  '#740: convite do grupo de WhatsApp do Nucleo (onboarding ou general), lido de site_config. Onboarding: membro ativo. General: membro ativo com termo assinado, ou admin da plataforma.';
