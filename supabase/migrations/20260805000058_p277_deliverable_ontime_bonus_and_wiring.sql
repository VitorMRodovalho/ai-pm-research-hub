-- p277 — Deliverable/artifact/action on-time BONUS + trigger wiring fix
-- (gamification rule-wiring probe, PM-chosen policy = on-time BONUS).
--
-- WHAT: The auto_trigger XP rules (deliverable_completed/30, artifact_published/15,
--   action_resolved/5) existed and were wired, but (1) had NO on-time/deadline semantics at all,
--   and (2) were dormant — the triggers fired only on AFTER UPDATE OF <col> (no INSERT coverage),
--   so items bulk-INSERTed in their final state, or completed before the rules' effective_from,
--   never paid out (1 award row total, ever; 24+ legitimately-completed items at 0 XP).
--
--   PM policy = ON-TIME BONUS (base always on completion; an extra bonus when completed by the
--   due_date; NO penalty for late — appropriate for volunteer work). This migration:
--     1. gamification_rules.on_time_bonus_points (config) — deliverable_completed +10,
--        action_resolved +2. Artifacts have no due_date → no bonus (base only).
--     2. tribe_deliverables.completed_at (audit; set by the trigger on completion).
--     3. _grant_auto_xp gains an optional p_on_time arg: awards base + on_time_bonus_points when
--        p_on_time IS TRUE and the rule configures a bonus. (DROP+CREATE adds the param; the
--        DEFAULT NULL keeps any 4-arg caller working = base only.)
--     4. The 3 trigger functions: fire on INSERT OR UPDATE (cover insert-already-final), compute
--        on-time vs due_date, and the action trigger falls back assignee_id→resolved_by→created_by
--        (3/4 resolved actions had NULL assignee and silently earned nothing).
--     5. Idempotent backfill of the 24+ orphaned completed/published/resolved items — BASE ONLY
--        (historical on-time is unreconstructible; tribe_deliverables had no completed_at), tagged
--        '(backfill p277)' in the reason. The _grant_auto_xp idempotency guard makes re-runs safe.
--
-- WHY: implements the "entrega no prazo é gamificada" business rule the PM described (it was never
--   actually built with on-time semantics) and lights up the dormant base award.
--
-- ROLLBACK: re-CREATE the prior 4-arg _grant_auto_xp + the 3 trigger fns (AFTER UPDATE OF <col>,
--   no on-time); DROP the 2 new columns; re-attach the AFTER UPDATE-only triggers. Backfilled
--   gamification_points rows would need manual cleanup by ref_id+category if a full revert is wanted.
--
-- NOTE: bonus values (10 / 2) are config in gamification_rules.on_time_bonus_points — tune freely
--   without code. The deeper canonical-metrics convergence (champions source, etc.) stays in #419.

-- ── 1. config + audit columns ───────────────────────────────────────────────
ALTER TABLE public.gamification_rules ADD COLUMN IF NOT EXISTS on_time_bonus_points integer;
ALTER TABLE public.tribe_deliverables  ADD COLUMN IF NOT EXISTS completed_at timestamptz;

COMMENT ON COLUMN public.gamification_rules.on_time_bonus_points IS
  'p277: extra points added to base_points when the work is completed by its due_date (on-time bonus policy). NULL = no on-time bonus (e.g. artifacts have no deadline).';
COMMENT ON COLUMN public.tribe_deliverables.completed_at IS
  'p277: timestamp the deliverable reached status=completed (set by trg_tribe_deliverable_completed_xp). Enables on-time audit.';

UPDATE public.gamification_rules SET on_time_bonus_points = 10 WHERE slug = 'deliverable_completed' AND on_time_bonus_points IS NULL;
UPDATE public.gamification_rules SET on_time_bonus_points = 2  WHERE slug = 'action_resolved'      AND on_time_bonus_points IS NULL;

