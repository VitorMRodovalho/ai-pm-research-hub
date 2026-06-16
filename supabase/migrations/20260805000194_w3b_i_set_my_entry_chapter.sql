-- Wave 3b-i (#740 / ADR-0104) — member-facing entry-chapter choice
--
-- WHAT: two self-scoped RPCs for the /perfil entry-chapter choice screen.
--   1. get_my_chapter_affiliations() — lists the caller's BR chapter affiliations
--      (the FACT, from member_chapter_affiliations) joined to chapter_registry for
--      display, flagging which one is_primary and which is the chosen entry chapter.
--   2. set_my_entry_chapter(p_chapter_code) — records the member's explicit, self-chosen
--      chapter of ENTRY (governance). Restricted (PM decision 2026-06-16) to a chapter
--      the member is ALREADY affiliated with (member_chapter_affiliations) — you enter via
--      a chapter you belong to, never an arbitrary one. Promotes that affiliation to the
--      one primary through the single-home upsert RPC (upsert_chapter_affiliation), so the
--      FACT primary stays aligned with the governance choice (and the deferred invariant
--      U_active_person_has_primary, Wave 3b-ii). Stores the bare code on
--      members.entry_chapter_code.
--
-- WHY: ADR-0104 separates FACT (which chapters a member belongs to) from GOVERNANCE (the
--      single entry chapter the member chooses). 3a-0 stopped the wrong display; 3a built
--      the FACT table + entry_chapter_code column; 3a-iii populated the FACT from the
--      worker. 3b-i gives the member the choice UI + the write path. members.chapter stays
--      the legacy/compat value here; it becomes derived in 3b-ii (additive step).
--
-- SECURITY: both SECDEF (member_chapter_affiliations is RLS rpc_only_deny_all). Both are
--   strictly self-scoped via auth.uid() → members.auth_id; no parameter selects another
--   member, so EXECUTE is safe for authenticated (unlike upsert_chapter_affiliation, which
--   takes p_person_id and is therefore service_role-only). set_my_entry_chapter (owned by
--   postgres, SECDEF) can call the service_role-restricted upsert_chapter_affiliation
--   because a SECDEF function executes as its owner, and postgres owns both.
--
-- ROLLBACK: DROP FUNCTION public.set_my_entry_chapter(text);
--           DROP FUNCTION public.get_my_chapter_affiliations();

BEGIN;

-- 1. Read: the caller's own BR chapter affiliations, for the choice screen.
CREATE OR REPLACE FUNCTION public.get_my_chapter_affiliations()
RETURNS TABLE (
  chapter_code text,
  legal_name   text,
  state        text,
  country      text,
  is_primary   boolean,
  is_entry     boolean,
  source       text,
  verified_at  timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT mca.chapter_code,
         cr.legal_name,
         cr.state,
         cr.country,
         mca.is_primary,
         (mca.chapter_code = m.entry_chapter_code) AS is_entry,
         mca.source,
         mca.verified_at
    FROM public.members m
    JOIN public.member_chapter_affiliations mca ON mca.person_id = m.person_id
    JOIN public.chapter_registry cr ON cr.chapter_code = mca.chapter_code
   WHERE m.auth_id = auth.uid()
     AND cr.country = 'BR'
   ORDER BY (mca.chapter_code = m.entry_chapter_code) DESC,
            mca.is_primary DESC,
            cr.display_order NULLS LAST,
            cr.chapter_code;
$function$;

COMMENT ON FUNCTION public.get_my_chapter_affiliations() IS
  'Wave 3b-i #740 / ADR-0104 — self-scoped list of the caller''s BR chapter affiliations (FACT) for the entry-chapter choice screen. SECDEF (table is RLS-locked); authenticated only.';

REVOKE EXECUTE ON FUNCTION public.get_my_chapter_affiliations() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_my_chapter_affiliations() FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_my_chapter_affiliations() TO authenticated;

-- 2. Write: record the member's explicit entry-chapter choice (governance).
CREATE OR REPLACE FUNCTION public.set_my_entry_chapter(p_chapter_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id       uuid;
  v_person_id       uuid;
  v_code            text := regexp_replace(coalesce(p_chapter_code, ''), '^PMI-', '');
  v_is_br           boolean;
  v_is_active       boolean;
  v_existing_source text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT id, person_id INTO v_member_id, v_person_id
    FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Caller has no member record';
  END IF;
  IF v_person_id IS NULL THEN
    RAISE EXCEPTION 'Member has no person identity';
  END IF;

  IF v_code = '' THEN
    RAISE EXCEPTION 'chapter_code is required';
  END IF;

  -- The chosen chapter must exist, be a Brazil chapter, and be active.
  SELECT (country = 'BR'), is_active INTO v_is_br, v_is_active
    FROM public.chapter_registry WHERE chapter_code = v_code;
  IF v_is_br IS NULL THEN
    RAISE EXCEPTION 'Unknown chapter %', v_code;
  END IF;
  IF NOT v_is_br THEN
    RAISE EXCEPTION 'Entry chapter must be a Brazil chapter (got %)', v_code
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT v_is_active THEN
    RAISE EXCEPTION 'Chapter % is not active', v_code
      USING ERRCODE = 'check_violation';
  END IF;

  -- PM decision (2026-06-16): restrict the choice to the member's OWN affiliations (FACT).
  -- You enter via a chapter you belong to, not an arbitrary one. Preserve the affiliation's
  -- existing source (a verified pmi_vep fact must not be relabelled self_declared).
  SELECT source INTO v_existing_source
    FROM public.member_chapter_affiliations
   WHERE person_id = v_person_id AND chapter_code = v_code;
  IF v_existing_source IS NULL THEN
    RAISE EXCEPTION 'You are not affiliated with chapter % — choose one of your PMI chapters', v_code
      USING ERRCODE = 'check_violation';
  END IF;

  -- Promote that affiliation to the one primary (single home for the one-primary invariant).
  PERFORM public.upsert_chapter_affiliation(v_person_id, v_code, v_existing_source, true);

  -- Record the governance choice.
  UPDATE public.members
     SET entry_chapter_code = v_code,
         updated_at = now()
   WHERE id = v_member_id;

  RETURN jsonb_build_object(
    'success', true,
    'member_id', v_member_id,
    'entry_chapter_code', v_code,
    'updated_at', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.set_my_entry_chapter(text) IS
  'Wave 3b-i #740 / ADR-0104 — self-scoped: records the caller''s explicit entry-chapter choice (governance). Restricted to a chapter the member is already affiliated with (member_chapter_affiliations); promotes it to primary via upsert_chapter_affiliation; stores bare code on members.entry_chapter_code. SECDEF; authenticated only.';

REVOKE EXECUTE ON FUNCTION public.set_my_entry_chapter(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_my_entry_chapter(text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.set_my_entry_chapter(text) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
