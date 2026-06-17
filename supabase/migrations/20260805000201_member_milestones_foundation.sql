-- PR 1 of #766 item 2/4 (server-side milestones framework).
-- See docs/specs/SPEC_766_SERVER_SIDE_MILESTONES.md.
-- Foundation: member_milestones (ADR-0013 Cat B domain lifecycle events; NOT
-- consolidated into admin_audit_log/notifications) + 3 RPCs + first milestone
-- onboarding_complete, replacing the client-side localStorage flag
-- nia_onboarding_celebrated in OnboardingChecklist.tsx (cross-device).
-- RLS: deny-all (mirrors onboarding_progress rpc_only_deny_all); all access via
-- SECURITY DEFINER RPCs gated by auth.uid(). PII: none (per-member own data).
-- Backfill is SILENT (acknowledged_at=now()) so existing all-complete members are
-- NOT re-celebrated. Race-safe: backfill runs BEFORE trigger creation (SPEC §6.3).
--
-- ROLLBACK:
--   DROP TRIGGER IF EXISTS trg_record_onboarding_complete_milestone ON public.onboarding_progress;
--   DROP FUNCTION IF EXISTS public._trg_record_onboarding_complete_milestone();
--   DROP FUNCTION IF EXISTS public.acknowledge_milestone(text);
--   DROP FUNCTION IF EXISTS public.get_my_milestones();
--   DROP FUNCTION IF EXISTS public.record_milestone(uuid, text, text, uuid, jsonb);
--   DROP TABLE IF EXISTS public.member_milestones CASCADE;
--   NOTIFY pgrst, 'reload schema';

-- 1. Table
CREATE TABLE IF NOT EXISTS public.member_milestones (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id       uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  milestone_key   text NOT NULL,
  occurred_at     timestamptz NOT NULL DEFAULT now(),
  source_type     text,
  source_id       uuid,
  metadata        jsonb NOT NULL DEFAULT '{}'::jsonb,
  acknowledged_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT member_milestones_key_chk CHECK (milestone_key IN
    ('onboarding_complete','term_signed','first_attendance','first_deliverable','promotion','profile_complete')),
  CONSTRAINT member_milestones_uq UNIQUE (member_id, milestone_key)
);

COMMENT ON TABLE public.member_milestones IS
  'ADR-0013 Cat B (domain lifecycle events). One row per (member, milestone), celebrated once. acknowledged_at NULL = celebration pending (replaces localStorage nia_onboarding_celebrated). See SPEC_766_SERVER_SIDE_MILESTONES.md.';
COMMENT ON COLUMN public.member_milestones.source_id IS
  'Informational reference WITHOUT FK (heterogeneous sources: certificate/attendance/onboarding/etc.); mirrors admin_audit_log.target_id.';
COMMENT ON COLUMN public.member_milestones.acknowledged_at IS
  'When the member dismissed/saw the celebration. NULL = pending. Not a cache column.';

CREATE INDEX IF NOT EXISTS idx_member_milestones_member ON public.member_milestones(member_id);

-- 2. RLS: deny-all; access only via SECURITY DEFINER RPCs below.
ALTER TABLE public.member_milestones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS member_milestones_rpc_only_deny_all ON public.member_milestones;
CREATE POLICY member_milestones_rpc_only_deny_all ON public.member_milestones
  FOR ALL USING (false);

