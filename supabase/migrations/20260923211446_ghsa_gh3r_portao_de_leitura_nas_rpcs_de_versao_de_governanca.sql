-- ============================================================================
-- GHSA-gh3r-fhjr-cr8w — tres RPCs de governanca devolviam conteudo de versao sem portao de chamador
-- ============================================================================
--
-- WHAT: helper unico _can_read_governance_version(p_version_id) e portao nele em
--   get_chain_workflow_detail, get_next_draft_version e get_previous_locked_version.
--   REVOKE de PUBLIC/anon em get_next_draft_version, que era executavel sem login.
-- WHY: as tres sao SECURITY DEFINER e nao conferiam quem chama (nem auth.uid(), nem membro ativo,
--   nem visibility_class). Quem tinha um id de versao ou de cadeia lia o texto; a do rascunho,
--   inclusive sem login. Os leitores com portao (get_governance_document_reader e
--   get_governance_document_draft_preview) ja aplicavam esses criterios.
-- REGRA (uma so, para as tres): service_role le; conta sem membro ativo nao le; audit_restricted
--   so manage_platform; manage_member le; quem abriu, assinou ou pode assinar cadeia ABERTA do
--   documento le o que assina; admin_only so admin; legal_scoped exige assinatura corrente;
--   public/active_members: versao travada para todo membro ativo, rascunho para revisao de
--   governanca, curadoria ou autoria.
-- COMPAT: chamadores no navegador (ReviewChainIsland, pagina de documentos) ja tratam
--   error/exists=false; negado responde igual a inexistente (sem oraculo). Os dois pareceristas
--   externos da rodada passam (participate_in_governance_review + active_members).
-- Corpos base conferidos IGUAIS ao vivo por md5 normalizado (capturas p255, 2146, p842).
-- ROLLBACK: reaplicar os corpos das tres capturas base e DROP do helper.
-- ============================================================================

