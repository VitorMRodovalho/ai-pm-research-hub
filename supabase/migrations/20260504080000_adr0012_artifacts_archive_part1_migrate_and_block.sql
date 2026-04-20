-- ADR-0012 Princípio 4 — artifacts table archival (part 1/2)
-- (a) migrate 29 legacy rows para publication_submissions com source=legacy_artifact
-- (b) COMMENT ON TABLE deprecated
-- (c) BEFORE INSERT trigger hard block (bypassa RLS service_role)
-- Decisão: Option B (archive+remap) conforme data-architect tier 3 audit p28.
-- Part 2 (remap readers) em migration 20260504080001.
-- Part 3 (DROP TABLE CASCADE + remove I_artifacts_frozen) deferred 48h+ per
-- ADR-0012 Princípio 3 shadow reasoning.
-- Zero gamification_points com category='artifact' → sem ref_id remap necessário
-- (risco HIGH do data-architect descartado por audit de dados real).

INSERT INTO public.publication_submissions (
  id, primary_author_id, title, abstract, target_url,
  target_type, target_name, status, submission_date, acceptance_date,
  organization_id, initiative_id, reviewer_feedback,
  created_at, updated_at, legacy_tribe_key
)
SELECT
  a.id, a.member_id,
  COALESCE(a.title, 'Legacy artifact sem título'),
  a.description, a.url,
  'other'::submission_target_type,
  CONCAT('Legacy artifact — ', COALESCE(a.type, 'unspecified type')),
  CASE a.status
    WHEN 'published' THEN 'published'::submission_status
    WHEN 'review' THEN 'under_review'::submission_status
    WHEN 'pending_review' THEN 'under_review'::submission_status
    WHEN 'draft' THEN 'draft'::submission_status
    ELSE 'draft'::submission_status END,
  COALESCE(a.submitted_at::date, a.created_at::date),
  a.published_at::date,
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid, -- Núcleo IA & GP organization
  (SELECT i.id FROM public.initiatives i WHERE i.legacy_tribe_id = a.tribe_id LIMIT 1),
  CONCAT_WS(' | ',
    '[Legacy artifact migrated via ADR-0012 principle 4 archival — migration 20260504080000]',
    CASE WHEN a.cycle IS NOT NULL THEN 'cycle=' || a.cycle END,
    CASE WHEN a.type IS NOT NULL THEN 'legacy_type=' || a.type END,
    CASE WHEN a.source IS NOT NULL THEN 'source=' || a.source END,
    CASE WHEN a.trello_card_id IS NOT NULL THEN 'trello_card_id=' || a.trello_card_id END,
    CASE WHEN a.tags IS NOT NULL AND array_length(a.tags, 1) > 0 THEN 'tags=' || array_to_string(a.tags, ',') END,
    CASE WHEN a.review_notes IS NOT NULL THEN 'review_notes=' || a.review_notes END,
    CASE WHEN a.curation_status IS NOT NULL THEN 'curation_status=' || a.curation_status END
  ),
  a.created_at, a.updated_at, a.tribe_id::text
FROM public.artifacts a
WHERE NOT EXISTS (SELECT 1 FROM public.publication_submissions ps WHERE ps.id = a.id);

COMMENT ON TABLE public.artifacts IS
  '[DEPRECATED — ADR-0012 Princípio 4, migration 20260504080000] Legacy production submissions table, frozen since V4 cutover 2026-04-13. 29 rows migrated to publication_submissions (reviewer_feedback contém metadata legacy). All new writes rejected via trg_reject_artifacts_insert. DROP TABLE deferred 48h+ per ADR-0012 Princípio 3.';

CREATE OR REPLACE FUNCTION public.reject_artifacts_insert()
RETURNS trigger LANGUAGE plpgsql
AS $function$
BEGIN
  RAISE EXCEPTION 'artifacts table is frozen (ADR-0012 Princípio 4). New submissions must use publication_submissions.'
    USING ERRCODE = 'check_violation';
END;
$function$;

DROP TRIGGER IF EXISTS trg_reject_artifacts_insert ON public.artifacts;
CREATE TRIGGER trg_reject_artifacts_insert
  BEFORE INSERT ON public.artifacts
  FOR EACH ROW EXECUTE FUNCTION public.reject_artifacts_insert();

NOTIFY pgrst, 'reload schema';