-- 3. record_milestone — internal SECURITY DEFINER helper (idempotent). Not granted
--    to authenticated/anon; only triggers/other definer RPCs invoke it.
CREATE OR REPLACE FUNCTION public.record_milestone(
  p_member_id uuid, p_milestone_key text, p_source_type text DEFAULT NULL,
  p_source_id uuid DEFAULT NULL, p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  IF p_member_id IS NULL OR p_milestone_key IS NULL THEN RETURN; END IF;
  INSERT INTO public.member_milestones (member_id, milestone_key, source_type, source_id, metadata)
  VALUES (p_member_id, p_milestone_key, p_source_type, p_source_id, COALESCE(p_metadata, '{}'::jsonb))
  ON CONFLICT (member_id, milestone_key) DO NOTHING;
END; $fn$;
REVOKE ALL ON FUNCTION public.record_milestone(uuid, text, text, uuid, jsonb) FROM PUBLIC;

-- 4. get_my_milestones — canonical read for the FE celebration surface.
CREATE OR REPLACE FUNCTION public.get_my_milestones()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  SELECT jsonb_build_object(
    'pending', COALESCE((SELECT jsonb_agg(row_to_json(p) ORDER BY p.occurred_at)
       FROM (SELECT milestone_key, occurred_at, metadata FROM public.member_milestones
             WHERE member_id = v_member_id AND acknowledged_at IS NULL) p), '[]'::jsonb),
    'history', COALESCE((SELECT jsonb_agg(row_to_json(h) ORDER BY h.occurred_at DESC)
       FROM (SELECT milestone_key, occurred_at, acknowledged_at, metadata FROM public.member_milestones
             WHERE member_id = v_member_id AND acknowledged_at IS NOT NULL) h), '[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END; $fn$;
REVOKE ALL ON FUNCTION public.get_my_milestones() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_milestones() TO authenticated;

-- 5. acknowledge_milestone — sets acknowledged_at for the caller's own milestone.
CREATE OR REPLACE FUNCTION public.acknowledge_milestone(p_milestone_key text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_member_id uuid;
  v_rows int;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  UPDATE public.member_milestones
  SET acknowledged_at = now()
  WHERE member_id = v_member_id AND milestone_key = p_milestone_key AND acknowledged_at IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'milestone_key', p_milestone_key, 'acknowledged', v_rows > 0);
END; $fn$;
REVOKE ALL ON FUNCTION public.acknowledge_milestone(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_milestone(text) TO authenticated;

-- 6. Backfill onboarding_complete SILENTLY (acknowledged_at=now()) for members who are
--    ALREADY complete — they must NOT receive a retroactive celebration. Uses the
--    STRICT predicate (every required step seeded+terminal, except conditional
--    volunteer_term which non-agreement members legitimately lack) so it never
--    suppresses a member who is only partially done. MUST run BEFORE the trigger.
INSERT INTO public.member_milestones (member_id, milestone_key, occurred_at, source_type, acknowledged_at, metadata)
SELECT m.id, 'onboarding_complete', now(), 'onboarding_backfill', now(),
       jsonb_build_object('backfill', true, 'migration', '20260805000201')
FROM public.members m
WHERE EXISTS (SELECT 1 FROM public.onboarding_progress op WHERE op.member_id = m.id)
  AND NOT EXISTS (
    SELECT 1 FROM public.onboarding_steps s
    WHERE s.is_required
      AND (
        EXISTS (SELECT 1 FROM public.onboarding_progress op
                WHERE op.step_key = s.id AND op.member_id = m.id
                  AND op.status NOT IN ('completed', 'skipped'))
        OR (s.id <> 'volunteer_term'
            AND NOT EXISTS (SELECT 1 FROM public.onboarding_progress op
                            WHERE op.step_key = s.id AND op.member_id = m.id))
      )
  )
ON CONFLICT (member_id, milestone_key) DO NOTHING;

-- 7. onboarding_complete hook: trigger on onboarding_progress. Strict all-complete
--    check (no required step non-terminal; no required step missing a row except the
--    conditional volunteer_term). Fires only when the changed row is terminal.
CREATE OR REPLACE FUNCTION public._trg_record_onboarding_complete_milestone()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_all_complete boolean;
BEGIN
  IF NEW.member_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('completed', 'skipped') THEN RETURN NEW; END IF;
  SELECT NOT EXISTS (
    SELECT 1 FROM public.onboarding_steps s
    WHERE s.is_required
      AND (
        EXISTS (SELECT 1 FROM public.onboarding_progress op
                WHERE op.step_key = s.id AND op.member_id = NEW.member_id
                  AND op.status NOT IN ('completed', 'skipped'))
        OR (s.id <> 'volunteer_term'
            AND NOT EXISTS (SELECT 1 FROM public.onboarding_progress op
                            WHERE op.step_key = s.id AND op.member_id = NEW.member_id))
      )
  ) INTO v_all_complete;
  IF v_all_complete THEN
    PERFORM public.record_milestone(NEW.member_id, 'onboarding_complete', 'onboarding', NEW.id,
      jsonb_build_object('via', 'onboarding_progress_trigger'));
  END IF;
  RETURN NEW;
END; $fn$;

REVOKE ALL ON FUNCTION public._trg_record_onboarding_complete_milestone() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_record_onboarding_complete_milestone ON public.onboarding_progress;
CREATE TRIGGER trg_record_onboarding_complete_milestone
  AFTER INSERT OR UPDATE ON public.onboarding_progress
  FOR EACH ROW EXECUTE FUNCTION public._trg_record_onboarding_complete_milestone();

NOTIFY pgrst, 'reload schema';
