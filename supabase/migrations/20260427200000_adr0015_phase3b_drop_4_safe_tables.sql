-- ============================================================================
-- ADR-0015 Phase 3b — DROP COLUMN tribe_id em 4 tabelas (batch safe)
--
-- Drop das tabelas cujos writers estão 100% em RPCs internas (refatoradas
-- nesta migration). As tabelas broadcast_log e hub_resources ficam deferidas
-- para Phase 3c porque têm writers em Edge Functions + scripts externos
-- que precisam ser atualizados junto para atomicidade.
--
-- Dropped:
--   - meeting_artifacts
--   - publication_submissions
--   - public_publications
--   - tribe_deliverables
--
-- Deferred (requer update de EF/script):
--   - broadcast_log        — EFs: send-tribe-broadcast, send-global-onboarding,
--                            send-allocation-notify escrevem tribe_id em INSERT
--   - hub_resources        — KnowledgeIsland.tsx escreve tribe_id em payload
--                            e SELECT; bulk_knowledge_ingestion/2_execute_upload.ts
--
-- Tasks:
--
-- A. Novo helper RLS `rls_can_for_initiative(action, initiative_id)`
--
-- B. Policy refactors (substitui rls_can_for_tribe → rls_can_for_initiative):
--    - meeting_artifacts_manage
--    - tribe_deliverables_write_v4
--    (broadcast_log_read_tribe_leader — DEFERRED junto com o drop)
--
-- C. Reader RPC refactors:
--    - list_meeting_artifacts       — %ROWTYPE no longer has tribe_id; explicit col list
--    - list_tribe_deliverables      — WHERE tribe_id → JOIN initiatives; SELECT derive
--    - list_initiative_deliverables — rewrite direct initiative filter
--    - get_public_publications      — pp.tribe_id → i.legacy_tribe_id AS tribe_id
--    - get_publication_detail       — mesma troca
--    - get_publication_submission_detail — ps.tribe_id → i.legacy_tribe_id
--
-- D. Writer RPC refactors (remover tribe_id do INSERT/UPDATE):
--    - save_presentation_snapshot      — meeting_artifacts INSERT
--    - admin_manage_publication        — public_publications create path
--    - auto_publish_approved_article   — public_publications trigger fn
--    - create_publication_submission   — publication_submissions INSERT
--    - upsert_tribe_deliverable        — tribe_deliverables INSERT
--
-- E. DROP COLUMN em 4 tabelas. FKs + indexes auto-dropped.
--
-- Rollback: irreversível (mesma estratégia Phase 3a/3b).
-- ADR: ADR-0015 Phase 3 (part b — batch 2 of N)
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- A. RLS helper: rls_can_for_initiative
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.rls_can_for_initiative(p_action text, p_initiative_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
    WHERE ae.auth_id = auth.uid()
      AND ae.is_authoritative = true
      AND (
        ekp.scope IN ('organization', 'global')
        OR (ekp.scope = 'initiative' AND ae.initiative_id = p_initiative_id)
      )
  );
$$;

GRANT EXECUTE ON FUNCTION public.rls_can_for_initiative(text, uuid) TO authenticated, anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- B. Policy refactors
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS meeting_artifacts_manage ON public.meeting_artifacts;
CREATE POLICY meeting_artifacts_manage ON public.meeting_artifacts
  FOR ALL
  USING (rls_is_superadmin() OR rls_can('manage_member') OR rls_can_for_initiative('write', initiative_id));

DROP POLICY IF EXISTS tribe_deliverables_write_v4 ON public.tribe_deliverables;
CREATE POLICY tribe_deliverables_write_v4 ON public.tribe_deliverables
  FOR ALL
  USING (rls_is_superadmin() OR rls_can_for_initiative('write_board', initiative_id));

-- ═══════════════════════════════════════════════════════════════════════════
-- C. Reader RPC refactors
-- ═══════════════════════════════════════════════════════════════════════════

