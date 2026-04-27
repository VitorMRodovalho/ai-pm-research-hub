-- ADR-0031 (p66) defense-in-depth REVOKE
-- pg_policy precondition: zero RLS refs to admin_list_members (verified pre-apply).

REVOKE EXECUTE ON FUNCTION public.admin_list_members(text, text, integer, text) FROM PUBLIC, anon;
