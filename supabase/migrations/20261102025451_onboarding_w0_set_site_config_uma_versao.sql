-- set_site_config: one version only, which writes jsonb.
-- WHAT: drops set_site_config(text, text) and recreates set_site_config(text, jsonb) writing p_value as jsonb
--       (a JSON null when the screen sends null), with the same manage_platform gate. updated_by is recorded on
--       every write, as the jsonb version already did and the text version did not. The dropped text version
--       refused with 'Admin access required' behind the same gate; the kept version says 'Superadmin only'.
-- WHY:  both versions had the same parameter names (p_key, p_value) and different types. PostgREST does not
--       support that ("Overloaded functions with the same argument names but different types are not
--       supported", error PGRST203), so a save from /admin/settings or /admin/report reached neither. And both
--       bodies wrote a text expression into site_config.value, which is jsonb: text to jsonb is an explicit-only
--       cast in Postgres, so the INSERT itself fails (42804, exercised through both versions on 2026-11-02, before
--       this apply). Measured on 2026-11-02: no save from the screens landed after 2026-04-26. The two WhatsApp
--       invite keys were last written on 2026-10-07 by migration 20261007021851 (#740), and the other keys on
--       2026-03-10. No row has updated_by.
-- CALLERS: src/pages/admin/settings.astro and src/pages/admin/report.astro, both by name through PostgREST.
--       No SQL function, trigger, Edge Function or script calls set_site_config.
-- ROLLBACK: recreate both versions as in 20260426212845_phase_bpp_pacote_i_misc_admin_6_fns_p63.sql
--       (sections 5 and 6).
DROP FUNCTION IF EXISTS public.set_site_config(text, text);

CREATE OR REPLACE FUNCTION public.set_site_config(p_key text, p_value jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Superadmin only'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Superadmin only';
  END IF;

  -- A null from the screen clears a setting. The column is NOT NULL, so it is stored as JSON null.
  INSERT INTO public.site_config (key, value, updated_at, updated_by)
  VALUES (p_key, COALESCE(p_value, 'null'::jsonb), now(), v_caller_id)
  ON CONFLICT (key) DO UPDATE SET
    value = EXCLUDED.value,
    updated_at = now(),
    updated_by = EXCLUDED.updated_by;
END;
$$;

REVOKE ALL ON FUNCTION public.set_site_config(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_site_config(text, jsonb) TO authenticated, service_role;

COMMENT ON FUNCTION public.set_site_config(text, jsonb) IS
  'Writes one site_config key as jsonb (null from the caller is stored as JSON null) and records updated_by. Gate: manage_platform via can_by_member. The only version: the (text, text) overload was dropped because PostgREST cannot pick between same-named overloads (PGRST203) and it wrote text into a jsonb column.';
