-- ADR-0037: Defense-in-depth REVOKE FROM PUBLIC, anon
-- get_chapter_needs and get_org_chart should not be callable by anonymous users.
-- Matches ADR-0030/0031/0034/0035/0036 precedent.

REVOKE EXECUTE ON FUNCTION public.get_chapter_needs(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_org_chart() FROM PUBLIC, anon;
