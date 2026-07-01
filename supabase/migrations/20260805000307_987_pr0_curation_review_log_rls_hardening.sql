-- =====================================================================
-- #308-PR0 (#987) — curation_review_log RLS deny-all + REVOKE anon
--                   get_all_certificates + denormalize initiative_id
--
-- Parent: #308 (planning) · Spec: docs/specs/SPEC_308_CURATOR_EVIDENCE_BUNDLES.md
-- ADR-0119. Behavior-neutral hardening — the smallest immediately-valuable
-- slice of #308. Three items, all re-grounded live this turn against prod
-- (project ldrfrvwhxsmgaabwmaik, 2026-06-30):
--
-- (a) curation_review_log SELECT was PERMISSIVE `USING(true)` to `authenticated`
--     (policy `curation_review_log_read`; confirmed via pg_policies). Any bearer
--     token could read every review row (subject only to the restrictive org
--     scope). Table has 0 rows today, so this is a LATENT hole closed before the
--     p197 curation flow (#194) produces production data. All reads must go via
--     SECURITY DEFINER RPCs that apply field-level filtering + the ADR-0105
--     rls_can_see_initiative confidential gate. Replaced with an explicit
--     deny-all `FOR SELECT USING(false)`. No app/EF code reads this table
--     directly (grep src/ + supabase/functions/ = only generated types) ⇒ neutral.
--
-- (b) get_all_certificates(text,text,boolean) is SECURITY DEFINER over the whole
--     certificates table (46 rows, PII join) and is anon-executable live:
--     proacl = {=X/postgres, anon=X, authenticated=X, service_role=X} — EXECUTE
--     held BOTH via the default PUBLIC grant AND an explicit anon grant, so
--     `REVOKE FROM anon` alone is a no-op (anon still inherits via PUBLIC).
--     REVOKE FROM PUBLIC, anon + re-GRANT authenticated, service_role. #965-class,
--     but this fn is READ-ONLY (no insert/update/delete/http_post) so it is NOT
--     in the #965 sweep _audit_secdef_public_grant_drift() and is deliberately
--     NOT added to that allowlist (SPEC §11 F-H7). authenticated stays (the fn
--     gates internally / callers are the admin UI).
--
-- (c) Denormalize initiative_id onto curation_review_log so any future SECDEF
--     read of the log can apply the ADR-0105 confidential gate JOIN-free.
--     GROUNDING CORRECTION: the SPEC said "from board_items" but board_items has
--     no initiative_id column; the real path is
--       curation_review_log.board_item_id
--         -> board_items.board_id (FK -> project_boards)
--         -> project_boards.initiative_id (nullable; FK -> initiatives ON DELETE SET NULL).
--     Column mirrors that FK convention. A BEFORE INSERT trigger keeps it
--     self-populated (no RPC body touched ⇒ neutral; the write path
--     submit_curation_review is untouched — SPEC §11 F-B2). Backfill is a no-op
--     today (0 rows) but idempotent.
--
-- GC-097: no RPC signature change; RLS + GRANT + one additive nullable column +
-- one BEFORE INSERT trigger fn + one read-only service_role-only audit fn (both
-- outside the #965 side-effect sweep).
--
-- Adversarial pre-apply review (4 lenses, wf_0a44bbf5-b4e): APPLY. Fixes folded in:
--   * security-medium: trigger derives initiative_id UNCONDITIONALLY (never trusts
--     caller input) — gate-bearing denorm must not be client-writable.
--   * spec_test-medium: added _audit_get_all_certificates_anon_execute() so the anon
--     REVOKE has a CI-runnable ratchet (was static-file-only).
-- Deferred (follow-up, kept out to stay single-purpose): REVOKE anon table-level DML
-- on curation_review_log (pre-existing, RLS-mitigated); optional drop of the now-inert
-- curation_review_log_write policy (writes are SECDEF-only).
-- =====================================================================

-- ── (a) curation_review_log: deny-all direct SELECT ───────────────────
DROP POLICY IF EXISTS curation_review_log_read ON public.curation_review_log;

CREATE POLICY curation_review_log_no_direct_select
  ON public.curation_review_log
  FOR SELECT
  TO public
  USING (false);

COMMENT ON POLICY curation_review_log_no_direct_select ON public.curation_review_log IS
  '#308-PR0 (#987): deny-all direct SELECT. Reads only via SECURITY DEFINER RPCs '
  'that apply per-field filtering + the ADR-0105 rls_can_see_initiative gate. '
  'Replaces curation_review_log_read USING(true) latent hole (0 rows at hardening time).';

-- ── (b) get_all_certificates: revoke anon (keep authenticated + service_role) ──
REVOKE EXECUTE ON FUNCTION public.get_all_certificates(text, text, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_all_certificates(text, text, boolean) TO authenticated, service_role;

-- Forward-defense (ratchet): a service_role-only oracle so CI can assert anon has
-- NO EXECUTE on get_all_certificates. This read-only fn is outside the #965
-- side-effect sweep (no insert/update/delete/http_post), so #965's ratchet cannot
-- cover it; this gives the REVOKE a live, CI-runnable guard against a future
-- re-GRANT to anon/PUBLIC. Catalog lookup only — no bodies, no PII.
CREATE OR REPLACE FUNCTION public._audit_get_all_certificates_anon_execute()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT has_function_privilege(
    'anon', 'public.get_all_certificates(text,text,boolean)'::regprocedure, 'EXECUTE');
$$;
REVOKE EXECUTE ON FUNCTION public._audit_get_all_certificates_anon_execute() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._audit_get_all_certificates_anon_execute() TO service_role;

-- ── (c) denormalize initiative_id (board_item -> project_board -> initiative) ──
ALTER TABLE public.curation_review_log
  ADD COLUMN IF NOT EXISTS initiative_id uuid
  REFERENCES public.initiatives(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.curation_review_log.initiative_id IS
  '#308-PR0 (#987): denormalized from board_items.board_id -> project_boards.initiative_id '
  'so SECDEF reads can apply the ADR-0105 rls_can_see_initiative confidential gate JOIN-free. '
  'Authoritatively set at INSERT by trg_curation_review_log_fill_initiative (caller input ignored). '
  'Append-only audit row: a later board->initiative repointing is NOT re-tracked. '
  'NULL = org-level board (visible).';

CREATE OR REPLACE FUNCTION public._curation_review_log_fill_initiative_id()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Gate-bearing denorm: ALWAYS derive from the board_item; never honor a
  -- caller-supplied initiative_id. A Tier-1 writer has a direct PostgREST INSERT
  -- path (curation_review_log_write policy + table INSERT grant) and could
  -- otherwise forge the ADR-0105 confidential anchor (board_item in a confidential
  -- initiative, initiative_id set to a public one). The sole legitimate writer
  -- (submit_curation_review, SECDEF) never sets this column ⇒ unconditional
  -- derivation is behavior-neutral. (Adversarial review 987/security-medium.)
  SELECT pb.initiative_id
    INTO NEW.initiative_id
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
   WHERE bi.id = NEW.board_item_id;
  RETURN NEW;
END;
$$;

-- Trigger functions fire regardless of EXECUTE grants; lock down anyway (hygiene).
REVOKE EXECUTE ON FUNCTION public._curation_review_log_fill_initiative_id() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_curation_review_log_fill_initiative ON public.curation_review_log;
CREATE TRIGGER trg_curation_review_log_fill_initiative
  BEFORE INSERT ON public.curation_review_log
  FOR EACH ROW
  EXECUTE FUNCTION public._curation_review_log_fill_initiative_id();

-- Backfill (idempotent; 0 rows today).
UPDATE public.curation_review_log crl
   SET initiative_id = (
     SELECT pb.initiative_id
       FROM public.board_items bi
       JOIN public.project_boards pb ON pb.id = bi.board_id
      WHERE bi.id = crl.board_item_id
   )
 WHERE crl.initiative_id IS NULL;

NOTIFY pgrst, 'reload schema';
