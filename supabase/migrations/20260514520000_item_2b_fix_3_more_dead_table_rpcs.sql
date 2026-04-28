-- Item 2 batch B: 3 more RPCs surfaceadas pelo drift detector v4 com refs a tabelas
-- inexistentes (member_role_changes + member_status_transitions).
-- LGPD-CRITICAL: delete_my_personal_data não funcionava — bloqueava direito ao esquecimento.

CREATE OR REPLACE FUNCTION public.delete_my_personal_data(p_confirm_text text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_cleared text[];
BEGIN
  SELECT id, name, email, phone, address, city, state, country, birth_date
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
  IF v_caller.phone IS NOT NULL THEN v_cleared := array_append(v_cleared, 'phone'); END IF;
  IF v_caller.address IS NOT NULL THEN v_cleared := array_append(v_cleared, 'address'); END IF;
  IF v_caller.city IS NOT NULL THEN v_cleared := array_append(v_cleared, 'city'); END IF;
  IF v_caller.birth_date IS NOT NULL THEN v_cleared := array_append(v_cleared, 'birth_date'); END IF;

  UPDATE members SET
    phone = NULL,
    address = NULL,
    city = NULL,
    birth_date = NULL,
    updated_at = now()
  WHERE id = v_caller.id;

  -- Audit trail único em admin_audit_log (member_role_changes ref removida — tabela nunca existiu)
  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller.id, 'lgpd_self_erasure', 'member', v_caller.id,
    jsonb_build_object(
      'cleared_fields', to_jsonb(v_cleared),
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

CREATE OR REPLACE FUNCTION public._auto_remove_designation_on_cert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_desig_to_remove text;
  v_old_designations text[];
  v_new_designations text[];
BEGIN
  IF NEW.type != 'contribution' OR NEW.function_role IS NULL THEN
    RETURN NEW;
  END IF;

  v_desig_to_remove := CASE
    WHEN NEW.function_role ILIKE '%comunica%'    THEN 'comms_member'
    WHEN NEW.function_role ILIKE '%curador%'      THEN 'curator'
    WHEN NEW.function_role ILIKE '%embaixador%'   THEN 'ambassador'
    WHEN NEW.function_role ILIKE '%chapter%board%' THEN 'chapter_board'
    ELSE NULL
  END;

  IF v_desig_to_remove IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT designations INTO v_old_designations FROM members WHERE id = NEW.member_id;

  IF v_old_designations IS NULL OR NOT (v_desig_to_remove = ANY(v_old_designations)) THEN
    RETURN NEW;
  END IF;

  v_new_designations := array_remove(v_old_designations, v_desig_to_remove);

  UPDATE members SET designations = v_new_designations, updated_at = now() WHERE id = NEW.member_id;

  -- Audit trail em admin_audit_log (era member_role_changes — tabela nunca existiu)
  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    NEW.issued_by,
    'designation_removed_on_cert',
    'member',
    NEW.member_id,
    jsonb_build_object(
      'field_name', 'designations',
      'old_value', to_jsonb(v_old_designations),
      'new_value', to_jsonb(v_new_designations),
      'effective_date', NEW.issued_at::date,
      'reason', 'Certificado de contribuição emitido: ' || NEW.function_role,
      'verification_code', NEW.verification_code
    )
  );

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_member_transitions(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  IF v_caller.id != p_member_id
    AND NOT public.can_by_member(v_caller.id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- Replaced member_status_transitions scan (table never existed) with admin_audit_log
  -- filtered by target=member + action ~ status/role transition
  RETURN jsonb_build_object('transitions', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', a.id,
      'action', a.action,
      'previous_status', a.changes->>'previous_status',
      'new_status', a.changes->>'new_status',
      'previous_tribe_id', a.changes->>'previous_tribe_id',
      'new_tribe_id', a.changes->>'new_tribe_id',
      'reason_category', a.changes->>'reason_category',
      'reason_detail', a.changes->>'reason_detail',
      'actor_name', m.name,
      'created_at', a.created_at
    ) ORDER BY a.created_at DESC)
    FROM admin_audit_log a
    LEFT JOIN members m ON m.id = a.actor_id
    WHERE a.target_type = 'member'
      AND a.target_id = p_member_id
      AND a.action ~ '(status|role|designation|tribe|offboard|onboard|reactiv)'
  ), '[]'::jsonb));
END;
$function$;

NOTIFY pgrst, 'reload schema';
