-- Track Q Phase B — drift signals #5 + #6 fix (partner subsystem)
--
-- Signal #5: get_partner_interaction_attachments dereferences
--   `v_interaction.partner_entity_id` — but `partner_interactions` table has
--   no such column (only `partner_id` FK → partner_entities.id). The function
--   would error at runtime ("record v_interaction has no field
--   partner_entity_id"). Currently dead code (no frontend / MCP callsite),
--   but live in pg_proc and types in database.gen.ts. Fix: use
--   `v_interaction.partner_id`.
--
-- Signal #6: get_partner_followups 'stale' bucket filter excludes
--   `'active'` partners. Defeats the bucket's purpose (catch active
--   partnerships with no recent interaction = relationship cooling). Other
--   buckets ('overdue', 'upcoming') correctly exclude only terminal statuses
--   ('inactive', 'churned'). Live data confirms 5 active partners are
--   stale-eligible and would be hidden by current filter.
--   Fix: drop 'active' from the NOT IN list.
--
-- Both fixes preserve all other behavior (auth gates, output shape, ordering).
-- Bodies otherwise verbatim from p52 Q-A capture
-- (20260425142756_qa_orphan_recovery_partner_crud.sql).

CREATE OR REPLACE FUNCTION public.get_partner_interaction_attachments(p_interaction_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_interaction record;
  v_entity record;
  v_is_gp boolean;
  v_is_curator boolean;
  v_is_leader boolean;
  v_is_chapter_stakeholder boolean;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  SELECT * INTO v_interaction FROM partner_interactions WHERE id = p_interaction_id;
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  -- Drift fix #5: was `v_interaction.partner_entity_id` (column does not exist
  -- on partner_interactions). FK column is `partner_id` → partner_entities.id.
  SELECT * INTO v_entity FROM partner_entities WHERE id = v_interaction.partner_id;

  v_is_gp := coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager');
  v_is_curator := 'curator' = ANY(coalesce(v_caller.designations, ARRAY[]::text[]));
  v_is_leader := v_caller.operational_role = 'tribe_leader';
  v_is_chapter_stakeholder := v_caller.operational_role IN ('sponsor', 'chapter_liaison')
    AND (v_entity.chapter IS NULL OR v_entity.chapter = v_caller.chapter);

  IF NOT (v_is_gp OR v_is_curator OR v_is_leader OR v_is_chapter_stakeholder) THEN
    RETURN '[]'::jsonb;
  END IF;

  IF v_entity.chapter IS NULL AND NOT v_is_gp AND NOT v_is_curator THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id', pa.id,
      'file_name', pa.file_name,
      'file_url', pa.file_url,
      'file_size', pa.file_size,
      'file_type', pa.file_type,
      'description', pa.description,
      'uploaded_by_name', m.name,
      'created_at', pa.created_at
    ) ORDER BY pa.created_at DESC)
    FROM partner_attachments pa
    JOIN members m ON m.id = pa.uploaded_by
    WHERE pa.partner_interaction_id = p_interaction_id
  ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_partner_followups()
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
  IF v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND v_caller.is_superadmin IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  RETURN jsonb_build_object(
    'overdue', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'partner_id', pe.id, 'partner_name', pe.name,
        'follow_up_date', pe.follow_up_date, 'next_action', pe.next_action,
        'days_overdue', CURRENT_DATE - pe.follow_up_date, 'status', pe.status
      ) ORDER BY pe.follow_up_date ASC), '[]'::jsonb)
      FROM partner_entities pe
      WHERE pe.follow_up_date < CURRENT_DATE AND pe.status NOT IN ('inactive', 'churned')
    ),
    'upcoming', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'partner_id', pe.id, 'partner_name', pe.name,
        'follow_up_date', pe.follow_up_date, 'next_action', pe.next_action,
        'days_until', pe.follow_up_date - CURRENT_DATE, 'status', pe.status
      ) ORDER BY pe.follow_up_date ASC), '[]'::jsonb)
      FROM partner_entities pe
      WHERE pe.follow_up_date >= CURRENT_DATE AND pe.follow_up_date <= CURRENT_DATE + 14
        AND pe.status NOT IN ('inactive', 'churned')
    ),
    'stale', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'partner_id', pe.id, 'partner_name', pe.name,
        'last_interaction_at', pe.last_interaction_at,
        'days_since', EXTRACT(DAY FROM now() - COALESCE(pe.last_interaction_at, pe.created_at))::int,
        'status', pe.status
      ) ORDER BY COALESCE(pe.last_interaction_at, pe.created_at) ASC), '[]'::jsonb)
      FROM partner_entities pe
      WHERE COALESCE(pe.last_interaction_at, pe.created_at) < now() - interval '30 days'
        -- Drift fix #6: was NOT IN ('inactive', 'churned', 'active') — the
        -- 'active' exclusion defeated the bucket's whole purpose (flagging
        -- active partnerships with no recent interaction = cooling
        -- relationship). Aligned with overdue/upcoming buckets.
        AND pe.status NOT IN ('inactive', 'churned')
    )
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
