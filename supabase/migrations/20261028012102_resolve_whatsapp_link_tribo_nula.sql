-- resolve_whatsapp_link: tribo nula passa a contar como tribo diferente nas duas checagens de acesso.
--
-- Corpo de partida: o vivo em 27/10/2026, igual a captura 20260805000289_onda2_fu2_sliceC_chapter_scope_remaining_pii_rpcs
-- (md5 do prosrc normalizado dcd235c95fff19762f2d9a5481f5b2d0).
-- (1) Portao de acesso: a disjuncao fica dentro de COALESCE(..., false). Quando o alvo nao tem tribo, a comparacao de
--     tribo dava NULL, a disjuncao inteira dava NULL e o IF NOT NULL nao entrava na recusa.
-- (2) Escopo por capitulo: "mesma tribo" vira COALESCE(v_caller.tribe_id = v_target.tribe_id, false), pelo mesmo motivo.
-- Assinatura, SECURITY DEFINER, search_path e GRANTs inalterados: CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION public.resolve_whatsapp_link(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller_id uuid := auth.uid();
  v_caller record;
  v_target record;
  v_clean_phone text;
  v_scope text;
begin
  -- Get caller
  select id, tribe_id, operational_role, is_superadmin
    into v_caller from public.members where auth_id = v_caller_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Caller not found');
  end if;

  -- Get target
  select id, phone, tribe_id, share_whatsapp, chapter
    into v_target from public.members where id = p_member_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Member not found');
  end if;

  -- Check opt-in
  if v_target.share_whatsapp is not true then
    return jsonb_build_object('success', false, 'error', 'Member has not opted in');
  end if;

  -- p180 ADR-0011 V4: hybrid V3+V4 PII access gate.
  -- V3 paths preserved (admin override + same-tribe). V4 path added via
  -- can_by_member('view_pii') — covers chapter_board, committee/workgroup
  -- coordinators+leaders, study_group owners, volunteer × {co_gp, leader,
  -- deputy_manager, manager}. Defense-in-depth: V3 stays as fallback if
  -- catalog drifts.
  -- Tribo nula nao e a mesma tribo: sem o COALESCE, um termo NULL deixava a condicao inteira NULL, e o
  -- IF NOT NULL nao entrava na recusa (falha aberta para alvo sem tribo).
  if not coalesce((
    v_caller.is_superadmin = true
    or v_caller.operational_role in ('manager', 'deputy_manager')
    or public.can_by_member(v_caller.id, 'view_pii')
    or (v_caller.tribe_id is not null and v_caller.tribe_id = v_target.tribe_id)
  ), false) then
    return jsonb_build_object('success', false, 'error', 'Not authorized');
  end if;

  -- FU-2 Slice C: an org-scoped view_pii grant must not unlock a cross-chapter WhatsApp link for a
  -- chapter-restricted caller (partner-chapter leader). Own-chapter and same-tribe stay allowed;
  -- GP/sede/manager (caller_chapter_scope() = NULL) are unrestricted.
  v_scope := public.caller_chapter_scope();
  if v_scope is not null
     and v_target.chapter is distinct from v_scope
     and not coalesce(v_caller.tribe_id = v_target.tribe_id, false)
  then
    return jsonb_build_object('success', false, 'error', 'Not authorized');
  end if;

  -- No phone registered
  if v_target.phone is null or v_target.phone = '' then
    return jsonb_build_object('success', false, 'error', 'No phone registered');
  end if;

  -- Clean phone: keep only digits
  v_clean_phone := regexp_replace(v_target.phone, '[^0-9]', '', 'g');

  return jsonb_build_object(
    'success', true,
    'url', 'https://wa.me/' || v_clean_phone
  );
end;
$function$;
