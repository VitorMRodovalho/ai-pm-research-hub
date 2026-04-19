-- Phase IP-3c — Workflow refinements based on PM correction (2026-04-18 p33):
-- * GP (Vitor) is submitter, not curator (opened_by populated)
-- * leader_awareness: non-blocking awareness gate for tribe_leaders/manager
-- * submitter_acceptance: GP final aceite pós-curadoria before presidents
-- * chapter_witness: pontos focais dos capítulos como testemunhas (seed pending)
-- * legal_signer designation: distingue quem tem poder legal dentro de chapter_board
-- * Lorena (diretoria voluntariado PMI-GO) limited to volunteer_term_template docs
-- * Comment visibility: submitter_only + change_notes added; public retained for back-compat

-- ========================================
-- 1. Update document_comments visibility CHECK
-- ========================================
ALTER TABLE public.document_comments DROP CONSTRAINT IF EXISTS document_comments_visibility_check;
ALTER TABLE public.document_comments ADD CONSTRAINT document_comments_visibility_check
  CHECK (visibility = ANY (ARRAY['curator_only'::text, 'submitter_only'::text, 'change_notes'::text, 'public'::text]));

-- ========================================
-- 2. Seed designations: legal_signer + voluntariado_director
-- ========================================
UPDATE public.members
SET designations = array_append(designations, 'legal_signer'::text)
WHERE email IN (
  'ivan.lourenco@pmigo.org.br',
  'presidencia@pmirs.org.br',
  'matheus.rocha@pmidf.org',
  'presidencia@pmimg.org.br',
  'jessica.alcantara@pmice.org.br'
)
AND NOT ('legal_signer' = ANY(designations));

UPDATE public.members
SET designations = array_append(designations, 'voluntariado_director'::text)
WHERE email = 'diretoriavoluntariado@pmigo.org.br'
AND NOT ('voluntariado_director' = ANY(designations));

-- ========================================
-- 3. Rewrite _can_sign_gate with new gate kinds + doc-aware president_go
-- ========================================
DROP FUNCTION IF EXISTS public._can_sign_gate(uuid, uuid, text);
CREATE OR REPLACE FUNCTION public._can_sign_gate(
  p_member_id uuid,
  p_chain_id uuid,
  p_gate_kind text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member record;
  v_chain record;
  v_doc_type text;
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.chapter, m.is_active, m.member_status
  INTO v_member FROM public.members m WHERE m.id = p_member_id;
  IF v_member.id IS NULL OR v_member.is_active = false THEN RETURN false; END IF;

  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.opened_by INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL OR v_chain.status NOT IN ('review','approved') THEN RETURN false; END IF;

  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_chain.gates) g WHERE g->>'kind' = p_gate_kind) THEN
    RETURN false;
  END IF;

  SELECT gd.doc_type INTO v_doc_type
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  RETURN CASE p_gate_kind
    WHEN 'curator' THEN 'curator' = ANY(v_member.designations)
    WHEN 'leader' THEN v_member.operational_role IN ('tribe_leader','manager','deputy_manager')
    WHEN 'leader_awareness' THEN
      v_member.operational_role IN ('tribe_leader','manager','deputy_manager')
      OR 'founder' = ANY(v_member.designations)
    WHEN 'submitter_acceptance' THEN
      v_chain.opened_by IS NOT NULL AND v_member.id = v_chain.opened_by
    WHEN 'president_go' THEN
      v_member.chapter = 'PMI-GO'
      AND 'chapter_board' = ANY(v_member.designations)
      AND (
        'legal_signer' = ANY(v_member.designations)
        OR (v_doc_type = 'volunteer_term_template' AND 'voluntariado_director' = ANY(v_member.designations))
      )
    WHEN 'president_others' THEN
      v_member.chapter IN ('PMI-CE','PMI-DF','PMI-MG','PMI-RS')
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)
    WHEN 'chapter_witness' THEN
      'chapter_witness' = ANY(v_member.designations)
    WHEN 'member_ratification' THEN
      v_member.member_status = 'active'
    WHEN 'external_signer' THEN
      v_member.operational_role = 'external_signer'
    ELSE false
  END;
