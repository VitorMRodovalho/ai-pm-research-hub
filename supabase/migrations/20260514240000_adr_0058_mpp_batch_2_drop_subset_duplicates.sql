-- ADR-0058 batch 2 — drop subset duplicate policies (Class B)
-- Both pairs have USING true; EXPLICIT role list is strictly subset of PUBLIC.
-- Drop EXPLICIT, keep PUBLIC. -4 mpp WARN (115 → 111).
--
-- courses:           "Public courses" (PUBLIC) covers anon_read_courses ({auth,anon}).
-- tribe_selections:  "Public tribe counts" (PUBLIC) covers anon_read_tribe_selections.

DROP POLICY IF EXISTS anon_read_courses ON public.courses;
DROP POLICY IF EXISTS anon_read_tribe_selections ON public.tribe_selections;

NOTIFY pgrst, 'reload schema';