-- list_meeting_artifacts: keep SETOF meeting_artifacts (row type adapts post-drop)
CREATE OR REPLACE FUNCTION public.list_meeting_artifacts(
  p_limit integer DEFAULT 100,
  p_tribe_id integer DEFAULT NULL::integer
)
RETURNS SETOF public.meeting_artifacts
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT ma.*
  FROM public.meeting_artifacts ma
  LEFT JOIN public.initiatives i ON i.id = ma.initiative_id
  WHERE ma.is_published = true
    AND (
      p_tribe_id IS NULL
      OR i.legacy_tribe_id = p_tribe_id
      OR ma.initiative_id IS NULL
    )
  ORDER BY ma.meeting_date DESC
  LIMIT p_limit;
$$;

-- list_tribe_deliverables: reader; gate via rls_is_member (returns empty set
-- for unauthenticated) to avoid triggering ADR-0011 matcher on a pure reader.
CREATE OR REPLACE FUNCTION public.list_tribe_deliverables(
  p_tribe_id integer,
  p_cycle_code text DEFAULT NULL
)
RETURNS SETOF public.tribe_deliverables
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT rls_is_member() THEN RETURN; END IF;

  RETURN QUERY
    SELECT td.* FROM public.tribe_deliverables td
    LEFT JOIN public.initiatives i ON i.id = td.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id
      AND (p_cycle_code IS NULL OR td.cycle_code = p_cycle_code)
    ORDER BY td.due_date ASC NULLS LAST, td.created_at DESC;
END;
$$;

-- list_initiative_deliverables: filter direct by initiative_id, SETOF tribe_deliverables
CREATE OR REPLACE FUNCTION public.list_initiative_deliverables(
  p_initiative_id uuid,
  p_cycle_code text DEFAULT NULL
)
RETURNS SETOF public.tribe_deliverables
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  PERFORM public.assert_initiative_capability(p_initiative_id, 'has_deliverables');

  RETURN QUERY
    SELECT td.* FROM public.tribe_deliverables td
    WHERE td.initiative_id = p_initiative_id
      AND (p_cycle_code IS NULL OR td.cycle_code = p_cycle_code)
    ORDER BY td.due_date ASC NULLS LAST, td.created_at DESC;
END;
$$;

-- get_public_publications: pp.tribe_id → i.legacy_tribe_id AS tribe_id
CREATE OR REPLACE FUNCTION public.get_public_publications(
  p_type text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL,
  p_cycle text DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(r) ORDER BY r.is_featured DESC, r.publication_date DESC NULLS LAST)
  INTO v_result
  FROM (
    SELECT pp.id, pp.title, pp.abstract, pp.authors, pp.publication_date, pp.publication_type,
           pp.external_url, pp.external_platform, pp.doi, pp.keywords,
           i.legacy_tribe_id AS tribe_id,
           pp.cycle_code,
           pp.language, pp.citation_count, pp.view_count, pp.thumbnail_url, pp.pdf_url, pp.is_featured
    FROM public.public_publications pp
    LEFT JOIN public.initiatives i ON i.id = pp.initiative_id
    WHERE pp.is_published = true
      AND (p_type IS NULL OR pp.publication_type = p_type)
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
      AND (p_cycle IS NULL OR pp.cycle_code = p_cycle)
      AND (p_search IS NULL OR pp.title ILIKE '%' || p_search || '%'
           OR pp.abstract ILIKE '%' || p_search || '%'
           OR EXISTS (SELECT 1 FROM unnest(pp.keywords) k WHERE k ILIKE '%' || p_search || '%'))
    ORDER BY pp.is_featured DESC, pp.publication_date DESC NULLS LAST
    LIMIT p_limit
  ) r;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- get_publication_detail: pp.tribe_id → i.legacy_tribe_id AS tribe_id
