-- #1838 -- o avaliador do comite deixa de ser barrado nas telas ao redor da entrevista.
-- Lote 1 de 4: as duas RPCs em escopo de CANDIDATURA.
--
-- Decisao do PM (17/08): gate por participacao no comite do ciclo somada a view_pii; as
-- ESCRITAS restritas aos papeis que decidem (evaluator, lead) -- observador observa. O dominio
-- de selection_committee.role e ('evaluator','lead','observer'), entao a lista de dois exclui
-- EXATAMENTE o observador: recorte exaustivo, nao amostra que envelhece.
--
-- Gate ADITIVO: quem passava antes continua passando. Nenhuma capacidade ampliada, nenhum combo
-- de engagement_kind_permissions semeado -- isto e scoping inline de RPC, o terceiro caminho de
-- autoridade do V4 (docs/reference/V4_AUTHORITY_MODEL.md).
--
-- is_selection_committee_member(id, NULL) e selection_committee_role_for(id) compartilham o
-- predicado (status='open' OR phase='evaluating'), que e o sinal publicado para a pagina, entao
-- tela e servidor nao divergem (#1590).
--
-- Corpos extraidos das capturas (md5 normalizado conferido IDENTICO ao vivo antes de editar),
-- com substituicoes CONTADAS e diferenca revisada. CREATE FUNCTION virou CREATE OR REPLACE onde
-- a captura era antiga, porque OR REPLACE preserva as ACLs.

CREATE OR REPLACE FUNCTION public.update_application_contact(
  p_application_id uuid,
  p_phone text DEFAULT NULL::text,
  p_linkedin_url text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  -- #1838: manage_member e capacidade de ciclo de vida de MEMBRO, restrita ao GP por
  -- invariante de LGPD, e aqui o alvo e um CANDIDATO -- telefone e LinkedIn de quem ainda nao
  -- e membro. Isto ESCREVE, entao o comite passa so nos papeis que decidem (evaluator, lead);
  -- observador observa. O EXISTS falha fechado se a candidatura nao existir.
  IF v_caller_id IS NULL OR NOT (
       public.can_by_member(v_caller_id, 'manage_member')
    OR (EXISTS (SELECT 1 FROM public.selection_applications sa
                 JOIN public.selection_committee sc
                   ON sc.cycle_id = sa.cycle_id AND sc.member_id = v_caller_id
                WHERE sa.id = p_application_id
                  AND sc.role IN ('evaluator', 'lead'))
        AND public.can_by_member(v_caller_id, 'view_pii'))
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  UPDATE public.selection_applications SET
    phone = COALESCE(NULLIF(p_phone, ''), phone),
    linkedin_url = COALESCE(NULLIF(p_linkedin_url, ''), linkedin_url),
    updated_at = now()
  WHERE id = p_application_id;

  RETURN jsonb_build_object('success', true);
END;
$function$;
CREATE OR REPLACE FUNCTION public.get_application_onboarding_pct(p_application_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result integer;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  -- #1838: manage_platform e administracao da plataforma, e esta RPC devolve UM INTEIRO de
  -- progresso de onboarding de uma candidatura. A exigencia era desproporcional ao que ela
  -- entrega. E LEITURA, entao qualquer papel do comite do ciclo DESTA candidatura passa, com
  -- view_pii. O EXISTS falha fechado se a candidatura nao existir.
  IF v_caller_id IS NULL OR NOT (
       public.can_by_member(v_caller_id, 'manage_platform')
    OR (EXISTS (SELECT 1 FROM public.selection_applications sa
                 WHERE sa.id = p_application_id
                   AND public.is_selection_committee_member(v_caller_id, sa.cycle_id))
        AND public.can_by_member(v_caller_id, 'view_pii'))
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform, or selection committee membership with view_pii';
  END IF;

  SELECT CASE
    WHEN count(*) = 0 THEN -1
    ELSE round(100.0 * count(*) FILTER (WHERE status = 'completed') / count(*))::int
  END INTO v_result
  FROM onboarding_progress
  WHERE application_id = p_application_id
  AND metadata->>'phase' = 'pre_onboarding';

  RETURN v_result;
END;
$function$;