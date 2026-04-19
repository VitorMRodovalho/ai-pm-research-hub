-- ============================================================================
-- IP-3d: atribuir drafts v2.2 a Vitor (GP/PM) para aparecer em
-- list_my_document_drafts (section "Seus rascunhos")
--
-- Context: IP-1 seed não setou authored_by em document_versions. Após
-- cleanup v2.2→draft (migration 20260503030000), os rascunhos ficaram
-- com authored_by=NULL, invisíveis a qualquer caller na seção
-- "Seus rascunhos" (filtra por authored_by = caller).
--
-- Fix: atribuir Vitor (PM) como author dos 4 rascunhos v2.2. Ele é
-- quem vai editá-los e submetê-los pro workflow de ratificação.
-- ============================================================================

UPDATE public.document_versions
SET authored_by = '880f736c-3e76-4df4-9375-33575c190305'::uuid,
    updated_at = now()
WHERE locked_at IS NULL AND authored_by IS NULL;

INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, created_at)
SELECT
  '880f736c-3e76-4df4-9375-33575c190305'::uuid,
  'ip3d.attribute_draft_to_gp',
  'document_version',
  dv.id,
  jsonb_build_object(
    'reason', 'Drafts v2.2 criados por IP-1 seed sem authored_by. Atribuindo a Vitor (PM/GP).',
    'version_label', dv.version_label
  ),
  now()
FROM public.document_versions dv
WHERE dv.authored_by = '880f736c-3e76-4df4-9375-33575c190305'::uuid
  AND dv.locked_at IS NULL;