CREATE OR REPLACE FUNCTION public.get_publication_detail(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pub jsonb;
BEGIN
  UPDATE public.public_publications SET view_count = view_count + 1
  WHERE id = p_id AND is_published = true;

  SELECT row_to_json(p)::jsonb INTO v_pub
  FROM (
    SELECT pp.id, pp.title, pp.abstract, pp.authors, pp.author_member_ids, pp.publication_date,
           pp.publication_type, pp.external_url, pp.external_platform, pp.doi, pp.keywords,
           i.legacy_tribe_id AS tribe_id,
           pp.cycle_code, pp.language, pp.citation_count, pp.view_count,
           pp.thumbnail_url, pp.pdf_url, pp.is_featured, pp.created_at
    FROM public.public_publications pp
    LEFT JOIN public.initiatives i ON i.id = pp.initiative_id
    WHERE pp.id = p_id AND pp.is_published = true
  ) p;

  RETURN v_pub;
END;
$$;

-- get_publication_submission_detail: ps.tribe_id → i.legacy_tribe_id AS tribe_id
CREATE OR REPLACE FUNCTION public.get_publication_submission_detail(p_submission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'submission', jsonb_build_object(
      'id', ps.id,
      'title', ps.title,
      'abstract', ps.abstract,
      'target_type', ps.target_type::text,
      'target_name', ps.target_name,
      'target_url', ps.target_url,
      'status', ps.status::text,
      'submission_date', ps.submission_date,
      'review_deadline', ps.review_deadline,
      'acceptance_date', ps.acceptance_date,
      'presentation_date', ps.presentation_date,
      'primary_author_id', ps.primary_author_id,
      'primary_author_name', m.name,
      'estimated_cost_brl', ps.estimated_cost_brl,
      'actual_cost_brl', ps.actual_cost_brl,
      'cost_paid_by', ps.cost_paid_by,
      'reviewer_feedback', ps.reviewer_feedback,
      'doi_or_url', ps.doi_or_url,
      'tribe_id', i.legacy_tribe_id,
      'tribe_name', i.title,
      'board_item_id', ps.board_item_id,
      'created_by', ps.created_by,
      'created_at', ps.created_at,
      'updated_at', ps.updated_at
    ),
    'authors', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', psa.id,
        'member_id', psa.member_id,
        'member_name', am.name,
        'author_order', psa.author_order,
        'is_corresponding', psa.is_corresponding
      ) ORDER BY psa.author_order), '[]'::jsonb)
      FROM public.publication_submission_authors psa
      JOIN public.members am ON am.id = psa.member_id
      WHERE psa.submission_id = ps.id
    )
  )
  INTO v_result
  FROM public.publication_submissions ps
  LEFT JOIN public.members m ON m.id = ps.primary_author_id
  LEFT JOIN public.initiatives i ON i.id = ps.initiative_id
  WHERE ps.id = p_submission_id;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- D. Writer RPC refactors (remove tribe_id from INSERT/UPDATE)
-- ═══════════════════════════════════════════════════════════════════════════

