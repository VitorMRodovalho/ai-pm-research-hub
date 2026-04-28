-- Hygiene: lock search_path on _trg_initiative_invitations_updated_at trigger function.
-- Closes Supabase advisor function_search_path_mutable WARN (last p78 advisor scan).
-- Body has no schema-qualified refs, so SET search_path = '' is purely defensive.

CREATE OR REPLACE FUNCTION public._trg_initiative_invitations_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END
$$;
