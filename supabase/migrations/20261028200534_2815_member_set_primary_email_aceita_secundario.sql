-- #2815, "Tornar principal" do perfil aceita o e-mail secundário verificado pela tela.
--
-- O card "E-mails cadastrados" lista members.secondary_emails, que é onde request_secondary_email_verification +
-- confirm_secondary_email gravam o endereço verificado. member_set_primary_email procurava o endereço só em
-- member_emails, que esse fluxo nunca preenche, e por isso respondia "Email not found" para quase todo secundário.
-- Quando a troca passava, mudava members.email e não mexia em secondary_emails: o novo principal seguia listado
-- como secundário e o antigo sumia do card.
--
-- Agora a função aceita o endereço que estiver em member_emails OU em members.secondary_emails do mesmo membro, e
-- troca os dois de lugar na mesma transação: o novo vai para members.email e o antigo entra em secondary_emails.
-- sync_member_email_trigger continua mantendo member_emails (rebaixa o antigo e insere o novo como principal).
-- Endereço que já pertence a outra conta recusa com mensagem genérica, antes de chegar ao gatilho, cuja mensagem
-- cita o id da outra conta. O portão #684, a mensagem genérica de "não encontrado" e a assinatura ficam iguais.
CREATE OR REPLACE FUNCTION public.member_set_primary_email(p_member_id uuid, p_email text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_is_service_role boolean := false;
  v_allowed boolean := false;
  v_target_org_id uuid;
  v_current_email text;
  v_secondary text[];
  v_norm text;
  v_row_id uuid;
  v_canonical citext;
  v_in_secondary boolean;
  v_new_secondary text[];
BEGIN
  -- #684: role-GUC discriminator (current_user is always the SECDEF owner under SECDEF).
  v_is_service_role := NOT public._request_is_rest_caller();

  IF NOT v_is_service_role THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF v_caller.id IS NULL THEN
      RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF v_caller.id = p_member_id OR public.can_by_member(v_caller.id, 'manage_member') THEN
      v_allowed := true;
    END IF;

    IF NOT v_allowed THEN
      RAISE EXCEPTION 'Unauthorized to set primary email';
    END IF;
  END IF;

  -- MED #2: org boundary anchor. FOR UPDATE serializes two swaps on the same member.
  SELECT organization_id, email, COALESCE(secondary_emails, '{}'::text[])
    INTO v_target_org_id, v_current_email, v_secondary
    FROM public.members WHERE id = p_member_id
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found: %', p_member_id;
  END IF;

  v_norm := lower(trim(coalesce(p_email, '')));

  IF v_norm <> '' AND lower(v_current_email) = v_norm THEN
    RETURN true;
  END IF;

  SELECT id, email INTO v_row_id, v_canonical
    FROM public.member_emails
   WHERE member_id = p_member_id AND email = v_norm::citext
   LIMIT 1;

  v_in_secondary := v_norm = ANY (SELECT lower(e) FROM unnest(v_secondary) AS e);

  IF v_norm = '' OR (v_row_id IS NULL AND NOT v_in_secondary) THEN
    -- HIGH (LGPD): generic message — no member_id echo, no helper-RPC hint.
    RAISE EXCEPTION 'Email not found for this member; ensure it was previously added.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.member_emails WHERE email = v_norm::citext AND member_id <> p_member_id)
     OR EXISTS (SELECT 1 FROM public.members WHERE lower(email) = v_norm AND id <> p_member_id) THEN
    RAISE EXCEPTION 'This email already belongs to another account; contact the platform team.';
  END IF;

  -- The old primary moves into the secondary list (it stays visible and can be promoted back), and the new one
  -- leaves it. Same set semantics as confirm_secondary_email: lowercase, distinct, sorted.
  SELECT COALESCE(array_agg(DISTINCT e ORDER BY e), '{}'::text[]) INTO v_new_secondary
    FROM (
      SELECT lower(x) AS e FROM unnest(v_secondary) AS x
      UNION
      SELECT lower(v_current_email)
    ) s
   WHERE e IS NOT NULL AND length(e) > 0 AND e <> v_norm;

  -- Same lock bypass confirm_secondary_email and remove_secondary_email use, local to this transaction.
  PERFORM set_config('app.bypass_secondary_emails_lock', 'true', true);

  UPDATE public.members
     SET email = COALESCE(v_canonical::text, v_norm),
         secondary_emails = v_new_secondary,
         updated_at = now()
   WHERE id = p_member_id;

  RETURN true;
END;
$function$;
