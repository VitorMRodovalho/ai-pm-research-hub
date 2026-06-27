-- #211 (ADR-0094 §G3.1): self-service initiative metadata editing.
--
-- Seeds the NEW V4 action `manage_initiative` (per ADR-0094 G3.1: "managers + initiative-scoped
-- owners") + a SECURITY DEFINER RPC `manage_initiative_metadata` that gates a whitelisted jsonb
-- merge on `can(caller_person_id, 'manage_initiative', 'initiative', p_initiative_id)`.
--
-- Authority seeds mirror the closest analog `manage_event`:
--   - organization scope → the manager tier (co_gp / deputy_manager / manager), identical to
--     manage_platform (least privilege for a new authority surface; comms_leader deliberately
--     omitted — PM can add it if initiative config editing should be a comms responsibility).
--   - initiative scope → owner/leader kinds (committee leader, study-group owner+leader,
--     volunteer leader, workgroup leader).
-- organization_id is taken from the existing manage_event org rows so this stays single-source
-- (no hardcoded org UUID) and multi-hub-consistent (ADR-0094 M1).

INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description, organization_id)
SELECT v.kind, v.role, 'manage_initiative', v.scope, v.descr,
       (SELECT organization_id FROM public.engagement_kind_permissions
        WHERE action = 'manage_event' AND scope = 'organization' LIMIT 1)
FROM (VALUES
  ('volunteer',         'co_gp',          'organization', 'GP co-manager: edit initiative config metadata'),
  ('volunteer',         'deputy_manager', 'organization', 'Deputy manager: edit initiative config metadata'),
  ('volunteer',         'manager',        'organization', 'Manager: edit initiative config metadata'),
  ('committee_member',  'leader',         'initiative',   'Committee leader: edit own initiative config metadata'),
  ('study_group_owner', 'leader',         'initiative',   'Study-group leader: edit own initiative config metadata'),
  ('study_group_owner', 'owner',          'initiative',   'Study-group owner: edit own initiative config metadata'),
  ('volunteer',         'leader',         'initiative',   'Initiative leader: edit own initiative config metadata'),
  ('workgroup_member',  'leader',         'initiative',   'Workgroup leader: edit own initiative config metadata')
) AS v(kind, role, scope, descr)
WHERE NOT EXISTS (
  SELECT 1 FROM public.engagement_kind_permissions ekp
  WHERE ekp.kind = v.kind AND ekp.role = v.role AND ekp.action = 'manage_initiative' AND ekp.scope = v.scope
);

CREATE OR REPLACE FUNCTION public.manage_initiative_metadata(p_initiative_id uuid, p_metadata jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  -- whitelist of editable config keys (issue #211 scope). Structural fields (status, name, kind,
  -- start_date/end_date, leader_member_id, ...) are intentionally NOT editable here.
  v_allowed text[] := ARRAY[
    'whatsapp_url','whatsapp_note','drive_url',
    'youtube_channel_nucleo','youtube_channel_event',
    'meeting_day','meeting_time_start','meeting_time_end','timezone',
    'cadence_hint','meeting_schedule','meeting_link','venue'
  ];
  v_filtered jsonb;
  v_bad text;
BEGIN
  SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  SELECT id INTO v_caller_person_id FROM public.persons WHERE legacy_member_id = v_caller_member_id;

  IF NOT public.can(v_caller_person_id, 'manage_initiative', 'initiative', p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: manage_initiative required for this initiative');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.initiatives WHERE id = p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  -- keep only whitelisted keys
  SELECT jsonb_object_agg(key, value) INTO v_filtered
  FROM jsonb_each(COALESCE(p_metadata, '{}'::jsonb))
  WHERE key = ANY(v_allowed);

  IF v_filtered IS NULL THEN
    RETURN jsonb_build_object('error', 'No editable metadata keys provided', 'allowed_keys', to_jsonb(v_allowed));
  END IF;

  -- basic URL shape validation for *_url keys (empty clears the field; otherwise must be http/https)
  SELECT key INTO v_bad
  FROM jsonb_each_text(v_filtered)
  WHERE key LIKE '%\_url' ESCAPE '\'
    AND value IS NOT NULL AND value <> ''
    AND value !~* '^https?://'
  LIMIT 1;
  IF v_bad IS NOT NULL THEN
    RETURN jsonb_build_object('error', format('Invalid URL for %s (must start with http:// or https://)', v_bad));
  END IF;

  UPDATE public.initiatives
  SET metadata = COALESCE(metadata, '{}'::jsonb) || v_filtered,
      updated_at = now()
  WHERE id = p_initiative_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller_member_id, 'initiative.metadata_updated', 'initiative', p_initiative_id,
          jsonb_build_object('updated', v_filtered),
          jsonb_build_object('keys', ARRAY(SELECT jsonb_object_keys(v_filtered))));

  RETURN jsonb_build_object(
    'ok', true,
    'initiative_id', p_initiative_id,
    'updated_keys', ARRAY(SELECT jsonb_object_keys(v_filtered))
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.manage_initiative_metadata(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.manage_initiative_metadata(uuid, jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';
