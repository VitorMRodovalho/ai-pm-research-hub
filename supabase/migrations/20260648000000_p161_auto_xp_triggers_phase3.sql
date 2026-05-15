-- p161 Fase 3 — 8 auto-XP triggers (Tier 2 production + Tier 3 curation)
-- Refs: docs/reference/SEMANTIC_TAXONOMY.md Q6 + Fase 1 (rules) + Fase 2 (champion RPCs)
-- PM ratification: 2026-05-15
-- Pattern: AFTER trigger → lookup gamification_rules (forward-only) → idempotent insert via (ref_id, category) check

-- ════════════════════════════════════════════════════════════
-- HELPER: shared XP grant function (DRY)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._grant_auto_xp(
  p_slug text,
  p_recipient_id uuid,
  p_ref_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_rule gamification_rules%ROWTYPE;
  v_org_id uuid;
BEGIN
  IF p_recipient_id IS NULL THEN
    RETURN;
  END IF;

  SELECT organization_id INTO v_org_id FROM members WHERE id = p_recipient_id;
  IF v_org_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_rule
  FROM gamification_rules
  WHERE slug = p_slug
    AND organization_id = v_org_id
    AND active = true
    AND effective_from <= now()
  ORDER BY effective_from DESC LIMIT 1;
  IF v_rule.slug IS NULL THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM gamification_points
    WHERE ref_id = p_ref_id AND category = p_slug AND member_id = p_recipient_id
  ) THEN
    RETURN;
  END IF;

  INSERT INTO gamification_points (member_id, points, reason, category, ref_id, organization_id)
  VALUES (p_recipient_id, v_rule.base_points, p_reason, v_rule.slug, p_ref_id, v_org_id);
END;
$function$;

COMMENT ON FUNCTION public._grant_auto_xp(text, uuid, uuid, text) IS
'Shared XP grant helper for Fase 3 triggers. Idempotent via (ref_id, category, member_id) check. Looks up forward-only active rule. Silent no-op if recipient/rule/org missing. NEVER raises — must not block source-table writes.';

