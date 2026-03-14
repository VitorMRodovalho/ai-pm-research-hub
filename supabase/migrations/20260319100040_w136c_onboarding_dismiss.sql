-- W136c: Persist onboarding welcome popup dismiss state
-- Previously used sessionStorage (reset on tab close), now persisted in DB

ALTER TABLE members ADD COLUMN IF NOT EXISTS onboarding_dismissed_at timestamptz;

-- Dismiss for all existing active members (they've already seen the popup)
UPDATE members SET onboarding_dismissed_at = now() WHERE is_active = true;

-- RPC to dismiss the onboarding popup for the current user
CREATE OR REPLACE FUNCTION dismiss_onboarding()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;
  UPDATE members SET onboarding_dismissed_at = now() WHERE id = v_member_id;
END;
$$;

GRANT EXECUTE ON FUNCTION dismiss_onboarding() TO authenticated;
