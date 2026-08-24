-- #1950: a chave de capacidade passa a DESCREVER o que sempre mediu: 1 lider + N-1 pesquisadores.
--
-- Historico, para nao parecer mudanca de regra: o valor foi de 7 para 8 mantendo o lider na
-- contagem (SPEC_TRIBE_SWITCH_AND_LEADER_REVIEW, tradeoff ratificado). Logo `8` sempre significou
-- 1 lider + 7 pesquisadores, e o nome `max_researchers_per_tribe` descrevia 8 pesquisadores, que e
-- outra coisa. Nada muda no comportamento: muda o nome, para o proximo leitor nao "consertar" a
-- contagem em direcao ao nome e desfazer a decisao da lideranca sem decidir.
--
-- ⚠️ O fallback tambem muda, de 7 para 8, pelo mesmo motivo: 7 era o valor ANTERIOR da setting e
-- ficou preso no corpo quando ela subiu. Com a linha ausente, o limite caia para 7 integrantes
-- (= 6 pesquisadores), que nunca foi a decisao de ninguem.

-- 1) a chave
UPDATE public.platform_settings
   SET key = 'max_members_per_tribe'
 WHERE key = 'max_researchers_per_tribe';

-- 2) o unico leitor da chave (as 3 superficies de escrita leem este helper, nao a chave)
CREATE OR REPLACE FUNCTION public.tribe_capacity_limit()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select (value #>> '{}')::int from public.platform_settings where key = 'max_members_per_tribe'),
    8
  );
$function$;

COMMENT ON FUNCTION public.tribe_capacity_limit() IS
  'Capacidade de uma tribo, em INTEGRANTES: o limite conta o lider. Valor 8 = 1 lider + 7 '
  'pesquisadores (decidido na Reuniao de Lideranca de 23/07 e ratificado em '
  'SPEC_TRIBE_SWITCH_AND_LEADER_REVIEW). SSOT = platform_settings.max_members_per_tribe, '
  'fallback 8. Consumido por select_tribe / admin_force_tribe_selection / review_tribe_request '
  'e exposto ao site por get_homepage_stats. #1950';

REVOKE ALL ON FUNCTION public.tribe_capacity_limit() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tribe_capacity_limit() TO authenticated, service_role;

-- 3) a superficie publica: o campo da resposta acompanha o nome da chave.
--    Unico consumidor medido em 24/08: TribesSection.astro, que aceita os dois nomes durante a
--    janela entre os deploys.
CREATE OR REPLACE FUNCTION public.get_homepage_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN jsonb_build_object(
    'members', (SELECT count(*) FROM public.v_operational_members),
    'observers', (SELECT count(*) FROM members WHERE member_status = 'observer'),
    'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni'),
    'tribes', (SELECT count(*) FROM tribes WHERE is_active),
    'initiatives', (
      SELECT count(*) FROM initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
        AND visibility <> 'confidential'
    ),
    'total_initiatives', (
      SELECT count(*) FROM initiatives WHERE status = 'active'
        AND visibility <> 'confidential'
    ),
    'active_leaders', (
      SELECT count(DISTINCT person_id) FROM auth_engagements
      WHERE status = 'active' AND role IN ('leader', 'co_leader', 'co_gp')
    ),
    'chapters', (public.get_chapter_metrics()->>'signed')::int,
    'impact_hours', round(public.get_impact_hours_canonical()),
    'max_members_per_tribe', public.tribe_capacity_limit()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_homepage_stats() FROM public;
GRANT EXECUTE ON FUNCTION public.get_homepage_stats() TO anon, authenticated, service_role;
