-- ARM Onda 1 #136: admin_reactivate_member guard contra des-anonimização
--
-- LGPD Art. 16 II: anonimização é irreversível. Reativar membro com anonymized_at
-- IS NOT NULL viola o princípio (dados originais foram destruídos).
--
-- Mudanças:
--   - Após resolver target, verifica anonymized_at IS NULL
--   - Se anonimizado: registra tentativa em admin_audit_log
--     (action=admin_reactivate_blocked_anonymized) e retorna erro estruturado
--   - Preserva DEFAULT 'researcher'::text para p_role (signature compatível)
--
-- Rollback: re-CREATE OR REPLACE com versão sem o branch.

CREATE OR REPLACE FUNCTION public.admin_reactivate_member(
  p_member_id uuid,
  p_tribe_id integer,
  p_role text DEFAULT 'researcher'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_caller   record;
  v_member   record;
  v_audit_id uuid;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Member not found'); END IF;

  -- ARM #136 guard: cannot reactivate anonymized member (LGPD Art. 16 II)
  IF v_member.anonymized_at IS NOT NULL THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id,
      'admin_reactivate_blocked_anonymized',
      'member',
      p_member_id,
      jsonb_build_object(
        'anonymized_at', v_member.anonymized_at,
        'attempted_tribe_id', p_tribe_id,
        'attempted_role', p_role
      ),
      jsonb_build_object('lgpd_basis', 'Art. 16 II — anonymization is irreversible')
    );
    RETURN jsonb_build_object(
      'error','Cannot reactivate anonymized member',
      'reason','LGPD Art. 16 II — anonymization is irreversible by law',
      'anonymized_at', v_member.anonymized_at
    );
  END IF;

  IF v_member.member_status = 'active' THEN
    RETURN jsonb_build_object('error','Member is already active');
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id,
    'member.status_transition',
    'member',
    p_member_id,
    jsonb_strip_nulls(jsonb_build_object(
      'previous_status', v_member.member_status,
      'new_status', 'active',
      'previous_tribe_id', v_member.tribe_id,
      'new_tribe_id', p_tribe_id
    )),
    jsonb_build_object('reason_category', 'return')
  )
  RETURNING id INTO v_audit_id;

  UPDATE public.members SET
    member_status = 'active',
    is_active = true,
    tribe_id = p_tribe_id,
    operational_role = p_role,
    status_changed_at = now(),
    offboarded_at = NULL,
    offboarded_by = NULL
  WHERE id = p_member_id;

  RETURN jsonb_build_object(
    'success', true,
    'audit_id', v_audit_id,
    'member_name', v_member.name,
    'new_tribe', p_tribe_id
  );
END;
$func$;

NOTIFY pgrst, 'reload schema';
