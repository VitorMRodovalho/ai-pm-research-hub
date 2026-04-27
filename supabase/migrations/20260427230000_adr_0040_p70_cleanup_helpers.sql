-- ADR-0040 p70 cleanup batch
-- Section A: DROP dead helper current_member_tier_rank (0 callers verified)
-- Section B: REVOKE-from-anon for 3 internal SECDEF helpers (defense-in-depth)
-- pg_policy precondition: zero RLS refs verified for all 4 fns.

-- Section A: DROP dead helper
DROP FUNCTION IF EXISTS public.current_member_tier_rank();

-- Section B: REVOKE-from-anon for internal helpers
REVOKE EXECUTE ON FUNCTION public._can_manage_event(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._can_sign_gate(uuid, uuid, text, text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.can_manage_comms_metrics() FROM PUBLIC, anon;

NOTIFY pgrst, 'reload schema';
