-- #1200 — admin_offboard_member writes member_offboarding_records itself with the
-- caller-supplied reason category (2ª reincidência: T7 03/07 'personal_workload' e
-- Débora 08/07 'end_of_cycle' ambos gravados como 'other').
--
-- Root cause (aterrada 2026-07-08): the MCP wrapper AND the deployed EF propagate
-- p_reason_category correctly. The record is written by trg_offboarding_stub
-- (AFTER UPDATE OF member_status on members → _offboarding_create_stub), which can
-- only infer the category from members.status_change_reason when it matches
-- '^[a-z_]+:\s' ("categoria: detalhe"). This RPC stores status_change_reason =
-- COALESCE(p_reason_detail, p_reason_category) with no prefix, so inference fails
-- and the trigger's #449a never-crash COALESCE lands on 'other' — for EVERY caller
-- (MCP wrapper and direct RPC alike) whenever a free-text detail is passed.
--
-- Fix: the RPC becomes the authoritative writer — it inserts the record with the
-- FK-validated p_reason_category (fallback 'other', keeping #449a never-crash
-- semantics) BEFORE the members UPDATE. trg_offboarding_stub keeps its EXISTS
-- guard and now only backfills status changes that bypass this RPC (direct
-- UPDATEs). One record per member (UNIQUE member_id) is preserved via
-- ON CONFLICT DO NOTHING, matching the trigger's first-offboard-wins semantics.
--
-- Signature unchanged → CREATE OR REPLACE (GC-097: DROP+CREATE only for
-- param type/count changes). Base body = migration 20260805000315 capture
-- (live md5 b410644f2a5fc32eec47683b69acdae6 verified equal pre-change).