-- ── 2. _grant_auto_xp: base + optional on-time bonus ────────────────────────
DROP FUNCTION IF EXISTS public._grant_auto_xp(text, uuid, uuid, text);
CREATE OR REPLACE FUNCTION public._grant_auto_xp(p_slug text, p_recipient_id uuid, p_ref_id uuid, p_reason text, p_on_time boolean DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_rule gamification_rules%ROWTYPE;
  v_org_id uuid;
  v_points int;
  v_reason text;
BEGIN
  IF p_recipient_id IS NULL THEN
    RETURN; -- silently skip if no recipient (NULL assignee/author)
  END IF;

  SELECT organization_id INTO v_org_id FROM members WHERE id = p_recipient_id;
  IF v_org_id IS NULL THEN
    RETURN; -- recipient member not found
  END IF;

  SELECT * INTO v_rule
  FROM gamification_rules
  WHERE slug = p_slug
    AND organization_id = v_org_id
    AND active = true
    AND effective_from <= now()
  ORDER BY effective_from DESC LIMIT 1;
  IF v_rule.slug IS NULL THEN
    RETURN; -- rule disabled or missing
  END IF;

  -- Idempotency: skip if already paid for this ref_id + category
  IF EXISTS (
    SELECT 1 FROM gamification_points
    WHERE ref_id = p_ref_id AND category = p_slug AND member_id = p_recipient_id
  ) THEN
    RETURN;
  END IF;

  -- On-time BONUS policy: base always; add on_time_bonus_points only when the caller asserts
  -- on-time (p_on_time IS TRUE) AND the rule configures a bonus. NULL/false → base only (no penalty).
  v_points := v_rule.base_points;
  v_reason := p_reason;
  IF p_on_time IS TRUE AND COALESCE(v_rule.on_time_bonus_points, 0) > 0 THEN
    v_points := v_points + v_rule.on_time_bonus_points;
    v_reason := p_reason || ' (no prazo +' || v_rule.on_time_bonus_points || ')';
  END IF;

  INSERT INTO gamification_points (member_id, points, reason, category, ref_id, organization_id)
  VALUES (p_recipient_id, v_points, v_reason, v_rule.slug, p_ref_id, v_org_id);
END;
$function$;

-- ── 3. trigger functions: INSERT OR UPDATE coverage + on-time + assignee fallback ──
CREATE OR REPLACE FUNCTION public.trg_tribe_deliverable_completed_xp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_on_time boolean;
BEGIN
  -- fire when the row IS completed and just became so (INSERT-already-completed OR UPDATE-into-completed)
  IF NEW.status = 'completed'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'completed') THEN
    -- on-time only meaningful with a deadline; NULL due_date → NULL (base only, no bonus)
    v_on_time := CASE WHEN NEW.due_date IS NULL THEN NULL ELSE (CURRENT_DATE <= NEW.due_date) END;
    PERFORM public._grant_auto_xp(
      'deliverable_completed',
      NEW.assigned_member_id,
      NEW.id,
      'Entregável concluído: ' || coalesce(substring(NEW.title FROM 1 FOR 80), '(sem título)'),
      v_on_time
    );
    -- persist completed_at for audit (UPDATE OF completed_at does NOT re-fire this OF status trigger)
    IF NEW.completed_at IS NULL THEN
      UPDATE public.tribe_deliverables SET completed_at = now() WHERE id = NEW.id AND completed_at IS NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_meeting_artifact_published_xp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- artifacts have no due_date → base only (p_on_time omitted → NULL → no bonus)
  IF NEW.is_published = true
     AND (TG_OP = 'INSERT' OR OLD.is_published IS DISTINCT FROM true) THEN
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

CREATE OR REPLACE FUNCTION public.trg_meeting_action_resolved_xp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_recipient uuid;
  v_on_time boolean;
BEGIN
  IF NEW.resolved_at IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.resolved_at IS NULL) THEN
    -- "tied to a person": prefer the assignee, fall back to who resolved / created it
    v_recipient := COALESCE(NEW.assignee_id, NEW.resolved_by, NEW.created_by);
    v_on_time := CASE WHEN NEW.due_date IS NULL THEN NULL ELSE (NEW.resolved_at::date <= NEW.due_date) END;
    PERFORM public._grant_auto_xp(
      'action_resolved',
      v_recipient,
      NEW.id,
      'Ação da reunião resolvida: ' || coalesce(substring(NEW.description FROM 1 FOR 80), '(sem descrição)'),
      v_on_time
    );
  END IF;
  RETURN NEW;
END;
$function$;

-- ── 4. re-attach triggers with INSERT OR UPDATE coverage ────────────────────
DROP TRIGGER IF EXISTS tribe_deliverable_completed_xp ON public.tribe_deliverables;
CREATE TRIGGER tribe_deliverable_completed_xp
  AFTER INSERT OR UPDATE OF status ON public.tribe_deliverables
  FOR EACH ROW EXECUTE FUNCTION public.trg_tribe_deliverable_completed_xp();

DROP TRIGGER IF EXISTS meeting_artifact_published_xp ON public.meeting_artifacts;
CREATE TRIGGER meeting_artifact_published_xp
  AFTER INSERT OR UPDATE OF is_published ON public.meeting_artifacts
  FOR EACH ROW EXECUTE FUNCTION public.trg_meeting_artifact_published_xp();

DROP TRIGGER IF EXISTS meeting_action_resolved_xp ON public.meeting_action_items;
CREATE TRIGGER meeting_action_resolved_xp
  AFTER INSERT OR UPDATE OF resolved_at ON public.meeting_action_items
  FOR EACH ROW EXECUTE FUNCTION public.trg_meeting_action_resolved_xp();

-- ── 5. idempotent backfill (BASE ONLY — historical on-time unreconstructible) ──
DO $backfill$
DECLARE r record;
BEGIN
  FOR r IN SELECT id, created_by, title FROM public.meeting_artifacts
           WHERE is_published = true AND created_by IS NOT NULL LOOP
    PERFORM public._grant_auto_xp('artifact_published', r.created_by, r.id,
      'Ata rica publicada (backfill p277): ' || coalesce(substring(r.title FROM 1 FOR 80), ''));
  END LOOP;

  FOR r IN SELECT id, assigned_member_id, title FROM public.tribe_deliverables
           WHERE status = 'completed' AND assigned_member_id IS NOT NULL LOOP
    PERFORM public._grant_auto_xp('deliverable_completed', r.assigned_member_id, r.id,
      'Entregável concluído (backfill p277, on-time não reconstruível): ' || coalesce(substring(r.title FROM 1 FOR 80), ''));
  END LOOP;

  FOR r IN SELECT id, COALESCE(assignee_id, resolved_by, created_by) AS rcpt, description
           FROM public.meeting_action_items WHERE resolved_at IS NOT NULL LOOP
    PERFORM public._grant_auto_xp('action_resolved', r.rcpt, r.id,
      'Ação resolvida (backfill p277): ' || coalesce(substring(r.description FROM 1 FOR 80), ''));
  END LOOP;
END
$backfill$;

NOTIFY pgrst, 'reload schema';
