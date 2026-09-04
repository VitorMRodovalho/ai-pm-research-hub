-- #2185 - metade ESCRITORA do `actor_kind`. A metade receptora (#2159, migration 20260904132206)
-- criou a coluna, o backfill e o trigger que classifica quem nao declara. Esta faz os escritores
-- automaticos DECLARAREM, para que `unknown` volte a significar "alguem escreveu sem dizer de onde"
-- em vez de "o caminho de sempre".
--
-- ⚠️ CORRIGE UMA AFIRMACAO ERRADA QUE ESTA NA MIGRATION 20260904132206, JA MERGEADA. O cabecalho
-- dela diz:
--
--     "Os dois escritores automaticos NAO sao funcoes de banco (a busca em `pg_proc` volta vazia):
--      sao Edge Functions gravando por PostgREST."
--
-- E falso. A busca que produziu aquele "vazio" procurava em `pg_proc` por funcoes CHAMADAS
-- `reconcile_initiative_drive_access` — mas isso e o valor da coluna `context`, nao o nome de
-- funcao nenhuma. Procurando o literal DENTRO do corpo, os escritores aparecem, e sao TRES funcoes
-- de banco. Nenhuma Edge Function esta envolvida, e por isso esta migration e o unico veiculo
-- necessario.
--
-- A licao, registrada porque custou uma frase errada num arquivo mergeado: antes de tratar um vazio
-- como fato, pergunte se a chave da busca e do mesmo TIPO que a coisa buscada. Nome de funcao e
-- valor de coluna sao eixos diferentes.
--
-- POR QUE A DECLARACAO E VERDADEIRA POR CONSTRUCAO: as tres comecam com
-- `IF current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE`. Nao existe caminho em que
-- uma pessoa autenticada as execute, entao `actor_kind = 'automation'` nao e suposicao, e o unico
-- valor que elas PODEM produzir.
--
-- ⚠️ E o `accessor_id` continua NULL de proposito. A coluna nova nao substitui o nulo: ela explica.
-- `accessor_id` nulo + `actor_kind = 'automation'` le "nao ha pessoa"; nulo + `unknown` le "ninguem
-- registrou quem foi". Eram o mesmo silencio ate a #2159, e e a diferenca inteira.
--
-- MEDIDO ANTES: human 27.914, automation 7.592, unknown 0. Depois desta migration, o lote diario das
-- 04:00 UTC de `reconcile_initiative_drive_access` (~136 linhas, medido sem excecao nos ultimos 15
-- dias) continua caindo em `automation` em vez de migrar para `unknown`, que era o que aconteceria
-- se so a metade receptora existisse.

CREATE OR REPLACE FUNCTION public.get_initiative_drive_roster(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_rows jsonb; v_member_ids uuid[];
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;

  WITH roster AS (
    -- primary member email
    SELECT DISTINCT e.person_id, m.id AS member_id, lower(m.email) AS email
    FROM public.engagements e
    JOIN public.members m ON m.person_id = e.person_id
    WHERE e.initiative_id = p_initiative_id AND e.status = 'active'
      AND m.member_status = 'active'
      AND m.email IS NOT NULL AND m.email <> ''
    UNION
    -- alternate emails (member_emails)
    SELECT DISTINCT e.person_id, m.id AS member_id, lower(me.email::text) AS email
    FROM public.engagements e
    JOIN public.members m ON m.person_id = e.person_id
    JOIN public.member_emails me ON me.member_id = m.id
    WHERE e.initiative_id = p_initiative_id AND e.status = 'active'
      AND m.member_status = 'active'
      AND me.email IS NOT NULL
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('person_id', person_id, 'member_id', member_id, 'email', email)), '[]'::jsonb),
         coalesce(array_agg(DISTINCT member_id), ARRAY[]::uuid[])
  INTO v_rows, v_member_ids
  FROM roster;

  -- #2185: DECLARA a origem. `accessor_id` nulo aqui significa "nao ha pessoa", e nao "ninguem
  -- registrou quem foi" — sao coisas diferentes que ate a #2159 eram o mesmo silencio. A funcao so
  -- roda como service_role (guarda acima), entao a declaracao e verdadeira por construcao.
  IF cardinality(v_member_ids) > 0 THEN
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason, actor_kind)
    SELECT NULL, mid, ARRAY['email'], 'reconcile_initiative_drive_access',
           'drive membership grant reconcile: active roster email set', 'automation'
    FROM unnest(v_member_ids) AS mid;
  END IF;

  RETURN v_rows;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_offboarded_member_emails()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_rows jsonb; v_member_ids uuid[];
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;

  WITH emails AS (
    SELECT m.id AS member_id, lower(m.email) AS email
    FROM public.members m
    WHERE m.member_status IN ('inactive','alumni') AND m.offboarded_at IS NOT NULL
      AND m.email IS NOT NULL AND m.email <> ''
    UNION
    SELECT me.member_id, lower(me.email::text) AS email
    FROM public.member_emails me
    JOIN public.members m ON m.id = me.member_id
    WHERE m.member_status IN ('inactive','alumni') AND m.offboarded_at IS NOT NULL
      AND me.email IS NOT NULL
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('member_id', member_id, 'email', email)), '[]'::jsonb),
         coalesce(array_agg(DISTINCT member_id), ARRAY[]::uuid[])
  INTO v_rows, v_member_ids
  FROM emails;

  -- LGPD: system (cron) read of ex-member emails for the Drive scan.
  -- #2185: a intencao "isto e automacao" ja estava neste comentario e nao estava no DADO. Agora esta.
  IF cardinality(v_member_ids) > 0 THEN
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason, actor_kind)
    SELECT NULL, mid, ARRAY['email'], 'audit_drive_offboarding_access',
           'weekly drive permission scan: offboarded email match set', 'automation'
    FROM unnest(v_member_ids) AS mid;
  END IF;

  RETURN v_rows;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_offboarded_member_emails(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_rows jsonb; v_member_ids uuid[];
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;

  WITH emails AS (
    SELECT m.id AS member_id, lower(m.email) AS email
    FROM public.members m
    WHERE m.id = p_member_id
      AND m.member_status IN ('inactive','alumni') AND m.offboarded_at IS NOT NULL
      AND m.email IS NOT NULL AND m.email <> ''
    UNION
    SELECT me.member_id, lower(me.email::text) AS email
    FROM public.member_emails me
    JOIN public.members m ON m.id = me.member_id
    WHERE m.id = p_member_id
      AND m.member_status IN ('inactive','alumni') AND m.offboarded_at IS NOT NULL
      AND me.email IS NOT NULL
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('member_id', member_id, 'email', email)), '[]'::jsonb),
         coalesce(array_agg(DISTINCT member_id), ARRAY[]::uuid[])
  INTO v_rows, v_member_ids
  FROM emails;

  -- LGPD Art.37: system (event-trigger) read of an ex-member's emails for the targeted Drive scan.
  -- #2185: mesma declaracao explicita da irma sem argumento.
  IF cardinality(v_member_ids) > 0 THEN
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason, actor_kind)
    SELECT NULL, mid, ARRAY['email'], 'audit_drive_offboarding_access',
           'event-triggered drive permission scan: offboarded email match set', 'automation'
    FROM unnest(v_member_ids) AS mid;
  END IF;

  RETURN v_rows;
END;
$function$;