-- save_presentation_snapshot (meeting_artifacts)
CREATE OR REPLACE FUNCTION public.save_presentation_snapshot(
  p_title text,
  p_meeting_date date,
  p_recording_url text DEFAULT NULL::text,
  p_agenda_items text[] DEFAULT '{}'::text[],
  p_snapshot jsonb DEFAULT '{}'::jsonb,
  p_event_id uuid DEFAULT NULL::uuid,
  p_tribe_id integer DEFAULT NULL::integer,
  p_deliberations text[] DEFAULT '{}'::text[],
  p_is_published boolean DEFAULT false
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller_id uuid;
  v_caller_tribe_id integer;
  v_is_admin boolean;
  v_id uuid;
  v_initiative_id uuid;
BEGIN
  SELECT id, tribe_id INTO v_caller_id, v_caller_tribe_id
  FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;

  v_is_admin := public.can_by_member(v_caller_id, 'manage_member');
  IF NOT v_is_admin THEN
    IF p_tribe_id IS NULL OR p_tribe_id != v_caller_tribe_id THEN
      RAISE EXCEPTION 'Leaders can only save snapshots for their own tribe';
    END IF;
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  INSERT INTO public.meeting_artifacts
    (title, meeting_date, recording_url, agenda_items, page_data_snapshot,
     event_id, initiative_id, created_by, is_published, deliberations)
  VALUES
    (p_title, p_meeting_date, p_recording_url, p_agenda_items, p_snapshot,
     p_event_id, v_initiative_id, v_caller_id, p_is_published, p_deliberations)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- admin_manage_publication (public_publications create path)
CREATE OR REPLACE FUNCTION public.admin_manage_publication(p_action text, p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_id uuid;
  v_tribe_id int;
  v_initiative_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members
  WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  IF NOT public.can_by_member(v_member_id, 'write_board') THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission';
  END IF;

  IF p_action = 'create' THEN
    v_tribe_id := (p_data->>'tribe_id')::int;
    IF v_tribe_id IS NOT NULL THEN
      SELECT id INTO v_initiative_id FROM public.initiatives
      WHERE legacy_tribe_id = v_tribe_id LIMIT 1;
    END IF;

    INSERT INTO public.public_publications (
      title, abstract, authors, author_member_ids, publication_date, publication_type,
      external_url, external_platform, doi, keywords,
      initiative_id, cycle_code,
      language, thumbnail_url, pdf_url, is_featured, is_published
    ) VALUES (
      p_data->>'title', p_data->>'abstract',
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_data->'authors','[]'::jsonb))),
      ARRAY(SELECT (jsonb_array_elements_text(COALESCE(p_data->'author_member_ids','[]'::jsonb)))::uuid),
      (p_data->>'publication_date')::date, COALESCE(p_data->>'publication_type','article'),
      p_data->>'external_url', p_data->>'external_platform', p_data->>'doi',
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_data->'keywords','[]'::jsonb))),
      v_initiative_id, p_data->>'cycle_code',
      COALESCE(p_data->>'language','pt-BR'), p_data->>'thumbnail_url', p_data->>'pdf_url',
      COALESCE((p_data->>'is_featured')::boolean, false),
      COALESCE((p_data->>'is_published')::boolean, false)
    ) RETURNING id INTO v_id;
    RETURN jsonb_build_object('ok', true, 'id', v_id);

  ELSIF p_action = 'update' THEN
    v_id := (p_data->>'id')::uuid;
    UPDATE public.public_publications SET
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
    UPDATE public.public_publications SET is_published = true, updated_at = now() WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'action', 'published');

  ELSIF p_action = 'unpublish' THEN
    v_id := (p_data->>'id')::uuid;
    UPDATE public.public_publications SET is_published = false, updated_at = now() WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'action', 'unpublished');

  ELSIF p_action = 'delete' THEN
    v_id := (p_data->>'id')::uuid;
    DELETE FROM public.public_publications WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'action', 'deleted');

  ELSE
    RAISE EXCEPTION 'invalid_action';
  END IF;
END;
$$;

-- auto_publish_approved_article (public_publications trigger fn)
CREATE OR REPLACE FUNCTION public.auto_publish_approved_article()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_authors text[];
  v_author_ids uuid[];
  v_initiative_id uuid;
BEGIN
  IF NEW.curation_status = 'approved'
    AND (OLD.curation_status IS DISTINCT FROM 'approved') THEN

    SELECT array_agg(m.name), array_agg(m.id)
    INTO v_authors, v_author_ids
    FROM public.board_item_assignments bia
    JOIN public.members m ON m.id = bia.member_id
    WHERE bia.item_id = NEW.id AND bia.role IN ('author','contributor');

    SELECT pb.initiative_id
      INTO v_initiative_id
    FROM public.project_boards pb WHERE pb.id = NEW.board_id;

    INSERT INTO public.public_publications (
      title, abstract, authors, author_member_ids, publication_type,
      initiative_id, cycle_code, board_item_id, is_published
    ) VALUES (
      NEW.title,
      NEW.description,
      COALESCE(v_authors, ARRAY[NEW.title]),
      v_author_ids,
      'article',
      v_initiative_id,
      'cycle3-2026',
      NEW.id,
      false
    ) ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- create_publication_submission (publication_submissions)
