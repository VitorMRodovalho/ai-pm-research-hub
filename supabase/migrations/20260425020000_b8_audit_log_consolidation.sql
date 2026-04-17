-- ============================================================
-- B8 — Audit log consolidation (ADR-0012 closure)
--
-- Consolidates 2 fragmented audit tables into admin_audit_log:
--   - member_role_changes (13 rows) → admin_audit_log (action='member.role_change')
--   - member_status_transitions (21 rows) → admin_audit_log (action='member.status_transition')
--
-- admin_audit_log is the master dim for admin-side auditing. 17/Abr audit
-- flagged 17 log tables fragmented; this closes 2 of them. Others
-- (platform_settings_log, partner_interactions, mcp_usage_log, etc.) are
-- domain-specific and stay separate.
--
-- Transformation:
-- member_status_transitions row → admin_audit_log row:
--   actor_id      ← actor_member_id
--   action        ← 'member.status_transition'
--   target_type   ← 'member'
--   target_id     ← member_id
--   changes (jsonb) ← previous_status, new_status, previous_tribe_id, new_tribe_id
--   metadata (jsonb) ← reason_category, reason_detail, items_reassigned_to,
--                      notified_leader, notified_member, _backfill_source
--
-- member_role_changes row → admin_audit_log row:
--   actor_id      ← COALESCE(executed_by, authorized_by)
--   action        ← 'member.role_change'
--   target_type   ← 'member'
--   target_id     ← member_id
--   changes (jsonb) ← field, old_value, new_value, effective_date, reference_doc_*
--   metadata (jsonb) ← change_type, reason, authorized_by, cycle_code, notes,
--                      _backfill_source
--
-- UUIDs preserved for traceability. `_backfill_source` key tags historical
-- rows so future migrations can distinguish pre-B8 vs post-B8 writes.
--
-- RPCs updated:
--   - admin_offboard_member: writes to admin_audit_log (not old tables)
--   - admin_reactivate_member: writes to admin_audit_log (not old tables)
--   - export_audit_log_csv: reads from admin_audit_log (not old tables)
--
-- Old tables SET SCHEMA z_archive (reversible — not DROP). Pattern from W132.
--
-- Rollback:
--   ALTER TABLE z_archive.member_role_changes SET SCHEMA public;
--   ALTER TABLE z_archive.member_status_transitions SET SCHEMA public;
--   DELETE FROM public.admin_audit_log WHERE metadata->>'_backfill_source' IN
--     ('member_role_changes','member_status_transitions');
--   -- Restore old RPC bodies from migrations 20260424050000 + 20260424060000.
-- ============================================================

-- ── Step 1: backfill historical rows ──────────────────────────

INSERT INTO public.admin_audit_log (id, actor_id, action, target_type, target_id, changes, metadata, created_at)
SELECT
  id,
  actor_member_id,
  'member.status_transition',
  'member',
  member_id,
  jsonb_strip_nulls(jsonb_build_object(
    'previous_status', previous_status,
    'new_status', new_status,
    'previous_tribe_id', previous_tribe_id,
    'new_tribe_id', new_tribe_id
  )),
  jsonb_strip_nulls(jsonb_build_object(
    'reason_category', reason_category,
    'reason_detail', reason_detail,
    'items_reassigned_to', items_reassigned_to,
    'notified_leader', notified_leader,
    'notified_member', notified_member,
    '_backfill_source', 'member_status_transitions'
  )),
  created_at
FROM public.member_status_transitions
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.admin_audit_log (id, actor_id, action, target_type, target_id, changes, metadata, created_at)
SELECT
  id,
  COALESCE(executed_by, authorized_by),
  'member.role_change',
  'member',
  member_id,
  jsonb_strip_nulls(jsonb_build_object(
    'field', field_name,
    'old_value', old_value,
    'new_value', new_value,
    'effective_date', effective_date,
    'reference_doc_url', reference_doc_url,
    'reference_doc_id', reference_doc_id
  )),
  jsonb_strip_nulls(jsonb_build_object(
    'change_type', change_type,
    'reason', reason,
    'authorized_by', authorized_by,
    'cycle_code', cycle_code,
    'notes', notes,
    '_backfill_source', 'member_role_changes'
  )),
  created_at
FROM public.member_role_changes
ON CONFLICT (id) DO NOTHING;

-- ── Step 2: rewrite admin_offboard_member to write admin_audit_log ─

DROP FUNCTION IF EXISTS public.admin_offboard_member(uuid, text, text, text, uuid);

