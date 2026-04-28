-- ADR-0058 batch 1 — multiple_permissive_policies fix
-- Flip publication_series_v4_org_scope from PERMISSIVE to RESTRICTIVE to match
-- canonical pattern (40/41 v4_org_scope policies are already RESTRICTIVE).
-- Closes ~18 multiple_permissive_policies WARN in one migration (133 → 115).

DROP POLICY IF EXISTS publication_series_v4_org_scope ON public.publication_series;

CREATE POLICY publication_series_v4_org_scope ON public.publication_series
  AS RESTRICTIVE FOR ALL
  USING (organization_id = auth_org() OR organization_id IS NULL)
  WITH CHECK (organization_id = auth_org() OR organization_id IS NULL);

NOTIFY pgrst, 'reload schema';
