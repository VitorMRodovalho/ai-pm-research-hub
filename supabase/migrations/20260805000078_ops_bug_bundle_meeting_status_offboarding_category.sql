-- Ops-bug bundle (p277) — meeting decisions (#450) + offboarding category (#449)
-- Scope: MINIMAL ("destravar já", PM-ratified 2026-05-31). Lowest blast radius.
--
-- #450 — register_decision + create_action_item(kind='decision') wrote status='completed',
--        invalid under meeting_action_items_status_check = {open,done,cancelled,carried_over}.
--        Every decision-registration RPC failed at runtime (23514). Fix: 'completed' -> 'done'.
--        (Live evidence pre-fix: 5 kind='decision' rows existed via direct DML, 0 via the RPCs;
--        0 rows ever held status='completed'.)
--
-- #449 — offboarding a member rolled back entirely. The AFTER UPDATE trigger trg_offboarding_stub
--        -> _offboarding_create_stub() re-derives the reason category by regex-parsing
--        members.status_change_reason (^[a-z_]+:\s). A normal reason never matches -> category NULL
--        -> violates member_offboarding_records.reason_category_code NOT NULL (FK
--        offboard_reason_categories) -> the whole offboard rolls back. offboard_member also
--        hardcoded the phantom category 'administrative' (not a real code; valid codes include
--        'other', which preserves return eligibility).
--        MINIMAL fix (record category falls back to 'other' / "Outros"; capturing the operator's
--        picked category is deferred to a follow-up):
--          (a) trigger inserts COALESCE(v_inferred_category, 'other') — never NULL, never crashes;
--          (c) offboard_member passes the real code 'other' instead of phantom 'administrative'.
--        admin_offboard_member is RESTORED to its original body here (a prior in-session apply had
--        temporarily carried a wider "precision" variant; minimal scope reverts it) so the live
--        body matches this capture and the Phase-C drift gate stays clean.
--
-- All CREATE OR REPLACE (signatures, SECURITY DEFINER, search_path preserved; privileges
-- preserved on REPLACE). Rollback: re-apply the prior bodies.

-- ── #450a register_decision ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.register_decision(p_event_id uuid, p_title text, p_description text DEFAULT NULL::text, p_related_card_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action_id uuid;
  v_event record;
  v_full_text text;
  v_card_id uuid;
  v_links_created int := 0;
  v_card_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  SELECT id INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
    RETURN jsonb_build_object('error', 'title_required');
  END IF;

  v_full_text := trim(p_title) ||
    CASE WHEN p_description IS NOT NULL AND length(trim(p_description)) > 0
      THEN E'\n\n' || trim(p_description)
      ELSE ''
    END;

  -- Decision is an action item with kind='decision' (terminal status 'done')
  INSERT INTO public.meeting_action_items (
    event_id, description, kind, status, created_by
  ) VALUES (
    p_event_id, v_full_text, 'decision', 'done', v_caller_id
  )
  RETURNING id INTO v_action_id;

  -- Mark resolved with timestamp
  UPDATE public.meeting_action_items
  SET resolved_at = now(),
      resolved_by = v_caller_id,
      resolution_note = 'Decision registered',
      updated_at = now()
  WHERE id = v_action_id;

  -- Fanout: link decision to each related card via board_item_event_links
  IF p_related_card_ids IS NOT NULL AND array_length(p_related_card_ids, 1) > 0 THEN
    FOREACH v_card_id IN ARRAY p_related_card_ids
    LOOP
      SELECT organization_id INTO v_card_org FROM public.board_items WHERE id = v_card_id;
      IF v_card_org IS NOT NULL THEN
        INSERT INTO public.board_item_event_links (
          organization_id, board_item_id, event_id, link_type, author_id, note
        ) VALUES (
          v_card_org, v_card_id, p_event_id, 'decision', v_caller_id,
          'Decision: ' || trim(p_title)
        )
        ON CONFLICT (board_item_id, event_id, link_type) DO NOTHING;
        GET DIAGNOSTICS v_links_created = ROW_COUNT;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'decision_id', v_action_id,
    'event_id', p_event_id,
    'title', trim(p_title),
    'related_cards_linked', COALESCE(array_length(p_related_card_ids, 1), 0),
    'created_at', now()
  );
END;
$function$;

