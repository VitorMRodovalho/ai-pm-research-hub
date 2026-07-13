-- #1364 — /admin/members and /admin/filiacao reconcile at a glance.
--
-- Root cause (grounded live 2026-07-13): there is NO chapter-code vocabulary drift. Every surface
-- uses the SAME bare 2-letter code (chapter_registry.chapter_code / members.entry_chapter_code /
-- member_chapter_affiliations.chapter_code are all 'RS', never 'BR-RS'). The reported divergence
-- (16 on /members vs 3 on /filiacao for PMI-RS) is two DIFFERENT populations, both correct:
--   * /admin/members = the full active roster, filtered by members.chapter ('PMI-RS').
--   * /admin/filiacao = a verification QUEUE — a strict subset of active members still needing
--     affiliation verification (pre-onboarding OR pmi_id_verified=false OR never verified).
-- So an already-verified member is correctly absent from the queue. Nothing counts wrong.
--
-- This RPC returns a per-chapter reconciliation so the FE can say, when a chapter filter is active,
-- "M active on /membros; N already verified (outside this queue)". Aggregate counts only — no PII,
-- so no log_pii_access (unlike the queue RPC). Same audience gate as the queue.

CREATE OR REPLACE FUNCTION public.get_affiliation_chapter_rollup()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_designations text[];
  v_result              jsonb;
BEGIN
  -- Same audience as get_affiliation_verification_queue: filiacao_director OR manage_member.
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;
  IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires filiacao_director designation or platform manager authority';
  END IF;

  -- Per members.chapter (the roster axis, = /admin/members): total active + how many fall in the
  -- verification-queue cohort. The in_queue predicate mirrors get_affiliation_verification_queue's
  -- cohort VERBATIM so the reconciliation never contradicts the queue itself.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'chapter', r.chapter,
    'total_active', r.total_active,
    'in_queue', r.in_queue,
    'verified_out', r.total_active - r.in_queue
  ) ORDER BY r.total_active DESC, r.chapter), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT m.chapter,
           count(*) AS total_active,
           count(*) FILTER (WHERE
             public.member_is_pre_onboarding(m.person_id, m.member_status)
             OR COALESCE(m.pmi_id_verified, false) = false
             OR NOT EXISTS (
               SELECT 1 FROM public.member_affiliation_verifications mv WHERE mv.member_id = m.id
             )
           ) AS in_queue
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.chapter IS NOT NULL
    GROUP BY m.chapter
  ) r;

  RETURN v_result;
END;
$function$;

-- Grants (defense in depth — internal gate already bars unauthorized callers).
REVOKE ALL ON FUNCTION public.get_affiliation_chapter_rollup() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_affiliation_chapter_rollup() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
