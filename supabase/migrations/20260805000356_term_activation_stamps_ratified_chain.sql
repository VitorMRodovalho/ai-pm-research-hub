-- Term activation must stamp the ratified approval chain.
--
-- Root cause of the live V_status_chain_coherence violation (doc 280c2c56, the v9 term
-- template activated in Onda 1 on 2026-07-07): activate_volunteer_term_version flips the
-- document to status='active' but never sets governance_documents.current_ratified_chain_id
-- nor approval_chains.activated_at. The invariant (#315 P0-Q6) requires every approved/active
-- governance_document to carry a non-null current_ratified_chain_id, so the activation left the
-- doc in an incoherent state.
--
-- Fix:
--   1. (root cause) On activation, resolve the approved chain for the current version and stamp
--      both current_ratified_chain_id (on the doc) and activated_at (on the chain).
--   2. (backfill) Repair any already-active/approved governance_document whose ratified chain is
--      null but which has an approved chain for its current version (covers doc 280c2c56 now).
CREATE OR REPLACE FUNCTION public.activate_volunteer_term_version(p_doc_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_member uuid;
  v_doc record;
  v_html text;
  v_deactivated int := 0;
  v_chain_id uuid;
BEGIN
  SELECT id INTO v_actor_member FROM members WHERE auth_id = auth.uid();
  IF v_actor_member IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  IF NOT public.can_by_member(v_actor_member, 'manage_platform', NULL, NULL) THEN
    RETURN jsonb_build_object('error', 'forbidden',
      'message', 'Apenas manage_platform pode ativar uma versão do Termo de Voluntariado.');
  END IF;

  SELECT g.id, g.doc_type, g.status, g.current_version_id, g.version
    INTO v_doc
  FROM governance_documents g WHERE g.id = p_doc_id;
  IF v_doc.id IS NULL THEN RETURN jsonb_build_object('error', 'document_not_found'); END IF;
  IF v_doc.doc_type <> 'volunteer_term_template' THEN
    RETURN jsonb_build_object('error', 'wrong_doc_type', 'doc_type', v_doc.doc_type);
  END IF;

  SELECT dv.content_html INTO v_html
  FROM document_versions dv
  WHERE dv.id = v_doc.current_version_id AND dv.locked_at IS NOT NULL;
  IF v_html IS NULL OR length(btrim(v_html)) = 0 THEN
    RETURN jsonb_build_object('error', 'no_locked_body',
      'message', 'A versão corrente não está travada (locked) ou não tem corpo HTML. Trave a versão na cadeia antes de ativar.',
      'current_version_id', v_doc.current_version_id);
  END IF;

  UPDATE governance_documents
     SET status = 'superseded', updated_at = now()
   WHERE doc_type = 'volunteer_term_template' AND status = 'active' AND id <> p_doc_id;
  GET DIAGNOSTICS v_deactivated = ROW_COUNT;

  SELECT ac.id INTO v_chain_id
  FROM approval_chains ac
  WHERE ac.document_id = p_doc_id
    AND ac.version_id = v_doc.current_version_id
    AND ac.status = 'approved'
  ORDER BY ac.approved_at DESC NULLS LAST
  LIMIT 1;

  UPDATE governance_documents
     SET status = 'active',
         current_ratified_chain_id = COALESCE(v_chain_id, current_ratified_chain_id),
         updated_at = now()
   WHERE id = p_doc_id;

  IF v_chain_id IS NOT NULL THEN
    UPDATE approval_chains
       SET activated_at = COALESCE(activated_at, now()), updated_at = now()
     WHERE id = v_chain_id;
  END IF;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_actor_member, 'volunteer_term_activated', 'governance_document', p_doc_id,
    jsonb_build_object('version', v_doc.version, 'current_version_id', v_doc.current_version_id,
      'superseded_count', v_deactivated, 'ratified_chain_id', v_chain_id));

  RETURN jsonb_build_object('success', true, 'activated', p_doc_id,
    'version', v_doc.version, 'superseded', v_deactivated, 'ratified_chain_id', v_chain_id);
END;
$function$;

-- Backfill: repair active/approved governance_documents whose ratified chain is null but which
-- have an approved chain for their current version. Stamps the chain's activated_at too.
-- Idempotent (guarded by current_ratified_chain_id IS NULL). Fixes doc 280c2c56 (v9 term, Onda 1).
WITH resolved AS (
  SELECT gd.id AS doc_id, ac.id AS chain_id
  FROM public.governance_documents gd
  JOIN public.approval_chains ac
    ON ac.document_id = gd.id
   AND ac.version_id = gd.current_version_id
   AND ac.status = 'approved'
  WHERE gd.status IN ('approved', 'active')
    AND gd.current_ratified_chain_id IS NULL
)
UPDATE public.governance_documents gd
   SET current_ratified_chain_id = r.chain_id, updated_at = now()
  FROM resolved r
 WHERE gd.id = r.doc_id;

UPDATE public.approval_chains ac
   SET activated_at = COALESCE(ac.activated_at, now()), updated_at = now()
  FROM public.governance_documents gd
 WHERE gd.current_ratified_chain_id = ac.id
   AND ac.activated_at IS NULL
   AND gd.status IN ('approved', 'active');
