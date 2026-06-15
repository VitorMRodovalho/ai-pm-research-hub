-- #693 defect 1 — honor HARD terminal VEP status in the selection funnel.
--
-- A candidate whose VEP application reached a hard terminal decision
-- (OfferNotExtended / Declined / Withdrawn / Expired / OfferExpired / Removed)
-- must NOT remain in an active selection_applications.status (screening …
-- final_eval / submitted). The worker re-import path is fixed at source
-- (cloudflare-workers/pmi-vep-sync/src/db.ts resolveReimportStatus, #693), but
-- (a) imports are manual/occasional, so rows that already drifted stay wrong
-- until the next sync, and (b) we want a systematic, idempotent reconciler the
-- weekly heal can call — NOT a one-off UPDATE on a single row (which the import
-- would re-collapse; see issue #693 recommendation 4).
--
-- This function is the canonical heal. It is SYMMETRIC-SAFE with
-- recompute_application_status (migration 20260805000090): that function never
-- moves a row INTO a terminal status and its main loop excludes rows whose
-- current status is already terminal (`WHERE cur NOT IN (...)`), so once this
-- reconciler sets 'rejected' / 'withdrawn' the heal-cron leaves it frozen — the
-- two never fight.
--
-- Mapping (mirrors the worker mapper's `rejected` bucket logic in
-- script-mapper.ts mapBucketAndStatusToNucleo):
--   withdrawn / removed                                   → 'withdrawn'
--   offernotextended / declined / expired / offerexpired  → 'rejected'
-- Only NON-terminal (active / in-flight) rows are healed; a row already at a
-- platform terminal status (approved/rejected/converted/withdrawn/cancelled/
-- waitlist/interview_noshow) is left untouched — the platform's own decision
-- stands (same invariant as resolveReimportStatus' terminal-safe guard).
--
-- ROLLBACK: DROP FUNCTION public.reconcile_vep_terminal_status(uuid, boolean);

CREATE OR REPLACE FUNCTION public.reconcile_vep_terminal_status(
  p_application_id uuid DEFAULT NULL::uuid,
  p_dry_run boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_changes jsonb := '[]'::jsonb;
  v_changed int := 0;
  v_evaluated int := 0;
  v_rec record;
  v_target text;
BEGIN
  -- Auth: authenticated callers need manage_platform. A no-JWT context
  -- (pg_cron / service_role) is the self-healing path and is allowed; anon is
  -- blocked by the GRANT ladder below, not by reaching here.
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: manage_platform required';
    END IF;
  END IF;

  FOR v_rec IN
    SELECT a.id, a.applicant_name, a.cycle_id, a.status AS cur, a.vep_status_raw,
           CASE
             WHEN lower(a.vep_status_raw) IN ('withdrawn','removed') THEN 'withdrawn'
             ELSE 'rejected'
           END AS target
    FROM public.selection_applications a
    WHERE a.vep_status_raw IS NOT NULL
      AND lower(a.vep_status_raw) IN
          ('offernotextended','declined','withdrawn','expired','offerexpired','removed')
      -- only heal ACTIVE / in-flight rows — never re-decide a platform-terminal one
      AND a.status NOT IN
          ('approved','rejected','converted','withdrawn','cancelled','waitlist','interview_noshow')
      AND (p_application_id IS NULL OR a.id = p_application_id)
  LOOP
    v_target := v_rec.target;
    v_changed := v_changed + 1;
    v_changes := v_changes || jsonb_build_object(
      'application_id',  v_rec.id,
      'applicant_name',  v_rec.applicant_name,
      'cycle_id',        v_rec.cycle_id,
      'vep_status_raw',  v_rec.vep_status_raw,
      'from',            v_rec.cur,
      'to',              v_target
    );

    IF NOT p_dry_run THEN
      UPDATE public.selection_applications
         SET status = v_target, updated_at = now()
       WHERE id = v_rec.id
         AND status = v_rec.cur;   -- snapshot guard: skip if changed concurrently

      IF FOUND THEN
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_caller_id,
          'selection.vep_terminal_reconciled',
          'selection_application',
          v_rec.id,
          jsonb_build_object('status', jsonb_build_object('from', v_rec.cur, 'to', v_target)),
          jsonb_build_object(
            'source',          'reconcile_vep_terminal_status',
            'cycle_id',        v_rec.cycle_id,
            'vep_status_raw',  v_rec.vep_status_raw
          )
        );
      END IF;
    END IF;
  END LOOP;

  SELECT count(*) INTO v_evaluated
  FROM public.selection_applications a
  WHERE a.vep_status_raw IS NOT NULL
    AND lower(a.vep_status_raw) IN
        ('offernotextended','declined','withdrawn','expired','offerexpired','removed')
    AND (p_application_id IS NULL OR a.id = p_application_id);

  RETURN jsonb_build_object(
    'success',   true,
    'dry_run',   p_dry_run,
    'evaluated', v_evaluated,
    'changed',   v_changed,
    'changes',   v_changes
  );
END;
$function$;

-- GRANT ladder: authenticated callers gated inside the body (manage_platform);
-- anon must never reach it. service_role / pg_cron run as table owner (no JWT).
REVOKE ALL ON FUNCTION public.reconcile_vep_terminal_status(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reconcile_vep_terminal_status(uuid, boolean) TO authenticated, service_role;

COMMENT ON FUNCTION public.reconcile_vep_terminal_status(uuid, boolean) IS
  '#693 — idempotent heal: sets selection_applications.status to a terminal '
  '(rejected/withdrawn) for any ACTIVE row whose vep_status_raw is a hard '
  'terminal VEP decision. Symmetric-safe with recompute_application_status '
  '(20260805000090). Dry-run supported. manage_platform-gated; cron/service bypass.';

-- ── Wire the reconciler into the existing daily selection heal ────────────────
-- #693 recommendation 3 ("travar a recorrência"): the worker fix prevents the
-- drift at import time, but a daily self-heal makes the anti-recurrence posture
-- automatic (and matches how selection status already self-heals every day —
-- cron `selection-status-recompute-daily` → _selection_status_recompute_cron).
-- We run the terminal reconcile FIRST so a just-terminalized row is excluded
-- from the in-flight recompute below (which skips terminal `cur`). The cron's
-- RETURN shape is intentionally UNCHANGED (still the recompute result) — the
-- reconcile is self-audited in admin_audit_log, and downstream tests/callers
-- read the recompute shape. Body kept byte-identical to the live function with
-- only the single PERFORM line + comment added (ROLLBACK: re-apply the prior
-- body without the reconcile PERFORM).
CREATE OR REPLACE FUNCTION public._selection_status_recompute_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
  v_changed int;
  v_affected_cycles uuid[];
  v_lead record;
BEGIN
  -- #693 — honor HARD terminal VEP decisions first (pull declined/withdrawn/
  -- expired apps out of the active funnel) so the in-flight recompute below
  -- never re-evaluates a row VEP has already terminated. Idempotent; self-audited.
  PERFORM public.reconcile_vep_terminal_status(NULL, false);

  -- apply mode over every cycle; forward-only + terminal-safe + audited inside.
  v_result := public.recompute_application_status(NULL, NULL, false);
  v_changed := COALESCE((v_result->>'changed')::int, 0);

  IF v_changed > 0 THEN
    SELECT array_agg(DISTINCT (c->>'cycle_id')::uuid) INTO v_affected_cycles
    FROM jsonb_array_elements(v_result->'changes') AS c;

    -- alert each lead of an affected cycle: a clobber recurred (root fix = #472 corr.#2)
    FOR v_lead IN
      SELECT DISTINCT sc.member_id
      FROM public.selection_committee sc
      WHERE sc.cycle_id = ANY(v_affected_cycles)
        AND sc.role = 'lead'
        AND sc.member_id IS NOT NULL
    LOOP
      PERFORM public.create_notification(
        v_lead.member_id,
        'selection_status_auto_healed',
        'Status de candidatos corrigido automaticamente',
        v_changed || ' candidato(s) tiveram o status recomputado a partir das avaliações/entrevistas '
          || '(possível clobber de re-import VEP — ver #472). Revise em /admin/selection.',
        '/admin/selection',
        'selection_cycle',
        v_affected_cycles[1]
      );
    END LOOP;
  END IF;

  RETURN v_result;
END;
$function$;