END;
$$;

-- ========================================
-- 4. Update gates jsonb of 4 v2.2 chains + set opened_by = Vitor
-- ========================================
DO $$
DECLARE
  v_vitor uuid;
BEGIN
  SELECT id INTO v_vitor FROM public.members WHERE email='vitor.rodovalho@outlook.com';
  IF v_vitor IS NULL THEN RAISE EXCEPTION 'Vitor member not found'; END IF;

  UPDATE public.approval_chains
  SET gates = '[
    {"kind": "curator",              "order": 1, "threshold": 1},
    {"kind": "leader_awareness",     "order": 2, "threshold": 0},
    {"kind": "submitter_acceptance", "order": 3, "threshold": 1},
    {"kind": "president_go",         "order": 4, "threshold": 1},
    {"kind": "president_others",     "order": 5, "threshold": 4},
    {"kind": "chapter_witness",      "order": 6, "threshold": 5},
    {"kind": "member_ratification",  "order": 7, "threshold": "all"}
  ]'::jsonb,
  opened_by = v_vitor,
  updated_at = now()
  WHERE id IN (
    '8b65de6c-b888-468c-892b-8249c8cf0482',
    '47f2d655-6ff2-4cb2-9fe0-97ebd8ba4532',
    '548fd268-0f08-4d90-9518-7bacdc907776'
  );

  UPDATE public.approval_chains
  SET gates = '[
    {"kind": "curator",              "order": 1, "threshold": 1},
    {"kind": "leader_awareness",     "order": 2, "threshold": 0},
    {"kind": "submitter_acceptance", "order": 3, "threshold": 1},
    {"kind": "president_go",         "order": 4, "threshold": 1},
    {"kind": "president_others",     "order": 5, "threshold": 4},
    {"kind": "chapter_witness",      "order": 6, "threshold": 5}
  ]'::jsonb,
  opened_by = v_vitor,
  updated_at = now()
  WHERE id = '8e7a70c6-f9dd-4c57-b5fa-b548ec965581';
END $$;