CREATE OR REPLACE FUNCTION public._can_read_governance_version(p_version_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_member uuid;
  v_ver record;
  v_doc record;
BEGIN
  -- service_role ja le as tabelas direto; o portao existe para contas de pessoa.
  IF auth.role() = 'service_role' THEN
    RETURN true;
  END IF;

  -- Membro ativo. Conta autenticada sem cadastro (fantasma) e anon nao leem nada.
  SELECT m.id INTO v_member
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true
  LIMIT 1;
  IF v_member IS NULL THEN
    RETURN false;
  END IF;

  SELECT dv.id, dv.document_id, dv.locked_at, dv.authored_by INTO v_ver
  FROM public.document_versions dv WHERE dv.id = p_version_id;
  IF v_ver.id IS NULL THEN
    RETURN false;
  END IF;

  SELECT gd.id, gd.visibility_class INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_ver.document_id;
  IF v_doc.id IS NULL THEN
    RETURN false;
  END IF;

  -- audit_restricted: so manage_platform, como no leitor (manage_member NAO basta).
  IF v_doc.visibility_class = 'audit_restricted' THEN
    RETURN public.can_by_member(v_member, 'manage_platform');
  END IF;

  IF public.can_by_member(v_member, 'manage_member') THEN
    RETURN true;
  END IF;

  -- Quem abriu, assinou ou pode assinar uma cadeia ABERTA do documento le o que assina,
  -- inclusive em documento legal_scoped.
  IF EXISTS (
    SELECT 1 FROM public.approval_chains ac
    WHERE ac.document_id = v_doc.id AND ac.closed_at IS NULL
      AND (
        ac.opened_by = v_member
        OR EXISTS (SELECT 1 FROM public.approval_signoffs s
                   WHERE s.approval_chain_id = ac.id AND s.signer_id = v_member)
        OR EXISTS (SELECT 1 FROM jsonb_array_elements(ac.gates) g
                   WHERE public._can_sign_gate(v_member, ac.id, g->>'kind'))
      )
  ) THEN
    RETURN true;
  END IF;

  IF v_doc.visibility_class = 'admin_only' THEN
    RETURN false;
  END IF;

  IF v_doc.visibility_class = 'legal_scoped' THEN
    RETURN EXISTS (SELECT 1 FROM public.member_document_signatures mds
                   WHERE mds.member_id = v_member AND mds.document_id = v_doc.id AND mds.is_current = true);
  END IF;

  -- public / active_members: versao travada e de todo membro ativo (espelho do leitor).
  IF v_ver.locked_at IS NOT NULL THEN
    RETURN true;
  END IF;

  -- Rascunho: espelho do draft preview (revisao de governanca, curadoria ou autoria).
  RETURN v_ver.authored_by = v_member
      OR public.can_by_member(v_member, 'participate_in_governance_review')
      OR public.can_by_member(v_member, 'curate_content');
END;
$fn$;

REVOKE ALL ON FUNCTION public._can_read_governance_version(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_chain_workflow_detail(p_chain_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_chain record;
  v_gates jsonb;
  v_signoffs jsonb;
  v_submitter jsonb;
BEGIN
  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id, ac.opened_at, ac.opened_by,
         gd.title, gd.doc_type, dv.version_label, dv.locked_at, dv.content_html
  INTO v_chain
  FROM public.approval_chains ac
  JOIN public.governance_documents gd ON gd.id = ac.document_id
  LEFT JOIN public.document_versions dv ON dv.id = ac.version_id
  WHERE ac.id = p_chain_id;

  IF v_chain.id IS NULL THEN
    RETURN jsonb_build_object('error','chain_not_found');
  END IF;

  -- GHSA-gh3r-fhjr-cr8w: sem este portao, qualquer conta autenticada com o chain_id lia o texto e os
  -- nomes de quem assina. Negado responde igual a inexistente, para nao virar oraculo de chain_id.
  IF NOT public._can_read_governance_version(v_chain.version_id) THEN
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
    'content_html', v_chain.content_html,
    'opened_at', v_chain.opened_at,
    'submitter', v_submitter,
    'gates', COALESCE(v_gates, '[]'::jsonb),
    'days_open', CASE WHEN v_chain.opened_at IS NOT NULL
      THEN EXTRACT(EPOCH FROM (now() - v_chain.opened_at))/86400
      ELSE NULL END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_next_draft_version(p_version_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_current record;
  v_draft record;
BEGIN
  SELECT dv.id, dv.document_id, dv.version_number
  INTO v_current
  FROM public.document_versions dv WHERE dv.id = p_version_id;
  IF v_current.id IS NULL THEN
    RETURN jsonb_build_object('error','version_not_found');
  END IF;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html,
         dv.content_markdown, dv.authored_at, dv.notes
  INTO v_draft
  FROM public.document_versions dv
  WHERE dv.document_id = v_current.document_id
    AND dv.version_number > v_current.version_number
    AND dv.locked_at IS NULL
  ORDER BY dv.version_number DESC
  LIMIT 1;

  IF v_draft.id IS NULL THEN
    RETURN jsonb_build_object('exists', false);
  END IF;

  -- GHSA-gh3r-fhjr-cr8w: esta funcao devolvia RASCUNHO a qualquer chamador, inclusive anon.
  IF NOT public._can_read_governance_version(v_draft.id) THEN
    RETURN jsonb_build_object('exists', false);
  END IF;

  RETURN jsonb_build_object(
    'exists', true,
    'version_id', v_draft.id,
    'version_number', v_draft.version_number,
    'version_label', v_draft.version_label,
    'content_html', v_draft.content_html,
    'content_markdown', v_draft.content_markdown,
    'authored_at', v_draft.authored_at,
    'notes', v_draft.notes
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.get_previous_locked_version(p_version_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_current record;
  v_prev record;
BEGIN
  SELECT dv.id, dv.document_id, dv.version_number
  INTO v_current FROM public.document_versions dv WHERE dv.id = p_version_id;
  IF v_current.id IS NULL THEN RETURN jsonb_build_object('error','version_not_found'); END IF;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html,
         dv.content_markdown, dv.locked_at, dv.published_at
  INTO v_prev
  FROM public.document_versions dv
  WHERE dv.document_id = v_current.document_id
    AND dv.version_number < v_current.version_number
    -- #842: locked_at gate removed — a superseded-but-unlocked round is still a real
    -- predecessor. The withdrawn-exclusion below already drops IP-1 seeds / abandoned chains.
    AND NOT EXISTS (
      SELECT 1 FROM public.approval_chains ac
      WHERE ac.version_id = dv.id AND ac.status = 'withdrawn'
    )
  ORDER BY dv.version_number DESC LIMIT 1;

  IF v_prev.id IS NULL THEN RETURN jsonb_build_object('exists', false); END IF;

  -- GHSA-gh3r-fhjr-cr8w: a versao anterior pode estar destravada (#842), e ai e rascunho.
  IF NOT public._can_read_governance_version(v_prev.id) THEN
    RETURN jsonb_build_object('exists', false);
  END IF;

  RETURN jsonb_build_object(
    'exists', true,
    'version_id', v_prev.id,
    'version_number', v_prev.version_number,
    'version_label', v_prev.version_label,
    'content_html', v_prev.content_html,
    'content_markdown', v_prev.content_markdown,
    'locked_at', v_prev.locked_at,
    'published_at', v_prev.published_at
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_next_draft_version(uuid) FROM PUBLIC, anon;
