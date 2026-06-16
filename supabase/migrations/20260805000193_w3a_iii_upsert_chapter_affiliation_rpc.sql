-- Wave 3a-iii (#740 / ADR-0104) — worker write path for member_chapter_affiliations
--
-- WHAT:
--   1. upsert_chapter_affiliation(p_person_id, p_chapter_code, p_source, p_is_primary)
--      — the SINGLE home for the one-primary invariant. The pmi-vep-sync worker calls
--      this (source='pmi_vep', is_primary=false) for each BR affiliation in the reliable
--      pmi_memberships snapshot. SECURITY DEFINER (the table is RLS rpc_only_deny_all);
--      EXECUTE granted to service_role only (the worker) — never anon/authenticated,
--      because it can rewrite any person's affiliation (privilege-escalation surface).
--   2. BEFORE UPDATE trigger to keep updated_at fresh (the table had no UPDATEs until
--      the worker starts issuing them — see ADR-0104 contract).
--
-- ONE-PRIMARY PROTOCOL (ADR-0104): the partial unique index
--   member_chapter_affiliations_one_primary_idx forbids two is_primary=true rows per
--   person, so a naive ON CONFLICT ... SET is_primary=true fails when the person already
--   has a *different* primary. The RPC therefore:
--     - p_is_primary=true  → demote any other primary first, then force this one primary
--       (used by Wave 3b / admin to set an explicit choice).
--     - p_is_primary=false → assert the FACT only; NEVER demote an existing primary
--       (preserves the legacy backfill + the future entry_chapter choice). If the person
--       has NO primary at all, this row becomes a *provisional* FACT primary so the table
--       is never left primary-less. That is a fact placeholder, NOT a headline claim — the
--       member's displayed chapter is members.entry_chapter_code (Wave 3b governance),
--       which supersedes it. The worker always passes is_primary=false: it asserts which
--       chapters a person belongs to, it never decides the headline (ADR-0104 rejects
--       array-order-based primary selection for members who already have a chapter).
--
-- WHY: ADR-0104 deferred the multi-chapter population from pmi_memberships to the worker
--      (it already maps "<State>, Brazil Chapter" → PMI-XX). This migration provides the
--      safe write path. Additive; no behavior change to existing reads.
--
-- ROLLBACK: DROP FUNCTION public.upsert_chapter_affiliation(uuid, text, text, boolean);
--           DROP TRIGGER member_chapter_affiliations_set_updated_at ON public.member_chapter_affiliations;

BEGIN;

-- 1. updated_at trigger (reuse the canonical V4 helper set_updated_at_v4()).
DROP TRIGGER IF EXISTS member_chapter_affiliations_set_updated_at ON public.member_chapter_affiliations;
CREATE TRIGGER member_chapter_affiliations_set_updated_at
  BEFORE UPDATE ON public.member_chapter_affiliations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at_v4();

-- 2. Single-home upsert RPC (one-primary invariant lives here).
CREATE OR REPLACE FUNCTION public.upsert_chapter_affiliation(
  p_person_id    uuid,
  p_chapter_code text,
  p_source       text DEFAULT 'pmi_vep',
  p_is_primary   boolean DEFAULT false
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_code         text := regexp_replace(coalesce(p_chapter_code, ''), '^PMI-', '');
  v_make_primary boolean;
BEGIN
  IF v_code = '' THEN
    RAISE EXCEPTION 'upsert_chapter_affiliation: chapter_code is required';
  END IF;
  IF p_source NOT IN ('pmi_vep', 'admin_import', 'self_declared', 'legacy') THEN
    RAISE EXCEPTION 'upsert_chapter_affiliation: invalid source %', p_source;
  END IF;

  -- An explicit primary demotes any other primary first (partial unique index guard).
  IF p_is_primary THEN
    UPDATE public.member_chapter_affiliations
       SET is_primary = false, updated_at = now()
     WHERE person_id = p_person_id AND is_primary = true AND chapter_code <> v_code;
  END IF;

  -- Provisional FACT primary only when the person has none (never overrides an existing one).
  v_make_primary := p_is_primary OR NOT EXISTS (
    SELECT 1 FROM public.member_chapter_affiliations
     WHERE person_id = p_person_id AND is_primary = true
  );

  INSERT INTO public.member_chapter_affiliations
    (person_id, chapter_code, source, is_primary, verified_at)
  VALUES (p_person_id, v_code, p_source, v_make_primary, now())
  ON CONFLICT (person_id, chapter_code) DO UPDATE
    SET source      = EXCLUDED.source,
        verified_at = now(),
        updated_at  = now(),
        is_primary  = CASE WHEN p_is_primary THEN true
                           ELSE public.member_chapter_affiliations.is_primary END;
END;
$function$;

COMMENT ON FUNCTION public.upsert_chapter_affiliation(uuid, text, text, boolean) IS
  'Wave 3a-iii #740 / ADR-0104 — single home for the one-primary invariant on member_chapter_affiliations. Worker (service_role) calls with is_primary=false to assert BR affiliation FACTS from pmi_memberships; is_primary=true (Wave 3b/admin) demotes others then forces primary. SECDEF; EXECUTE service_role only.';

-- EXECUTE: worker only. This SECDEF function can rewrite any person's affiliation, so it
-- must NOT be reachable by anon/authenticated (privilege escalation). Mirrors the
-- locked-table RPC pattern (member_emails / ADR-0095).
REVOKE EXECUTE ON FUNCTION public.upsert_chapter_affiliation(uuid, text, text, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.upsert_chapter_affiliation(uuid, text, text, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.upsert_chapter_affiliation(uuid, text, text, boolean) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.upsert_chapter_affiliation(uuid, text, text, boolean) TO service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
