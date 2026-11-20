-- #3103: a autoexclusão do art. 18 limpa também a cópia em persons.
--
-- Desde a #2556, update_my_profile grava phone, address, city e birth_date em members E em persons
-- (WHERE id = v_caller.person_id). delete_my_personal_data zerava só members e devolvia success, e a
-- tela dizia "Dados pessoais apagados" com a cópia em persons intacta. Esta versão:
--   1. zera os mesmos quatro campos em persons, pela person_id do membro e pela ponte legacy_member_id;
--   2. zera members.phone_encrypted junto com phone, como os caminhos de anonimização já fazem;
--   3. lista em cleared_fields o que saiu, com o prefixo persons. para o que saiu de persons, e grava
--      isso no admin_audit_log como antes.
-- Assinatura, retorno e o DELETE de push_subscriptions (#2806) ficam iguais.

CREATE OR REPLACE FUNCTION public.delete_my_personal_data(p_confirm_text text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_person record;
  v_cleared text[];
  v_push_deleted integer;
  v_persons_updated integer;
BEGIN
  SELECT id, person_id, name, email, phone, phone_encrypted, address, city, state, country, birth_date
  INTO v_caller
  FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  IF p_confirm_text IS NULL OR upper(trim(p_confirm_text)) != 'DELETAR MEUS DADOS PESSOAIS' THEN
    RETURN jsonb_build_object(
      'error', 'confirmation_required',
      'message', 'Confirme enviando o parâmetro p_confirm_text com o texto: DELETAR MEUS DADOS PESSOAIS',
      'warning', 'Esta ação é IRREVERSÍVEL. Limpa endereço, cidade, telefone, aniversário. Preserva nome, email, contribuições, certificados emitidos.'
    );
  END IF;

  v_cleared := '{}';
  IF v_caller.phone IS NOT NULL OR v_caller.phone_encrypted IS NOT NULL THEN v_cleared := array_append(v_cleared, 'phone'); END IF;
  IF v_caller.address IS NOT NULL THEN v_cleared := array_append(v_cleared, 'address'); END IF;
  IF v_caller.city IS NOT NULL THEN v_cleared := array_append(v_cleared, 'city'); END IF;
  IF v_caller.birth_date IS NOT NULL THEN v_cleared := array_append(v_cleared, 'birth_date'); END IF;

  UPDATE members SET
    phone = NULL,
    phone_encrypted = NULL,
    address = NULL,
    city = NULL,
    birth_date = NULL,
    updated_at = now()
  WHERE id = v_caller.id;

  -- #3103: a mesma pessoa em persons. Lê antes de zerar para a lista dizer o que de fato saiu.
  SELECT bool_or(p.phone IS NOT NULL) AS phone, bool_or(p.address IS NOT NULL) AS address,
         bool_or(p.city IS NOT NULL) AS city, bool_or(p.birth_date IS NOT NULL) AS birth_date
  INTO v_person
  FROM persons p
  WHERE p.id = v_caller.person_id OR p.legacy_member_id = v_caller.id;
  IF v_person.phone THEN v_cleared := array_append(v_cleared, 'persons.phone'); END IF;
  IF v_person.address THEN v_cleared := array_append(v_cleared, 'persons.address'); END IF;
  IF v_person.city THEN v_cleared := array_append(v_cleared, 'persons.city'); END IF;
  IF v_person.birth_date THEN v_cleared := array_append(v_cleared, 'persons.birth_date'); END IF;

  UPDATE persons SET
    phone = NULL,
    address = NULL,
    city = NULL,
    birth_date = NULL,
    updated_at = now()
  WHERE id = v_caller.person_id OR legacy_member_id = v_caller.id;
  GET DIAGNOSTICS v_persons_updated = ROW_COUNT;

  -- #2806: a inscrição de push do aparelho é dado pessoal e sai na autoexclusão. Esta função não marca
  -- anonymized_at, então o gatilho trg_push_subscriptions_purge não a cobre: o DELETE fica aqui.
  DELETE FROM public.push_subscriptions WHERE member_id = v_caller.id;
  GET DIAGNOSTICS v_push_deleted = ROW_COUNT;
  IF v_push_deleted > 0 THEN v_cleared := array_append(v_cleared, 'push_subscriptions'); END IF;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller.id, 'lgpd_self_erasure', 'member', v_caller.id,
    jsonb_build_object(
      'cleared_fields', to_jsonb(v_cleared),
      'persons_rows', v_persons_updated,
      'cleared_at', now(),
      'legal_basis', 'LGPD Lei 13.709/2018 Art. 18 — Direito ao esquecimento',
      'preserved', 'name, email, pmi_id, state, country, historical contributions'
    ));

  RETURN jsonb_build_object(
    'success', true,
    'cleared_fields', to_jsonb(v_cleared),
    'preserved', jsonb_build_array('name', 'email', 'pmi_id', 'state', 'country', 'photo_url', 'linkedin_url', 'credly_url'),
    'message', 'Dados pessoais limpos. Histórico de contribuições e certificados preservados. Para excluir completamente sua conta, contate o gestor do projeto.',
    'legal_basis', 'LGPD Lei 13.709/2018 Art. 18'
  );
END;
$function$;
