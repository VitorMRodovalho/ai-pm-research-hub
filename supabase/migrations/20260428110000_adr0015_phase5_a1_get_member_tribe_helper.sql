-- ADR-0015 Phase 5 Fase A1 — Helper RPC para derivar tribe via engagements
--
-- get_member_tribe(member_id) retorna o legacy_tribe_id da iniciativa research_tribe
-- à qual o member tem engagement 'volunteer' com status 'active'.
-- Quando múltiplos engagements (ex: volunteer em tribe A + ambassador em outra coisa),
-- retorna apenas o volunteer em research_tribe (ordem: mais recente por start_date).
--
-- Substitui leituras de members.tribe_id no refactor Phase 5 (Option A / drop completo).
--
-- Data validation (2026-04-18):
--   - 38/38 active members com tribe_id: helper retorna mesmo valor (100% match).
--   - 0 mismatches em dados ativos.
--   - 5 stale members (1 alumni + 4 observer) com members.tribe_id set mas sem
--     engagement ativo → helper retorna NULL (comportamento correto).
--
-- Semantic note: este refactor intencionalmente retorna NULL para alumni/observers
-- pós-Phase 5. Essa é a semântica V4 (tribe-less quando engagement inativo).
-- Se precisar de "tribo histórica" em display, use `get_member_tribe_historical`
-- (TODO criar se necessário em Fase A5 frontend audit).

CREATE OR REPLACE FUNCTION public.get_member_tribe(p_member_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT i.legacy_tribe_id
  FROM public.members m
  JOIN public.engagements e ON e.person_id = m.person_id
  JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE m.id = p_member_id
    AND e.kind = 'volunteer'
    AND e.status = 'active'
    AND i.kind = 'research_tribe'
  ORDER BY e.start_date DESC NULLS LAST
  LIMIT 1;
$function$;

GRANT EXECUTE ON FUNCTION public.get_member_tribe(uuid) TO authenticated, service_role;
