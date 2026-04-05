-- Chapter Needs: feedback loop for chapter board members
-- Allows chapter_board designation to submit needs/requests for their chapter

BEGIN;

CREATE TABLE IF NOT EXISTS public.chapter_needs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter     text NOT NULL CHECK (chapter IN ('PMI-GO', 'PMI-CE', 'PMI-DF', 'PMI-MG', 'PMI-RS')),
  submitted_by uuid NOT NULL REFERENCES public.members(id),
  category    text NOT NULL CHECK (category IN ('research', 'tools', 'events', 'training', 'communication', 'other')),
  title       text NOT NULL,
  description text,
  status      text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_review', 'planned', 'done', 'declined')),
  admin_notes text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.chapter_needs ENABLE ROW LEVEL SECURITY;

-- chapter_board, sponsor, chapter_liaison can see needs for their chapter
CREATE POLICY "chapter_needs_select" ON public.chapter_needs
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM members m WHERE m.auth_id = auth.uid()
      AND (
        m.is_superadmin = true
        OR m.operational_role IN ('manager', 'deputy_manager')
        OR (m.chapter = chapter_needs.chapter AND (
          m.designations && ARRAY['chapter_board', 'sponsor', 'chapter_liaison']::text[]
        ))
      )
    )
  );

-- chapter_board, sponsor, chapter_liaison can insert for their own chapter
CREATE POLICY "chapter_needs_insert" ON public.chapter_needs
  FOR INSERT TO authenticated WITH CHECK (
    EXISTS (
      SELECT 1 FROM members m WHERE m.auth_id = auth.uid()
      AND m.id = chapter_needs.submitted_by
      AND m.chapter = chapter_needs.chapter
      AND (
        m.designations && ARRAY['chapter_board', 'sponsor', 'chapter_liaison']::text[]
      )
    )
  );

-- Admin can update status/notes
CREATE POLICY "chapter_needs_update_admin" ON public.chapter_needs
  FOR UPDATE TO authenticated USING (
    EXISTS (
      SELECT 1 FROM members m WHERE m.auth_id = auth.uid()
      AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager'))
    )
  );

-- RPC: submit a chapter need (validates caller)
CREATE OR REPLACE FUNCTION submit_chapter_need(
  p_category text, p_title text, p_description text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
DECLARE
  v_member record;
  v_id uuid;
BEGIN
  SELECT id, chapter, designations INTO v_member
  FROM members WHERE auth_id = auth.uid() LIMIT 1;

  IF v_member IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF v_member.chapter IS NULL THEN
    RETURN jsonb_build_object('error', 'No chapter assigned');
  END IF;

  IF NOT (v_member.designations && ARRAY['chapter_board', 'sponsor', 'chapter_liaison']::text[]) THEN
    RETURN jsonb_build_object('error', 'Requires chapter_board, sponsor, or chapter_liaison designation');
  END IF;

  INSERT INTO chapter_needs (chapter, submitted_by, category, title, description)
  VALUES (v_member.chapter, v_member.id, p_category, p_title, p_description)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$$;

-- RPC: list chapter needs (for the caller's chapter or all for admin)
CREATE OR REPLACE FUNCTION get_chapter_needs(p_chapter text DEFAULT NULL)
RETURNS TABLE(
  id uuid, chapter text, category text, title text, description text,
  status text, admin_notes text, submitted_by_name text,
  created_at timestamptz, updated_at timestamptz
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
DECLARE
  v_member record;
  v_chapter text;
BEGIN
  SELECT m.id, m.chapter, m.is_superadmin, m.operational_role, m.designations
  INTO v_member FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  IF v_member IS NULL THEN RETURN; END IF;

  v_chapter := COALESCE(p_chapter, v_member.chapter);

  -- Admin can see all chapters
  IF v_member.is_superadmin OR v_member.operational_role IN ('manager', 'deputy_manager') THEN
    -- OK, can see any chapter
  ELSIF v_member.designations && ARRAY['chapter_board', 'sponsor', 'chapter_liaison']::text[] THEN
    v_chapter := v_member.chapter; -- force own chapter
  ELSE
    RETURN;
  END IF;

  RETURN QUERY
  SELECT cn.id, cn.chapter, cn.category, cn.title, cn.description,
         cn.status, cn.admin_notes, m.name,
         cn.created_at, cn.updated_at
  FROM chapter_needs cn
  JOIN members m ON m.id = cn.submitted_by
  WHERE (v_chapter IS NULL OR cn.chapter = v_chapter)
  ORDER BY cn.created_at DESC
  LIMIT 50;
END;
$$;

GRANT EXECUTE ON FUNCTION submit_chapter_need TO authenticated;
GRANT EXECUTE ON FUNCTION get_chapter_needs TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