-- ── #450b create_action_item ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_action_item(p_event_id uuid, p_description text, p_assignee_id uuid DEFAULT NULL::uuid, p_due_date date DEFAULT NULL::date, p_board_item_id uuid DEFAULT NULL::uuid, p_checklist_item_id uuid DEFAULT NULL::uuid, p_kind text DEFAULT 'action'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_action_id uuid;
  v_assignee_name text;
  v_event record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- V4 gate: manage_event (mirrors ADR-0045 RLS on board_item_event_links)
  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  -- Validate event exists
  SELECT id, title INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN RETURN jsonb_build_object('error', 'event_not_found'); END IF;

  -- Validate kind
  IF p_kind NOT IN ('action','decision','followup','general') THEN
    RETURN jsonb_build_object('error', 'invalid_kind',
      'valid_kinds', jsonb_build_array('action','decision','followup','general'));
  END IF;

  -- Validate description
  IF p_description IS NULL OR length(trim(p_description)) = 0 THEN
    RETURN jsonb_build_object('error', 'description_required');
  END IF;

  -- Lookup assignee name (snapshot, even if assignee gets renamed later)
  IF p_assignee_id IS NOT NULL THEN
    SELECT name INTO v_assignee_name FROM public.members WHERE id = p_assignee_id;
    IF v_assignee_name IS NULL THEN
      RETURN jsonb_build_object('error', 'assignee_not_found', 'assignee_id', p_assignee_id);
    END IF;
  END IF;

  INSERT INTO public.meeting_action_items (
    event_id, description, assignee_id, assignee_name, due_date,
    board_item_id, checklist_item_id, kind, status, created_by
  ) VALUES (
    p_event_id, trim(p_description), p_assignee_id, v_assignee_name, p_due_date,
    p_board_item_id, p_checklist_item_id, p_kind,
    CASE WHEN p_kind = 'decision' THEN 'done' ELSE 'open' END,
    v_caller_id
  )
  RETURNING id INTO v_action_id;

  -- If linked to a board_item, also create board_item_event_links entry
  IF p_board_item_id IS NOT NULL THEN
    INSERT INTO public.board_item_event_links (
      organization_id, board_item_id, event_id, link_type, author_id, note
    )
    SELECT bi.organization_id, p_board_item_id, p_event_id,
      CASE p_kind
        WHEN 'decision' THEN 'decision'
        WHEN 'action' THEN 'action_emerged'
        ELSE 'discussed'
      END,
      v_caller_id, trim(p_description)
    FROM public.board_items bi
    WHERE bi.id = p_board_item_id
    ON CONFLICT (board_item_id, event_id, link_type) DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'action_item_id', v_action_id,
    'event_id', p_event_id,
    'kind', p_kind,
    'created_at', now()
  );
END;
$function$;

-- ── #449a offboarding trigger: never crash on category (minimal: COALESCE only)
CREATE OR REPLACE FUNCTION public._offboarding_create_stub()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_inferred_category text;
  v_reason_text       text;
  v_chapter           text;
  v_cycle_code        text;
BEGIN
  IF NEW.member_status NOT IN ('alumni','observer','inactive') THEN
    RETURN NEW;
  END IF;

  IF EXISTS (SELECT 1 FROM public.member_offboarding_records WHERE member_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  v_reason_text := COALESCE(NEW.status_change_reason, '');
  v_inferred_category := NULL;
  IF v_reason_text ~ '^[a-z_]+:\s' THEN
    v_inferred_category := SPLIT_PART(v_reason_text, ':', 1);
    IF NOT EXISTS (SELECT 1 FROM public.offboard_reason_categories WHERE code = v_inferred_category) THEN
      v_inferred_category := NULL;
    END IF;
  END IF;

  v_chapter := NEW.chapter;
  SELECT cycle_code INTO v_cycle_code
  FROM public.cycles WHERE is_current = true ORDER BY cycle_start DESC LIMIT 1;

  INSERT INTO public.member_offboarding_records (
    member_id, offboarded_at, offboarded_by,
    reason_category_code, reason_detail,
    tribe_id_at_offboard, chapter_at_offboard, cycle_code_at_offboard
  ) VALUES (
    NEW.id, COALESCE(NEW.offboarded_at, now()), NEW.offboarded_by,
    COALESCE(v_inferred_category, 'other'), NULLIF(TRIM(v_reason_text), ''),
    NEW.tribe_id, v_chapter, v_cycle_code
  );

  RETURN NEW;
END;
$function$;

-- ── admin_offboard_member: RESTORED to original body (precision deferred) ─────
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

  IF p_new_status NOT IN ('observer','alumni','inactive') THEN
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
    WHEN 'observer' THEN 'observer'
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

-- ── #449c offboard_member: pass a real category code (not phantom) ───────────
CREATE OR REPLACE FUNCTION public.offboard_member(p_member_id uuid, p_new_status text, p_reason text, p_effective_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN public.admin_offboard_member(
    p_member_id       => p_member_id,
    p_new_status      => p_new_status,
    p_reason_category => 'other',
    p_reason_detail   => p_reason,
    p_reassign_to     => NULL
  );
END;
$function$;
