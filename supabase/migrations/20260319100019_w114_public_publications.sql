-- W114: Public Publications — Schema + RPCs + Auto-publish trigger
-- Gap G9.1/G10.1: Publications must be accessible without login

-- ── Table ──
CREATE TABLE IF NOT EXISTS public.public_publications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  abstract text,
  authors text[] NOT NULL,
  author_member_ids uuid[],
  publication_date date,
  publication_type text NOT NULL DEFAULT 'article'
    CHECK (publication_type IN ('article','framework','toolkit','case_study','webinar_recording','ebook','podcast')),
  external_url text,
  external_platform text,
  doi text,
  keywords text[],
  tribe_id int REFERENCES tribes(id),
  cycle_code text,
  language text DEFAULT 'pt-BR',
  citation_count int DEFAULT 0,
  view_count int DEFAULT 0,
  thumbnail_url text,
  pdf_url text,
  is_featured boolean DEFAULT false,
  is_published boolean DEFAULT true,
  board_item_id uuid REFERENCES board_items(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pub_type ON public_publications(publication_type);
CREATE INDEX IF NOT EXISTS idx_pub_date ON public_publications(publication_date DESC);
CREATE INDEX IF NOT EXISTS idx_pub_cycle ON public_publications(cycle_code);
CREATE INDEX IF NOT EXISTS idx_pub_tribe ON public_publications(tribe_id);

ALTER TABLE public_publications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pub_read_published" ON public_publications
  FOR SELECT USING (is_published = true);

CREATE POLICY "pub_admin_manage" ON public_publications
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin OR operational_role IN ('manager','deputy_manager')
    OR designations && ARRAY['curator'])));

GRANT SELECT ON public_publications TO anon;
GRANT SELECT ON public_publications TO authenticated;

-- ── RPC: get_public_publications ──
CREATE OR REPLACE FUNCTION get_public_publications(
  p_type text DEFAULT NULL,
  p_tribe_id int DEFAULT NULL,
  p_cycle text DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_limit int DEFAULT 50
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(r) ORDER BY r.is_featured DESC, r.publication_date DESC NULLS LAST)
  INTO v_result
  FROM (
    SELECT id, title, abstract, authors, publication_date, publication_type,
           external_url, external_platform, doi, keywords, tribe_id, cycle_code,
           language, citation_count, view_count, thumbnail_url, pdf_url, is_featured
    FROM public_publications
    WHERE is_published = true
      AND (p_type IS NULL OR publication_type = p_type)
      AND (p_tribe_id IS NULL OR tribe_id = p_tribe_id)
      AND (p_cycle IS NULL OR cycle_code = p_cycle)
      AND (p_search IS NULL OR title ILIKE '%' || p_search || '%'
           OR abstract ILIKE '%' || p_search || '%'
           OR EXISTS (SELECT 1 FROM unnest(keywords) k WHERE k ILIKE '%' || p_search || '%'))
    ORDER BY is_featured DESC, publication_date DESC NULLS LAST
    LIMIT p_limit
  ) r;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION get_public_publications TO anon;
GRANT EXECUTE ON FUNCTION get_public_publications TO authenticated;