-- ========================================
-- 5. New RPC: get_chain_workflow_detail
-- ========================================
CREATE OR REPLACE FUNCTION public.get_chain_workflow_detail(p_chain_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_chain record;
  v_gates jsonb;
  v_submitter jsonb;
BEGIN
  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id, ac.opened_at, ac.opened_by,
         gd.title, gd.doc_type, dv.version_label, dv.locked_at
  INTO v_chain
  FROM public.approval_chains ac
  JOIN public.governance_documents gd ON gd.id = ac.document_id
  LEFT JOIN public.document_versions dv ON dv.id = ac.version_id
  WHERE ac.id = p_chain_id;

  IF v_chain.id IS NULL THEN
    RETURN jsonb_build_object('error','chain_not_found');
  END IF;

  SELECT jsonb_build_object('id', m.id, 'name', m.name, 'chapter', m.chapter, 'role', m.operational_role)
  INTO v_submitter
  FROM public.members m WHERE m.id = v_chain.opened_by;

  SELECT jsonb_agg(
    jsonb_build_object(
      'kind', g->>'kind',
      'order', (g->>'order')::int,
      'threshold', g->>'threshold',
      'signed_count', (
        SELECT COUNT(*) FROM public.approval_signoffs s
        WHERE s.approval_chain_id = v_chain.id
          AND s.gate_kind = g->>'kind'
          AND s.signoff_type IN ('approval','acknowledge')
      ),
      'signers', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'name', m.name,
          'chapter', m.chapter,
          'signed_at', s.signed_at,
          'signoff_type', s.signoff_type,
          'hash_short', SUBSTRING(s.signature_hash FROM 1 FOR 12)
        ) ORDER BY s.signed_at), '[]'::jsonb)
        FROM public.approval_signoffs s
        LEFT JOIN public.members m ON m.id = s.signer_id
        WHERE s.approval_chain_id = v_chain.id AND s.gate_kind = g->>'kind'
      ),
      'eligible_pending', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'chapter', m.chapter)
          ORDER BY m.name), '[]'::jsonb)
        FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, v_chain.id, g->>'kind')
          AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
            WHERE s.approval_chain_id = v_chain.id
              AND s.gate_kind = g->>'kind'
              AND s.signer_id = m.id)
      )
    ) ORDER BY (g->>'order')::int
  )
  INTO v_gates
  FROM jsonb_array_elements(v_chain.gates) g;

  RETURN jsonb_build_object(
    'chain_id', v_chain.id,
    'chain_status', v_chain.status,
    'document_id', v_chain.document_id,
    'document_title', v_chain.title,
    'doc_type', v_chain.doc_type,
    'version_id', v_chain.version_id,
    'version_label', v_chain.version_label,
    'locked_at', v_chain.locked_at,
    'opened_at', v_chain.opened_at,
    'submitter', v_submitter,
    'gates', COALESCE(v_gates, '[]'::jsonb),
    'days_open', CASE WHEN v_chain.opened_at IS NOT NULL
      THEN EXTRACT(EPOCH FROM (now() - v_chain.opened_at))/86400
      ELSE NULL END
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_chain_workflow_detail(uuid) TO authenticated;

-- ========================================
-- 6. Comment RPCs (create_document_comment, resolve_document_comment, list_document_comments, create_change_note)
-- ========================================
CREATE OR REPLACE FUNCTION public.create_document_comment(
  p_version_id uuid,
  p_clause_anchor text,
  p_body text,
  p_visibility text,
  p_parent_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member record;
  v_comment_id uuid;
BEGIN
  SELECT m.id, m.name, m.operational_role, m.designations, m.is_active
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL OR v_member.is_active = false THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  IF p_visibility NOT IN ('curator_only','submitter_only','change_notes') THEN
    RETURN jsonb_build_object('error','invalid_visibility');
  END IF;

  IF NOT (
    'curator' = ANY(v_member.designations)
    OR v_member.operational_role IN ('manager','deputy_manager','tribe_leader')
    OR 'founder' = ANY(v_member.designations)
  ) THEN
    RETURN jsonb_build_object('error','not_authorized');
  END IF;

  IF length(COALESCE(p_body,'')) = 0 THEN
    RETURN jsonb_build_object('error','empty_body');
  END IF;

  INSERT INTO public.document_comments (document_version_id, author_id, clause_anchor, body, parent_id, visibility)
  VALUES (p_version_id, v_member.id, p_clause_anchor, p_body, p_parent_id, p_visibility)
  RETURNING id INTO v_comment_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'document_comment_created', 'document_comment', v_comment_id,
    jsonb_build_object('version_id', p_version_id, 'visibility', p_visibility, 'clause_anchor', p_clause_anchor));

  RETURN jsonb_build_object('success', true, 'comment_id', v_comment_id, 'created_at', now());
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_document_comment(uuid, text, text, text, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_document_comment(
  p_comment_id uuid,
  p_resolution_note text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member record;
  v_comment record;
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.is_active
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL OR v_member.is_active = false THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  SELECT c.id, c.author_id, c.resolved_at INTO v_comment
  FROM public.document_comments c WHERE c.id = p_comment_id;
  IF v_comment.id IS NULL THEN
    RETURN jsonb_build_object('error','not_found');
  END IF;
  IF v_comment.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('error','already_resolved');
  END IF;

  IF NOT (
    v_comment.author_id = v_member.id
    OR 'curator' = ANY(v_member.designations)
    OR v_member.operational_role IN ('manager','deputy_manager')
  ) THEN
    RETURN jsonb_build_object('error','not_authorized');
  END IF;

  UPDATE public.document_comments
  SET resolved_at = now(), resolved_by = v_member.id, resolution_note = p_resolution_note, updated_at = now()
  WHERE id = p_comment_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'document_comment_resolved', 'document_comment', p_comment_id,
    jsonb_build_object('resolution_note', p_resolution_note));

  RETURN jsonb_build_object('success', true, 'resolved_at', now());
END;
$$;
GRANT EXECUTE ON FUNCTION public.resolve_document_comment(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_document_comments(
  p_version_id uuid,
  p_include_resolved boolean DEFAULT false
) RETURNS TABLE (
  id uuid,
  clause_anchor text,
  body text,
  visibility text,
  parent_id uuid,
  author_id uuid,
  author_name text,
  author_role text,
  created_at timestamptz,
  resolved_at timestamptz,
  resolved_by_name text,
  resolution_note text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member record;
  v_can_see_all boolean;
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.is_active
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL OR v_member.is_active = false THEN RETURN; END IF;

  v_can_see_all := (
    'curator' = ANY(v_member.designations)
    OR v_member.operational_role IN ('manager','deputy_manager')
    OR 'founder' = ANY(v_member.designations)
  );

  RETURN QUERY
  SELECT c.id, c.clause_anchor, c.body, c.visibility, c.parent_id,
    c.author_id, m.name AS author_name, m.operational_role AS author_role,
    c.created_at, c.resolved_at,
    (SELECT rm.name FROM public.members rm WHERE rm.id = c.resolved_by) AS resolved_by_name,
    c.resolution_note
  FROM public.document_comments c
  JOIN public.members m ON m.id = c.author_id
  WHERE c.document_version_id = p_version_id
    AND (p_include_resolved OR c.resolved_at IS NULL)
    AND (
      v_can_see_all
      OR c.author_id = v_member.id
      OR (c.visibility = 'curator_only' AND ('curator' = ANY(v_member.designations)))
    )
  ORDER BY c.clause_anchor NULLS LAST, c.created_at ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.list_document_comments(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_change_note(
  p_chain_id uuid,
  p_body text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member record;
  v_chain record;
  v_comment_id uuid;
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.is_active
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL OR v_member.is_active = false THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  SELECT ac.id, ac.version_id, ac.opened_by INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN
    RETURN jsonb_build_object('error','chain_not_found');
  END IF;

  IF NOT (
    v_chain.opened_by = v_member.id
    OR v_member.operational_role IN ('manager','deputy_manager')
  ) THEN
    RETURN jsonb_build_object('error','not_authorized');
  END IF;

  IF length(COALESCE(p_body,'')) = 0 THEN
    RETURN jsonb_build_object('error','empty_body');
  END IF;

  INSERT INTO public.document_comments (document_version_id, author_id, body, visibility)
  VALUES (v_chain.version_id, v_member.id, p_body, 'change_notes')
  RETURNING id INTO v_comment_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'change_note_created', 'document_comment', v_comment_id,
    jsonb_build_object('chain_id', p_chain_id, 'version_id', v_chain.version_id));

  RETURN jsonb_build_object('success', true, 'comment_id', v_comment_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_change_note(uuid, text) TO authenticated;

-- ========================================
-- 7. Update document_comments RLS to support new visibility taxonomy
-- ========================================
DROP POLICY IF EXISTS document_comments_read_visibility ON public.document_comments;
CREATE POLICY document_comments_read_visibility ON public.document_comments
FOR SELECT USING (
  author_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid())
  OR EXISTS (SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid() AND can_by_member(m.id, 'manage_member'))
  OR (visibility = 'curator_only' AND EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid()
      AND ('curator' = ANY(m.designations)
           OR m.operational_role IN ('manager','deputy_manager','tribe_leader'))
  ))
  OR (visibility = 'change_notes' AND EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid()
      AND (m.operational_role IN ('manager','deputy_manager','tribe_leader')
           OR 'chapter_board' = ANY(m.designations)
           OR 'chapter_witness' = ANY(m.designations)
           OR 'curator' = ANY(m.designations))
  ))
);

NOTIFY pgrst, 'reload schema';
