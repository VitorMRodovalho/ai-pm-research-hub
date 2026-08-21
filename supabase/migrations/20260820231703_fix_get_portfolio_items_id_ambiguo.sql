-- get_portfolio_items falhava com 42702 "column reference \"id\" is ambiguous" em TODA chamada.
-- A funcao e RETURNS TABLE(id uuid, ...), entao `id` e parametro de SAIDA e vira variavel
-- PL/pgSQL. Na linha que resolve o chamador, `SELECT id ... FROM members` ficava ambiguo entre
-- essa variavel e members.id, e o Postgres recusa antes de qualquer gate rodar.
--
-- Efeito no produto: a listagem de portfolio nao montava para ninguem. Os cards ESTAVAM marcados
-- (`is_portfolio_item = true`); era falha de LEITURA, nao perda de dado.
--
-- Medido: 301 funcoes usam o mesmo padrao nao qualificado `SELECT id INTO ... FROM members`, e
-- esta e a UNICA que quebra, porque e a unica com parametro de saida chamado `id`. As outras 300
-- devolvem jsonb/json/void e nao colidem. O padrao e uma mina: so detona quando alguem adiciona
-- um OUT param com nome de coluna usada na consulta.
--
-- Correcao minima e cirurgica: qualificar o alias. Nada mais do corpo muda.
--
-- NOTA: ao remover esta ambiguidade, apareceu um SEGUNDO defeito independente que ela mascarava
-- (`42703: column pb.cycle_code does not exist`). Ele e corrigido na migration seguinte,
-- 20260821000448_fix_get_portfolio_items_cycle_code_canonico.sql. Sozinha, esta migration NAO faz
-- a listagem de portfolio voltar a funcionar.
CREATE OR REPLACE FUNCTION public.get_portfolio_items(p_tribe_id integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_cycle_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, title text, status text, tribe_id integer, initiative_id uuid, baseline_date date, baseline_locked_at timestamp with time zone, forecast_date date, due_date date, is_portfolio_item boolean, portfolio_kpi_refs text[], cycle_code text, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id FROM members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT (can_by_member(v_member_id, 'view_internal_analytics') OR can_by_member(v_member_id, 'view_chapter_dashboards') OR can_by_member(v_member_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Access denied — requires view_internal_analytics or view_chapter_dashboards';
  END IF;

  RETURN QUERY
  SELECT bi.id, bi.title, bi.status,
         i.legacy_tribe_id AS tribe_id,
         pb.initiative_id,
         bi.baseline_date, bi.baseline_locked_at,
         bi.forecast_date, bi.due_date,
         bi.is_portfolio_item, bi.portfolio_kpi_refs,
         pb.cycle_code,
         bi.updated_at
  FROM board_items bi
  JOIN project_boards pb ON pb.id = bi.board_id
  LEFT JOIN initiatives i ON i.id = pb.initiative_id
  WHERE bi.is_portfolio_item = true
    AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    AND (p_status IS NULL OR bi.status = p_status)
    AND (p_cycle_code IS NULL OR pb.cycle_code = p_cycle_code)
    AND public.rls_can_see_initiative(pb.initiative_id)
  ORDER BY bi.due_date NULLS LAST, bi.updated_at DESC;
END $function$;
