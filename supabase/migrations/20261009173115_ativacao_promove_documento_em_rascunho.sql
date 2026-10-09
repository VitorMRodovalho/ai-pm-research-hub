-- =====================================================================================
-- Ativacao de cadeia promove o documento que circulou direto de rascunho
--
-- trg_sync_ratification_cache (AFTER INSERT OR UPDATE OF status ON approval_chains) atualiza o
-- cache de ratificacao do documento quando a cadeia vira 'active' e promovia so 'under_review'.
-- Medido em 09/10/2026: o TAP do Grupo de Estudos CPMAI, primeira cadeia do sistema a chegar em
-- 'approved' pelo fluxo normal de assinaturas, esta com o documento em 'draft'; ao ativar a
-- cadeia ele continuaria 'draft'. Agora 'draft' e 'under_review' viram 'active'; os demais status
-- (active, superseded, withdrawn...) nao mudam.
--
-- Corpo montado sobre o vivo (identico a captura 20260516520000). Assinatura, SECURITY DEFINER,
-- search_path, grants e o gatilho nao mudam (CREATE OR REPLACE).
-- ROLLBACK: reaplicar a captura 20260516520000 de trg_sync_ratification_cache.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.trg_sync_ratification_cache()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_activated_at timestamptz;
BEGIN
  IF NEW.status = 'active' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'active') THEN
    v_activated_at := COALESCE(NEW.activated_at, NEW.approved_at, now());

    -- Auto-supersede prior active chain for same doc (if any)
    UPDATE public.approval_chains
       SET status = 'superseded',
           closed_at = COALESCE(closed_at, v_activated_at),
           notes = COALESCE(notes, '') || E'\n[auto-superseded by chain ' || NEW.id::text || ' at ' || v_activated_at::text || ' — new ratification supersedes prior active chain]',
           updated_at = now()
     WHERE document_id = NEW.document_id
       AND id <> NEW.id
       AND status = 'active';

    -- Update governance_documents cache
    UPDATE public.governance_documents
       SET first_ratified_at         = COALESCE(first_ratified_at, v_activated_at),
           first_ratified_chain_id   = COALESCE(first_ratified_chain_id, NEW.id),
           first_ratified_version_id = COALESCE(first_ratified_version_id, NEW.version_id),
           current_ratified_at         = v_activated_at,
           current_ratified_chain_id   = NEW.id,
           current_ratified_version_id = NEW.version_id,
           -- A ativacao promove o documento que ainda esta em rascunho ou em revisao. Antes so
           -- 'under_review' virava 'active', e um documento que circulou direto de 'draft' (o TAP
           -- do Grupo de Estudos CPMAI, primeira cadeia aprovada pelo fluxo normal, 09/10/2026)
           -- ficava 'draft' com a cadeia ativa.
           status = CASE WHEN status IN ('draft', 'under_review') THEN 'active' ELSE status END,
           updated_at = now()
     WHERE id = NEW.document_id;
  END IF;
  RETURN NEW;
END;
$function$;
