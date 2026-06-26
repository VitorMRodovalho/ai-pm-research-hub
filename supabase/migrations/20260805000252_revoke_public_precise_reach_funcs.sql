-- PR-3 (governance) — hardening + cross-ref fix for the precise-location reach functions.
-- (1) Align ACL of the 3 new reach funcs (mig ...251) to the REVOKE-PUBLIC pattern of the
--     existing reach funcs (country_reach, state_reach v1/v2 hardened in ...242). The 3 new
--     funcs were created with default PUBLIC EXECUTE (=X/postgres) — benign (SECDEF,
--     search_path='', aggregate/zero-direct-PII output) but inconsistent with the documented pattern.
-- (2) Fix the COMMENT cross-ref on members.allow_precise_location_in_public_map: it pointed to
--     "RoPA H.4", but H.4 is get_public_continent_reach (Art.7,IX, no consent); the flag is
--     documented in H.2 (state precise portion) + H.3 (precise country). Behavior-neutral.

REVOKE ALL ON FUNCTION public.get_public_state_reach_v3(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_state_reach_v3(integer) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_public_precise_country_reach() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_precise_country_reach() TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_public_continent_reach() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_continent_reach() TO anon, authenticated, service_role;

COMMENT ON COLUMN public.members.allow_precise_location_in_public_map IS
  'LGPD opt-in (Art. 7,I): authorizes displaying the member''s state (BR/US) or country (other supported countries) on the public map EVEN AT k=1 (sole member). Distinct from legacy allow_state_in_public_map (k>=3, "nunca individual"). Re-consent required; the two are never merged. RoPA H.2 (state precise portion) and H.3 (precise country).';
