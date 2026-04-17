-- ============================================================
-- B8.1 — platform_settings_log consolidation + get_audit_log fix
--
-- Fecha o TODO deixado por B8 (commit 2e0fe45 / mig 20260425020000):
--   - ADR-0013 "Consolidação pendente (P2): platform_settings_log"
--
-- Descobrimento 17/Abr p4: B8 movou member_status_transitions +
-- member_role_changes para z_archive via ALTER TABLE SET SCHEMA, mas
-- get_audit_log NÃO foi atualizada. A função está QUEBRADA em produção
-- (qualquer admin abrindo /admin/audit-log recebe "relation does not exist").
--
-- Esta migration:
--   1. Backfill 1 row de platform_settings_log → admin_audit_log
--   2. Reescreve admin_update_setting para escrever direto em admin_audit_log
--   3. Reescreve get_audit_log lendo admin_audit_log (bug fix)
--   4. Reescreve export_audit_log_csv para usar admin_audit_log (remove dep de psl)
--   5. Move platform_settings_log para z_archive
--
-- Mapeamento shape:
--   platform_settings_log row → admin_audit_log row:
--     actor_id      ← actor_member_id
--     action        ← 'platform.setting_changed'
--     target_type   ← 'setting'
--     target_id     ← NULL (settings keyed por string, not uuid)
--     changes       ← {previous_value, new_value}
--     metadata      ← {setting_key, reason, _backfill_source='platform_settings_log'}
--
-- Rollback:
--   ALTER TABLE z_archive.platform_settings_log SET SCHEMA public;
--   (reexecutar versões anteriores de admin_update_setting/get_audit_log/export_audit_log_csv)
--   DELETE FROM public.admin_audit_log WHERE action='platform.setting_changed'
--     AND metadata->>'_backfill_source'='platform_settings_log';
-- ============================================================

-- 1. Backfill existing platform_settings_log rows into admin_audit_log
-- ------------------------------------------------------------
INSERT INTO public.admin_audit_log (
  id, actor_id, action, target_type, target_id, changes, metadata, created_at
)
SELECT
  psl.id,
  psl.actor_member_id,
  'platform.setting_changed'::text,
  'setting'::text,
  NULL::uuid,
  jsonb_build_object(
    'previous_value', psl.previous_value,
    'new_value',      psl.new_value
  ),
  jsonb_build_object(
    'setting_key',      psl.setting_key,
    'reason',           psl.reason,
    '_backfill_source', 'platform_settings_log'
  ),
  psl.created_at
FROM public.platform_settings_log psl
ON CONFLICT (id) DO NOTHING;

-- 1b. Seed manage_platform action in engagement_kind_permissions (ADR-0011)
-- ------------------------------------------------------------
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope)
VALUES
  ('volunteer', 'co_gp',          'manage_platform', 'organization'),
  ('volunteer', 'deputy_manager', 'manage_platform', 'organization'),
  ('volunteer', 'manager',        'manage_platform', 'organization')
ON CONFLICT DO NOTHING;

-- 2. Rewrite admin_update_setting to write directly to admin_audit_log
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_update_setting(text, jsonb, text);