CREATE FUNCTION public.admin_offboard_member(
  p_member_id        uuid,
  p_new_status       text,
  p_reason_category  text,
  p_reason_detail    text DEFAULT NULL,
  p_reassign_to      uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller             record;
  v_member             record;
  v_audit_id           uuid;
  v_new_role           text;
  v_items_reassigned   integer := 0;
  v_engagements_closed integer := 0;
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

  IF v_member.member_status = p_new_status THEN
    RETURN jsonb_build_object('error','Member is already ' || p_new_status);
  END IF;

  v_new_role := CASE p_new_status
    WHEN 'alumni'   THEN 'alumni'
    WHEN 'observer' THEN 'observer'
    WHEN 'inactive' THEN 'none'
  END;

  -- Audit: status transition
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id,
    'member.status_transition',
    'member',
    p_member_id,
    jsonb_strip_nulls(jsonb_build_object(
      'previous_status', COALESCE(v_member.member_status,'active'),
      'new_status', p_new_status,
      'previous_tribe_id', v_member.tribe_id
    )),
    jsonb_strip_nulls(jsonb_build_object(
      'reason_category', p_reason_category,
      'reason_detail', p_reason_detail,
      'items_reassigned_to', p_reassign_to
    ))
  )
  RETURNING id INTO v_audit_id;

  -- Audit: role change (only if role actually changes)
  IF v_member.operational_role IS DISTINCT FROM v_new_role THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id,
      'member.role_change',
      'member',
      p_member_id,
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

  RETURN jsonb_build_object(
    'success', true,
    'audit_id', v_audit_id,
    'transition_id', v_audit_id,  -- BC alias
    'member_name', v_member.name,
    'previous_status', COALESCE(v_member.member_status,'active'),
    'new_status', p_new_status,
    'new_role', v_new_role,
    'items_reassigned', v_items_reassigned,
    'engagements_closed', v_engagements_closed,
    'designations_cleared', COALESCE(array_length(v_member.designations,1),0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_offboard_member(uuid, text, text, text, uuid) TO authenticated;

-- ── Step 3: rewrite admin_reactivate_member ──────────────────

DROP FUNCTION IF EXISTS public.admin_reactivate_member(uuid, integer, text);

CREATE FUNCTION public.admin_reactivate_member(
  p_member_id uuid,
  p_tribe_id  integer,
  p_role      text DEFAULT 'researcher'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
$$;

GRANT EXECUTE ON FUNCTION public.admin_reactivate_member(uuid, integer, text) TO authenticated;

-- ── Step 4: rewrite export_audit_log_csv to read admin_audit_log ──

DROP FUNCTION IF EXISTS public.export_audit_log_csv(text, text, text);

CREATE FUNCTION public.export_audit_log_csv(
  p_category text DEFAULT 'all',
  p_start_date text DEFAULT NULL,
  p_end_date text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_csv text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN 'Unauthorized'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RETURN 'Unauthorized: requires view_pii permission';
  END IF;

  SELECT string_agg(
    category||','||to_char(event_date,'YYYY-MM-DD HH24:MI')||','||COALESCE(replace(actor_name,',',';'),'')||','||
    COALESCE(replace(action,',',';'),'')||','||COALESCE(replace(subject,',',';'),'')||','||
    COALESCE(replace(summary,',',';'),'')||','||COALESCE(replace(detail,',',';'),''), E'\n'
  ) INTO v_csv
  FROM (
    SELECT
      'members' AS category,
      al.created_at AS event_date,
      actor.name AS actor_name,
      CASE al.action
        WHEN 'member.status_transition' THEN 'status_change'
        WHEN 'member.role_change' THEN 'role_change'
        ELSE al.action
      END AS action,
      target.name AS subject,
      CASE al.action
        WHEN 'member.status_transition' THEN
          COALESCE(al.changes->>'previous_status','') || ' → ' || COALESCE(al.changes->>'new_status','')
        WHEN 'member.role_change' THEN
          COALESCE(al.changes->>'old_value','') || ' → ' || COALESCE(al.changes->>'new_value','')
        ELSE al.changes::text
      END AS summary,
      COALESCE(al.metadata->>'reason_detail', al.metadata->>'reason') AS detail
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor  ON actor.id  = al.actor_id
    LEFT JOIN public.members target ON target.id = al.target_id
    WHERE (p_category = 'all' OR p_category = 'members')
      AND al.action IN ('member.status_transition','member.role_change')
      AND (p_start_date IS NULL OR al.created_at >= p_start_date::timestamptz)
      AND (p_end_date   IS NULL OR al.created_at <= (p_end_date::date + 1)::timestamptz)
    UNION ALL
    SELECT 'settings', psl.created_at, actor.name, 'setting_changed', psl.setting_key,
           psl.previous_value::text || ' → ' || psl.new_value::text, psl.reason
    FROM public.platform_settings_log psl
    LEFT JOIN public.members actor ON actor.id = psl.actor_member_id
    WHERE (p_category='all' OR p_category='settings')
      AND (p_start_date IS NULL OR psl.created_at >= p_start_date::timestamptz)
      AND (p_end_date   IS NULL OR psl.created_at <= (p_end_date::date + 1)::timestamptz)
    UNION ALL
    SELECT 'partnerships', pi.created_at, actor.name, pi.interaction_type, pe.name,
           pi.summary, pi.outcome
    FROM public.partner_interactions pi
    JOIN public.partner_entities pe ON pe.id = pi.partner_id
    LEFT JOIN public.members actor ON actor.id = pi.actor_member_id
    WHERE (p_category='all' OR p_category='partnerships')
      AND (p_start_date IS NULL OR pi.created_at >= p_start_date::timestamptz)
      AND (p_end_date   IS NULL OR pi.created_at <= (p_end_date::date + 1)::timestamptz)
    ORDER BY event_date DESC
  ) entries;

  RETURN 'Categoria,Data,Actor,Ação,Assunto,Resumo,Detalhe' || E'\n' || COALESCE(v_csv,'');
END;
$$;

GRANT EXECUTE ON FUNCTION public.export_audit_log_csv(text, text, text) TO authenticated;

-- ── Step 5: archive old tables ──────────────────────────────

ALTER TABLE public.member_role_changes       SET SCHEMA z_archive;
ALTER TABLE public.member_status_transitions SET SCHEMA z_archive;

-- ── Step 6: reload PostgREST ────────────────────────────────

NOTIFY pgrst, 'reload schema';

COMMENT ON COLUMN public.admin_audit_log.action IS
  'Audit action category. Known values: member.status_transition, member.role_change, member.anonymize, event.insert, event.update, event.delete, settings.changed, certificate.issued, etc. ADR-0012 B8: member_role_changes/member_status_transitions consolidated here 2026-04-18.';
