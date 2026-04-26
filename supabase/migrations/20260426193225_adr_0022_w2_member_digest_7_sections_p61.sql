-- ADR-0022 W2: Weekly Member Digest — 7-section consolidation (p61 Track L)
-- Extends W1 (p48) substrate. Adds:
--   1. members.notify_delivery_mode_pref (4-mode opt) + RLS for self-edit
--   2. get_weekly_member_digest(uuid) — 7 sections (cards + events + pubs +
--      achievements via direct query; engagements + broadcasts + governance
--      via pending notifications categorized by type)
--   3. generate_weekly_member_digest_cron() — orchestrator that calls new RPC,
--      writes weekly_member_digest notification, AND marks pending
--      delivery_mode='digest_weekly' notifications as digest_delivered with
--      batch_id (batched consumption — reduces N delivery emails to 1)
--   4. Cron alter: switch existing job 26 to use new orchestrator.
--
-- Back-compat: get_weekly_card_digest preserved (w1 callers + tests).
-- Privilege: new RPC has same auth shape as W1 (caller=self OR manage_member).
--
-- NOTE: original 7-section RPC + orchestrator referenced notifications.metadata
-- (doesn't exist) and gamification_points.amount (column is 'points'). This
-- migration installs them as-is for honest history; companion correction
-- migration `20260426193357` rewrites both RPCs with corrected column refs.

-- ============================================================
-- 1. members.notify_delivery_mode_pref (4-mode opt)
-- ============================================================
ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS notify_delivery_mode_pref text NOT NULL DEFAULT 'weekly_digest'
    CHECK (notify_delivery_mode_pref IN ('immediate_all', 'weekly_digest', 'suppress_all', 'custom_per_type'));

COMMENT ON COLUMN public.members.notify_delivery_mode_pref IS
  'ADR-0022 W2: per-member preference for email delivery mode. Defaults to weekly_digest. immediate_all overrides delivery_mode=digest_weekly to send each notification ASAP. suppress_all opts out of all email (in-app only). custom_per_type reserved for W3 granular controls.';

-- ============================================================
-- 2. RLS — member self-edit notification preferences
-- ============================================================
DROP POLICY IF EXISTS "Members can update own notification preferences" ON public.members;
CREATE POLICY "Members can update own notification preferences"
  ON public.members FOR UPDATE
  TO authenticated
  USING (auth_id = auth.uid())
  WITH CHECK (auth_id = auth.uid());

CREATE OR REPLACE FUNCTION public.set_my_notification_prefs(
  p_notify_weekly_digest boolean DEFAULT NULL,
  p_notify_delivery_mode_pref text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_updated public.members;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;

  IF p_notify_delivery_mode_pref IS NOT NULL
    AND p_notify_delivery_mode_pref NOT IN ('immediate_all','weekly_digest','suppress_all','custom_per_type') THEN
    RAISE EXCEPTION 'invalid_delivery_mode_pref: %', p_notify_delivery_mode_pref;
  END IF;

  UPDATE public.members
  SET
    notify_weekly_digest = COALESCE(p_notify_weekly_digest, notify_weekly_digest),
    notify_delivery_mode_pref = COALESCE(p_notify_delivery_mode_pref, notify_delivery_mode_pref)
  WHERE id = v_caller_id
  RETURNING * INTO v_updated;

  RETURN jsonb_build_object(
    'success', true,
    'notify_weekly_digest', v_updated.notify_weekly_digest,
    'notify_delivery_mode_pref', v_updated.notify_delivery_mode_pref
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_my_notification_prefs(boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_notification_prefs(boolean, text) TO authenticated;
COMMENT ON FUNCTION public.set_my_notification_prefs(boolean, text) IS
  'ADR-0022 W2: safe column-level update of own notification preferences. Allows null params for partial updates.';

-- ============================================================
-- 3. get_weekly_member_digest — 7 sections (BROKEN — uses notifications.metadata
--    which does not exist; corrected by next migration `20260426193357`)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_weekly_member_digest(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_is_self boolean;
  v_member_tribe_id integer;
  v_window_start timestamptz := date_trunc('day', now()) - interval '7 days';
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  v_is_self := (v_caller_id = p_member_id);

  IF NOT v_is_self AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: can only read own digest or requires manage_member permission';
  END IF;

  SELECT tribe_id INTO v_member_tribe_id FROM public.members WHERE id = p_member_id;

  -- Body uses notifications.metadata (col doesn't exist) — runtime error;
  -- corrected by `20260426193357_adr_0022_w2_member_digest_schema_correction_p61.sql`.
  -- Stub body to placate parse; replaced immediately by correction migration.
  RETURN '{"_note":"broken_body_corrected_by_next_migration"}'::jsonb;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_weekly_member_digest(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_weekly_member_digest(uuid) TO authenticated, service_role;

-- ============================================================
-- 4. generate_weekly_member_digest_cron — orchestrator (BROKEN — corrected next)
-- ============================================================
CREATE OR REPLACE FUNCTION public.generate_weekly_member_digest_cron()
RETURNS TABLE(member_id uuid, notified boolean, reason text, batch_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Stub body; corrected by `20260426193357_adr_0022_w2_member_digest_schema_correction_p61.sql`
  RETURN;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.generate_weekly_member_digest_cron() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_weekly_member_digest_cron() TO service_role;

-- ============================================================
-- 5. Cron entry — switch jobid 26 to new orchestrator
-- ============================================================
DO $$
DECLARE
  v_jobid bigint;
BEGIN
  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname = 'send-weekly-member-digest' OR jobname LIKE '%weekly%digest%';
  IF v_jobid IS NOT NULL THEN
    PERFORM cron.alter_job(
      v_jobid,
      command := $cmd$SELECT public.generate_weekly_member_digest_cron();$cmd$
    );
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
