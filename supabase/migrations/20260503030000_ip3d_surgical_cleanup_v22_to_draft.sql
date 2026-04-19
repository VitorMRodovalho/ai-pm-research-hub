-- ============================================================================
-- IP-3d surgical cleanup — return v2.2 versions to draft state
--
-- Authorized by PM 2026-04-19 p34 post-smoke test.
-- Rationale: IP-1 seed (20260429060001-60005) lockou os docs v2.1 + criou
-- chains v2.2 em review, pulando o step zero (edição do documento antes
-- de lacrar). Notas de versão ficaram embedded no content_html, que
-- viraria legal evidence sem limpeza. PM decidiu que, antes de qualquer
-- signatário real (presidentes, witnesses), faremos cleanup cirúrgico:
--   * Delete os 4 approval_chains em review (v2.2 chains)
--   * Delete 3 signoffs associados (2 smoke p33 + 1 earlier)
--   * Unlock document_versions v2.2 (set locked_at=NULL)
--   * Reset governance_documents.current_version_id de volta pra v2.1
--     (preserva invariante J — current must be locked, v2.1 is locked)
--
-- v2.1 permanece no histórico como evidência imutável do que foi enviado
-- pro Ivan (legal counsel). v2.2 vira draft editável por Vitor via novo
-- editor /admin/governance/documents/[docId]/versions/new?draft=<v2.2_id>
--
-- Atomicidade: tudo numa migration (PostgreSQL BEGIN/COMMIT implícito).
-- Trigger trg_document_version_immutable desabilitado brevemente para
-- permitir UPDATE de locked_at=NULL; re-enabled no final.
--
-- Rollback: restaurar estado via script (requires backup de state anterior).
-- Alternative: re-lock via lock_document_version com mesmos gates.
-- ============================================================================

CREATE TEMP TABLE _cleanup_targets AS
SELECT
  ac.id AS chain_id,
  ac.version_id,
  ac.document_id,
  gd.title AS document_title,
  dv.version_label,
  (SELECT count(*) FROM public.approval_signoffs s WHERE s.approval_chain_id = ac.id) AS signoff_count
FROM public.approval_chains ac
JOIN public.governance_documents gd ON gd.id = ac.document_id
JOIN public.document_versions dv ON dv.id = ac.version_id
WHERE ac.status IN ('draft','review');

DELETE FROM public.approval_signoffs
WHERE approval_chain_id IN (SELECT chain_id FROM _cleanup_targets);

DELETE FROM public.approval_chains
WHERE id IN (SELECT chain_id FROM _cleanup_targets);

ALTER TABLE public.document_versions DISABLE TRIGGER trg_document_version_immutable;
UPDATE public.document_versions
SET locked_at = NULL, locked_by = NULL, published_at = NULL, published_by = NULL, updated_at = now()
WHERE id IN (SELECT version_id FROM _cleanup_targets);
ALTER TABLE public.document_versions ENABLE TRIGGER trg_document_version_immutable;

UPDATE public.governance_documents gd
SET current_version_id = (
  SELECT dv.id FROM public.document_versions dv
  WHERE dv.document_id = gd.id AND dv.locked_at IS NOT NULL
  ORDER BY dv.version_number DESC LIMIT 1
),
updated_at = now()
WHERE gd.id IN (SELECT DISTINCT document_id FROM _cleanup_targets);

INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, created_at)
SELECT
  '880f736c-3e76-4df4-9375-33575c190305'::uuid,
  'ip3d.surgical_cleanup_v22_to_draft',
  'approval_chain',
  chain_id,
  jsonb_build_object(
    'reason', 'PM-authorized cleanup 2026-04-19 p34: return v2.2 to draft state, remove version notes from content_html, before any real signatory.',
    'document_id', document_id,
    'document_title', document_title,
    'version_id', version_id,
    'version_label', version_label,
    'deleted_signoffs', signoff_count,
    'preserves_invariant_J', true
  ),
  now()
FROM _cleanup_targets;

DROP TABLE _cleanup_targets;

NOTIFY pgrst, 'reload schema';
