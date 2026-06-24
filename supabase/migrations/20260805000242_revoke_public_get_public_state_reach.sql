-- World map follow-up: tighten the legacy get_public_state_reach() ACL to match the v2 pattern.
-- Grounded 2026-06-23: the legacy fn was the ONLY of the 3 public-reach RPCs still exposed to
-- PUBLIC (proacl leading {=X/postgres}), while get_public_state_reach_v2(integer) and
-- get_public_country_reach are already anon/authenticated/service_role only. Benign (zero-PII
-- k>=5 aggregate) but inconsistent with the v2 REVOKE-PUBLIC + explicit-GRANT pattern; this
-- removes the implicit PUBLIC EXECUTE grant. No behavior change for the three legitimate roles,
-- which keep their explicit grants.
REVOKE ALL ON FUNCTION public.get_public_state_reach() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_state_reach() TO anon, authenticated, service_role;
