-- ============================================================================
-- Migration: Phase IP-2 A.2 — document_versions lifecycle audit hooks
-- ADR-0016 D5: audit camada 2 — lifecycle events (publish/lock/created) -> admin_audit_log
-- Rollback:
--   DROP TRIGGER trg_document_version_audit_insert ON public.document_versions;
--   DROP TRIGGER trg_document_version_audit_update ON public.document_versions;
--   DROP FUNCTION public.trg_document_version_audit();
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trg_document_version_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_actor_id uuid;
  v_doc_info jsonb;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();

  SELECT jsonb_build_object(
    'document_id', gd.id,
    'document_title', gd.title,
    'doc_type', gd.doc_type
  ) INTO v_doc_info
  FROM public.governance_documents gd
  WHERE gd.id = NEW.document_id;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
    VALUES (
      COALESCE(v_actor_id, NEW.authored_by),
      'document_version.created',
      'document_version',
      NEW.id,
      v_doc_info || jsonb_build_object(
        'version_number', NEW.version_number,
        'version_label', NEW.version_label,
        'authored_at', NEW.authored_at
      )
    );
    RETURN NEW;
  END IF;

  -- UPDATE: audit lifecycle transitions.
  IF OLD.published_at IS NULL AND NEW.published_at IS NOT NULL THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
    VALUES (
      COALESCE(v_actor_id, NEW.published_by),
      'document_version.published',
      'document_version',
      NEW.id,
      v_doc_info || jsonb_build_object(
        'version_number', NEW.version_number,
        'published_at', NEW.published_at
      )
    );
  END IF;

  IF OLD.locked_at IS NULL AND NEW.locked_at IS NOT NULL THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
    VALUES (
      COALESCE(v_actor_id, NEW.locked_by),
      'document_version.locked',
      'document_version',
      NEW.id,
      v_doc_info || jsonb_build_object(
        'version_number', NEW.version_number,
        'locked_at', NEW.locked_at
      )
    );
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.trg_document_version_audit() IS
  'Grava eventos de lifecycle de document_versions em admin_audit_log. Actions: document_version.created, document_version.published, document_version.locked. ADR-0016 D5 camada 2.';

DROP TRIGGER IF EXISTS trg_document_version_audit_insert ON public.document_versions;
CREATE TRIGGER trg_document_version_audit_insert
  AFTER INSERT ON public.document_versions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_document_version_audit();

DROP TRIGGER IF EXISTS trg_document_version_audit_update ON public.document_versions;
CREATE TRIGGER trg_document_version_audit_update
  AFTER UPDATE ON public.document_versions
  FOR EACH ROW
  WHEN (
    (OLD.published_at IS NULL AND NEW.published_at IS NOT NULL)
    OR (OLD.locked_at IS NULL AND NEW.locked_at IS NOT NULL)
  )
  EXECUTE FUNCTION public.trg_document_version_audit();
