-- Defeito 2 da #1901, independente do 'id' ambiguo que a migration anterior corrigiu.
-- Removida a ambiguidade, a chamada avancava e batia em 42703: `pb.cycle_code does not exist`.
--
-- So apareceu com impersonacao de membro real. Como service_role a funcao para antes, em
-- 'Not authenticated', e o defeito fica invisivel: um teste do tipo "nao da mais 42702" passaria
-- com a funcao ainda 100% quebrada.
--
-- Por que NAO seguir o HINT do Postgres (`pb.cycle_scope`): essa coluna esta NULA nas 33 linhas de
-- project_boards. Mapear para ela compilaria e devolveria `cycle_code` sempre nulo, com o filtro
-- `p_cycle_code` nunca casando. Compila, roda, e mente.
--
-- Decisao do PM (2026-08-20): apontar para a tabela CANONICA `cycles`. `board_items.cycle` e
-- inteiro (479 cards no ciclo 3, 236 no 2, 41 no 4, 71 nulos) e mapeia direto para
-- `cycles.cycle_code` no formato `cycle_N`. LEFT JOIN em vez de concatenar direto, para que um
-- ciclo ausente do catalogo vire NULL em vez de codigo fabricado.
--
-- 📌 ITEM SEPARADO, REGISTRADO E NAO RESOLVIDO AQUI: existem DUAS convencoes de `cycle_code` no
-- mesmo banco. A canonica `cycles` usa `cycle_3`; `portfolio_kpi_targets` usa `cycle3-2026`, e e
-- essa que `exec_portfolio_health` consome. Esta funcao passa a falar a canonica.
--
-- PROVA (impersonando membro com view_internal_analytics, pos-correcao):
--   94 linhas sem filtro, 92 com p_cycle_code = 'cycle_3'.
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
         c.cycle_code,
         bi.updated_at
  FROM board_items bi
  JOIN project_boards pb ON pb.id = bi.board_id
  LEFT JOIN initiatives i ON i.id = pb.initiative_id
  LEFT JOIN public.cycles c ON c.cycle_code = 'cycle_' || bi.cycle::text
  WHERE bi.is_portfolio_item = true
    AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
    AND (p_status IS NULL OR bi.status = p_status)
    AND (p_cycle_code IS NULL OR c.cycle_code = p_cycle_code)
    AND public.rls_can_see_initiative(pb.initiative_id)
  ORDER BY bi.due_date NULLS LAST, bi.updated_at DESC;
END $function$;
