-- #465 — close the anon member-name leak on the tribe-stats RPC family (LGPD; CLAUDE.md invariant #6:
-- anon/ghost gets nothing from PII; public data only via vetted get_public_* SECDEF RPCs).
--
-- get_tribe_stats(integer) is SECURITY DEFINER (owner postgres/bypassrls), has NO in-body auth gate,
-- AND is EXECUTE-able by anon (both via the PUBLIC default grant `=X` and a direct `anon=X` grant). So a
-- direct REST call with the public anon key — bypassing the tribe page's client-side canExploreTribes
-- gate (which already denies anon) — returns member NAMES in top_contributors[].name. This is the active
-- leak filed as #465 (confirmed live via SET ROLE anon by the PR4-C-clean adversarial review; pre-existing
-- since mig 068, NOT introduced by the #419 metric-4 work).
--
-- The only legitimate consumer (src/pages/tribe/[id].astro loadTribeStats) runs for an authenticated
-- ACTIVE platform member (canExploreTribes denies anon before the RPC is reached) → role=authenticated,
-- which KEEPS EXECUTE. The MCP surface is the separate, app-gated get_tribe_stats_ranked. So revoking the
-- anon/PUBLIC grant closes the direct-API leak with zero impact on legitimate callers.
--
-- IMPORTANT (functions default-grant EXECUTE to PUBLIC — same trap as the pg_default_acl view leak,
-- reference_pg_default_acl_anon_view_leak): REVOKE FROM anon alone is insufficient because anon also
-- inherits EXECUTE via PUBLIC. Revoke from BOTH PUBLIC and anon, then re-grant authenticated + service_role
-- (they hold their own direct grants independent of PUBLIC, so they are unaffected — the re-GRANT is
-- belt-and-suspenders).
--
-- exec_tribe_dashboard(integer, text): paired DEFENSE-IN-DEPTH. It is NOT leaking today (its body gates on
-- auth.uid + can_by_member → anon already gets "Not authenticated"), but it carries the same needless
-- anon/PUBLIC EXECUTE grant on a SECDEF that emits member names. Stripping it prevents the grant from
-- becoming an active leak if the in-body gate ever regresses. No behavioural change (anon was already
-- rejected; authenticated unaffected).
--
-- Rollback: GRANT EXECUTE ON FUNCTION public.get_tribe_stats(integer) TO PUBLIC;  (and likewise exec_tribe_dashboard)
-- Cross-ref: #465; CLAUDE.md key decision #6; METRIC_DISPARITY_AUDIT_2026-05-28 Bucket A (ungated SECDEF).

-- get_tribe_stats — the active leak
REVOKE EXECUTE ON FUNCTION public.get_tribe_stats(integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_tribe_stats(integer) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_tribe_stats(integer) TO authenticated, service_role;

-- exec_tribe_dashboard — defense-in-depth (already body-gated; strip the needless anon/PUBLIC grant)
REVOKE EXECUTE ON FUNCTION public.exec_tribe_dashboard(integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.exec_tribe_dashboard(integer, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.exec_tribe_dashboard(integer, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
