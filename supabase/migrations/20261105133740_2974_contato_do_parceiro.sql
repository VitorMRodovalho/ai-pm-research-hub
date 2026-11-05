-- #2974: o contato do parceiro (contact_name e contact_email) só sai para quem pode ver parceiros: superadmin,
-- view_partner ou manage_partner.
--
-- 1. partner_entities: a leitura direta da tabela pede uma dessas três condições.
-- 2. list_card_partners: mesma assinatura e mesmas linhas. partner_contact_name vem para quem atende a regra acima e
--    sai NULL para os demais. Nome, tipo, capítulo e status do parceiro seguem como estão.

ALTER POLICY partners_read_members ON public.partner_entities
  USING (public.rls_is_superadmin() OR public.rls_can('view_partner') OR public.rls_can('manage_partner'));

CREATE OR REPLACE FUNCTION public.list_card_partners(p_board_item_id uuid)
 RETURNS TABLE(link_id uuid, link_role text, link_notes text, linked_at timestamp with time zone, linked_by_name text, partner_entity_id uuid, partner_name text, partner_entity_type text, partner_chapter text, partner_status text, partner_contact_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_ve_contato boolean;
BEGIN
  SELECT m.id,
         (coalesce(m.is_superadmin, false)
          OR public.can_by_member(m.id, 'view_partner')
          OR public.can_by_member(m.id, 'manage_partner'))
    INTO v_member_id, v_ve_contato
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN RETURN; END IF;
  -- Leitura pela API: membro com vínculo vigente.
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN; END IF;

  -- #785: confidential initiative visibility gate (item->board->initiative)
  IF NOT public.rls_can_see_item(p_board_item_id) THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    pc.id, pc.link_role, pc.notes, pc.created_at, cm.name,
    pe.id, pe.name, pe.entity_type, pe.chapter, pe.status,
    CASE WHEN v_ve_contato THEN pe.contact_name END
  FROM public.partner_cards pc
  JOIN public.partner_entities pe ON pe.id = pc.partner_entity_id
  LEFT JOIN public.members cm ON cm.id = pc.created_by
  WHERE pc.board_item_id = p_board_item_id
  ORDER BY pc.created_at DESC;
END;
$function$;
