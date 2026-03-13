-- ═══════════════════════════════════════════════════════════════
-- W109: Board status vocabulary + curation pipeline
-- Add curation_pipeline config to board_sla_config
-- Add admin_update_board_columns RPC for tribe leaders
-- ═══════════════════════════════════════════════════════════════

-- 1. Add curation_pipeline column to board_sla_config
ALTER TABLE public.board_sla_config
ADD COLUMN IF NOT EXISTS curation_pipeline jsonb DEFAULT '[
  {"key": "ideation", "label": {"pt": "Ideação", "en": "Ideation", "es": "Ideación"}},
  {"key": "research", "label": {"pt": "Pesquisa", "en": "Research", "es": "Investigación"}},
  {"key": "drafting", "label": {"pt": "Redação", "en": "Drafting", "es": "Redacción"}},
  {"key": "author_review", "label": {"pt": "Revisão Autores", "en": "Author Review", "es": "Revisión Autores"}},
  {"key": "peer_review", "label": {"pt": "Peer Review", "en": "Peer Review", "es": "Peer Review"}},
  {"key": "leader_review", "label": {"pt": "Revisão Líder", "en": "Leader Review", "es": "Revisión Líder"}},
  {"key": "curation", "label": {"pt": "Curadoria", "en": "Curation", "es": "Curaduría"}},
  {"key": "published", "label": {"pt": "Publicado", "en": "Published", "es": "Publicado"}}
]'::jsonb;

COMMENT ON COLUMN public.board_sla_config.curation_pipeline IS
  'Status obrigatórios para items que vão para curadoria (7 etapas do Manual de Governança)';

-- 2. RPC: admin_update_board_columns
CREATE OR REPLACE FUNCTION public.admin_update_board_columns(
  p_board_id uuid,
  p_columns jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_is_admin boolean;
  v_tribe_id int;
BEGIN
  SELECT operational_role, is_superadmin, tribe_id
  INTO v_role, v_is_admin, v_tribe_id
  FROM public.members WHERE auth_id = auth.uid();

  -- Tribe leader can edit their own tribe's boards
  -- Admin/PM/DM can edit any board
  IF NOT (v_is_admin OR v_role IN ('manager', 'deputy_manager')) THEN
    IF v_role = 'tribe_leader' THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.project_boards
        WHERE id = p_board_id AND tribe_id = v_tribe_id
      ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
      END IF;
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
    END IF;
  END IF;

  -- Validate: must have at least 2 columns, max 8
  IF jsonb_array_length(p_columns) < 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'minimum_2_columns');
  END IF;

  IF jsonb_array_length(p_columns) > 8 THEN
    RETURN jsonb_build_object('success', false, 'error', 'maximum_8_columns');
  END IF;

  UPDATE public.project_boards
  SET columns = p_columns, updated_at = now()
  WHERE id = p_board_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_board_columns(uuid, jsonb) TO authenticated;