-- ── RPC: get_publication_detail ──
CREATE OR REPLACE FUNCTION get_publication_detail(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pub jsonb;
BEGIN
  UPDATE public_publications SET view_count = view_count + 1 WHERE id = p_id AND is_published = true;

  SELECT row_to_json(p)::jsonb INTO v_pub
  FROM (
    SELECT id, title, abstract, authors, author_member_ids, publication_date,
           publication_type, external_url, external_platform, doi, keywords,
           tribe_id, cycle_code, language, citation_count, view_count,
           thumbnail_url, pdf_url, is_featured, created_at
    FROM public_publications WHERE id = p_id AND is_published = true
  ) p;

  RETURN v_pub;
END;
$$;

GRANT EXECUTE ON FUNCTION get_publication_detail TO anon;
GRANT EXECUTE ON FUNCTION get_publication_detail TO authenticated;

-- ── RPC: admin_manage_publication ──
CREATE OR REPLACE FUNCTION admin_manage_publication(p_action text, p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member members%ROWTYPE;
  v_id uuid;
BEGIN
  SELECT * INTO v_member FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR NOT (
    v_member.is_superadmin
    OR v_member.operational_role IN ('manager','deputy_manager')
    OR v_member.designations && ARRAY['curator']
  ) THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  IF p_action = 'create' THEN
    INSERT INTO public_publications (
      title, abstract, authors, author_member_ids, publication_date, publication_type,
      external_url, external_platform, doi, keywords, tribe_id, cycle_code,
      language, thumbnail_url, pdf_url, is_featured, is_published
    ) VALUES (
      p_data->>'title', p_data->>'abstract',
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_data->'authors','[]'::jsonb))),
      ARRAY(SELECT (jsonb_array_elements_text(COALESCE(p_data->'author_member_ids','[]'::jsonb)))::uuid),
      (p_data->>'publication_date')::date, COALESCE(p_data->>'publication_type','article'),
      p_data->>'external_url', p_data->>'external_platform', p_data->>'doi',
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_data->'keywords','[]'::jsonb))),
      (p_data->>'tribe_id')::int, p_data->>'cycle_code',
      COALESCE(p_data->>'language','pt-BR'), p_data->>'thumbnail_url', p_data->>'pdf_url',
      COALESCE((p_data->>'is_featured')::boolean, false),
      COALESCE((p_data->>'is_published')::boolean, false)
    ) RETURNING id INTO v_id;
    RETURN jsonb_build_object('ok', true, 'id', v_id);

  ELSIF p_action = 'update' THEN
    v_id := (p_data->>'id')::uuid;
    UPDATE public_publications SET
      title = COALESCE(p_data->>'title', title),
      abstract = COALESCE(p_data->>'abstract', abstract),
      external_url = COALESCE(p_data->>'external_url', external_url),
      external_platform = COALESCE(p_data->>'external_platform', external_platform),
      doi = COALESCE(p_data->>'doi', doi),
      thumbnail_url = COALESCE(p_data->>'thumbnail_url', thumbnail_url),
      pdf_url = COALESCE(p_data->>'pdf_url', pdf_url),
      is_featured = COALESCE((p_data->>'is_featured')::boolean, is_featured),
      publication_date = COALESCE((p_data->>'publication_date')::date, publication_date),
      updated_at = now()
    WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'id', v_id);

  ELSIF p_action = 'publish' THEN
    v_id := (p_data->>'id')::uuid;
    UPDATE public_publications SET is_published = true, updated_at = now() WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'action', 'published');

  ELSIF p_action = 'unpublish' THEN
    v_id := (p_data->>'id')::uuid;
    UPDATE public_publications SET is_published = false, updated_at = now() WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'action', 'unpublished');

  ELSIF p_action = 'delete' THEN
    v_id := (p_data->>'id')::uuid;
    DELETE FROM public_publications WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'action', 'deleted');

  ELSE
    RAISE EXCEPTION 'invalid_action';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_manage_publication TO authenticated;

-- ── Trigger: Auto-create draft publication when curation approves ──
CREATE OR REPLACE FUNCTION auto_publish_approved_article()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_authors text[];
  v_author_ids uuid[];
  v_tribe_id int;
BEGIN
  -- Only fire when curation_status changes to 'approved'
  IF NEW.curation_status = 'approved'
    AND (OLD.curation_status IS DISTINCT FROM 'approved') THEN

    SELECT array_agg(m.name), array_agg(m.id)
    INTO v_authors, v_author_ids
    FROM board_item_assignments bia
    JOIN members m ON m.id = bia.member_id
    WHERE bia.item_id = NEW.id AND bia.role IN ('author','contributor');

    SELECT pb.tribe_id INTO v_tribe_id
    FROM project_boards pb WHERE pb.id = NEW.board_id;

    INSERT INTO public_publications (
      title, abstract, authors, author_member_ids, publication_type,
      tribe_id, cycle_code, board_item_id, is_published
    ) VALUES (
      NEW.title,
      NEW.description,
      COALESCE(v_authors, ARRAY[NEW.title]),
      v_author_ids,
      'article',
      v_tribe_id,
      'cycle3-2026',
      NEW.id,
      false  -- GP/curator publishes manually after final review
    ) ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auto_publish_approved
  AFTER UPDATE OF curation_status ON board_items
  FOR EACH ROW
  WHEN (NEW.curation_status = 'approved')
  EXECUTE FUNCTION auto_publish_approved_article();
