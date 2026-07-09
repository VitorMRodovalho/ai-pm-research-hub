-- 1229: set_tribe_video — atomic dual-write of a tribe's intro video across both sources.
--
-- Context (#1229): the leader intro video lives in TWO places that were kept in sync by hand:
--   * Fonte B  public.tribes.video_url / video_duration        (legacy projection the app + picker read today)
--   * Fonte A  public.initiatives.metadata.video_url / video_duration  (V4 primitive, kind='research_tribe')
-- Manual dual-write is the source of drift on every video swap (e.g. T06 kept the old link in `tribes`
-- while `initiatives.metadata` already carried the errata). This RPC becomes the single atomic writer:
-- one call writes BOTH, so they can never diverge. Read surface stays `tribes` (get_tribe_picker_cards, #1227).
--
-- Authority (mirrors manage_initiative_metadata): tribe leader (manage_initiative, initiative-scoped)
-- OR platform admin (manage_platform). SECURITY DEFINER; self-gated; anon has no grant.

CREATE OR REPLACE FUNCTION public.set_tribe_video(
  p_tribe_id integer,
  p_url text,
  p_duration text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_initiative_id uuid;
  v_tribe_name text;
  v_old_url text;
  v_new_url text := NULLIF(btrim(p_url), '');
  v_new_dur text := NULLIF(btrim(p_duration), '');
BEGIN
  -- authn
  SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  SELECT id INTO v_caller_person_id FROM public.persons WHERE legacy_member_id = v_caller_member_id;

  -- resolve tribe + its V4 initiative bridge
  SELECT t.name, t.video_url INTO v_tribe_name, v_old_url
  FROM public.tribes t WHERE t.id = p_tribe_id;
  IF v_tribe_name IS NULL THEN
    RETURN jsonb_build_object('error', 'Tribe not found');
  END IF;

  SELECT i.id INTO v_initiative_id
  FROM public.initiatives i
  WHERE i.legacy_tribe_id = p_tribe_id AND i.kind = 'research_tribe'
  LIMIT 1;

  -- authz: tribe leader (initiative-scoped manage_initiative) OR platform admin
  IF NOT (
    (v_initiative_id IS NOT NULL
       AND public.can(v_caller_person_id, 'manage_initiative', 'initiative', v_initiative_id))
    OR public.can(v_caller_person_id, 'manage_platform')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: tribe leader or manage_platform required');
  END IF;

  -- URL shape validation (empty/NULL clears the field; else must be http/https)
  IF v_new_url IS NOT NULL AND v_new_url !~* '^https?://' THEN
    RETURN jsonb_build_object('error', 'Invalid URL (must start with http:// or https://)');
  END IF;

  -- Fonte B (tribes) — the projection the app/picker reads today
  UPDATE public.tribes
  SET video_url = v_new_url, video_duration = v_new_dur
  WHERE id = p_tribe_id;

  -- Fonte A (initiatives.metadata) — V4 primitive; kept in sync atomically
  IF v_initiative_id IS NOT NULL THEN
    UPDATE public.initiatives
    SET metadata = jsonb_set(
                     jsonb_set(coalesce(metadata, '{}'::jsonb), '{video_url}',
                       CASE WHEN v_new_url IS NULL THEN 'null'::jsonb ELSE to_jsonb(v_new_url) END, true),
                     '{video_duration}',
                       CASE WHEN v_new_dur IS NULL THEN 'null'::jsonb ELSE to_jsonb(v_new_dur) END, true),
        updated_at = now()
    WHERE id = v_initiative_id;
  END IF;

  -- audit
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_member_id, 'tribe.video_updated', 'initiative', v_initiative_id,
    jsonb_build_object('tribe_id', p_tribe_id, 'old_url', v_old_url,
                       'new_url', v_new_url, 'duration', v_new_dur),
    jsonb_build_object('tribe_name', v_tribe_name, 'initiative_id', v_initiative_id)
  );

  RETURN jsonb_build_object(
    'ok', true,
    'tribe_id', p_tribe_id,
    'tribe_name', v_tribe_name,
    'video_url', v_new_url,
    'video_duration', v_new_dur,
    'synced_initiative', v_initiative_id IS NOT NULL
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.set_tribe_video(integer, text, text) TO authenticated;
