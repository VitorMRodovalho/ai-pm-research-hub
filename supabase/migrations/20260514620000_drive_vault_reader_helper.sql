-- Helper RPC para EFs lerem Vault decrypted_secrets via service_role.
-- vault.decrypted_secrets não é acessível direto via Supabase JS client
-- (default schema = public). SECDEF RPC bypassa.
-- Authority: service_role only (revoga PUBLIC, GRANT explicit).

CREATE OR REPLACE FUNCTION public._get_vault_secret(p_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_secret text;
BEGIN
  IF current_user NOT IN ('service_role', 'postgres', 'supabase_admin') THEN
    RETURN NULL;
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = p_name
  LIMIT 1;

  RETURN v_secret;
END;
$$;

REVOKE ALL ON FUNCTION public._get_vault_secret(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._get_vault_secret(text) TO service_role;

COMMENT ON FUNCTION public._get_vault_secret(text) IS
'Helper for Edge Functions (service_role) to read Vault decrypted_secrets. Bypasses public-schema default of Supabase JS client. Internal-only — REVOKEd from authenticated/anon.';

NOTIFY pgrst, 'reload schema';