CREATE OR REPLACE FUNCTION public.create_publication_submission(
  p_title text,
  p_target_type submission_target_type,
  p_target_name text,
  p_primary_author_id uuid,
  p_tribe_id integer DEFAULT NULL::integer,
  p_board_item_id uuid DEFAULT NULL::uuid,
  p_abstract text DEFAULT NULL::text,
  p_target_url text DEFAULT NULL::text,
  p_estimated_cost_brl numeric DEFAULT 0
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_submission_id uuid;
  v_member_id uuid;
  v_initiative_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Not authenticated';
  END IF;

  SELECT id INTO v_member_id FROM public.members
  WHERE auth_id = auth.uid() AND is_active = true LIMIT 1;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not an active member';
  END IF;

  IF NOT public.can_by_member(v_member_id, 'write_board') THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission';
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  INSERT INTO public.publication_submissions (
    title, target_type, target_name, primary_author_id,
    initiative_id,
    board_item_id, abstract, target_url, estimated_cost_brl, created_by
  )
  VALUES (
    p_title, p_target_type, p_target_name, p_primary_author_id,
    v_initiative_id,
    p_board_item_id, p_abstract, p_target_url, p_estimated_cost_brl, v_member_id
  )
  RETURNING id INTO v_submission_id;

  INSERT INTO public.publication_submission_authors
    (submission_id, member_id, author_order, is_corresponding)
  VALUES (v_submission_id, p_primary_author_id, 1, true);

  RETURN v_submission_id;
END;
$$;

-- upsert_tribe_deliverable (tribe_deliverables)
CREATE OR REPLACE FUNCTION public.upsert_tribe_deliverable(
  p_id uuid DEFAULT NULL::uuid,
  p_tribe_id integer DEFAULT NULL::integer,
  p_cycle_code text DEFAULT NULL::text,
  p_title text DEFAULT NULL::text,
  p_description text DEFAULT NULL::text,
  p_status text DEFAULT 'planned'::text,
  p_assigned_member_id uuid DEFAULT NULL::uuid,
  p_artifact_id uuid DEFAULT NULL::uuid,
  p_due_date date DEFAULT NULL::date
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_member_tribe_id integer;
  v_is_admin boolean;
  v_result public.tribe_deliverables%ROWTYPE;
  v_initiative_id uuid;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_member_tribe_id
  FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT public.can_by_member(v_member_id, 'write') THEN
    RAISE EXCEPTION 'Unauthorized: requires write permission';
  END IF;

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  IF NOT v_is_admin THEN
    IF p_tribe_id IS NULL OR p_tribe_id != v_member_tribe_id THEN
      RAISE EXCEPTION 'Unauthorized: non-admin can only manage deliverables for own tribe';
    END IF;
  END IF;

  IF p_title IS NULL OR p_title = '' THEN
    RAISE EXCEPTION 'Title is required';
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  IF p_id IS NOT NULL THEN
    -- UPDATE: pin by initiative_id now that tribe_id column is gone
    UPDATE public.tribe_deliverables
       SET title              = COALESCE(p_title, title),
           description        = p_description,
           status             = COALESCE(p_status, status),
           assigned_member_id = p_assigned_member_id,
           artifact_id        = p_artifact_id,
           due_date           = p_due_date
     WHERE id = p_id
       AND initiative_id = v_initiative_id
    RETURNING * INTO v_result;

    IF v_result IS NULL THEN
      RAISE EXCEPTION 'Deliverable not found or initiative mismatch';
    END IF;
  ELSE
    INSERT INTO public.tribe_deliverables
      (initiative_id, cycle_code, title, description, status,
       assigned_member_id, artifact_id, due_date)
    VALUES
      (v_initiative_id, p_cycle_code, p_title, p_description, p_status,
       p_assigned_member_id, p_artifact_id, p_due_date)
    RETURNING * INTO v_result;
  END IF;

  RETURN to_jsonb(v_result);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- E. DROP COLUMN em 4 tabelas. FKs + indexes auto-dropped.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.meeting_artifacts DROP COLUMN tribe_id;
ALTER TABLE public.publication_submissions DROP COLUMN tribe_id;
ALTER TABLE public.public_publications DROP COLUMN tribe_id;
ALTER TABLE public.tribe_deliverables DROP COLUMN tribe_id;

COMMIT;

NOTIFY pgrst, 'reload schema';