-- ════════════════════════════════════════════════════════════
-- TIER 2 — Production output triggers (3)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_tribe_deliverable_completed_xp()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  IF (OLD.status IS DISTINCT FROM NEW.status)
     AND NEW.status = 'completed'
     AND OLD.status != 'completed' THEN
    PERFORM public._grant_auto_xp(
      'deliverable_completed',
      NEW.assigned_member_id,
      NEW.id,
      'Entregável concluído: ' || coalesce(substring(NEW.title FROM 1 FOR 80), '(sem título)')
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tribe_deliverable_completed_xp ON public.tribe_deliverables;
CREATE TRIGGER tribe_deliverable_completed_xp
  AFTER UPDATE OF status ON public.tribe_deliverables
  FOR EACH ROW EXECUTE FUNCTION public.trg_tribe_deliverable_completed_xp();

CREATE OR REPLACE FUNCTION public.trg_meeting_artifact_published_xp()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  IF OLD.is_published = false AND NEW.is_published = true THEN
    PERFORM public._grant_auto_xp(
      'artifact_published',
      NEW.created_by,
      NEW.id,
      'Ata rica publicada: ' || coalesce(substring(NEW.title FROM 1 FOR 80), '(sem título)')
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS meeting_artifact_published_xp ON public.meeting_artifacts;
CREATE TRIGGER meeting_artifact_published_xp
  AFTER UPDATE OF is_published ON public.meeting_artifacts
  FOR EACH ROW EXECUTE FUNCTION public.trg_meeting_artifact_published_xp();

CREATE OR REPLACE FUNCTION public.trg_meeting_action_resolved_xp()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  IF OLD.resolved_at IS NULL AND NEW.resolved_at IS NOT NULL THEN
    PERFORM public._grant_auto_xp(
      'action_resolved',
      NEW.assignee_id,
      NEW.id,
      'Ação da reunião resolvida: ' || coalesce(substring(NEW.description FROM 1 FOR 80), '(sem descrição)')
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS meeting_action_resolved_xp ON public.meeting_action_items;
CREATE TRIGGER meeting_action_resolved_xp
  AFTER UPDATE OF resolved_at ON public.meeting_action_items
  FOR EACH ROW EXECUTE FUNCTION public.trg_meeting_action_resolved_xp();

-- ════════════════════════════════════════════════════════════
-- TIER 3 — Curation triggers (5)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_doc_version_authored_xp()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  PERFORM public._grant_auto_xp(
    'curation_doc_authored',
    NEW.authored_by,
    NEW.id,
    'Versão de doc proposta — v' || coalesce(NEW.version_label, NEW.version_number::text, '?')
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS doc_version_authored_xp ON public.document_versions;
CREATE TRIGGER doc_version_authored_xp
  AFTER INSERT ON public.document_versions
  FOR EACH ROW EXECUTE FUNCTION public.trg_doc_version_authored_xp();

CREATE OR REPLACE FUNCTION public.trg_doc_version_locked_xp()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  IF OLD.locked_at IS NULL AND NEW.locked_at IS NOT NULL THEN
    PERFORM public._grant_auto_xp(
      'curation_doc_locked',
      NEW.locked_by,
      NEW.id,
      'Versão de doc travada — v' || coalesce(NEW.version_label, NEW.version_number::text, '?')
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS doc_version_locked_xp ON public.document_versions;
CREATE TRIGGER doc_version_locked_xp
  AFTER UPDATE OF locked_at ON public.document_versions
  FOR EACH ROW EXECUTE FUNCTION public.trg_doc_version_locked_xp();

CREATE OR REPLACE FUNCTION public.trg_doc_version_published_xp()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  IF OLD.published_at IS NULL AND NEW.published_at IS NOT NULL THEN
    PERFORM public._grant_auto_xp(
      'curation_doc_published',
      NEW.published_by,
      NEW.id,
      'Versão canônica publicada — v' || coalesce(NEW.version_label, NEW.version_number::text, '?')
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS doc_version_published_xp ON public.document_versions;
CREATE TRIGGER doc_version_published_xp
  AFTER UPDATE OF published_at ON public.document_versions
  FOR EACH ROW EXECUTE FUNCTION public.trg_doc_version_published_xp();

CREATE OR REPLACE FUNCTION public.trg_approval_signoff_xp()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  PERFORM public._grant_auto_xp(
    'curation_ratification',
    NEW.signer_id,
    NEW.id,
    'Ratificação assinada — gate ' || coalesce(NEW.gate_kind, '?')
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS approval_signoff_xp ON public.approval_signoffs;
CREATE TRIGGER approval_signoff_xp
  AFTER INSERT ON public.approval_signoffs
  FOR EACH ROW EXECUTE FUNCTION public.trg_approval_signoff_xp();

CREATE OR REPLACE FUNCTION public.trg_doc_comment_resolved_xp()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  IF OLD.resolved_at IS NULL AND NEW.resolved_at IS NOT NULL THEN
    PERFORM public._grant_auto_xp(
      'curation_comment_resolved',
      NEW.resolved_by,
      NEW.id,
      'Comentário resolvido em doc'
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS doc_comment_resolved_xp ON public.document_comments;
CREATE TRIGGER doc_comment_resolved_xp
  AFTER UPDATE OF resolved_at ON public.document_comments
  FOR EACH ROW EXECUTE FUNCTION public.trg_doc_comment_resolved_xp();

NOTIFY pgrst, 'reload schema';

-- ════════════════════════════════════════════════════════════
-- Rollback (in reverse order)
-- ════════════════════════════════════════════════════════════
-- DROP TRIGGER IF EXISTS doc_comment_resolved_xp ON public.document_comments;
-- DROP FUNCTION IF EXISTS public.trg_doc_comment_resolved_xp();
-- DROP TRIGGER IF EXISTS approval_signoff_xp ON public.approval_signoffs;
-- DROP FUNCTION IF EXISTS public.trg_approval_signoff_xp();
-- DROP TRIGGER IF EXISTS doc_version_published_xp ON public.document_versions;
-- DROP FUNCTION IF EXISTS public.trg_doc_version_published_xp();
-- DROP TRIGGER IF EXISTS doc_version_locked_xp ON public.document_versions;
-- DROP FUNCTION IF EXISTS public.trg_doc_version_locked_xp();
-- DROP TRIGGER IF EXISTS doc_version_authored_xp ON public.document_versions;
-- DROP FUNCTION IF EXISTS public.trg_doc_version_authored_xp();
-- DROP TRIGGER IF EXISTS meeting_action_resolved_xp ON public.meeting_action_items;
-- DROP FUNCTION IF EXISTS public.trg_meeting_action_resolved_xp();
-- DROP TRIGGER IF EXISTS meeting_artifact_published_xp ON public.meeting_artifacts;
-- DROP FUNCTION IF EXISTS public.trg_meeting_artifact_published_xp();
-- DROP TRIGGER IF EXISTS tribe_deliverable_completed_xp ON public.tribe_deliverables;
-- DROP FUNCTION IF EXISTS public.trg_tribe_deliverable_completed_xp();
-- DROP FUNCTION IF EXISTS public._grant_auto_xp(text, uuid, uuid, text);
