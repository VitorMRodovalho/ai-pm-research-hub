-- #1136 Part 3: quadrant_name data-hygiene.
-- Align every tribe's quadrant_name (canonical EN) and quadrant_name_i18n (jsonb {pt,en,es})
-- to the single frontend SSOT (src/i18n data.qN.title), so the DB fallback columns mirror the
-- frontend labels. Fixes: q1/tribe 12 (PT text in canonical col + null i18n), q2/tribe 2 (i18n
-- carried the q1 name), and null quadrant_name_i18n on tribes 9,10,11,12. Idempotent.
UPDATE public.tribes t SET
  quadrant_name = s.canonical,
  quadrant_name_i18n = s.i18n
FROM (VALUES
  (1, 'The Augmented Practitioner', '{"pt":"O Praticante Aumentado","en":"The Augmented Practitioner","es":"El Practicante Aumentado"}'::jsonb),
  (2, 'AI Project Management',       '{"pt":"Gestão de Projetos de IA","en":"AI Project Management","es":"Gestión de Proyectos de IA"}'::jsonb),
  (3, 'Organizational Leadership',   '{"pt":"Liderança Organizacional","en":"Organizational Leadership","es":"Liderazgo Organizacional"}'::jsonb),
  (4, 'Future & Responsibility',     '{"pt":"Futuro e Responsabilidade","en":"Future & Responsibility","es":"Futuro y Responsabilidad"}'::jsonb)
) AS s(quadrant, canonical, i18n)
WHERE t.quadrant = s.quadrant
  AND (t.quadrant_name IS DISTINCT FROM s.canonical OR t.quadrant_name_i18n IS DISTINCT FROM s.i18n);