CREATE OR REPLACE FUNCTION public.admin_offboard_member(p_member_id uuid, p_new_status text, p_reason_category text, p_reason_detail text DEFAULT NULL::text, p_reassign_to uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller             record;
  v_member             record;
  v_audit_id           uuid;
  v_new_role           text;
  v_items_reassigned   integer := 0;
  v_engagements_closed integer := 0;
  v_vol_terms_skipped  integer := 0;
  v_prev_status        text;
  v_reason_record      record;
  v_reason_code        text;
  v_certificate_id     uuid;
  v_certificate_code   text;
  v_emit_error         text;
  v_current_cycle_int  integer;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  -- #1022-C: 'observer' retired as an offboard target (governance/LGPD — an "ouvinte"/observer is a
  -- non-volunteer not bound by the volunteer term, leaving data/IP/LGPD policy unbound; PM pulled it
  -- back). Only 'alumni' (friendly, re-invitable) and 'inactive' (administrative, reversible) remain.
  -- This is NOT engagement.kind='observer' (a participatory engagement kind, untouched).
  IF p_new_status NOT IN ('alumni','inactive') THEN
    RETURN jsonb_build_object('error','Invalid status: ' || p_new_status);
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Member not found'); END IF;

  v_prev_status := COALESCE(v_member.member_status,'active');

  IF v_prev_status = p_new_status THEN
    RETURN jsonb_build_object('error','Member is already ' || p_new_status);
  END IF;

  BEGIN
    PERFORM public.validate_status_transition(v_prev_status, p_new_status);
  EXCEPTION WHEN sqlstate '22023' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id, 'member.status_transition_blocked', 'member', p_member_id,
      jsonb_build_object('attempted_from', v_prev_status, 'attempted_to', p_new_status),
      jsonb_build_object('error', SQLERRM, 'arm9_gate', 'validate_status_transition')
    );
    RETURN jsonb_build_object('error', SQLERRM, 'arm9_gate', 'validate_status_transition');
  END;

  v_new_role := CASE p_new_status
    WHEN 'alumni'   THEN 'alumni'
    WHEN 'inactive' THEN 'none'
  END;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 'member.status_transition', 'member', p_member_id,
    jsonb_strip_nulls(jsonb_build_object(
      'previous_status', v_prev_status, 'new_status', p_new_status,
      'previous_tribe_id', v_member.tribe_id
    )),
    jsonb_strip_nulls(jsonb_build_object(
      'reason_category', p_reason_category, 'reason_detail', p_reason_detail,
      'items_reassigned_to', p_reassign_to
    ))
  )
  RETURNING id INTO v_audit_id;

  IF v_member.operational_role IS DISTINCT FROM v_new_role THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id, 'member.role_change', 'member', p_member_id,
      jsonb_build_object(
        'field', 'operational_role',
        'old_value', to_jsonb(v_member.operational_role),
        'new_value', to_jsonb(v_new_role),
        'effective_date', CURRENT_DATE
      ),
      jsonb_strip_nulls(jsonb_build_object(
        'change_type', 'role_changed',
        'reason', p_reason_detail,
        'authorized_by', v_caller.id
      ))
    );
  END IF;

  -- #1200: authoritative offboarding record with the REAL caller-supplied category.
  -- FK-validated with fallback 'other' (#449a never-crash). Must run BEFORE the
  -- members UPDATE so trg_offboarding_stub's EXISTS guard skips its inference stub.
  -- ON CONFLICT (member_id) DO NOTHING preserves the one-record-per-member,
  -- first-offboard-wins semantics the trigger already had.
  SELECT code INTO v_reason_code FROM public.offboard_reason_categories WHERE code = p_reason_category;
  v_reason_code := COALESCE(v_reason_code, 'other');

  INSERT INTO public.member_offboarding_records (
    member_id, offboarded_at, offboarded_by,
    reason_category_code, reason_detail,
    tribe_id_at_offboard, chapter_at_offboard, cycle_code_at_offboard
  ) VALUES (
    p_member_id, now(), v_caller.id,
    v_reason_code, NULLIF(TRIM(COALESCE(p_reason_detail, '')), ''),
    v_member.tribe_id, v_member.chapter,
    (SELECT cycle_code FROM public.cycles WHERE is_current = true ORDER BY cycle_start DESC LIMIT 1)
  )
  ON CONFLICT (member_id) DO NOTHING;

  UPDATE public.members SET
    member_status        = p_new_status,
    operational_role     = v_new_role,
    is_active            = false,
    designations         = '{}'::text[],
    offboarded_at        = now(),
    offboarded_by        = v_caller.id,
    status_changed_at    = now(),
    status_change_reason = COALESCE(p_reason_detail, p_reason_category),
    updated_at           = now()
  WHERE id = p_member_id;

  IF v_member.person_id IS NOT NULL THEN
    UPDATE public.engagements SET
      status = 'offboarded', end_date = CURRENT_DATE,
      revoked_at = now(), revoked_by = v_caller.person_id,
      revoke_reason = COALESCE(p_reason_detail, p_reason_category),
      updated_at = now()
    WHERE person_id = v_member.person_id AND status = 'active';
    GET DIAGNOSTICS v_engagements_closed = ROW_COUNT;
  END IF;

  IF p_reassign_to IS NOT NULL THEN
    UPDATE public.board_items SET assignee_id = p_reassign_to
    WHERE assignee_id = p_member_id AND status != 'archived';
    GET DIAGNOSTICS v_items_reassigned = ROW_COUNT;
  END IF;

  -- #322 offboarding extension: auto-skip any open volunteer_term step for
  -- the offboarded member. Idempotent via status='pending' filter. Respects
  -- #321 trigger ordering: if a cert was inserted before offboard, the step
  -- is already 'completed' and gets filtered out here.
  UPDATE public.onboarding_progress
  SET
    status = 'skipped',
    completed_at = now(),
    updated_at = now(),
    metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
      'completed_via', 'p234_322_offboarding_extension',
      'reason', 'offboarded_pre_signing',
      'offboarded_to_status', p_new_status,
      'offboarded_at', now(),
      'migration', '20260805000019'
    )
  WHERE member_id = p_member_id
    AND step_key = 'volunteer_term'
    AND status = 'pending';
  GET DIAGNOSTICS v_vol_terms_skipped = ROW_COUNT;

  IF v_vol_terms_skipped > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (
      v_caller.id,
      'onboarding.volunteer_term_skipped_on_offboard',
      'member',
      p_member_id,
      jsonb_build_object(
        'rows_affected', v_vol_terms_skipped,
        'offboarded_to_status', p_new_status,
        'reason', 'offboarded_pre_signing',
        'migration', '20260805000019'
      )
    );
  END IF;

  -- ARM-9 G3: auto-emit alumni_recognition certificate
  IF p_new_status = 'alumni' AND p_reason_category IS NOT NULL THEN
    SELECT * INTO v_reason_record FROM public.offboard_reason_categories
    WHERE code = p_reason_category;

    IF FOUND AND v_reason_record.preserves_return_eligibility = true THEN
      BEGIN
        -- Safe cycle extraction: digits from cycle_code text, fallback 3
        SELECT COALESCE(NULLIF(regexp_replace(cycle_code, '[^0-9]', '', 'g'), '')::int, 3)
        INTO v_current_cycle_int
        FROM public.cycles WHERE is_current = true LIMIT 1;
        v_current_cycle_int := COALESCE(v_current_cycle_int, 3);

        v_certificate_code := 'CERT-' || extract(year FROM now())::text || '-' || upper(substr(md5(random()::text), 1, 6));

        INSERT INTO public.certificates (
          member_id, type, title, description, cycle, function_role,
          language, issued_by, verification_code, issued_at, source
        ) VALUES (
          p_member_id,
          'alumni_recognition',
          'Reconhecimento Alumni — Núcleo IA & GP',
          'Em reconhecimento à contribuição como voluntário(a) ao programa Núcleo IA & GP. Saída amigável em ' || to_char(now(), 'DD/MM/YYYY') || ' (' || v_reason_record.label_pt || '). Elegível para retorno via re-engagement pipeline.',
          v_current_cycle_int,
          v_member.operational_role,
          'pt-BR',
          v_caller.id,
          v_certificate_code,
          now(),
          'arm9_g3_auto_emit'
        )
        RETURNING id INTO v_certificate_id;

        PERFORM public.create_notification(
          p_member_id,
          'certificate_issued',
          'Certificado Alumni emitido',
          'Você recebeu o certificado Reconhecimento Alumni — válido para perfil profissional e LinkedIn.',
          '/gamification',
          'certificate',
          v_certificate_id
        );
      EXCEPTION WHEN OTHERS THEN
        v_emit_error := SQLERRM;
        v_certificate_id := NULL;
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_caller.id, 'arm9.alumni_badge_emit_failed', 'member', p_member_id,
          jsonb_build_object('reason_category', p_reason_category),
          jsonb_build_object('error', v_emit_error)
        );
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'audit_id', v_audit_id,
    'transition_id', v_audit_id,
    'member_name', v_member.name,
    'previous_status', v_prev_status,
    'new_status', p_new_status,
    'new_role', v_new_role,
    'items_reassigned', v_items_reassigned,
    'engagements_closed', v_engagements_closed,
    'vol_terms_skipped', v_vol_terms_skipped,
    'designations_cleared', COALESCE(array_length(v_member.designations,1),0),
    'alumni_certificate_id', v_certificate_id,
    'alumni_certificate_emit_error', v_emit_error
  );
END;
$function$;
