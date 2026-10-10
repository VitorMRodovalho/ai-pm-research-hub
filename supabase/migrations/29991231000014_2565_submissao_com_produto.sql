-- =====================================================================================
-- #2565: create_publication_submission volta a registrar submissao (toda submissao com produto)
--
-- MEDIDO em 2026-10-09: publication_submissions.content_product_id e NOT NULL sem default desde a
-- 20260805000045 (p265), e o INSERT da funcao nao o preenchia; exercido pela orquestradora em
-- transacao desfeita, um lider com write_board recebia 23502. As tres telas de submissao chamam esta
-- funcao. A ultima submissao registrada e de 16/03.
--
-- O QUE MUDA (decisao do GP de 09/10: so este pedaco)
--   - a funcao resolve o produto da submissao (ADR-0099 §6): com card, o produto do card ou um novo
--     com source_kind 'board_item' (ligado ao card); sem card, 'external' com a URI do destino.
--     Criterio do backfill da p265: instrumento = tipo do destino, modo de revisao pelo tipo, status
--     under_review;
--   - card informado precisa ser visivel a quem chama (#785), porque a funcao passa a gravar nele.
--   Fora do escopo: dono do desfecho (decisao e), produto na aprovacao da curadoria (decisao c) e a
--   metrica articles_published.
--
-- Corpo montado sobre o vivo (md5 normalizado == captura 20260427200000, conferido em 09/10).
-- Assinatura, SECURITY DEFINER e grants nao mudam (CREATE OR REPLACE).
-- ROLLBACK: reaplicar a captura 20260427200000 de create_publication_submission.
-- =====================================================================================

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
  v_product_id uuid;
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

  -- #2565 (ADR-0099 §6): toda submissao pertence a um produto. Com card: o produto ja ligado ao card,
  -- ou um produto novo com source_kind 'board_item', ligado ao card; sem card: 'external' com a URI do
  -- destino. Mesmo criterio do backfill da p265 (instrumento = tipo do destino; modo de revisao pelo
  -- tipo; status under_review).
  IF p_board_item_id IS NOT NULL THEN
    IF NOT public.rls_can_see_item(p_board_item_id) THEN
      RAISE EXCEPTION 'Board item not found';
    END IF;
    SELECT bi.content_product_id INTO v_product_id FROM public.board_items bi WHERE bi.id = p_board_item_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Board item not found';
    END IF;
  END IF;

  IF v_product_id IS NULL THEN
    INSERT INTO public.content_products (
      title, summary, source_kind, source_board_item_id, source_external_uri,
      target_instrument, review_mode, status,
      initiative_id, proposer_member_id, publication_metadata, created_by
    )
    VALUES (
      p_title, p_abstract,
      CASE WHEN p_board_item_id IS NOT NULL THEN 'board_item' ELSE 'external' END::public.content_product_source_kind,
      p_board_item_id,
      CASE WHEN p_board_item_id IS NULL
           THEN coalesce(nullif(btrim(p_target_url), ''), nullif(btrim(p_target_name), ''), p_title) END,
      p_target_type::text::public.content_product_instrument,
      CASE p_target_type::text
        WHEN 'pmi_global_conference' THEN 'independent_blind'
        WHEN 'pmi_chapter_event'     THEN 'sequential'
        WHEN 'academic_journal'      THEN 'independent_blind'
        WHEN 'academic_conference'   THEN 'independent_blind'
        WHEN 'webinar'               THEN 'collaborative'
        WHEN 'blog_post'             THEN 'sequential'
        WHEN 'linkedin_newsletter'   THEN 'sequential'
        ELSE 'collaborative'
      END::public.review_mode,
      'under_review'::public.content_product_status,
      v_initiative_id, p_primary_author_id,
      jsonb_build_object('origin', 'create_publication_submission'),
      v_member_id
    )
    RETURNING id INTO v_product_id;

    IF p_board_item_id IS NOT NULL THEN
      UPDATE public.board_items SET content_product_id = v_product_id WHERE id = p_board_item_id;
    END IF;
  END IF;

  INSERT INTO public.publication_submissions (
    title, target_type, target_name, primary_author_id,
    initiative_id,
    board_item_id, abstract, target_url, estimated_cost_brl, created_by,
    content_product_id
  )
  VALUES (
    p_title, p_target_type, p_target_name, p_primary_author_id,
    v_initiative_id,
    p_board_item_id, p_abstract, p_target_url, p_estimated_cost_brl, v_member_id,
    v_product_id
  )
  RETURNING id INTO v_submission_id;

  INSERT INTO public.publication_submission_authors
    (submission_id, member_id, author_order, is_corresponding)
  VALUES (v_submission_id, p_primary_author_id, 1, true);

  RETURN v_submission_id;
END;
$$;
