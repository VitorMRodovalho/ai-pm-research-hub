-- V2 (Refs #2880): a vaga ganha um rotulo de exibicao proprio na home, lido por get_public_home_openings.
--
-- POR QUE: a home mostra cada vaga pelo titulo do VEP sem o sufixo " - Nucleo IA & GP ...", cortado no loader
-- (publicHomeData, loadHomeOpenings). A vaga 76625 tem o titulo "Embaixador(a) do Nucleo IA & GP - 2026/27": o nome
-- da organizacao vem sem o hifen antes, o corte nao acha o sufixo e a home mostra o titulo inteiro. Decisao do GP
-- (03/11/2026): um campo de exibicao por vaga, com o corte atual como reserva quando o campo for nulo.
--
-- O QUE MUDA:
--   - coluna nova vep_opportunities.home_label text, nula por padrao, e nunca em branco quando preenchida;
--   - a 76625 recebe 'Embaixador(a)'; o bloco confere que mudou exatamente 1 linha e, se nao, desfaz o apply inteiro;
--   - get_public_home_openings devolve home_label no fim do RETURNS TABLE. Mudar o RETURNS TABLE pede DROP e CREATE;
--     o corpo e o mesmo da captura 20261031185042, com a coluna a mais, e os grants sao refeitos aqui.
--
-- O QUE NAO MUDA: quais vagas aparecem, a ordem, o link e o prazo. As outras vagas seguem com home_label nulo e o
-- mesmo rotulo de hoje, pelo corte. Os leitores da tabela leem por colunas nomeadas, e os SELECT * gravam num record
-- do qual so usam campos nomeados. O worker do VEP so le a tabela.
--
-- ROLLBACK: reaplicar a funcao de 20261031185042 (DROP e CREATE com os 9 campos, REVOKE de PUBLIC e GRANT a anon,
--   authenticated e service_role) e ALTER TABLE public.vep_opportunities DROP CONSTRAINT
--   vep_opportunities_home_label_check, DROP COLUMN home_label. O loader segue funcionando sem o campo (usa o corte).

ALTER TABLE public.vep_opportunities
  ADD COLUMN home_label text,
  ADD CONSTRAINT vep_opportunities_home_label_check CHECK (home_label IS NULL OR btrim(home_label) <> '');

COMMENT ON COLUMN public.vep_opportunities.home_label IS
  'Home, seção Vagas abertas (GP 03/11/2026): rótulo de exibição da vaga. Nulo = a home usa o título do VEP sem o sufixo da organização.';

DO $$
DECLARE
  v_n integer;
BEGIN
  UPDATE public.vep_opportunities
     SET home_label = 'Embaixador(a)'
   WHERE opportunity_id = '76625';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'V2: expected 1 row for opportunity 76625 in vep_opportunities, updated %', v_n;
  END IF;
END $$;

DROP FUNCTION public.get_public_home_openings();

CREATE FUNCTION public.get_public_home_openings()
 RETURNS TABLE(opportunity_id text, title text, role_default text, listing text, vep_url text,
               application_deadline date, start_date date, time_commitment text, line_title text, home_label text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT o.opportunity_id::text,
         o.title,
         o.role_default,
         o.home_listing,
         CASE WHEN o.home_listing = 'open' THEN o.vep_url END,
         CASE WHEN o.home_listing = 'open' THEN o.application_deadline END,
         o.start_date,
         o.time_commitment,
         CASE WHEN i.kind = 'research_tribe' THEN i.title END,
         o.home_label
  FROM public.vep_opportunities o
  LEFT JOIN public.initiatives i ON i.id = o.initiative_id
  WHERE o.home_listing IN ('open', 'soon')
    AND (o.initiative_id IS NULL
         OR (coalesce(i.visibility, 'standard') <> 'confidential' AND public.rls_can_see_initiative(i.id)))
    AND (o.home_listing = 'soon'
         OR (o.vep_url LIKE 'https://volunteer.pmi.org/opportunities/%'
             AND o.application_deadline > (now() AT TIME ZONE 'America/Sao_Paulo')::date))
  ORDER BY (o.home_listing = 'open') DESC, (i.kind = 'research_tribe') IS TRUE DESC,
           o.application_deadline NULLS LAST, o.title;
$function$;
COMMENT ON FUNCTION public.get_public_home_openings() IS
  'Home (#join), seção Vagas abertas (GP 31/10/2026): vagas marcadas em vep_opportunities.home_listing, sem iniciativa confidencial; link e prazo só das abertas; home_label é o rótulo de exibição (GP 03/11/2026). Vazio = a home esconde a seção.';
REVOKE ALL ON FUNCTION public.get_public_home_openings() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_home_openings() TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
