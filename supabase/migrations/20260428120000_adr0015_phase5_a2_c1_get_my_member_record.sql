-- ADR-0015 Phase 5 Fase A2 Commit 1 — get_my_member_record derivando tribe_id via engagements
--
-- Mudança: `m.tribe_id` → `public.get_member_tribe(m.id)`.
--
-- Este é o helper de maior leverage da Phase 5: quase todo RPC authenticated chama
--   SELECT * INTO v_caller FROM public.get_my_member_record();
-- e depois usa v_caller.tribe_id para auth/scope decisions. Ao mudar aqui, todos
-- os callers auto-herdam a semântica V4 (tribo derivada de engagement ativo) sem
-- mudança de código nos próprios callers.
--
-- Semantic change (intencional):
--   - Antes: retornava members.tribe_id (cache, podia ter stale data)
--   - Depois: retorna tribe derivada de engagement volunteer ativo em research_tribe
--   - Para active members com engagement: 100% match com dado anterior (38/38 validados)
--   - Para alumni/observers (engagement inativo): NULL
--   - Para membros sem engagement: NULL (antes era NULL também)
--
-- Output shape PRESERVADO:
--   (id uuid, tribe_id integer, operational_role text, is_superadmin boolean, designations text[])
--
-- Downstream impact (zero-change para callers):
--   - RPCs que fazem `v_caller.tribe_id = p_tribe_id` para auth continuam funcionando
--   - RPCs que fazem `v_caller.tribe_id IS NULL` para detect "not in tribe" continuam
--   - RPCs que fazem `get_my_member_record().tribe_id` em SELECT list continuam
--
-- Performance: função helper é SECURITY DEFINER STABLE SQL. Executa 1 query por chamada.
--   get_my_member_record() já retorna LIMIT 1, então é 1 call de helper por invocação.
--   Impact: insignificante (< 1ms extra).

CREATE OR REPLACE FUNCTION public.get_my_member_record()
 RETURNS TABLE(id uuid, tribe_id integer, operational_role text, is_superadmin boolean, designations text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    m.id,
    public.get_member_tribe(m.id) AS tribe_id,
    m.operational_role,
    m.is_superadmin,
    m.designations
  FROM public.members m
  WHERE m.auth_id = auth.uid()
     OR auth.uid() = ANY(COALESCE(m.secondary_auth_ids, '{}'))
  LIMIT 1;
$function$;

-- Grants preservados (mesmos do anterior, reaplica para segurança)
GRANT EXECUTE ON FUNCTION public.get_my_member_record() TO authenticated, service_role;

-- Notification PostgREST
NOTIFY pgrst, 'reload schema';
