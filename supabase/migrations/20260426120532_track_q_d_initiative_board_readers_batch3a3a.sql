-- Track Q-D — initiative/board readers hardening (batch 3a.3a, atomic REVOKE-only)
--
-- Discovery (p58) of the "initiative/board readers" Q-D bucket surfaced
-- 23 candidates (audit doc estimated 13). Per-fn callsite analysis split
-- into:
--
-- - 3a.3a (this batch): 4 fns truly dead (zero src/EF/tests callers) or
--   internal-only (called only from another SECDEF fn). REVOKE-only;
--   no body changes. Safe atomic.
-- - 3a.3b (next batch, PM ratify needed): 18 fns are member-tier
--   readers (initiative pages, board components, profile, etc.).
--   Treatment: REVOKE FROM PUBLIC + anon, KEEP authenticated. Per-page
--   tier verification needed before applying.
-- - Excluded: get_initiative_member_contacts already V4-gated with
--   can(person_id, 'view_pii', 'initiative') + log_pii_access_batch.
--   Discovered during 3a.3 triage; properly compliant. Documented in
--   audit doc as reference compliant pattern.
--
-- Batch 3a.3a — 4 fns REVOKE-only:
--
-- (a) Dead-code (3 fns; no callers in src/, supabase/functions/, tests/):
-- - get_board_timeline(p_board_id uuid) — board timeline reader. Body
--   uses members.tribe_id (legacy column path; ADR-0015 Phase 5 backlog).
--   Currently live in pg_proc but unreachable from any caller (no
--   .rpc('get_board_timeline'...) anywhere; only typed in
--   src/lib/database.gen.ts which is auto-generated from pg_proc).
-- - get_initiative_board_summary(p_initiative_id uuid) — count-by-status
--   summary for initiative's board. Zero callers.
-- - list_initiative_meeting_artifacts(p_limit, p_initiative_id) — meeting
--   artifacts filtered by initiative. Zero callers (initiative pages use
--   list_meeting_artifacts which is initiative-id-aware via
--   resolve_tribe_id; this fn was redundant from day 1).
--
-- (b) Internal helper (1 fn; only called via SECDEF chain):
-- - search_board_items(p_query, p_tribe_id) — board search. Only callsite
--   is public.search_initiative_board_items (also SECDEF, postgres-owned).
--   REVOKE from PUBLIC/anon/authenticated; SECDEF chain preserves access
--   via postgres role (search_initiative_board_items runs as definer
--   when called by authenticated user → can call REVOKE'd fn through
--   superuser implicit privileges).
--
-- All 4 fns retain bodies unchanged. ACL is the only delta. Post-state:
-- only postgres + service_role have EXECUTE.
--
-- Risk: zero. No frontend or EF callsite is broken. Static analysis
-- contract test (tests/contracts/initiative-primitive.test.mjs) verifies
-- the original GRANT in v4_phase2 migration file — REVOKE in this NEW
-- file is independent and doesn't affect the static migration content
-- check.

REVOKE EXECUTE ON FUNCTION public.get_board_timeline(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_initiative_board_summary(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.list_initiative_meeting_artifacts(integer, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.search_board_items(text, integer) FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
