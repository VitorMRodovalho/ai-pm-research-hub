-- Home, seção "Vagas abertas" dentro de "Faça parte" (#join). Decisão do GP em 31/10/2026 (aprovada ~17:05Z):
-- quais vagas aparecem é decidido por uma marcação POR VAGA no banco, que começa desligada, e não por id no código.
-- Fecha a lacuna que a 20261024024922 (home v2, D1) deixou registrada: vep_opportunities não guardava o prazo de
-- inscrição. A URL pública já está gravada em toda vaga ativa (https://volunteer.pmi.org/opportunities/<id>).
--
-- (1) vep_opportunities.home_listing: 'hidden' (padrão), 'open' (inscrição aberta, com link) ou 'soon' (em breve,
--     sem link). Independe de is_active, que segue querendo dizer "o Aplicar importa": a vaga piloto da linha pode
--     estar 'open' na home e fora da importação.
-- (2) vep_opportunities.application_deadline: o prazo de inscrição do VEP (postingEndDateUTC, data em UTC, a mesma
--     que a página pública do VEP mostra), separado de end_date, que é o fim da atuação.
-- (3) get_public_home_openings(): leitora pública da seção. Devolve só campos públicos (nunca initiative_id,
--     organization_id, essay_mapping, requirements nem eligibility), exclui vaga de iniciativa confidencial no
--     próprio corpo (ADR-0105, mesmo portão das leitoras de 20261024024922), devolve link e prazo só de vaga 'open',
--     e uma vaga 'open' sem prazo, com prazo vencido ou sem URL pública não sai. O VEP fecha a inscrição em
--     postingEndDateUTC (05:00Z, 02:00 em Brasília do dia do prazo), então a vaga deixa a home no começo desse dia.
--     Sem recorte por organização, como as demais leitoras públicas da home: há uma organização hoje, e o recorte
--     entra junto em todas quando houver a segunda (ADR-0004, ADR-0134 §10).
--
-- Nenhuma linha muda de visibilidade com esta migration: todas nascem 'hidden' e a RPC devolve 0 linhas até o pacote
-- de dados marcar as vagas. A tela que lê a RPC (JoinSection) some quando a leitura falha ou volta vazia.
--
-- Rollback: DROP FUNCTION public.get_public_home_openings();
--   ALTER TABLE public.vep_opportunities DROP CONSTRAINT vep_opportunities_home_listing_check,
--     DROP COLUMN home_listing, DROP COLUMN application_deadline;

ALTER TABLE public.vep_opportunities
  ADD COLUMN home_listing text NOT NULL DEFAULT 'hidden',
  ADD COLUMN application_deadline date,
  ADD CONSTRAINT vep_opportunities_home_listing_check CHECK (home_listing IN ('hidden', 'open', 'soon'));

COMMENT ON COLUMN public.vep_opportunities.home_listing IS
  'Home, seção Vagas abertas (GP 31/10/2026): hidden (padrão), open (inscrição aberta, com link) ou soon (em breve, sem link). Independe de is_active.';
COMMENT ON COLUMN public.vep_opportunities.application_deadline IS
  'Prazo de inscrição no VEP (postingEndDateUTC, data em UTC). Não confundir com end_date, o fim da atuação.';

CREATE OR REPLACE FUNCTION public.get_public_home_openings()
 RETURNS TABLE(opportunity_id text, title text, role_default text, listing text, vep_url text,
               application_deadline date, start_date date, time_commitment text, line_title text)
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
         CASE WHEN i.kind = 'research_tribe' THEN i.title END
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
  'Home (#join), seção Vagas abertas (GP 31/10/2026): vagas marcadas em vep_opportunities.home_listing, sem iniciativa confidencial; link e prazo só das abertas. Vazio = a home esconde a seção.';
REVOKE ALL ON FUNCTION public.get_public_home_openings() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_home_openings() TO anon, authenticated, service_role;
