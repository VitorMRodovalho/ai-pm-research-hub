-- p158 F1: dual_track candidate linking — backfill orphan pairs + auto-link trigger
--
-- Discovery (PM directive 2026-05-14): candidates submitting 2 separate VEP applications for
-- both researcher AND leader roles in the same cycle were treated as independent
-- (linked_application_id NULL, promotion_path NULL). p152 W4 OPP-152.7-lite (commit c91b5f1)
-- surfaced siblings in the PMI Profile tab but did not establish a persistent link.
--
-- PM ask 14/05: full linking so (a) sibling questionnaires merge in candidate view, (b) decisions
-- per-role are possible (approve as researcher, reject as leader), (c) IA sentiment sees both
-- essays. Audit at p158 boot found 2 orphan pairs needing backfill:
--   - William Junio (cycle4-2026, both submitted, scoring only on leader app)
--   - Rodolfo Santana — actually has 3 apps total. Apps 1+2 (leader converted + researcher
--     approved, both VEP 269580) are already linked via the legacy 'triaged_to_leader' path.
--     App 3 (leader rejected, VEP 269582, 36 days later) is a direct_leader resubmission, NOT a
--     dual_track sibling — backfill filter (a1.linked NULL AND a2.linked NULL) correctly skipped
--     it. Document as known false-positive of the broader orphan-detection query.
--
-- Schema additions:
--   - CHECK constraint extended: promotion_path now allows 'dual_track' alongside existing
--     'direct_researcher', 'direct_leader', 'triaged_to_leader'.
--   - linked_application_id mutual reciprocity established for dual_track pairs.
--
-- Trigger: BEFORE INSERT on selection_applications. When a new row arrives whose email+cycle
-- already has a sibling row with different role_applied AND NULL linked_application_id, links
-- both apps and sets promotion_path='dual_track' on both. Forward path: worker pmi-vep-sync
-- /ingest inserts → auto-link. The sibling NULL-linked filter ensures we don't re-link rows
-- that already participate in a different promotion path (triaged_to_leader or direct_*).
--
-- Existing 'triaged_to_leader' semantics PRESERVED — different path (researcher promoted to
-- leader post-evaluation, single decision lifecycle, programmatic creation with same VEP id).

-- 0) Extend promotion_path CHECK to allow 'dual_track'
ALTER TABLE public.selection_applications
  DROP CONSTRAINT IF EXISTS selection_applications_promotion_path_check;

ALTER TABLE public.selection_applications
  ADD CONSTRAINT selection_applications_promotion_path_check
  CHECK (promotion_path IS NULL OR promotion_path = ANY (ARRAY[
    'direct_researcher'::text,
    'direct_leader'::text,
    'triaged_to_leader'::text,
    'dual_track'::text
  ]));

-- 1) Backfill orphan pairs (same email + same cycle + diff role + BOTH linked NULL)
WITH orphan_pairs AS (
  SELECT
    a1.id AS app1_id,
    a2.id AS app2_id
  FROM selection_applications a1
  JOIN selection_applications a2
    ON lower(a1.email) = lower(a2.email)
   AND a1.cycle_id    = a2.cycle_id
   AND a1.id          < a2.id
   AND a1.role_applied <> a2.role_applied
  WHERE a1.linked_application_id IS NULL
    AND a2.linked_application_id IS NULL
)
UPDATE selection_applications a
SET    linked_application_id = CASE WHEN a.id = op.app1_id THEN op.app2_id ELSE op.app1_id END,
       promotion_path        = 'dual_track',
       updated_at            = now()
FROM   orphan_pairs op
WHERE  a.id IN (op.app1_id, op.app2_id);

-- 2) Trigger function for forward-going auto-link
CREATE OR REPLACE FUNCTION public._trg_auto_link_dual_track()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_sibling_id uuid;
BEGIN
  IF NEW.linked_application_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_sibling_id
  FROM public.selection_applications
  WHERE lower(email)        = lower(NEW.email)
    AND cycle_id            = NEW.cycle_id
    AND role_applied       <> NEW.role_applied
    AND linked_application_id IS NULL
  ORDER BY created_at
  LIMIT 1;

  IF v_sibling_id IS NULL THEN
    RETURN NEW;
  END IF;

  NEW.linked_application_id := v_sibling_id;
  NEW.promotion_path        := 'dual_track';

  UPDATE public.selection_applications
  SET    linked_application_id = NEW.id,
         promotion_path        = 'dual_track',
         updated_at            = now()
  WHERE  id = v_sibling_id;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public._trg_auto_link_dual_track() IS
  'BEFORE INSERT auto-link: when a candidate''s second VEP application arrives in the same cycle with a different role_applied and no existing link, sets linked_application_id mutual + promotion_path=dual_track on both rows. Sibling NULL-linked filter avoids re-linking rows already in triaged_to_leader or direct_* paths. p158 F1 (2026-05-14).';

DROP TRIGGER IF EXISTS trg_auto_link_dual_track ON public.selection_applications;
CREATE TRIGGER trg_auto_link_dual_track
BEFORE INSERT ON public.selection_applications
FOR EACH ROW
EXECUTE FUNCTION public._trg_auto_link_dual_track();

COMMENT ON TRIGGER trg_auto_link_dual_track ON public.selection_applications IS
  'Auto-link sibling applications at INSERT time (dual_track pattern). p158 F1.';

NOTIFY pgrst, 'reload schema';
