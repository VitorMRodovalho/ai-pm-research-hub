-- #1682 — a mesma ponte do `export_my_data`, na outra superfície de leitura do titular.
--
-- `list_my_consents` filtrava por `member_id` num ledger em que nenhuma das 56 linhas o carrega
-- (medido 08/08/2026), então devolvia `[]` para todo mundo. É a irmã do `export_my_data`: as duas
-- respondem à MESMA pergunta do titular ("de que eu consenti?"). A issue #1682 deixava aberta a
-- alternativa de declarar esta tela como "só consentimentos de membro" em vez de consertá-la —
-- recusada aqui: com o export já alcançando o ledger por candidatura, uma tela que respondesse
-- `[]` para a mesma pessoa passaria a ser um SEGUNDO significado de "meus consentimentos", e a
-- divergência entre as duas leituras é pior do que a ausência de uma delas.
--
-- ⚠️ Nenhum consumidor no produto chama esta RPC hoje (grep em `src/` e `supabase/functions/`,
-- excluindo `database.gen.ts`). Ela é consertada porque é a superfície que uma tela futura vai
-- usar, e porque deixar as duas divergentes é justamente como um defeito destes reaparece.
--
-- Refs #1682, #1666

CREATE OR REPLACE FUNCTION public.list_my_consents()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_emails text[];
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- #1682: mesma resolução de e-mails do `export_my_data` — o ledger é endereçado pela
  -- candidatura, e o e-mail da candidatura pode não ser o do cadastro.
  SELECT COALESCE(array_agg(DISTINCT s.e), ARRAY[]::text[]) INTO v_emails
  FROM (
    SELECT lower(trim(m.email::text))  AS e FROM public.members m        WHERE m.id = v_member_id         AND m.email IS NOT NULL
    UNION
    SELECT lower(trim(me.email::text))      FROM public.member_emails me WHERE me.member_id = v_member_id AND me.email IS NOT NULL
  ) s;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', cr.id,
    'policy_type', cr.policy_type,
    'policy_version', cr.policy_version,
    'policy_document_id', cr.policy_document_id,
    'accepted_at', cr.accepted_at,
    'channel', cr.channel,
    'revoked_at', cr.revoked_at,
    'revocation_reason', cr.revocation_reason,
    'is_active', (cr.revoked_at IS NULL),
    'created_at', cr.created_at,
    'application_id', cr.application_id,
    'linked_by', CASE WHEN cr.member_id = v_member_id THEN 'member_id' ELSE 'application_email' END
  ) ORDER BY cr.accepted_at DESC), '[]'::jsonb)
  INTO v_result
  FROM public.consent_records cr
  WHERE cr.member_id = v_member_id
     OR cr.application_id IN (
          SELECT sa.id FROM public.selection_applications sa
          WHERE lower(trim(sa.email)) = ANY (v_emails)
        );

  RETURN v_result;
END;
$function$;
