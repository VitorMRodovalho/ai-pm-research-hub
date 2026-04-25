-- Track Q-A Batch F — orphan recovery: partner CRUD (7 fns)
--
-- Captures live bodies as-of 2026-04-25 for partnerships read/write surface.
-- Bodies preserved verbatim from `pg_get_functiondef` — no behavior change.
--
-- Drift signal (non-scope for Q-A capture):
-- - add_partner_interaction inserts into partner_interactions.partner_id and
--   updates partner_entities WHERE id = p_partner_id. Implies
--   partner_interactions.partner_id FKs to partner_entities.id.
-- - get_partner_interaction_attachments dereferences
--   v_interaction.partner_entity_id (different column name) to look up
--   partner_entities.id. Either two FK columns coexist or one is legacy
--   alias. Phase B drift inspection should reconcile naming.
-- - get_partner_followups filters `pe.status NOT IN ('inactive','churned','active')`
--   on the 'stale' bucket — likely intent was to find stale non-active
--   non-terminal entries, but the predicate excludes 'active' too. Capturing
--   verbatim; flag as Phase B candidate (potential bug).
--
-- All 7 are SECURITY DEFINER. Authority gates use legacy operational_role
-- comparisons + designations array. V4 can_by_member migration deferred.

CREATE OR REPLACE FUNCTION public.add_partner_attachment(p_entity_id uuid DEFAULT NULL::uuid, p_interaction_id uuid DEFAULT NULL::uuid, p_file_name text DEFAULT NULL::text, p_file_url text DEFAULT NULL::text, p_file_size integer DEFAULT NULL::integer, p_file_type text DEFAULT NULL::text, p_description text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_id uuid;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  -- Upload permission: GP, Deputy, Curator
  IF NOT (
    coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR 'curator' = ANY(coalesce(v_caller.designations, ARRAY[]::text[]))
  ) THEN
    RETURN jsonb_build_object('error', 'Only GP, Deputy, or Curator can upload partnership attachments');
  END IF;

  IF p_entity_id IS NULL AND p_interaction_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Must link to entity or interaction');
  END IF;

  INSERT INTO partner_attachments (partner_entity_id, partner_interaction_id, file_name, file_url, file_size, file_type, description, uploaded_by)
  VALUES (p_entity_id, p_interaction_id, p_file_name, p_file_url, p_file_size, p_file_type, p_description, v_caller.id)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.add_partner_interaction(p_partner_id uuid, p_interaction_type text, p_summary text, p_details text DEFAULT NULL::text, p_outcome text DEFAULT NULL::text, p_next_action text DEFAULT NULL::text, p_follow_up_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_interaction_id uuid;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  IF v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND v_caller.is_superadmin IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  INSERT INTO partner_interactions (
    partner_id, interaction_type, summary, details, outcome, next_action, follow_up_date, actor_member_id
  ) VALUES (
    p_partner_id, p_interaction_type, p_summary, p_details, p_outcome, p_next_action, p_follow_up_date, v_caller.id
  ) RETURNING id INTO v_interaction_id;

  UPDATE partner_entities
  SET
    last_interaction_at = now(),
    next_action = COALESCE(p_next_action, next_action),
    follow_up_date = COALESCE(p_follow_up_date, follow_up_date),
    updated_at = now(),
    notes = COALESCE(notes, '') || E'\n[' || to_char(now(), 'YYYY-MM-DD') || '] ' || p_interaction_type || ': ' || p_summary
  WHERE id = p_partner_id;

  RETURN jsonb_build_object('success', true, 'interaction_id', v_interaction_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_partner_attachment(p_attachment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_attachment record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  IF NOT (
    coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR 'curator' = ANY(coalesce(v_caller.designations, ARRAY[]::text[]))
  ) THEN
    RETURN jsonb_build_object('error', 'Only GP, Deputy, or Curator can delete attachments');
  END IF;

  SELECT * INTO v_attachment FROM partner_attachments WHERE id = p_attachment_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Attachment not found'); END IF;

  DELETE FROM partner_attachments WHERE id = p_attachment_id;

  RETURN jsonb_build_object('ok', true, 'deleted_file', v_attachment.file_name);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_partner_entity_attachments(p_entity_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_entity record;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_curator boolean;
  v_is_chapter_stakeholder boolean;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  SELECT * INTO v_entity FROM partner_entities WHERE id = p_entity_id;
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  v_is_gp := coalesce(v_caller.is_superadmin, false)
    OR v_caller.operational_role IN ('manager', 'deputy_manager');
  v_is_curator := 'curator' = ANY(coalesce(v_caller.designations, ARRAY[]::text[]));
  v_is_leader := v_caller.operational_role = 'tribe_leader';

  -- Sponsor/liaison: only see their chapter's partnerships
  v_is_chapter_stakeholder := v_caller.operational_role IN ('sponsor', 'chapter_liaison')
    AND (v_entity.chapter IS NULL OR v_entity.chapter = v_caller.chapter);
    -- NULL chapter = cross-chapter → GP only

  -- Visibility check
  IF NOT (v_is_gp OR v_is_curator OR v_is_leader OR v_is_chapter_stakeholder) THEN
    RETURN '[]'::jsonb;
  END IF;

  -- Cross-chapter partnerships (no chapter set): GP/Curator only
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
    WHERE pa.partner_entity_id = p_entity_id
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
        AND pe.status NOT IN ('inactive', 'churned', 'active')
    )
  );
END;
$function$;

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

  SELECT * INTO v_entity FROM partner_entities WHERE id = v_interaction.partner_entity_id;

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

CREATE OR REPLACE FUNCTION public.get_partner_interactions(p_partner_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  IF v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND v_caller.is_superadmin IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', pi.id,
      'interaction_type', pi.interaction_type,
      'summary', pi.summary,
      'details', pi.details,
      'outcome', pi.outcome,
      'next_action', pi.next_action,
      'follow_up_date', pi.follow_up_date,
      'actor_name', m.name,
      'created_at', pi.created_at
    ) ORDER BY pi.created_at DESC
  ) INTO v_result
  FROM partner_interactions pi
  LEFT JOIN members m ON m.id = pi.actor_member_id
  WHERE pi.partner_id = p_partner_id;

  RETURN jsonb_build_object(
    'interactions', COALESCE(v_result, '[]'::jsonb),
    'total', (SELECT count(*) FROM partner_interactions WHERE partner_id = p_partner_id)
  );
END;
$function$;
