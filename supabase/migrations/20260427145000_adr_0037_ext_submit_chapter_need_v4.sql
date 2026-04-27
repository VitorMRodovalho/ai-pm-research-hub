-- ADR-0037 Extension: submit_chapter_need V3→V4 conversion
-- via view_internal_analytics + Path Y chapter_board engagement preservation.
-- Closes chapter_needs subsystem 100% V4 (get + submit).
-- See docs/adr/ADR-0037-chapter-needs-and-org-chart-v4-conversion.md § Extension.

CREATE OR REPLACE FUNCTION public.submit_chapter_need(
  p_category text,
  p_title text,
  p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_id uuid;
BEGIN
  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1;

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF v_caller_chapter IS NULL THEN
    RETURN jsonb_build_object('error', 'No chapter assigned');
  END IF;

  -- V4 gate (replaces V3 designation check, ADR-0037 ext)
  -- Path A/B: view_internal_analytics (sponsor + chapter_liaison + chapter_board × liaison + org-tier)
  -- Path Y: chapter_board engagement (any role) for board_member preservation
  IF NOT (
    public.can_by_member(v_caller_id, 'view_internal_analytics')
    OR EXISTS (
      SELECT 1 FROM public.auth_engagements ae
      WHERE ae.person_id = v_caller_person_id
        AND ae.kind = 'chapter_board'
        AND ae.status = 'active'
    )
  ) THEN
    RETURN jsonb_build_object(
      'error',
      'Requires chapter_board, sponsor, or organization governance role'
    );
  END IF;

  INSERT INTO public.chapter_needs (chapter, submitted_by, category, title, description)
  VALUES (v_caller_chapter, v_caller_id, p_category, p_title, p_description)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.submit_chapter_need(text, text, text) FROM PUBLIC, anon;

NOTIFY pgrst, 'reload schema';
