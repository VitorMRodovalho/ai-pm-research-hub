-- ============================================================================
-- p219 — BUG-218.A: auto-link new volunteer engagements to existing ciclo cert
-- ADR: ADR-0006 (Person + Engagement) / ADR-0007 (Authority)
--
-- Purpose:
--   sign_volunteer_agreement() (mig 20260415020000) links cert ← all current
--   volunteer engagements at SIGNING TIME. But when a NEW volunteer engagement
--   is created AFTER that signing, agreement_certificate_id is left NULL,
--   inflating the pending-agreements backlog (surfaced in p219 boot during
--   Vitor smoke: 2 of his 3 backlog rows were already covered by his existing
--   TERM-2026-7654C7 — just not linked).
--
--   This migration:
--   (1) Backfills existing orphan kind=volunteer engagements where the member
--       has an issued ciclo cert covering the engagement's start_year.
--   (2) Installs a BEFORE INSERT trigger that auto-links new volunteer
--       engagements to existing ciclo cert at creation time.
--
-- Scope: kind='volunteer' ONLY (per PM decision, p219).
--        study_group_owner / study_group_participant kinds also have
--        requires_agreement=true but no signing flow yet — handled separately.
--
-- Rollback:
--   DROP TRIGGER IF EXISTS trg_auto_link_volunteer_engagement_to_cycle_cert ON public.engagements;
--   DROP FUNCTION IF EXISTS public._trg_auto_link_volunteer_engagement_to_cycle_cert();
--   -- Backfill rollback NOTE: live affected rows persist; if rollback needed,
--   -- run targeted UPDATE setting agreement_certificate_id=NULL for the
--   -- specific engagement ids the backfill touched (captured in admin_audit_log
--   -- below). See P162 #150 for traceability.
-- ============================================================================

-- ════════════════════════════════════════════════════════════════════════
-- (1) BACKFILL: orphan kind=volunteer engagements where matching cert exists
-- ════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_affected int;
  v_affected_ids uuid[];
BEGIN
  WITH updated AS (
    UPDATE public.engagements e
    SET agreement_certificate_id = c.id
    FROM public.persons p, public.certificates c
    WHERE p.id = e.person_id
      AND c.member_id = p.legacy_member_id
      AND c.type = 'volunteer_agreement'
      AND c.status = 'issued'
      AND c.cycle = EXTRACT(YEAR FROM e.start_date)::int
      AND e.kind = 'volunteer'
      AND e.status = 'active'
      AND e.agreement_certificate_id IS NULL
    RETURNING e.id, e.person_id, c.id AS cert_id
  ),
  audit_insert AS (
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    SELECT
      NULL::uuid AS actor_id,
      'bug_218_a_backfill_volunteer_engagement_cert' AS action,
      'engagement' AS target_type,
      u.id AS target_id,
      jsonb_build_object(
        'engagement_id', u.id,
        'person_id', u.person_id,
        'cert_id_linked', u.cert_id,
        'migration', '20260803000003'
      )
    FROM updated u
    RETURNING target_id
  )
  SELECT count(*), array_agg(target_id) INTO v_affected, v_affected_ids FROM audit_insert;

  RAISE NOTICE 'BUG-218.A backfill: % engagements linked to ciclo cert. IDs: %', v_affected, v_affected_ids;
END$$;

-- ════════════════════════════════════════════════════════════════════════
-- (2) FORWARD-FIX trigger
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._trg_auto_link_volunteer_engagement_to_cycle_cert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_cert_id uuid;
  v_cycle int;
BEGIN
  -- only run when cert is not already linked
  IF NEW.agreement_certificate_id IS NOT NULL THEN RETURN NEW; END IF;

  -- only run for kind=volunteer + status=active
  IF NEW.kind <> 'volunteer' THEN RETURN NEW; END IF;
  IF NEW.status <> 'active' THEN RETURN NEW; END IF;

  -- resolve member_id from person_id
  SELECT legacy_member_id INTO v_member_id
  FROM public.persons WHERE id = NEW.person_id;
  IF v_member_id IS NULL THEN RETURN NEW; END IF;

  -- derive cycle from engagement start_date
  v_cycle := EXTRACT(YEAR FROM COALESCE(NEW.start_date, CURRENT_DATE))::int;

  -- look up issued ciclo cert (most recent if multiple — shouldn't happen given
  -- sign_volunteer_agreement() guard, but ORDER BY for safety)
  SELECT id INTO v_cert_id
  FROM public.certificates
  WHERE member_id = v_member_id
    AND type = 'volunteer_agreement'
    AND status = 'issued'
    AND cycle = v_cycle
  ORDER BY issued_at DESC LIMIT 1;

  IF v_cert_id IS NOT NULL THEN
    NEW.agreement_certificate_id := v_cert_id;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_auto_link_volunteer_engagement_to_cycle_cert ON public.engagements;

CREATE TRIGGER trg_auto_link_volunteer_engagement_to_cycle_cert
BEFORE INSERT ON public.engagements
FOR EACH ROW
EXECUTE FUNCTION public._trg_auto_link_volunteer_engagement_to_cycle_cert();

COMMENT ON FUNCTION public._trg_auto_link_volunteer_engagement_to_cycle_cert() IS
  'BUG-218.A (p219): auto-links new kind=volunteer engagements to existing ciclo volunteer_agreement cert when one exists for the member, preventing pending-agreement backlog inflation for engagements created after cert signing.';

-- ════════════════════════════════════════════════════════════════════════
-- SANITY check
-- ════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_orphan_count int;
BEGIN
  SELECT count(*) INTO v_orphan_count
  FROM public.engagements e
  JOIN public.persons p ON p.id = e.person_id
  JOIN public.certificates c ON c.member_id = p.legacy_member_id
    AND c.type = 'volunteer_agreement'
    AND c.status = 'issued'
    AND c.cycle = EXTRACT(YEAR FROM e.start_date)::int
  WHERE e.kind = 'volunteer'
    AND e.status = 'active'
    AND e.agreement_certificate_id IS NULL;

  IF v_orphan_count > 0 THEN
    RAISE EXCEPTION 'BUG-218.A sanity FAIL: % volunteer engagements still orphan despite matching ciclo cert. Backfill query failed.', v_orphan_count;
  END IF;
  RAISE NOTICE 'BUG-218.A sanity OK: 0 orphan volunteer engagements with matching ciclo cert.';
END$$;

NOTIFY pgrst, 'reload schema';
