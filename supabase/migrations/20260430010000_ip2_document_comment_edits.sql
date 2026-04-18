-- ============================================================================
-- Migration: Phase IP-2 A.1 — document_comment_edits (history + 15min window)
-- ADR-0016 D5: audit em 3 camadas (approval_signoffs + admin_audit_log + comments)
-- Rollback:
--   DROP TABLE public.document_comment_edits CASCADE;
--   DROP TRIGGER trg_document_comment_enforce_edit_window ON public.document_comments;
--   DROP FUNCTION public.trg_document_comment_enforce_edit_window();
--   CREATE TRIGGER trg_document_comments_set_updated_at
--     BEFORE UPDATE ON public.document_comments
--     FOR EACH ROW EXECUTE FUNCTION public.trg_approval_chain_set_updated_at();
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.document_comment_edits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id uuid NOT NULL REFERENCES public.document_comments(id) ON DELETE CASCADE,
  edited_by uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  previous_body text NOT NULL,
  new_body text NOT NULL,
  edited_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.document_comment_edits IS
  'Historico imutavel de edicoes em document_comments. Permite mostrar "editado" tag + auditoria. Edicoes soh permitidas dentro de 15min da criacao (trg_document_comment_enforce_edit_window) exceto para admins (can_by_member manage_member). ADR-0016 D5.';

CREATE INDEX IF NOT EXISTS idx_document_comment_edits_comment
  ON public.document_comment_edits(comment_id, edited_at);
CREATE INDEX IF NOT EXISTS idx_document_comment_edits_editor
  ON public.document_comment_edits(edited_by);

-- ---------------------------------------------------------------------------
-- Unified trigger: edit window enforcement + history logging + updated_at
-- Subsumes prior trg_document_comments_set_updated_at (drops it below).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_document_comment_enforce_edit_window()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_is_admin boolean := false;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.body IS DISTINCT FROM OLD.body THEN
    SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();

    IF v_caller_member_id IS NOT NULL THEN
      v_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');
    END IF;

    -- Non-admins can only edit within 15min of creation.
    IF NOT v_is_admin AND (now() - OLD.created_at) > interval '15 minutes' THEN
      RAISE EXCEPTION 'Edit window expired: comments can only be edited within 15 minutes of posting (comment_id=%, age=%)',
        OLD.id, now() - OLD.created_at
        USING ERRCODE = 'check_violation';
    END IF;

    -- Log edit history (admin edits also logged for audit completeness).
    INSERT INTO public.document_comment_edits (comment_id, edited_by, previous_body, new_body)
    VALUES (OLD.id, COALESCE(v_caller_member_id, OLD.author_id), OLD.body, NEW.body);
  END IF;

  -- updated_at maintenance (subsumes old trg_document_comments_set_updated_at).
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_document_comments_set_updated_at ON public.document_comments;
DROP TRIGGER IF EXISTS trg_document_comment_enforce_edit_window ON public.document_comments;
CREATE TRIGGER trg_document_comment_enforce_edit_window
  BEFORE UPDATE ON public.document_comments
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_document_comment_enforce_edit_window();

-- ---------------------------------------------------------------------------
-- RLS: history visible to self (author or editor) + admin; inserts trigger-only.
-- ---------------------------------------------------------------------------
ALTER TABLE public.document_comment_edits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS document_comment_edits_read_scoped ON public.document_comment_edits;
CREATE POLICY document_comment_edits_read_scoped ON public.document_comment_edits
  FOR SELECT TO authenticated
  USING (
    edited_by IN (SELECT id FROM public.members WHERE auth_id = auth.uid())
    OR comment_id IN (
      SELECT id FROM public.document_comments WHERE author_id IN (
        SELECT id FROM public.members WHERE auth_id = auth.uid()
      )
    )
    OR EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
               AND public.can_by_member(m.id, 'manage_member'))
  );

-- Block direct INSERT; only trigger SECURITY DEFINER can write.
DROP POLICY IF EXISTS document_comment_edits_insert_none ON public.document_comment_edits;
CREATE POLICY document_comment_edits_insert_none ON public.document_comment_edits
  FOR INSERT TO authenticated
  WITH CHECK (false);

GRANT SELECT ON public.document_comment_edits TO authenticated;
REVOKE ALL ON public.document_comment_edits FROM anon;
