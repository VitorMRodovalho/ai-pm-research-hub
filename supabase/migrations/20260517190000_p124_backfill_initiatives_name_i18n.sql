-- p124 — backfill metadata.name_i18n for the 6 active initiatives that lack
-- trilingual labels. The 7 research_tribe initiatives already had name_i18n
-- (and quadrant_name_i18n) populated from a prior wave; the catalog page +
-- tribe detail page consume name_i18n[lang_code] when present, falling back
-- to the canonical title column.
--
-- Rollback: UPDATE initiatives SET metadata = metadata - 'name_i18n' WHERE id IN (...)
--
-- Also opportunistic: update the canonical PT title to add the diacritics
-- that were lost in original CSV import (Comite→Comitê, Comunicacao→
-- Comunicação, Publicacoes→Publicações, Submissoes→Submissões).

UPDATE public.initiatives
SET title = 'Comitê de Curadoria',
    metadata = metadata || jsonb_build_object('name_i18n', jsonb_build_object(
      'pt', 'Comitê de Curadoria',
      'en', 'Curation Committee',
      'es', 'Comité de Curaduría'
    ))
WHERE id = '6a93cc94-c4a0-4280-8ea7-452ec6ec48a5';

UPDATE public.initiatives
SET metadata = metadata || jsonb_build_object('name_i18n', jsonb_build_object(
      'pt', 'LATAM LIM 2026 — De Cinco Capítulos a Uma Plataforma',
      'en', 'LATAM LIM 2026 — From Five Chapters to One Platform',
      'es', 'LATAM LIM 2026 — De Cinco Capítulos a Una Plataforma'
    ))
WHERE id = 'a68fcc06-7de8-400b-b5b3-60e368fb46ac';

UPDATE public.initiatives
SET metadata = metadata || jsonb_build_object('name_i18n', jsonb_build_object(
      'pt', 'Preparatório CPMAI — Ciclo 3 (2026)',
      'en', 'CPMAI Prep Course — Cycle 3 (2026)',
      'es', 'Preparatorio CPMAI — Ciclo 3 (2026)'
    ))
WHERE id = '2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19';

UPDATE public.initiatives
SET title = 'Hub de Comunicação',
    metadata = metadata || jsonb_build_object('name_i18n', jsonb_build_object(
      'pt', 'Hub de Comunicação',
      'en', 'Communications Hub',
      'es', 'Hub de Comunicaciones'
    ))
WHERE id = '9ea82b09-55c6-4cc3-ab7f-178518d0ab47';

UPDATE public.initiatives
SET metadata = metadata || jsonb_build_object('name_i18n', jsonb_build_object(
      'pt', 'Newsletter — Frontiers AI Project Management',
      'en', 'Newsletter — Frontiers AI Project Management',
      'es', 'Newsletter — Frontiers AI Project Management'
    ))
WHERE id = 'ba824d24-af69-429d-a601-3672e97f8e37';

UPDATE public.initiatives
SET title = 'Publicações & Submissões',
    metadata = metadata || jsonb_build_object('name_i18n', jsonb_build_object(
      'pt', 'Publicações & Submissões',
      'en', 'Publications & Submissions',
      'es', 'Publicaciones & Envíos'
    ))
WHERE id = 'e885525e-a0f1-4e16-813c-497047209047';

NOTIFY pgrst, 'reload schema';
