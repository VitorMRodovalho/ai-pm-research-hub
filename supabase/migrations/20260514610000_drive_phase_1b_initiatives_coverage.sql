-- Drive Integration Phase 1b: estender cobertura para iniciativas (não só boards).
-- PM insight: cada iniciativa (tribo/comitê/workgroup/congresso) tem pasta Drive
-- na sua estrutura de quadrante. Vincular direto a iniciativa permite:
-- - Acesso "Drive da tribo" em /tribos/[id]
-- - Cards de boards filhos herdam contexto Drive
-- - Future: atas de events.minutes_url que apontam para Drive folder

CREATE TABLE IF NOT EXISTS public.initiative_drive_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  initiative_id uuid NOT NULL REFERENCES public.initiatives(id) ON DELETE CASCADE,
  drive_folder_id text NOT NULL,
  drive_folder_url text NOT NULL,
  drive_folder_name text,
  link_purpose text DEFAULT 'workspace' CHECK (link_purpose IN ('workspace', 'minutes', 'archive', 'shared_resources')),
  linked_by uuid NOT NULL REFERENCES public.members(id),
  linked_at timestamptz NOT NULL DEFAULT now(),
  unlinked_at timestamptz,
  unlinked_by uuid REFERENCES public.members(id),
  UNIQUE(initiative_id, drive_folder_id, link_purpose)
);

CREATE INDEX IF NOT EXISTS idx_initiative_drive_links_initiative_id ON public.initiative_drive_links(initiative_id);
CREATE INDEX IF NOT EXISTS idx_initiative_drive_links_active ON public.initiative_drive_links(initiative_id) WHERE unlinked_at IS NULL;

ALTER TABLE public.initiative_drive_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY initiative_drive_links_read_authenticated ON public.initiative_drive_links
  FOR SELECT TO authenticated
  USING (rls_is_member());

CREATE OR REPLACE FUNCTION public.link_initiative_to_drive(
  p_initiative_id uuid,
  p_drive_folder_id text,
  p_drive_folder_url text,
  p_drive_folder_name text DEFAULT NULL,
  p_link_purpose text DEFAULT 'workspace'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_is_authorized boolean;
  v_existing record;
  v_new_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF p_link_purpose NOT IN ('workspace', 'minutes', 'archive', 'shared_resources') THEN
    RETURN jsonb_build_object('error', 'Invalid link_purpose. Use: workspace | minutes | archive | shared_resources');
  END IF;

  v_is_authorized := public.can_by_member(v_caller_id, 'manage_member')
    OR public.can(v_caller_id, 'write', 'initiative', p_initiative_id);

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member or write on initiative');
  END IF;

  IF coalesce(trim(p_drive_folder_id), '') = '' OR coalesce(trim(p_drive_folder_url), '') = '' THEN
    RETURN jsonb_build_object('error', 'drive_folder_id and drive_folder_url required');
  END IF;

  SELECT id INTO v_existing.id FROM public.initiative_drive_links
  WHERE initiative_id = p_initiative_id AND drive_folder_id = p_drive_folder_id
    AND link_purpose = p_link_purpose AND unlinked_at IS NULL;
  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'existing', true, 'link_id', v_existing.id);
  END IF;

  INSERT INTO public.initiative_drive_links (
    initiative_id, drive_folder_id, drive_folder_url, drive_folder_name, link_purpose, linked_by
  ) VALUES (
    p_initiative_id, p_drive_folder_id, p_drive_folder_url, p_drive_folder_name, p_link_purpose, v_caller_id
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'success', true,
    'link_id', v_new_id,
    'initiative_id', p_initiative_id,
    'drive_folder_id', p_drive_folder_id,
    'link_purpose', p_link_purpose
  );
END;
$$;

REVOKE ALL ON FUNCTION public.link_initiative_to_drive(uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_initiative_to_drive(uuid, text, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.link_initiative_to_drive(uuid, text, text, text, text) IS
'Phase 1b expansion: vincula pasta Drive a iniciativa. link_purpose: workspace | minutes | archive | shared_resources. Authority: manage_member OR can(write, initiative). Idempotent.';

CREATE OR REPLACE FUNCTION public.get_initiative_drive_links(p_initiative_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_initiative record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT id, title, kind INTO v_initiative
  FROM public.initiatives WHERE id = p_initiative_id;
  IF v_initiative.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'link_purpose', l.link_purpose,
    'linked_by_name', m.name,
    'linked_at', l.linked_at
  ) ORDER BY
    CASE l.link_purpose
      WHEN 'workspace' THEN 1
      WHEN 'shared_resources' THEN 2
      WHEN 'minutes' THEN 3
      WHEN 'archive' THEN 4
      ELSE 5
    END,
    l.linked_at DESC
  ), '[]'::jsonb)
  INTO v_result
  FROM public.initiative_drive_links l
  LEFT JOIN public.members m ON m.id = l.linked_by
  WHERE l.initiative_id = p_initiative_id AND l.unlinked_at IS NULL;

  RETURN jsonb_build_object(
    'initiative_id', p_initiative_id,
    'initiative_title', v_initiative.title,
    'initiative_kind', v_initiative.kind,
    'drive_links', v_result,
    'fetched_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_initiative_drive_links(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_initiative_drive_links(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.unlink_initiative_from_drive(p_link_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_link record;
  v_is_authorized boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_link FROM public.initiative_drive_links WHERE id = p_link_id;
  IF v_link.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Link not found');
  END IF;

  IF v_link.unlinked_at IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Already unlinked');
  END IF;

  v_is_authorized := public.can_by_member(v_caller_id, 'manage_member')
    OR public.can(v_caller_id, 'write', 'initiative', v_link.initiative_id);

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  UPDATE public.initiative_drive_links
  SET unlinked_at = now(), unlinked_by = v_caller_id
  WHERE id = p_link_id;

  RETURN jsonb_build_object('success', true, 'link_id', p_link_id);
END;
$$;

REVOKE ALL ON FUNCTION public.unlink_initiative_from_drive(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unlink_initiative_from_drive(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