CREATE FUNCTION public.admin_update_setting(
  p_key text,
  p_new_value jsonb,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller record;
  v_old_value jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- ADR-0011: can_by_member with manage_platform action (seeded above)
  -- is_superadmin fallback preserves legacy superadmin flag for emergency access
  IF NOT (v_caller.is_superadmin IS TRUE
       OR public.can_by_member(v_caller.id, 'manage_platform')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RETURN jsonb_build_object('error', 'Reason is required');
  END IF;

  SELECT value INTO v_old_value FROM public.platform_settings WHERE key = p_key;

  -- Write to admin_audit_log (canonical, post-B8.1)
  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'platform.setting_changed',
    'setting',
    NULL,
    jsonb_build_object('previous_value', v_old_value, 'new_value', p_new_value),
    jsonb_build_object('setting_key', p_key, 'reason', p_reason)
  );

  UPDATE public.platform_settings
  SET value = p_new_value,
      changed_by = v_caller.id,
      changed_at = now(),
      change_reason = p_reason
  WHERE key = p_key;

  RETURN jsonb_build_object(
    'success', true,
    'key', p_key,
    'previous', v_old_value,
    'new', p_new_value
  );
END;
$$;

-- 3. Rewrite get_audit_log reading from admin_audit_log (bug fix + B8.1)
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_audit_log(uuid, uuid, text, timestamptz, timestamptz, integer, integer);

CREATE FUNCTION public.get_audit_log(
  p_actor_id uuid DEFAULT NULL,
  p_target_id uuid DEFAULT NULL,
  p_action text DEFAULT NULL,
  p_date_from timestamptz DEFAULT NULL,
  p_date_to timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller record;
  v_entries jsonb;
  v_total bigint;
  v_actors jsonb;
  v_search text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- ADR-0011: audit log carries member changes + settings (PII-adjacent).
  -- Use manage_platform (seeded above) OR is_superadmin fallback.
  IF NOT (v_caller.is_superadmin IS TRUE
       OR public.can_by_member(v_caller.id, 'manage_platform')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  v_search := CASE WHEN p_action IS NOT NULL AND trim(p_action) != ''
                   THEN '%' || trim(p_action) || '%' ELSE NULL END;

  WITH unified AS (
    -- Members category: from admin_audit_log (post-B8)
    SELECT
      al.id::text AS id,
      'members'::text AS category,
      al.created_at AS event_date,
      al.actor_id AS actor_id,
      actor.name AS actor_name,
      CASE al.action
        WHEN 'member.status_transition' THEN 'status_change'
        WHEN 'member.role_change' THEN 'role_change'
        ELSE replace(al.action, 'member.', '')
      END AS action,
      target.name AS target_name,
      al.target_id AS target_id,
      CASE al.action
        WHEN 'member.status_transition' THEN
          COALESCE(al.changes->>'previous_status','') || ' → ' || COALESCE(al.changes->>'new_status','')
        WHEN 'member.role_change' THEN
          COALESCE(al.changes->>'field','') || ': ' ||
          COALESCE(al.changes->>'old_value','') || ' → ' || COALESCE(al.changes->>'new_value','')
        ELSE al.changes::text
      END AS summary,
      COALESCE(al.metadata->>'reason_detail', al.metadata->>'reason') AS detail
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor  ON actor.id  = al.actor_id
    LEFT JOIN public.members target ON target.id = al.target_id
    WHERE al.target_type = 'member'
      AND al.action IN ('member.status_transition','member.role_change')

    UNION ALL

    -- Boards category: from board_lifecycle_events (Cat B, stays separate)
    SELECT
      ble.id::text,
      'boards',
      ble.created_at,
      ble.actor_member_id,
      actor.name,
      ble.action,
      COALESCE(bi.title, 'Card'),
      ble.item_id,
      COALESCE(ble.previous_status, '') ||
        CASE WHEN ble.new_status IS NOT NULL AND ble.previous_status IS NOT NULL THEN ' → ' || ble.new_status
             WHEN ble.new_status IS NOT NULL THEN ble.new_status
             ELSE '' END,
      ble.reason
    FROM public.board_lifecycle_events ble
    LEFT JOIN public.board_items bi ON bi.id = ble.item_id
    LEFT JOIN public.members actor ON actor.id = ble.actor_member_id

    UNION ALL

    -- Settings category: from admin_audit_log (post-B8.1)
    SELECT
      al.id::text,
      'settings',
      al.created_at,
      al.actor_id,
      actor.name,
      'setting_changed',
      COALESCE(al.metadata->>'setting_key', '(unknown)'),
      NULL::uuid,
      COALESCE(al.changes->>'previous_value', '?') || ' → ' ||
      COALESCE(al.changes->>'new_value', '?'),
      al.metadata->>'reason'
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE al.action = 'platform.setting_changed'

    UNION ALL

    -- Partnerships category: from partner_interactions (Cat B, stays separate)
    SELECT
      pi.id::text,
      'partnerships',
      pi.created_at,
      pi.actor_member_id,
      actor.name,
      pi.interaction_type,
      pe.name,
      NULL::uuid,
      pi.summary,
      pi.outcome
    FROM public.partner_interactions pi
    JOIN public.partner_entities pe ON pe.id = pi.partner_id
    LEFT JOIN public.members actor ON actor.id = pi.actor_member_id
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', u.id, 'category', u.category, 'created_at', u.event_date,
      'actor_id', u.actor_id, 'actor_name', COALESCE(u.actor_name, 'Sistema'),
      'action', u.action, 'target_name', u.target_name, 'target_id', u.target_id,
      'changes', NULL, 'summary', u.summary, 'detail', u.detail
    ) ORDER BY u.event_date DESC
  )
  INTO v_entries
  FROM unified u
  WHERE (p_actor_id IS NULL OR u.actor_id = p_actor_id)
    AND (p_target_id IS NULL OR u.target_id = p_target_id)
    AND (p_date_from IS NULL OR u.event_date >= p_date_from)
    AND (p_date_to IS NULL OR u.event_date <= p_date_to)
    AND (v_search IS NULL
      OR u.action ILIKE v_search OR u.category ILIKE v_search
      OR u.target_name ILIKE v_search OR u.summary ILIKE v_search
      OR COALESCE(u.detail,'') ILIKE v_search
      OR COALESCE(u.actor_name,'') ILIKE v_search)
  LIMIT p_limit OFFSET p_offset;

  -- Total count with same filters
  WITH unified2 AS (
    SELECT al.actor_id AS actor_id, al.created_at AS event_date,
           CASE al.action WHEN 'member.status_transition' THEN 'status_change'
                          WHEN 'member.role_change' THEN 'role_change'
                          ELSE replace(al.action,'member.','') END AS action,
           'members'::text AS category,
           target.name AS target_name,
           CASE al.action
             WHEN 'member.status_transition' THEN
               COALESCE(al.changes->>'previous_status','')||' → '||COALESCE(al.changes->>'new_status','')
             WHEN 'member.role_change' THEN
               COALESCE(al.changes->>'old_value','')||' → '||COALESCE(al.changes->>'new_value','')
             ELSE al.changes::text END AS summary,
           COALESCE(al.metadata->>'reason_detail', al.metadata->>'reason') AS detail,
           actor.name AS actor_name,
           al.target_id
    FROM public.admin_audit_log al
    LEFT JOIN public.members target ON target.id = al.target_id
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE al.target_type = 'member'
      AND al.action IN ('member.status_transition','member.role_change')
    UNION ALL
    SELECT ble.actor_member_id, ble.created_at, ble.action, 'boards',
           COALESCE(bi.title,'Card'),
           COALESCE(ble.previous_status,'')||COALESCE(' → '||ble.new_status,''),
           ble.reason, actor.name, ble.item_id
    FROM public.board_lifecycle_events ble
    LEFT JOIN public.board_items bi ON bi.id = ble.item_id
    LEFT JOIN public.members actor ON actor.id = ble.actor_member_id
    UNION ALL
    SELECT al.actor_id, al.created_at, 'setting_changed', 'settings',
           COALESCE(al.metadata->>'setting_key','(unknown)'),
           COALESCE(al.changes->>'previous_value','?')||' → '||COALESCE(al.changes->>'new_value','?'),
           al.metadata->>'reason', actor.name, NULL::uuid
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE al.action = 'platform.setting_changed'
    UNION ALL
    SELECT pi.actor_member_id, pi.created_at, pi.interaction_type, 'partnerships',
           pe.name, pi.summary, pi.outcome, actor.name, NULL::uuid
    FROM public.partner_interactions pi
    JOIN public.partner_entities pe ON pe.id = pi.partner_id
    LEFT JOIN public.members actor ON actor.id = pi.actor_member_id
  )
  SELECT count(*) INTO v_total FROM unified2 u
  WHERE (p_actor_id IS NULL OR u.actor_id = p_actor_id)
    AND (p_target_id IS NULL OR u.target_id = p_target_id)
    AND (p_date_from IS NULL OR u.event_date >= p_date_from)
    AND (p_date_to IS NULL OR u.event_date <= p_date_to)
    AND (v_search IS NULL
      OR u.action ILIKE v_search OR u.category ILIKE v_search
      OR u.target_name ILIKE v_search OR u.summary ILIKE v_search
      OR COALESCE(u.detail,'') ILIKE v_search
      OR COALESCE(u.actor_name,'') ILIKE v_search);

  -- Actors
  SELECT jsonb_agg(DISTINCT jsonb_build_object('id', a.id, 'name', a.name))
  INTO v_actors
  FROM (
    SELECT DISTINCT al.actor_id AS id FROM public.admin_audit_log al
      WHERE al.actor_id IS NOT NULL
    UNION SELECT DISTINCT ble.actor_member_id FROM public.board_lifecycle_events ble
      WHERE ble.actor_member_id IS NOT NULL
    UNION SELECT DISTINCT pi.actor_member_id FROM public.partner_interactions pi
      WHERE pi.actor_member_id IS NOT NULL
  ) ids JOIN public.members a ON a.id = ids.id;

  RETURN jsonb_build_object(
    'entries', COALESCE(v_entries, '[]'::jsonb),
    'total', COALESCE(v_total, 0),
    'actors', COALESCE(v_actors, '[]'::jsonb)
  );
END;
$$;

-- 4. Rewrite export_audit_log_csv: settings now from admin_audit_log
-- ------------------------------------------------------------
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
    category||','||to_char(event_date,'YYYY-MM-DD HH24:MI')||','||
    COALESCE(replace(actor_name,',',';'),'')||','||
    COALESCE(replace(action,',',';'),'')||','||
    COALESCE(replace(subject,',',';'),'')||','||
    COALESCE(replace(summary,',',';'),'')||','||
    COALESCE(replace(detail,',',';'),''),
    E'\n'
  ) INTO v_csv
  FROM (
    -- Members category
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

    -- Settings category: now from admin_audit_log (post-B8.1)
    SELECT
      'settings',
      al.created_at,
      actor.name,
      'setting_changed',
      COALESCE(al.metadata->>'setting_key', '(unknown)'),
      COALESCE(al.changes->>'previous_value','?') || ' → ' ||
      COALESCE(al.changes->>'new_value','?'),
      al.metadata->>'reason'
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE (p_category='all' OR p_category='settings')
      AND al.action = 'platform.setting_changed'
      AND (p_start_date IS NULL OR al.created_at >= p_start_date::timestamptz)
      AND (p_end_date   IS NULL OR al.created_at <= (p_end_date::date + 1)::timestamptz)

    UNION ALL

    -- Partnerships category: unchanged
    SELECT
      'partnerships',
      pi.created_at,
      actor.name,
      pi.interaction_type,
      pe.name,
      pi.summary,
      pi.outcome
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

-- 5. Archive platform_settings_log (move to z_archive)
-- ------------------------------------------------------------
ALTER TABLE public.platform_settings_log SET SCHEMA z_archive;

COMMENT ON TABLE z_archive.platform_settings_log IS
  'Archived 2026-04-17 (B8.1). Rows consolidated to admin_audit_log with action=platform.setting_changed. Kept for forensic reference only — no active writers.';

-- 6. Register in schema_migrations + reload
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
